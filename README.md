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

## Install one domain as an agent skill

ArchDev's domain skills are independently installable. Each skill bootstraps a
compatible ArchDev CLI on first use and configures only the capability it owns.

| Skill | Use it for | ArchDev login | Local runner |
| --- | --- | --- | --- |
| `tasks` | Plans, dependencies, claims, and fenced completion | Required for shared Tasks | Not installed |
| `jobs` | Exact-commit pipelines, logs, retries, and repository automation | Not required | Installed only by `jobs setup` |

Install a skill for your machine:

```bash
npx skills add ArchAstro/archdev --skill tasks --global --yes
npx skills add ArchAstro/archdev --skill jobs --global --yes
```

Or omit `--global` to install into the current repository:

```bash
npx skills add ArchAstro/archdev --skill tasks --yes
npx skills add ArchAstro/archdev --skill jobs --yes
```

The Tasks skill never runs umbrella setup or installs the Jobs runner. The Jobs
skill does not log in or configure a model provider; it runs `jobs setup` only
when durable local automation is requested.

## Repository scope

This repository owns public distribution: installers, skills, release metadata,
and downloadable binaries. ArchDev's source and release build stay in
firstlanding. Report installation and packaging problems with a GitHub issue
here.
