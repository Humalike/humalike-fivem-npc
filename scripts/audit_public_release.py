#!/usr/bin/env python3
"""Reject private deployment details and credentials from public release inputs."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import zipfile


PRIVATE_MARKERS = (
    "strefa" + "rp",
    "srp" + "-core",
    "sandbox" + "-a",
    "sandbox" + "-b",
    "sandbox" + "-c",
    "37" + ".27.109.249",
    ".internal." + "humalike.com",
)
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"\bak_secret_(?!replace_me\b)[A-Za-z0-9_-]{8,}"),
)
TEXT_SUFFIXES = {
    "",
    ".cfg",
    ".css",
    ".html",
    ".js",
    ".json",
    ".lua",
    ".md",
    ".mjs",
    ".py",
    ".sh",
    ".svg",
    ".toml",
    ".ts",
    ".tsx",
    ".txt",
    ".yaml",
    ".yml",
}


def _violations(name: str, data: bytes) -> list[str]:
    if len(data) > 5_000_000:
        return []
    text = data.decode("utf-8", errors="ignore")
    lowered = text.lower()
    findings = [
        f"{name}: private marker {marker!r}"
        for marker in PRIVATE_MARKERS
        if marker in lowered
    ]
    findings.extend(
        f"{name}: credential-like content matched {pattern.pattern!r}"
        for pattern in SECRET_PATTERNS
        if pattern.search(text)
    )
    return findings


def audit_repository(root: Path) -> list[str]:
    tracked = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout.split(b"\0")
    findings: list[str] = []
    for raw in tracked:
        if not raw:
            continue
        relative = raw.decode()
        path = root / relative
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        findings.extend(_violations(relative, path.read_bytes()))

    workflow_dir = root / ".github" / "workflows"
    for workflow in workflow_dir.glob("*.yml"):
        text = workflow.read_text(encoding="utf-8").lower()
        if "aws-actions" in text or "doppler" in text or "deploy through" in text:
            findings.append(
                f"{workflow.relative_to(root)}: deployment automation must remain private"
            )
    return findings


def audit_archive(path: Path) -> list[str]:
    findings: list[str] = []
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            if info.is_dir() or Path(info.filename).suffix.lower() not in TEXT_SUFFIXES:
                continue
            findings.extend(_violations(info.filename, archive.read(info)))
    return findings


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()

    findings = audit_repository(args.root.resolve())
    if args.archive:
        findings.extend(audit_archive(args.archive))
    if findings:
        raise SystemExit("public release audit failed:\n- " + "\n- ".join(findings))
    print("public release audit passed")


if __name__ == "__main__":
    main()
