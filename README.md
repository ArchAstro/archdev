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

## Install skills for your coding tools

Install all five skills and follow the prompts to choose your coding tools
and project or global installation:

```sh
npx skills add ArchAstro/archdev
```

Or choose an individual skill below. Node.js and npm are required.
The skills install or update the ArchDev CLI on first use.

## Install Rooms independently

Rooms gives a coding agent shared team recall and structured work updates. It
does not require the rest of the ArchDev workflow, a daemon, or a resident
agent. The skill installs or updates the ArchDev CLI on first use.

```bash
npx skills add ArchAstro/archdev --skill rooms
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
npx skills add ArchAstro/archdev --skill tasks
```

Then ask your agent:
“Turn our plan into Tasks, open the web review, and iterate on my feedback.”

## Install Jobs independently

Jobs guides a coding agent through repository setup, private submissions,
pipeline and model configuration, durable job execution, automatic PR watching,
and recovery. It follows the CLI's setup audit and installs ArchDev if needed.
Tasks are optional: `archdev jobs repo submit` (the canonical replacement for
`archdev push`) sends any committed branch through its configured pipeline.
Use `--task <task-id>` only when you want to associate an existing Task.

```bash
npx skills add ArchAstro/archdev --skill jobs
```

Ask your agent to configure repository automation, run a pipeline, or
investigate a failed job.

## Install Agents independently

Agents guides interactive and headless coding, Factory, saved sessions,
workflows, definitions, and worktree/local-work management. It also covers
`settings provider`: connect your ChatGPT or Grok subscription through OAuth,
use an API key when chosen, manage accounts, and select the intended model.
Agent-only onboarding does not install Jobs.

```bash
npx skills add ArchAstro/archdev --skill agents
```

Ask your agent to connect your provider, run a coding session, resume existing
work, or set up Factory.

## Install Reviews independently

Reviews drives local browser code review: capture changes, stream inline
feedback to the coding agent, fix and verify, then open a fresh snapshot.
It also covers GitHub access through the site, AI review workflows,
publication, and the Jobs handoff for automated PR remediation.

```bash
npx skills add ArchAstro/archdev --skill reviews
```

Ask your coding agent to open local review and iterate on your feedback. No
Task, PR, or daemon is required for that local loop, and the agent can author
the risk/theme annotations itself with `reviews manifest` and
`reviews local --metadata`, with no model key or ArchDev login.

## Repository scope

This repository owns public distribution: installers, skills, release
metadata, and downloadable binaries. ArchDev's source and release build stay
in firstlanding. Report installation and packaging problems with a GitHub
issue here.

## Skill bootstrap integrity

Each skill includes Bash and PowerShell bootstraps. When installation or an
upgrade is needed, they download the installer from a fixed GitHub commit,
verify its SHA-256 digest against the value shipped in the skill, and execute
it only on a match. Downloads are temporary and removed after success or failure.
Skill bootstraps ignore installer/release URL overrides and keep archive verification
enabled. There is no digest environment override. Updating the installer
requires reviewing its source and updating the pinned revision and digest together.

This protects the bootstrap-to-installer boundary. It does not prove that the
installer or CLI is harmless: the installer remains trusted code, and release
archives are checked against checksums published with the release. Existing
compatible CLI executables on PATH are reused without reinstalling them.

`tests/agents-skill.sh`, `tests/jobs-skill.sh`, `tests/reviews-skill.sh`,
`tests/rooms-skill.sh`, and `tests/tasks-skill.sh` exercise packaged Unix skills.
`tests/skill-bootstrap.ps1` checks all five PowerShell bootstraps, including
rejection of untrusted installer bytes before execution. `tests/bootstrap-pins.py`
checks the shipped digests against the actual pinned upstream script bytes without
executing them. These run in the
Installer Smoke Test workflow on pull requests and pushes to main.
