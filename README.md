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

The release archive installs `archdev`. The Unix installer also configures
Bash, Zsh, or Fish completions for the active shell.

## Install Tasks

Tasks turns a conversation or an existing coding-agent plan into a dependency
graph for browser review. The agent opens the review, reads your feedback,
revises the same plan, and verifies that **Approve & save** saved the Tasks.
The skill installs or updates ArchDev on first use; no Factory or daemon is
required.

```bash
npx skills add ArchAstro/archdev --skill tasks
```

Then ask your agent:
“Turn our plan into Tasks, open the web review, and iterate on my feedback.”

## Skills (deprecated)

The agents, inspect, jobs, and rooms skills have moved to `deprecated/` and
are no longer published.

## Repository scope

This repository owns public distribution: installers, release
metadata, and downloadable binaries. ArchDev's source and release build stay
in firstlanding. Report installation and packaging problems with a GitHub
issue here.
