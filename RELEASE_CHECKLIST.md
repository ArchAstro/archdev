# Cloud installer release check

Run this when publishing `install-cloud.sh` or changing a CLI release's cloud
installation, hooks, or authentication behavior.

- [ ] `bash -n install-cloud.sh` and `python3 scripts/test-cloud-installer.py` pass.
  The Installer Smoke Test workflow runs the process contracts on Linux for
  pull requests, pushes to main, and manual dispatch. Its existing fixture
  tests cover archive installation separately. These are local contract tests,
  not proof of Claude's network proxy or hook dispatch.
- [ ] After the script is published at the public main-branch URL, configure a
  personal Claude Code web environment using the README's one-line snippet,
  network hosts, and token variable. Rebuild the snapshot so setup runs.
- [ ] Start a cloud session with the ArchDev skill available. Confirm setup
  installed the CLI, the SessionStart contract appeared, and `archdev auth
  status` and `archdev log messages --limit 1` succeed without a manual login.
  Confirm presence appears and a requested team-room post succeeds in auto
  mode without a credential appearing in the transcript. Record the CLI
  version, date, and cloud session reference in the release evidence.
- [ ] When section 3.1's direct `ARCHDEV_TOKEN` resolution is in the released
  CLI, remove the temporary login-hook block and verify the refreshed cloud
  environment authenticates without creating `credentials.json`. Also remove
  the exact legacy login hook from existing settings if the refresh retains
  them; preserve all unrelated hooks.

Known temporary limitation: Claude dispatches SessionStart hooks in parallel.
The login hook does not guarantee authentication before the first presence
update. Section 3.1's direct token resolution closes this gap. Do not wrap the
stock startup command to impose ordering: CLI hook self-repair restores it.
Check the first presence update explicitly in the live proof.

The live cloud check must be completed after publication; a passing local
fixture run does not complete it.
