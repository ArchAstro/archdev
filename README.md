# ArchDev CLI

Public distribution repository for the ArchDev CLI. GitHub Releases contain
binaries built and tested from the private firstlanding source repository.

## Install

GitHub Releases are the canonical distribution path.

### macOS

Prefer Homebrew:

```bash
brew install ArchAstro/tools/archdev
```

Or use the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/ArchAstro/archdev/main/install.sh | bash
```

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/ArchAstro/archdev/main/install.sh | bash
```

### Windows

```powershell
irm https://raw.githubusercontent.com/ArchAstro/archdev/main/install.ps1 | iex
```

The release archive installs both `archdev` and its `archdev-dashboard`
sidecar. The Unix installer also configures Bash, Zsh, or Fish completions for
the active shell.

## Install Rooms independently

Rooms gives a coding agent shared team recall and structured work updates. It
does not require the rest of the ArchDev workflow, a daemon, or a resident
agent. The skill installs or updates the ArchDev CLI on first use.

Install for your machine:

```bash
npx skills add ArchAstro/archdev --skill rooms --global --yes
```

Or install only in the current repository:

```bash
npx skills add ArchAstro/archdev --skill rooms --yes
```

Then ask your coding agent to connect to the company Room, search what the team
knows, or start a substantial piece of work. The first participant creates the
Room; later participants join the same Room automatically.

## Repository scope

This repository owns public distribution: installers, skills, release
metadata, and downloadable binaries. ArchDev's source and release build stay
in firstlanding. Report installation and packaging problems with a GitHub
issue here.
