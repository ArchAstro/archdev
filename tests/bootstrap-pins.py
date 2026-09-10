"""Check shipped installer pins against actual immutable upstream bytes; never execute them."""
import hashlib
from pathlib import Path
import re
import subprocess

repo = Path(__file__).resolve().parent.parent
for extension in ("sh", "ps1"):
    scripts = sorted(repo.glob(f"skills/*/scripts/bootstrap.{extension}"))
    assert len(scripts) == 5, "Expected five public skill bootstraps"
    pins = []
    for script in scripts:
        source = script.read_text()
        if extension == "sh":
            revision = re.search(r'^installer_revision="([a-f0-9]{40})"$', source, re.M)
            digest = re.search(r'^installer_sha256="([a-f0-9]{64})"$', source, re.M)
        else:
            revision = re.search(r'/ArchAstro/archdev/([a-f0-9]{40})/install.ps1', source)
            digest = re.search(r'\$installerSha256 = "([a-f0-9]{64})"', source)
        assert revision and digest, f"Missing immutable pin in {script}"
        pins.append((revision[1], digest[1]))
    assert len(set(pins)) == 1, f"Installer pins disagree across {extension} skills"
    revision, digest = pins[0]
    # Cross the real HTTPS boundary and compare bytes without executing the installer.
    url = f"https://raw.githubusercontent.com/ArchAstro/archdev/{revision}/install.{extension}"
    content = subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--proto", "=https", url])
    assert hashlib.sha256(content).hexdigest() == digest, f"Incorrect installer digest for {url}"
    print(f"PASS: all five {extension} bootstraps pin the verified upstream installer bytes")
