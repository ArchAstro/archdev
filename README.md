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

## Repository scope

This repository owns public distribution: installers, release metadata, and
downloadable binaries. ArchDev's source and release build stay in firstlanding.
Report installation and packaging problems with a GitHub issue here.
