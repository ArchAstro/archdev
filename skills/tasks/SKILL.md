---
name: tasks
description: Use when someone asks to plan work, create or import a dependency graph, find ready or blocked work, claim and fence a task, update task context, manage blockers or links, or complete shared work through ArchDev Tasks.
---

# Tasks

ArchDev Tasks is the shared work ledger. It uses the ArchDev user session, but
it does not need `archdev setup`, a Jobs runner, a model provider, or repository
configuration.

## Start

Resolve the absolute path of this loaded `SKILL.md` from the host's skill
inventory. Do not derive it from the current repository. Bootstrap ArchDev from
that directory.

Unix:

```sh
skill_file="/absolute/path/to/loaded/tasks/SKILL.md"
skill_dir="$(cd -P "$(dirname "$skill_file")" && pwd)"
archdev="$(bash "$skill_dir/scripts/bootstrap.sh")"
```

Windows PowerShell:

```powershell
$skillFile = 'C:\absolute\path\to\loaded\tasks\SKILL.md'
$skillDir = Split-Path -Parent (Resolve-Path -LiteralPath $skillFile)
$archdev = & powershell -NoProfile -File "$skillDir\scripts\bootstrap.ps1"
```

If bootstrap fails, report its error and point to the official ArchDev
installer. Run `"$archdev" tasks guide` before changing shared work; it is the
CLI's current claim, lease, dependency, and completion contract.

Commands that only print help, the guide, or the graph schema work signed out.
Before reading or changing server-backed Tasks, run `"$archdev" auth status`.
On a nonzero result, run `"$archdev" auth login`, let the user finish browser
sign-in, then retry. Do not run umbrella setup or install Jobs for Tasks.

## Inspect and plan

Search before creating duplicate work. JSON output is preferred when another
agent will consume the result.

```sh
"$archdev" --json tasks search "retry handling"
"$archdev" --json tasks ready --explain
"$archdev" --json tasks blocked
"$archdev" --json tasks show "<task-id>"
```

`tasks ready` is a snapshot, not an ownership guarantee. Only `tasks claim` is
the atomic gate.

For one task:

```sh
"$archdev" --json tasks create "Add retry handling" --priority 1 --tag reliability
```

For a dependency-aware plan, render the schema, author a JSON graph, inspect it,
and then import it. Do not translate an existing plan into a series of
independent creates that can leave half a graph behind.

```sh
"$archdev" tasks graph schema > task-graph.schema.json
"$archdev" --json tasks graph import --file plan.json
"$archdev" --json tasks deps add "<task-id>" --blocked-by "<prerequisite-id>"
"$archdev" --json tasks deps list "<task-id>"
"$archdev" --json tasks deps remove "<task-id>" --blocked-by "<prerequisite-id>"
"$archdev" --json tasks deps cycles
```

## Claim and fence execution

Claim immediately before starting implementation:

```sh
"$archdev" --json tasks claim "<task-id>" --session-name "short purpose"
```

Keep the returned `lease.id` and `session_id`. Use both values on every fenced
update and completion. Never borrow identifiers from another process or claim.

```sh
"$archdev" --json tasks update "<task-id>" --description "Current verified state" --lease-id "<lease-id>" --session-id "<session-id>"
"$archdev" --json tasks comment "<task-id>" "Concrete progress, blocker, or verification result"
"$archdev" --json tasks links add "<task-id>" "<pull-request-or-object>"
"$archdev" --json tasks links remove "<task-id>" "<pull-request-or-object>"
"$archdev" --json tasks close "<task-id>" --lease-id "<lease-id>" --session-id "<session-id>"
```

If work stops without completion, release the exact lease instead of leaving
ownership stale:

```sh
"$archdev" --json tasks release "<task-id>" --lease-id "<lease-id>" --session-id "<session-id>"
```

Reopen completed work only when the user asks to resume that shared task:

```sh
"$archdev" --json tasks reopen "<task-id>"
```

A stale-lease or ownership refusal is authoritative. Re-read the task and ask
the user before taking over someone else's work.

## Room-owned work

Room work is still a Task. Use the canonical Tasks namespace and an explicit
Room ID:

```sh
"$archdev" --json tasks list --room "<room-id>"
"$archdev" --json tasks create "Watch deploy health" --room "<room-id>" --kind daily
"$archdev" --json tasks close "<task-id>" --room "<room-id>"
```

Do not use the deprecated `rooms jobs` spelling. Do not create, claim, update,
close, release, link, comment on, or import Tasks unless the user requested the
corresponding shared-work mutation. Never put secrets or customer data in a
Task, comment, or graph.
