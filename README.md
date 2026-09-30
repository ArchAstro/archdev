# ArchDev

Review coding-agent changes by risk and share what your team learns through
ArchDev's organization stream.

## Install through your coding agent

Paste this prompt into your agent:

```text
Read https://archdev.ai/install.md and set up ArchDev for me.
```

Your agent checks the required software, installs ArchDev, and helps you sign
in. It asks where to configure the setup and waits for your answer:

- **For me on this machine:** personal setup across repositories.
- **For this repository:** shareable setup files for your teammates.

Before enabling activity reporting, it explains organization stream visibility
and asks for your approval. Each teammate installs software and signs in for
themselves. No credentials are shared through the repository, and the agent
won't commit or push setup files without permission.

See the [installation guide](https://docs.archdev.ai/docs/start-here/install)
for what to expect, then ask your agent to review your changes with ArchDev.

## Distribution sources

This repository owns public installers, release metadata, downloadable
binaries, and agent skills. The implementation and release build stay in the
private firstlanding repository. Report installation and packaging problems
with a GitHub issue here.

## License

The files in this repository (including installers, skills, and documentation)
are licensed under the [MIT License](LICENSE). Release binaries are built from
a separate private source repository; this license does not apply to those
binaries.
