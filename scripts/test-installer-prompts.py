#!/usr/bin/env python3
"""install.sh's sign-in and setup prompts, driven through a pseudo-terminal.

Each test runs the documented one-liner shape (`cat install.sh | bash -s --`)
in a pty, so the script arrives on stdin and the prompts read /dev/tty, the
way they do under `curl | bash`. The release is a local fixture whose archdev
remembers sign-in in a state directory and records the setup it was asked
for, so a test can assert what the installer actually ran.
"""
import fcntl
import hashlib
import os
from pathlib import Path
import pty
import re
import select
import shutil
import struct
import subprocess
import tarfile
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.31.0"
ENTER = b"\r"
DOWN = b"\x1b[B"
ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]|\r")

FAKE_ARCHDEV = f"""#!/bin/sh
state="$FAKE_STATE"
case "$1 ${{2:-}}" in
  "--version "*) echo {VERSION} ;;
  "auth status")
    if [ -f "$state/signed-in" ]; then
      printf 'Status: Authenticated (org)\\nEmail: dev@example.test\\nOrganization: Example Org\\n'
    else
      echo 'Error: Not authenticated. Run: archdev auth login' >&2
      exit 1
    fi
    ;;
  "auth login")
    # Stands in for the copy/paste flow: the code is typed at the terminal.
    printf 'Paste the code from your browser: '
    IFS= read -r code
    [ "$code" = good ] || {{ echo 'Error: That code is not valid' >&2; exit 1; }}
    touch "$state/signed-in"
    ;;
  "setup "*)
    printf '%s\\n%s\\n' "$*" "$PWD" >"$state/setup"
    if [ -n "${{FAKE_SETUP_FAIL:-}}" ]; then echo 'Error: hooks directory is read-only' >&2; exit 1; fi
    echo 'Recorded the one-time installation announcement (evt_1).'
    ;;
  *) exit 1 ;;
esac
"""


class InstallerPromptTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.state = self.root / "state"
        self.tools = self.root / "tools"
        self.release = self.root / "release"
        for directory in (self.home, self.state, self.tools, self.release):
            directory.mkdir()
        self.build_release()
        # Repository placement is offered only inside a Git repository with
        # Node.js on PATH; the hooks themselves never run here.
        (self.tools / "node").write_text("#!/bin/sh\nexit 0\n")
        (self.tools / "node").chmod(0o755)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.env = {
            "HOME": str(self.home),
            "PATH": f"{self.tools}:/usr/bin:/bin",
            "SHELL": "/bin/bash",
            "TERM": "xterm-256color",
            "LANG": "C.UTF-8",
            "FAKE_STATE": str(self.state),
        }

    def build_release(self):
        fake = self.root / "archdev"
        fake.write_text(FAKE_ARCHDEV)
        fake.chmod(0o755)
        sums = []
        for target in ("darwin-arm64", "darwin-x64", "linux-arm64", "linux-x64", "linux-x64-musl"):
            archive = self.release / f"archdev-{target}.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                tar.add(fake, arcname="archdev")
            sums.append(f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n")
        (self.release / "SHA256SUMS").write_text("".join(sums))

    # -- pty driver ---------------------------------------------------------

    def start(self, *args, cwd=None, **env):
        """Run the one-liner in a pty. The wrapper reports whether the
        terminal settings came back unchanged, then exits with the
        installer's status."""
        command = (
            'before="$(stty -g)"; trap ":" INT; '
            f'cat {ROOT / "install.sh"} | bash -s -- --base-url file://{self.release} '
            f'--version {VERSION} --install-dir "$HOME/.local/bin" "$@"; status=$?; '
            '[ "$(stty -g)" = "$before" ] && echo TTY-RESTORED || echo TTY-CHANGED; exit $status'
        )
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(cwd or self.root)
            os.execve("/bin/bash", ["bash", "-c", command, "installer", *args], dict(self.env, **env))
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))
        self.pid, self.fd, self.output, self.seen = pid, fd, b"", 0
        self.addCleanup(self.close)

    def close(self):
        try:
            os.close(self.fd)
        except OSError:
            pass
        try:
            os.kill(self.pid, 9)
            os.waitpid(self.pid, 0)
        except (OSError, ChildProcessError):
            pass

    def read_some(self, timeout):
        ready, _, _ = select.select([self.fd], [], [], timeout)
        if not ready:
            return False
        try:
            chunk = os.read(self.fd, 65536)
        except OSError:
            return None
        if not chunk:
            return None
        self.output += chunk
        return True

    def text(self):
        return ANSI.sub(b"", self.output).decode("utf-8", "replace")

    def expect(self, pattern, timeout=20):
        """Wait for `pattern` to appear after the last match."""
        deadline = time.monotonic() + timeout
        regex = re.compile(pattern)
        while True:
            match = regex.search(self.text(), self.seen)
            if match:
                self.seen = match.end()
                return match
            remaining = deadline - time.monotonic()
            if remaining <= 0 or self.read_some(remaining) is None:
                self.fail(f"never saw {pattern!r}; output:\n{self.text()}")

    def answer(self, question, *keys):
        """Wait for a menu to finish drawing, then press keys."""
        self.expect(re.escape(question))
        self.expect(r"select")
        for key in keys:
            os.write(self.fd, key)
            time.sleep(0.05)

    def finish(self, timeout=30):
        """Wait for the installer to exit; one still waiting at a prompt fails
        the test instead of hanging it."""
        deadline = time.monotonic() + timeout
        while True:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                break
            if time.monotonic() >= deadline:
                self.fail(f"installer did not exit; output:\n{self.text()}")
            self.read_some(0.1)
        while self.read_some(0.1):
            pass
        self.assertIn("TTY-RESTORED", self.text())
        return os.waitstatus_to_exitcode(status)

    def setup_call(self):
        path = self.state / "setup"
        return path.read_text().splitlines() if path.exists() else None

    # -- scenarios ----------------------------------------------------------

    def test_sign_in_then_global_setup_outside_a_repository(self):
        # The full first-run path outside a repository: browser sign-in, then
        # setup installs globally without asking anything else.
        self.start()
        self.answer("Sign in now?", ENTER)
        self.expect("Paste the code")
        os.write(self.fd, b"good\r")
        self.expect("Signed in as dev@example.test")
        self.assertEqual(self.finish(), 0)
        self.assertNotIn("Where should ArchDev install", self.text())
        self.assertEqual(self.setup_call(), ["setup --scope user --reporting enabled", str(self.root)])
        self.assertIn("Skill and hooks installed for this user", self.text())
        self.assertIn("is ready", self.text())
        self.assertIn("Set up this repository with ArchDev.", self.text())

    def test_repository_placement_runs_setup_in_the_repository(self):
        (self.state / "signed-in").touch()
        self.start(cwd=self.repo)
        self.expect("Signed in as dev@example.test")
        self.answer("Where should ArchDev install its skill and hooks?", DOWN, ENTER)
        self.assertEqual(self.finish(), 0)
        self.assertEqual(self.setup_call(), ["setup --scope repository --reporting enabled", str(self.repo)])
        self.assertIn("Start your coding agent in this repository", self.text())

    def test_enter_in_a_repository_installs_globally(self):
        (self.state / "signed-in").touch()
        self.start(cwd=self.repo)
        self.answer("Where should ArchDev install its skill and hooks?", ENTER)
        self.assertEqual(self.finish(), 0)
        self.assertEqual(self.setup_call(), ["setup --scope user --reporting enabled", str(self.repo)])

    def test_a_digit_jumps_to_that_option(self):
        (self.state / "signed-in").touch()
        self.start(cwd=self.repo)
        self.answer("Where should ArchDev install its skill and hooks?", b"2", ENTER)
        self.assertEqual(self.finish(), 0)
        self.assertEqual(self.setup_call()[0], "setup --scope repository --reporting enabled")

    @unittest.skipIf(shutil.which("node", path="/usr/bin:/bin"), "a system node is on the test PATH")
    def test_without_node_a_repository_installs_globally_without_asking(self):
        # Repository hooks need Node.js; with no node on PATH there is no choice.
        (self.tools / "node").unlink()
        (self.state / "signed-in").touch()
        self.start(cwd=self.repo)
        self.assertEqual(self.finish(), 0)
        self.assertNotIn("Where should ArchDev install", self.text())
        self.assertEqual(self.setup_call()[0], "setup --scope user --reporting enabled")

    def test_skipping_sign_in_skips_setup(self):
        self.start()
        self.answer("Sign in now?", DOWN, ENTER)
        self.assertEqual(self.finish(), 0)
        self.assertIsNone(self.setup_call())
        self.assertIn("Sign in first, then run: archdev setup", self.text())

    def test_failed_sign_in_still_installs(self):
        self.start()
        self.answer("Sign in now?", ENTER)
        self.expect("Paste the code")
        os.write(self.fd, b"wrong\r")
        self.expect("Sign-in did not finish")
        self.assertEqual(self.finish(), 0)
        self.assertIsNone(self.setup_call())
        self.assertTrue((self.home / ".local/bin/archdev").exists())

    def test_failed_setup_shows_the_error_and_exits_nonzero(self):
        (self.state / "signed-in").touch()
        self.start(FAKE_SETUP_FAIL="1")
        self.assertEqual(self.finish(), 1)
        self.assertIn("hooks directory is read-only", self.text())
        self.assertIn("then run: archdev setup --scope user", self.text())

    def test_interrupt_at_a_prompt_restores_the_terminal(self):
        self.start()
        self.answer("Sign in now?", b"\x03")
        self.assertEqual(self.finish(), 130)

    def test_plain_terminal_uses_numbered_prompts(self):
        self.start(TERM="dumb")
        self.expect(r"Sign in now\?")
        self.expect(r"Choose \[1\]: ")
        os.write(self.fd, b"2\r")
        self.assertEqual(self.finish(), 0)
        self.assertIn("Skipped. Sign in later", self.text())

    def test_rejected_archdev_token_explains_why(self):
        self.start(ARCHDEV_TOKEN="rejected")
        self.assertEqual(self.finish(), 0)
        self.assertIn("ARCHDEV_TOKEN did not sign you in", self.text())
        self.assertIn("Not authenticated", self.text())
        self.assertNotIn("Sign in now?", self.text())


if __name__ == "__main__":
    unittest.main()
