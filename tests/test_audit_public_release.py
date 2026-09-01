from __future__ import annotations

import unittest

from scripts.audit_public_release import _violations


class PublicReleaseAuditTest(unittest.TestCase):
    def test_license_placeholder_is_allowed(self) -> None:
        self.assertEqual(
            _violations("example.cfg", b"ak_secret_replace_me"),
            [],
        )

    def test_real_license_shape_is_rejected(self) -> None:
        value = ("ak" + "_secret_not-a-placeholder-value").encode()
        findings = _violations("server.cfg", value)
        self.assertEqual(len(findings), 1)

    def test_private_environment_marker_is_rejected(self) -> None:
        marker = ("sandbox" + "-a").encode()
        findings = _violations("deploy.sh", marker)
        self.assertEqual(len(findings), 1)


if __name__ == "__main__":
    unittest.main()
