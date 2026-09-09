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

## Install Tasks independently

Tasks turns a conversation or an existing coding-agent plan into a dependency
graph for browser review. The agent opens the review, reads your feedback,
revises the same plan, and verifies that **Approve & save** saved the Tasks.
The skill installs or updates ArchDev on first use; no Factory or daemon is
required.

```bash
npx skills add ArchAstro/archdev --skill tasks --global --yes
```

Omit `--global` to install only in the current repository. Then ask your agent:
“Turn our plan into Tasks, open the web review, and iterate on my feedback.”

## Install Jobs independently

Jobs guides a coding agent through repository setup, private submissions,
pipeline and model configuration, durable job execution, automatic PR watching,
and recovery. It follows the CLI's setup audit and installs ArchDev if needed.
Tasks are optional: `archdev jobs repo submit` (the canonical replacement for
`archdev push`) sends any committed branch through its configured pipeline.
Use `--task <task-id>` only when you want to associate an existing Task.

```bash
npx skills add ArchAstro/archdev --skill jobs --global --yes
```

Omit `--global` for repository-only installation. Ask your agent to configure
repository automation, run a pipeline, or investigate a failed job.

## Install Agents independently

Agents guides interactive and headless coding, Factory, saved sessions,
workflows, definitions, and worktree/local-work management. It also covers
`settings provider`: connect your ChatGPT or Grok subscription through OAuth,
use an API key when chosen, manage accounts, and select the intended model.
Agent-only onboarding does not install Jobs.

```bash
npx skills add ArchAstro/archdev --skill agents --global --yes
```

Omit `--global` for repository-only installation. Ask your agent to connect your
provider, run a coding session, resume existing work, or set up Factory.

## Repository scope

This repository owns public distribution: installers, skills, release
metadata, and downloadable binaries. ArchDev's source and release build stay
in firstlanding. Report installation and packaging problems with a GitHub
issue here.
