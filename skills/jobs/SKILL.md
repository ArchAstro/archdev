---
name: jobs
description: Use when someone asks to run durable repository automation, execute a pipeline against an exact commit, inspect or retry a job, read persisted logs, manage the local runner, submit or sync a repository, automate review delivery, or recover conflicts through ArchDev Jobs.
---

# Jobs

ArchDev Jobs runs repository automation in isolated worktrees against exact
commits. Jobs is local: do not authenticate an ArchDev user or configure a model
provider unless a pipeline step independently requires one.

## Start

Resolve the absolute path of this loaded `SKILL.md` from the host's skill
inventory. Do not derive it from the current repository. Bootstrap ArchDev from
that directory.

Unix:

```sh
skill_file="/absolute/path/to/loaded/jobs/SKILL.md"
skill_dir="$(cd -P "$(dirname "$skill_file")" && pwd)"
archdev="$(bash "$skill_dir/scripts/bootstrap.sh")"
```

Windows PowerShell:

```powershell
$skillFile = 'C:\absolute\path\to\loaded\jobs\SKILL.md'
$skillDir = Split-Path -Parent (Resolve-Path -LiteralPath $skillFile)
$archdev = & powershell -NoProfile -File "$skillDir\scripts\bootstrap.ps1"
```

If bootstrap fails, report its error and point to the official ArchDev
installer. Run all repository commands from the intended Git checkout.

Inspect configuration and runner state before changing either:

```sh
"$archdev" check
"$archdev" --json jobs runner status
"$archdev" --json jobs list
```

A stopped or absent runner is not an authentication failure. These inspection
commands may return nonzero before first setup; when durable work was requested,
continue with `jobs setup`. Do not run `archdev auth login`, `archdev agents
setup`, provider login, or umbrella setup for Jobs.

## Choose foreground or durable execution

Use `--here` only when the user asked to run a pipeline immediately in the
current checkout. This can mutate the checkout and does not create durable job
history:

```sh
"$archdev" jobs run "<pipeline>" --here
```

For work that must survive the terminal, first enable local automation. This
installs or starts the per-user runner and registers the current repository; it
does not configure model access:

```sh
"$archdev" jobs setup
```

Commit the intended input before submission. A durable named run captures the
current committed `HEAD`, ignores later working-tree edits, and disables
automatic publication unless the pipeline explicitly publishes:

```sh
"$archdev" --json jobs run "<pipeline>"
```

Keep the returned job ID.

## Observe and control jobs

```sh
"$archdev" --json jobs show "<job-id>"
"$archdev" jobs logs "<job-id>"
"$archdev" --json jobs cancel "<job-id>"
"$archdev" --json jobs retry "<job-id>"
```

Retry only failed non-PR jobs. Pull-request retries belong to the PR watcher.
Cancellation can be asynchronous; re-read the job until it reaches a terminal
state rather than reporting success from the request alone.

Ordinary cleanup targets terminal jobs:

```sh
"$archdev" --json jobs clean --status succeeded failed cancelled
```

`jobs clean --all` stops the runner and can permanently delete active jobs and
owned artifacts. Run it only after explicit user approval of the exact cleanup.

## Runner lifecycle

Use the runner namespace instead of the deprecated `daemon` commands:

```sh
"$archdev" --json jobs runner doctor
"$archdev" jobs runner start
"$archdev" jobs runner stop
"$archdev" jobs runner uninstall
```

`runner uninstall` removes the native service but preserves repositories, job
history, reports, and project configuration. Run stop or uninstall only when the
user requested that local service change.

## Repository delivery

`jobs setup` normally enables the current repository. Use the explicit
repository lifecycle when diagnosing or scripting it:

```sh
"$archdev" jobs repo enable
"$archdev" jobs repo submit
"$archdev" jobs repo sync
"$archdev" jobs repo disable
```

`repo submit` sends committed `HEAD` to the private runner and can rebase the
submitted branch according to repository policy. Check `git status`, the
current branch, and the intended commit first. `repo sync` updates a clean
source checkout only when the recorded identity fences match.

For event-shaped diagnostics, submit only a payload whose schema the selected
binding expects:

```sh
"$archdev" --json jobs trigger one_off --payload '{"prompt":"Run the focused verification"}'
```

Never invent successful logs, publication, or settlement. Inspect the terminal
job, attempts, and persisted output. Do not expose private worktree paths,
credentials, or customer data in prompts, payloads, or reports.
