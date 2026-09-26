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

## Skills and harness hooks

The `archdev` CLI installs the skills and the harness hooks. There is no
Claude Code plugin.

```bash
archdev setup                              # first run: login, repo, hooks for every harness; offers skills
archdev setup --skills                     # only the skills, for every detected coding tool
archdev repo hook setup                    # only the hooks, for every harness on this machine
archdev repo hook setup --harness claude   # hooks for one harness: claude, codex, grok, pi, or archdev
archdev repo status                        # check CLI, login, model access, repo wiring, and hooks
```

`archdev setup --skills` runs
`npx skills add ArchAstro/archdev --skill '*' --global --agent <detected tools>`.
Most `archdev` commands run inside Claude Code or Codex reinstall that
harness's hooks when they are missing or stale (not in Factory or daemon
sessions), and the `archdev` skill's bootstrap script installs them for the
harness running it (Claude Code, Codex, or Grok).

`archdev repo hook setup --uninstall --harness <name>` removes a harness's
hooks and records the opt-out in `~/.archdev/hook-opt-out.json`. Full
`archdev setup`, the self-heal, and the skill bootstrap leave that harness
alone. `archdev repo hook setup` without `--harness`, or with `--force`,
reinstalls it and clears the opt-out.

The hooks give every session the ArchDev contract, including sessions that
never load the skill. In Claude Code they also run for subagents:
SubagentStart tells each subagent to load the `archdev` skill.

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
