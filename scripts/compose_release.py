#!/usr/bin/env python3
"""Compose a deterministic FiveM release from one monorepo revision."""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
from pathlib import PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile
from typing import Any
import zipfile


COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SEMVER_PATTERN = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)
FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)


class ReleaseError(RuntimeError):
    """Raised when source provenance or release contents are invalid."""


def _run(command: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> bytes:
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.decode(errors="replace").strip()
        raise ReleaseError(f"command failed: {' '.join(command)}: {detail}") from exc
    return completed.stdout


def load_lock(path: Path) -> dict[str, Any]:
    try:
        lock = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReleaseError(f"cannot read release lock {path}: {exc}") from exc

    if lock.get("schema_version") != 2:
        raise ReleaseError("release.lock.json must use schema_version 2")
    product = lock.get("product")
    resources = lock.get("resources")
    if not isinstance(product, dict) or not SEMVER_PATTERN.fullmatch(
        str(product.get("version", ""))
    ):
        raise ReleaseError("product.version must be valid SemVer")
    if product.get("name") != "humalike-fivem":
        raise ReleaseError("product.name must be humalike-fivem")
    if not isinstance(resources, list) or not resources:
        raise ReleaseError("resources must be a non-empty list")

    names: set[str] = set()
    for resource in resources:
        if not isinstance(resource, dict):
            raise ReleaseError("each resource lock entry must be an object")
        name = resource.get("name")
        source_path = resource.get("path")
        includes = resource.get("include")
        if not isinstance(name, str) or not re.fullmatch(
            r"humalike(?:-[a-z-]+)?", name
        ):
            raise ReleaseError(f"invalid resource name: {name!r}")
        if name in names:
            raise ReleaseError(f"duplicate resource: {name}")
        names.add(name)
        if not isinstance(source_path, str):
            raise ReleaseError(f"{name} has no source path")
        normalized_source = PurePosixPath(source_path)
        if normalized_source.is_absolute() or ".." in normalized_source.parts:
            raise ReleaseError(f"{name} has an unsafe source path")
        if normalized_source.as_posix() != f"resources/{name}":
            raise ReleaseError(f"{name} must live at resources/{name}")
        if not SEMVER_PATTERN.fullmatch(str(resource.get("version", ""))):
            raise ReleaseError(f"{name} has an invalid version")
        if not isinstance(includes, list) or not includes:
            raise ReleaseError(f"{name} has no include paths")
        for include in includes:
            candidate = Path(str(include))
            if candidate.is_absolute() or ".." in candidate.parts:
                raise ReleaseError(f"{name} has unsafe include path: {include}")
    return lock


def _repository_root(path: Path) -> Path:
    output = _run(["git", "rev-parse", "--show-toplevel"], cwd=path)
    return Path(output.decode().strip()).resolve()


def _resolve_revision(repository: Path, revision: str) -> str:
    resolved = _run(["git", "rev-parse", f"{revision}^{{commit}}"], cwd=repository)
    commit = resolved.decode().strip()
    if not COMMIT_PATTERN.fullmatch(commit):
        raise ReleaseError(f"Git returned an invalid revision: {commit!r}")
    return commit


def _read_revision_file(repository: Path, revision: str, relative: str) -> bytes:
    if PurePosixPath(relative).is_absolute() or ".." in PurePosixPath(relative).parts:
        raise ReleaseError(f"unsafe revision path: {relative}")
    return _run(["git", "show", f"{revision}:{relative}"], cwd=repository)


def _export_resource(
    repository: Path,
    revision: str,
    resource: dict[str, Any],
    destination: Path,
    scratch: Path,
) -> None:
    source_path = resource["path"]
    pathspecs = [f"{source_path}/{include}" for include in resource["include"]]
    archive = _run(
        ["git", "archive", "--format=tar", revision, "--", *pathspecs],
        cwd=repository,
    )
    snapshot = scratch / f"snapshot-{resource['name']}"
    snapshot.mkdir()
    root = snapshot.resolve()
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as bundle:
        for member in bundle.getmembers():
            target = (snapshot / member.name).resolve()
            if target != root and root not in target.parents:
                raise ReleaseError(f"archive contains unsafe path: {member.name}")
            if member.issym() or member.islnk() or member.isdev():
                raise ReleaseError(f"archive contains unsupported entry: {member.name}")
        bundle.extractall(snapshot, filter="data")

    exported = snapshot / source_path
    if not exported.is_dir():
        raise ReleaseError(f"{resource['name']} source does not exist at {source_path}")
    shutil.copytree(exported, destination)


def _strip_lua_comments(text: str) -> str:
    return re.sub(r"--[^\n]*", "", text)


def _quoted_values(text: str) -> list[str]:
    return [match[1] for match in re.findall(r"(['\"])(.*?)\1", text, flags=re.DOTALL)]


def _block_values(manifest: str, directive: str) -> list[str]:
    match = re.search(rf"\b{re.escape(directive)}\s*\{{(.*?)\}}", manifest, re.DOTALL)
    return _quoted_values(match.group(1)) if match else []


def _singular_values(manifest: str, directive: str) -> list[str]:
    return [
        match.group(2)
        for match in re.finditer(
            rf"\b{re.escape(directive)}\s*\(?\s*(['\"])(.*?)\1",
            manifest,
        )
    ]


def _assert_paths_exist(
    resource_root: Path, patterns: list[str], *, context: str
) -> None:
    for pattern in patterns:
        if pattern.startswith("@"):
            continue
        matches = list(resource_root.glob(pattern))
        if not matches:
            raise ReleaseError(f"{context} references missing path: {pattern}")


def validate_resource(
    resource_root: Path, resource: dict[str, Any], bundled_names: set[str]
) -> None:
    manifest_path = resource_root / "fxmanifest.lua"
    if not manifest_path.is_file():
        raise ReleaseError(f"{resource['name']} has no fxmanifest.lua")
    manifest = _strip_lua_comments(manifest_path.read_text(encoding="utf-8"))

    versions = _singular_values(manifest, "version")
    if versions != [resource["version"]]:
        raise ReleaseError(
            f"{resource['name']} manifest version {versions!r} does not match lock {resource['version']}"
        )

    path_directives = ["files", "client_scripts", "server_scripts", "shared_scripts"]
    paths: list[str] = []
    for directive in path_directives:
        paths.extend(_block_values(manifest, directive))
    for directive in (
        "file",
        "client_script",
        "server_script",
        "shared_script",
        "ui_page",
    ):
        paths.extend(_singular_values(manifest, directive))
    _assert_paths_exist(resource_root, paths, context=resource["name"])

    dependencies = _block_values(manifest, "dependencies") + _singular_values(
        manifest, "dependency"
    )
    missing_dependencies = sorted(
        dependency
        for dependency in dependencies
        if not dependency.startswith("/") and dependency not in bundled_names
    )
    if missing_dependencies:
        raise ReleaseError(
            f"{resource['name']} has unbundled dependencies: {', '.join(missing_dependencies)}"
        )

    for ui_page in _singular_values(manifest, "ui_page"):
        if ui_page.startswith("http://") or ui_page.startswith("https://"):
            continue
        html_path = resource_root / ui_page
        html = html_path.read_text(encoding="utf-8")
        references = re.findall(r"(?:src|href)\s*=\s*['\"]([^'\"]+)['\"]", html)
        for reference in references:
            if reference.startswith(("http://", "https://", "data:", "#")):
                continue
            relative = reference.lstrip("/")
            target = (html_path.parent / relative).resolve()
            if not target.is_file():
                raise ReleaseError(
                    f"{resource['name']} NUI references missing asset: {reference}"
                )

    forbidden = (".git", ".github", "node_modules", ".pnpm-store", "tests", "web/src")
    for relative in forbidden:
        if (resource_root / relative).exists():
            raise ReleaseError(
                f"{resource['name']} release contains forbidden path: {relative}"
            )


def _release_manifest(lock: dict[str, Any], revision: str) -> dict[str, Any]:
    return {
        "schemaVersion": 2,
        "product": lock["product"],
        "source": {
            "repository": "https://github.com/Humalike/humalike-fivem-npc.git",
            "revision": revision,
        },
        "resources": [
            {
                "name": item["name"],
                "path": item["path"],
                "version": item["version"],
            }
            for item in lock["resources"]
        ],
    }


def _write_deterministic_zip(source: Path, destination: Path) -> None:
    with zipfile.ZipFile(
        destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as bundle:
        for path in sorted(item for item in source.rglob("*") if item.is_file()):
            relative = path.relative_to(source).as_posix()
            info = zipfile.ZipInfo(relative, date_time=FIXED_ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, path.read_bytes(), compresslevel=9)


def _write_update_bundle(
    resource_root: Path, destination: Path, lock: dict[str, Any], revision: str
) -> None:
    """The signed payload the in-game updater installs: every released file of
    the resource, relative to its directory, with its size and SHA-256."""
    files = []
    for path in sorted(item for item in resource_root.rglob("*") if item.is_file()):
        data = path.read_bytes()
        files.append(
            {
                "path": path.relative_to(resource_root).as_posix(),
                "size": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "data": base64.b64encode(data).decode("ascii"),
            }
        )
    bundle = {
        "schema": 1,
        "product": lock["product"]["name"],
        "resource": lock["resources"][0]["name"],
        "version": lock["resources"][0]["version"],
        "revision": revision,
        "files": files,
    }
    destination.write_text(
        json.dumps(bundle, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def compose(lock_path: Path, output: Path, *, revision: str = "HEAD") -> Path:
    repository = _repository_root(lock_path.resolve().parent)
    resolved_revision = _resolve_revision(repository, revision)
    try:
        relative_lock = lock_path.resolve().relative_to(repository).as_posix()
    except ValueError as exc:
        raise ReleaseError("release lock must be inside the monorepo") from exc

    with tempfile.TemporaryDirectory(prefix="humalike-lock-") as lock_temporary:
        committed_lock = Path(lock_temporary) / "release.lock.json"
        committed_lock.write_bytes(
            _read_revision_file(repository, resolved_revision, relative_lock)
        )
        lock = load_lock(committed_lock)
    resources = lock["resources"]
    if len(resources) != 1:
        raise ReleaseError("installable archive requires exactly one resource")
    output.mkdir(parents=True, exist_ok=True)
    archive_path = output / f"{resources[0]['name']}.zip"

    with tempfile.TemporaryDirectory(prefix="humalike-release-") as temporary:
        scratch = Path(temporary)
        package_root = scratch / "package"
        package_root.mkdir()
        names = {resource["name"] for resource in resources}

        for resource in resources:
            target = package_root / resource["name"]
            _export_resource(
                repository,
                resolved_revision,
                resource,
                target,
                scratch,
            )
            validate_resource(target, resource, names)
            for name in ("LICENSE.md", "NOTICE"):
                (target / name).write_bytes(
                    _read_revision_file(repository, resolved_revision, name)
                )

        _write_deterministic_zip(package_root, archive_path)
        _write_update_bundle(
            package_root / resources[0]["name"],
            output / f"{resources[0]['name']}.update.json",
            lock,
            resolved_revision,
        )

    digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    checksum_path = archive_path.with_suffix(".zip.sha256")
    checksum_path.write_text(f"{digest}  {archive_path.name}\n", encoding="ascii")
    manifest_path = archive_path.with_suffix(".manifest.json")
    manifest_path.write_text(
        json.dumps(_release_manifest(lock, resolved_revision), indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
    return archive_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=Path("release.lock.json"))
    parser.add_argument("--output", type=Path, default=Path("artifacts"))
    parser.add_argument(
        "--revision",
        default="HEAD",
        help="Monorepo commit to export (default: HEAD)",
    )
    arguments = parser.parse_args()
    archive = compose(arguments.lock, arguments.output, revision=arguments.revision)
    print(archive)


if __name__ == "__main__":
    main()
