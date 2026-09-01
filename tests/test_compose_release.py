from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

from scripts.compose_release import ReleaseError, compose, load_lock


def _git(repository: Path, *arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments],
        cwd=repository,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout.strip()


class ComposeReleaseTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        _git(self.root, "init", "--quiet")
        _git(self.root, "config", "user.email", "release-test@humalike.com")
        _git(self.root, "config", "user.name", "HumaLike Release Test")
        (self.root / "release").mkdir()
        (self.root / "examples" / "humalike-adapter").mkdir(parents=True)
        (self.root / "release" / "INSTALL.md").write_text("install\n", encoding="utf-8")
        (self.root / "release" / "humalike.example.cfg").write_text(
            "ensure humalike\n", encoding="utf-8"
        )
        (self.root / "COMPATIBILITY.md").write_text("compatibility\n", encoding="utf-8")
        (self.root / "LICENSE.md").write_text("license\n", encoding="utf-8")
        (self.root / "NOTICE").write_text("notice\n", encoding="utf-8")
        (self.root / "examples" / "humalike-adapter" / "fxmanifest.lua").write_text(
            "dependency 'humalike'\n", encoding="utf-8"
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _resource(self, name: str, manifest: str, files: dict[str, str]) -> None:
        resource = self.root / "resources" / name
        resource.mkdir(parents=True)
        (resource / "fxmanifest.lua").write_text(manifest, encoding="utf-8")
        for relative, contents in files.items():
            destination = resource / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(contents, encoding="utf-8")

    @staticmethod
    def _entry(name: str, includes: list[str]) -> dict[str, object]:
        return {
            "name": name,
            "path": f"resources/{name}",
            "version": "0.1.0",
            "include": includes,
        }

    def _commit_fixture(self, *, broken_world: bool = False) -> tuple[Path, str]:
        manifest = """fx_version 'cerulean'\ngame 'gta5'\nversion '0.1.0'\nclient_script 'client/main.lua'\nui_page 'web/dist/index.html'\nfiles { 'web/dist/index.html', 'web/dist/assets/*' }\n"""
        if broken_world:
            manifest += "file 'missing.txt'\n"
        self._resource(
            "humalike",
            manifest,
            {
                "client/main.lua": "return true\n",
                "web/dist/index.html": '<script src="assets/app.js"></script>\n',
                "web/dist/assets/app.js": "console.log('voice')\n",
            },
        )
        lock = {
            "schema_version": 2,
            "product": {
                "name": "humalike-fivem",
                "version": "0.1.0-test.1",
                "protocols": {"world_state": 1, "voice_control": 1},
            },
            "resources": [
                self._entry("humalike", ["fxmanifest.lua", "client", "web/dist"]),
            ],
        }
        lock_path = self.root / "release.lock.json"
        lock_path.write_text(json.dumps(lock), encoding="utf-8")
        _git(self.root, "add", ".")
        _git(self.root, "commit", "--quiet", "-m", "fixture")
        return lock_path, _git(self.root, "rev-parse", "HEAD")

    def test_composition_is_deterministic_and_uses_committed_files_only(self) -> None:
        lock, revision = self._commit_fixture()
        (self.root / "resources" / "humalike" / "uncommitted-secret.txt").write_text(
            "must not ship", encoding="utf-8"
        )
        first = compose(lock, self.root / "first", revision=revision)
        second = compose(lock, self.root / "second", revision=revision)

        self.assertEqual(
            hashlib.sha256(first.read_bytes()).digest(),
            hashlib.sha256(second.read_bytes()).digest(),
        )
        with zipfile.ZipFile(first) as archive:
            names = archive.namelist()
            self.assertEqual(first.name, "humalike.zip")
            self.assertTrue(all(name.startswith("humalike/") for name in names))
            self.assertIn("humalike/fxmanifest.lua", names)
            self.assertIn("humalike/client/main.lua", names)
            self.assertFalse(any("uncommitted-secret" in name for name in names))
            self.assertFalse(any("tests/" in name for name in names))
            self.assertFalse(any("web/src/" in name for name in names))
            self.assertIn("humalike/LICENSE.md", names)
            self.assertIn("humalike/NOTICE", names)
        manifest = json.loads(first.with_suffix(".manifest.json").read_text())
        self.assertEqual(manifest["source"]["revision"], revision)
        self.assertEqual(
            manifest["source"]["repository"],
            "https://github.com/Humalike/humalike-fivem-npc.git",
        )

    def test_missing_manifest_asset_fails_the_release(self) -> None:
        lock, revision = self._commit_fixture(broken_world=True)
        with self.assertRaisesRegex(ReleaseError, "missing path"):
            compose(lock, self.root / "out", revision=revision)

    def test_missing_nui_entrypoint_asset_fails_the_release(self) -> None:
        lock, _ = self._commit_fixture()
        index = self.root / "resources/humalike/web/dist/index.html"
        index.write_text(
            '<script src="assets/missing.js"></script>\n', encoding="utf-8"
        )
        _git(self.root, "add", ".")
        _git(self.root, "commit", "--quiet", "-m", "break NUI reference")
        with self.assertRaisesRegex(ReleaseError, "NUI references missing asset"):
            compose(lock, self.root / "out")

    def test_lock_requires_current_schema(self) -> None:
        lock, _ = self._commit_fixture()
        payload = json.loads(lock.read_text(encoding="utf-8"))
        payload["schema_version"] = 1
        lock.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(ReleaseError, "schema_version 2"):
            load_lock(lock)


if __name__ == "__main__":
    unittest.main()
