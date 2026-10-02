#!/usr/bin/env python3
"""Local process contract tests; the release checklist owns the live cloud proof."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class CloudInstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.settings = self.root / ".claude/settings.json"
        self.env = dict(os.environ, HOME=str(self.root), PATH=f"{self.bin}:{os.environ['PATH']}",
                        TEST_ROOT=str(self.root), ARCHDEV_INSTALL_DIR=str(self.root / "installed-bin"),
                        ARCHDEV_PRESENCE_DISABLED="1")
        self.env.pop("ARCHDEV_TOKEN", None)
        self.env.pop("BASH_ENV", None)
        self.write_command("curl", '''
[ "${FAIL_DOWNLOAD:-}" != 1 ] || exit 22
[ "$1" = -fsSL ] && [ "$2" = https://raw.githubusercontent.com/ArchAstro/archdev/main/install.sh ] && [ "$3" = -o ] || exit 1
cp "$TEST_ROOT/installer" "$4"
''')
        (self.root / "installer").write_text('''
set -eu
[ "$ARCHDEV_INSTALL_DIR" = "$TEST_ROOT/installed-bin" ]
[ "$ARCHDEV_INSTALL_SKIP_PATH_UPDATE" = true ]
[ "$ARCHDEV_INSTALL_SKIP_COMPLETIONS" = true ]
[ "$*" = "--version latest" ]
[ "${FAIL_INSTALL:-}" != 1 ]
mkdir -p "$ARCHDEV_INSTALL_DIR"
cp "$TEST_ROOT/bin/archdev" "$ARCHDEV_INSTALL_DIR/archdev"
printf installed > "$TEST_ROOT/installed"
''')
        self.write_command("archdev", '''
case "$*" in
  'repo hook setup --harness claude --force')
    [ "${FAIL_HOOKS:-}" != 1 ] || exit 1
    printf hooks > "$TEST_ROOT/hooks"
    ;;
  'auth login --token '*)
    printf '%s' "$4" > "$TEST_ROOT/login-token"
    echo 'must not appear in session output'
    exit "${FAIL_LOGIN:-0}"
    ;;
  *) exit 1 ;;
esac
''')

    def write_command(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body)
        path.chmod(0o755)

    def run_setup(self, **env):
        # The cloud runner has errexit enabled. A setup error must still return 0.
        result = subprocess.run(["bash", "-e", str(ROOT / "install-cloud.sh")],
                                env=dict(self.env, **env), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_setup_then_session_login_preserves_settings_and_is_repeatable(self):
        # Setup: an existing user hook and preferences must survive cloud setup.
        existing = {"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo existing"}]}]},
                    "permissions": {"allow": ["Bash(echo *)"]}}
        self.settings.parent.mkdir()
        self.settings.write_text(json.dumps(existing))
        self.run_setup()
        first = self.settings.read_text()
        self.run_setup()
        self.assertEqual(first, self.settings.read_text())
        data = json.loads(first)
        self.assertEqual(data["permissions"], existing["permissions"])
        self.assertEqual(data["hooks"]["SessionStart"][1:], existing["hooks"]["SessionStart"])
        self.assertTrue((self.root / "installed").exists())
        self.assertTrue((self.root / "hooks").exists())
        self.assertFalse((self.root / "login-token").exists())
        # Session boundary: execute the saved hook with a token absent at setup.
        command = data["hooks"]["SessionStart"][0]["hooks"][0]["command"]
        for extra in ({}, {"ARCHDEV_TOKEN": "fixture-token"},
                      {"ARCHDEV_TOKEN": "fixture-token", "FAIL_LOGIN": "1"}):
            result = subprocess.run(["bash", "-c", command], env=dict(self.env, **extra),
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout + result.stderr, "")
        self.assertEqual((self.root / "login-token").read_text(), "fixture-token")
        self.assertNotIn("fixture-token", first)

    def test_setup_uses_installed_cli_even_when_path_has_another(self):
        # Retain the executable in the fixture release, then poison PATH.
        fixture = self.root / "released-archdev"
        fixture.write_bytes((self.bin / "archdev").read_bytes())
        fixture.chmod(0o755)
        installer = self.root / "installer"
        installer.write_text(installer.read_text().replace(
            '$TEST_ROOT/bin/archdev', '$TEST_ROOT/released-archdev'))
        self.write_command("archdev", 'exit 99\n')
        result = self.run_setup()
        self.assertIn("setup complete", result.stdout)
        self.assertTrue((self.root / "hooks").exists())

    def test_fresh_settings(self):
        self.run_setup()
        self.assertEqual(len(json.loads(self.settings.read_text())["hooks"]["SessionStart"]), 1)

    def test_failures_report_without_blocking_startup(self):
        for failure in ("FAIL_DOWNLOAD", "FAIL_INSTALL", "FAIL_HOOKS"):
            with self.subTest(failure=failure):
                result = self.run_setup(**{failure: "1"})
                self.assertIn("continuing without blocking", result.stderr)
                self.assertFalse(self.settings.exists())

    def test_invalid_settings_are_not_overwritten(self):
        self.settings.parent.mkdir()
        self.settings.write_text("invalid json")
        result = self.run_setup()
        self.assertIn("could not update Claude settings", result.stderr)
        self.assertEqual(self.settings.read_text(), "invalid json")
        self.assertEqual(list(self.settings.parent.glob(".cloud-settings.*")), [])


if __name__ == "__main__":
    unittest.main()
