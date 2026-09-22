---
name: archdev
description: Core ArchDev workflow — use for anything involving ArchDev. Covers archdev CLI setup, upgrade, login, and model access; archdev.json configuration and validation (check); repo onboarding and readiness (repo status, repo init); mapping a repo's plans, tasks, agents, and review workflow into the activity taxonomy (repo map); session start/stop hooks (repo hook setup); reporting build events as unstructured notes or schema-validated payloads (archdev log, log --event); and observing agent activity (repo monitor). Load at session start whenever the archdev CLI is installed, the repo contains archdev.json, or the task touches plans, tasks, sessions, commits, PRs, or harness hooks.
---

# ArchDev

Requires CLI 0.45.3 or newer (the `repo` namespace, `log --event`,
harness hooks, plus `extract brief`, `extract finalize`, and
`log --assessment` for sealed risk assessments on plan/task/pr events).
The bootstrap script below upgrades older installs automatically.

Three phases, in order: Bootstrap → Map → Monitor. Each phase has a
reference file with the concrete commands.

## 0. Resolve the CLI and check readiness

Resolve the absolute directory containing this loaded `SKILL.md`,
independent of the current repository, and bootstrap from there:

Bash/Zsh:

```sh
archdev="$(bash /absolute/path/to/archdev/scripts/bootstrap.sh)"
```

Fish:

```fish
set archdev (bash /absolute/path/to/archdev/scripts/bootstrap.sh)
```

PowerShell:

```powershell
$archdev = & powershell -NoProfile -File 'C:\absolute\path\to\archdev\scripts\bootstrap.ps1'
```

Examples below use `"$archdev"`; PowerShell uses `& $archdev`. Prefer
global `--json` for machine-readable results. If bootstrap fails, report
the error and point to the [official installer](https://github.com/ArchAstro/archdev#install).

Then run `"$archdev" repo status --json`. It reports every readiness
check (version, login, model access, repo wiring, taxonomy, hooks) as
ok/missing with its remediation — follow them top to bottom, re-run
until all ok, then continue at the phase it points at.

## 1. Bootstrap

Read [bootstrap.md](references/bootstrap.md). Goal: CLI installed and
current, user logged in (`auth status`), model access configured
(`settings provider status` — separate from login), repo wiring valid
(`check`). Do not run full `archdev setup` merely to inspect state.

## 2. Map

Read [map.md](references/map.md). Goal: repo opted in via `archdev.json`
(`repo init` when missing; personal overrides stay in gitignored
`archdev.local.json`), plus the `activity` taxonomy describing how this
repo plans, codes, reviews, and takes instruction. End by installing
start + stop hooks (`repo hook setup`) so session coverage starts
immediately.

## 3. Monitor

Read [monitor.md](references/monitor.md). Goal: the agent self-checks at
stopping points against the mapped taxonomy and reports hits with
`archdev log` — free text (`agent.message`) or schema-validated
payloads (`log --event`). Every post carries human-readable text: structured
posts add `--message "<one-line summary>"` as the headline over the
CLI-rendered payload summary. A PR created (or updated to a new head)
outside `archdev publish` gets its hunk review annotations stored with
`extract run pr.review-annotations` before the `pr.*` post. No daemon,
no log tailing: the model is the sensor until an event proves reliable enough to promote into the stop
hook.
