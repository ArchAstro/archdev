---
name: agents
description: Use to set up and run ArchDev coding agents, resume or stop sessions, run Factory or workflows, inspect custom agent definitions, manage worktrees and local work, or configure settings provider with ChatGPT/Grok subscriptions, API keys, and model aliases.
---

# Agents

Use ArchDev's public `agents` commands to run and manage coding sessions.
You drive setup, select the intended execution mode, retain the returned
identities, and inspect completion or hand the interactive session to the
human. Tasks are optional for ordinary coding sessions; do not create a Task
or DAG just to start an agent. Factory also supports session-led one-off work.

## 1. Bootstrap

Resolve the absolute directory containing this loaded `SKILL.md`, independently
of the current repository. Bootstrap returns the executable's absolute path on
stdout and installs or upgrades ArchDev if its Agents/provider commands are
missing. It does not log in or install a daemon itself.

Bash/Zsh:

```sh
archdev="$(bash /absolute/path/to/agents/scripts/bootstrap.sh)"
```

Fish:

```fish
set archdev (bash /absolute/path/to/agents/scripts/bootstrap.sh)
```

PowerShell:

```powershell
$archdev = & powershell -NoProfile -File 'C:\absolute\path\to\agents\scripts\bootstrap.ps1'
```

Examples below use `"$archdev"`; PowerShell uses `& $archdev` with the same
arguments. Prefer global `--json` for commands that expose structured results.
Some commands, such as provider accounts, still print text. If bootstrap fails,
report the error and point to the [official installer](https://github.com/ArchAstro/archdev#install).
Use help from the installed version; do not assume a new command exists because
an older CLI prints generic help with a successful exit code.

## 2. Connect account and model access

Read [providers.md](references/providers.md) when choosing providers, using
subscriptions/API keys, managing accounts, or changing models.

1. Inspect existing `archdev.json`, the gitignored `archdev.local.json`, and
   applicable user model settings. Preserve configured provider choices.
2. From the intended Git repository, run `"$archdev" agents setup` for
   agent-only onboarding. It connects ArchDev/model access and validates agent
   model settings without installing Jobs, private Git remotes, or Factory
   automation. It may persist a missing `factory.model` default after validation.
3. Choose the provider interactively, or use `agents setup --provider openai
   --provider-email <email>` for ChatGPT OAuth; use `xai` for Grok or `archdev`
   for the ArchDev model router. The setup selector is `archdev`; the model
   provider identifier for that router is `platform`.
4. Keep browser/device-code login running while the human signs in. Check
   `auth status` separately from `settings provider status`: ArchDev identity
   and BYO model credentials are different authentications. BYO does not remove
   ArchDev's account-login requirement.
5. Inspect the chosen provider's model list and select the intended model
   explicitly with `--model <selector>` or `/model` inside the TUI. A provider
   login alone is not proof the next request uses that provider. Verify the
   actual selected model and a small authorized request when setup requires it.

For existing model access, go straight to the requested operation. Do not run
full `archdev setup` merely to inspect a session or log in to ChatGPT.

## 3. Choose the execution mode

| Intent | Command |
| --- | --- |
| Interactive coding session | `agents start [prompt] [--model <selector>]` |
| One headless request | `agents run <prompt> [--model <selector>] [--output-format json]` |
| Continue a headless session | `agents run <prompt> --resume <session-id> --output-format json` |
| Resume an ordinary or Factory TUI | `agents resume <session-id> [--model <selector>]` |
| Run a named model workflow | `agents workflows run <name> [--input <text>] [--output-format json]` |
| Start Factory | `agents factory run [--workers <n>] [--model <selector>]` |
| Inspect saved/live sessions | `agents sessions list` / `show <id>` / `stop <id>` |
| Inspect effective custom definitions | `agents definitions list` / `show <name>` |
| Create/remove lifecycle-managed worktrees | `agents worktrees create <branch> [path]` / `remove <path>` |
| Inspect/clean Factory-owned local work | `agents work list` / `show <id>` / `clean [ids...]` |

Read [execution.md](references/execution.md) for workflow/definition authoring,
images, Factory operation, session control, worktree hooks, and cleanup.
`agents` is the ArchDev CLI namespace, not an ArchAgents platform-agent
creation/deployment API.

`archdev run` is the short Factory alias in builds containing that change;
use `agents factory run` for the unambiguous canonical command. Older builds
used top-level `run --print` for headless execution. Do not use that old
spelling for new automation. Check `agents run --help` for `--resume` before
headless continuation on older installations; upgrade if it is absent.

### Interactive sessions

Start the command in a real terminal/persistent PTY. Keep the process handle;
a tool yielding output does not mean the agent exited. Hand the terminal to
the human if they want to interact, or drive normal prompt input through the
PTY when they asked you to operate the session. Do not open duplicate sessions
because one is quiet, or call an interactive TUI complete because startup
printed a banner. Save the real session ID for later inspection/resume.

### Headless requests

```sh
"$archdev" agents run "Inspect the failing test and explain its cause" --output-format json
```

A prompt is required unless using the image mode documented in the reference.
Supported controls include `--model`, `--max-turns`, `--permission-mode`, and
`--output-format`. Choose permissions from the user's authorized operation;
do not routinely enable bypass mode. A headless command may edit files when
its prompt and permissions allow it, so use the intended checkout.

Parse the final result, including `session_id`, `is_error`, and `result`, and
check process exit status. Preserve `session_id` for continuation; do not parse
an arbitrary tool log line as the final answer. Verify the requested code or
artifact with the repository's checks before claiming success. For headless
continuation use a saved ordinary session; resume Factory interactively with
`agents resume` so its control lifecycle is restored.

## 4. Enable Factory only when requested

Factory coordinates workers, Tasks, one-off work, and repository automation.
It requires an initialized repository: connect model access, then run
`jobs setup` if registration/runner setup is needed. Full `archdev setup` also
performs those steps and can propose repository configuration.

Before registering, account for the Jobs side effects: registration enables
discovery/remediation of eligible authored PRs, and project defaults may enable
automatic branch publication. `publish.auto: false` does not disable PR
watching. If the user wants no upstream mutations, do not promise isolation by
setting that field; establish the intended automation scope first.

Run `agents factory run` in a persistent PTY. `--workers` accepts 1–32 and
selects worker concurrency; inspect configured models/capacity before raising
it. `factory.model` configures the overseer; `factory.worker_model` can override
workers. Missing worker model inherits the active overseer selection. Preserve
existing Tasks and session identity when resuming, rather than starting a new
Factory to bypass a blocked assignment. Use the Jobs skill, when installed,
for daemon/private-pipeline recovery and the Tasks skill for a web review loop;
neither companion skill is required merely to install this one.

## 5. Verify and finish

Report the chosen command/mode, actual model, session/work ID, observed result,
and any remaining blocker. Use `agents sessions show <id>` to check a live or
resumable session. Stop only the requested owner with `agents sessions stop
<id>` when asked; do not kill the shared daemon to stop one agent.

For configuration changes, run `"$archdev" --json check` and inspect effective
sources. Static validation is not evidence that OAuth completed, a subscription
has available capacity, or a job ran. Keep credentials out of commits, logs,
shared pages, and model prompts. Commit/push only within the user's authorization.
