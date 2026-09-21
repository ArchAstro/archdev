# Sessions, workflows, Factory, and local work

Use the bootstrapped executable for these commands. Keep IDs returned by their
owning commands: session ID, work ID, Task ID, and daemon job ID are different
identities. Do not infer one from another's name or filesystem path.

## 1. Interactive and headless work

`agents start [prompt]` opens an ordinary interactive session; `agents run
<prompt>` performs one headless request. Ordinary sessions do not require Jobs
registration and can run outside Git, though Git/worktree features then do not
apply. Agent-only `agents setup` itself runs from a Git repository.

1. Read repository instructions and establish scope before sending a coding
   prompt. Use the current checkout only if edits there are intended.
2. For interactive work, retain the PTY/process and use normal terminal input.
   `/model` selects a model; `/help` describes the installed TUI commands. A
   terminal session that is waiting for input is not a failed job.
3. For headless work, supply the prompt as one argument and check final output
   plus exit status. `--max-turns` bounds agent turns; it is not a wall-clock
   timeout. Permission choices are `default`, `acceptEdits`, `plan`, `deny`,
   `auto`, and `bypass`; use only the authority the user granted.
4. Continue an ordinary headless conversation with `agents run <new-prompt>
   --resume <session-id>`. Do not substitute a fresh session when continuity
   matters. Use `agents resume <session-id>` for interactive resume, including
   Factory sessions; it restores the saved mode.

### Images

Image generation is part of `agents run`, with a separate option namespace:

```sh
archdev agents run --image-list-models
archdev agents run --image-options
archdev agents run --image "A simple red rocket icon" --image-model <listed-id> --image-output-dir <directory>
```

Use the returned model capabilities/options; do not guess supported sizes or
formats. Image mode uses `--image-model` and `--image-output-format`, not the
ordinary text model/output flags. It can create files and consume provider
usage, so run it when requested and inspect the returned output paths. Do not
combine it with an ordinary headless prompt or workflow invocation.

## 2. Inspect and stop sessions

```sh
archdev --json agents sessions list
archdev --json agents sessions show <session-id>
archdev agents sessions stop <session-id>
archdev agents resume <session-id>
```

1. Run from the intended project's directory. These commands inspect its
   top-level saved/live sessions, not a global list of every worker.
2. `show` reports ordinary/Factory mode, model, repository, activity, child work,
   running instances, and resume information. A saved session with no live
   owner is resumable, not necessarily crashed.
3. `stop` asks the authenticated live owner to cancel and drain its work.
   Factory drains its external workers before acknowledging. Wait for that
   acknowledgement; do not replace it with a PID kill or delete control files.
4. Stop preserves session history and identity. If the owner exited/changed
   before acknowledgement, inspect again; do not report success from a stale
   endpoint. Multiple live incarnations of the same session are handled by
   the session control command.
5. Prefer the printed resume command and stable ID. Keep private control
   tokens/files out of prompts, shared logs, and commits.

## 3. Definitions and reusable agent behavior

`agents definitions` inspects the same effective definitions used for
read-only delegation. It does not deploy platform agents or create Factory
workers. Put a specialist in `<repo>/.archdev/agents/api-reviewer.md`:

```markdown
---
name: api-reviewer
description: Inspect API contracts and callers for compatibility defects
model: "$session"
tools: [read, grep, find, ls, git]
---

Inspect the requested API change and unchanged callers. Report concrete
compatibility defects with file and line evidence. Do not propose unrelated
rewrites.
```

1. Project `.archdev/agents/*.md` overrides same-named user definitions under
   `~/.archdev/agents`. A name defaults to the filename; description and a
   prompt are required. ArchDev's explicit roots do not imply another CLI's
   `.claude/agents` fallback.
2. Model can be a selector, alias, inherited `$session`, or ordered selectors.
   These are read-only exploration agents. Effective tools are restricted to
   the explorer tool set; `disallowed-tools` wins over `tools`. Adding `write`
   or permission metadata cannot turn one into a coding worker.
3. Inspect both data and errors with `agents definitions list`, then
   `agents definitions show api-reviewer`. Confirm effective source/model/tools;
   a malformed definition can be reported while other definitions still load.
4. In an ordinary `agents start` TUI, `/delegate api-reviewer <request>` invokes a specialist and
   `/delegate --bg api-reviewer <request>` starts background delegation.
   `/route <request>` chooses by name/description matching. `/subagents` and
   `/subagents stop <id>` inspect/stop session subagents. These are TUI slash
   commands, not additional shell subcommands under `agents`. Factory has its
   own exploration/control tools and does not expose these ordinary-session
   delegation commands.
5. Some compatible frontmatter is accepted but not enforced by this runner
   (including `permissions`, `max-turns`, `memory`, `skills`, `mcp-scope`,
   `effort`, and `color`). Do not promise behavior from those fields.

Shared skill roots are project/user `.agents/skills`; hooks are project/user
`.archdev/hooks.json`. Use the bundled `docs` agent tool in an ordinary `agents start` session before
extending hooks, skills, workflow schemas, or agent definitions. Factory does
not expose that ordinary-session tool.
That is a tool available to the agent, not an `archdev docs` CLI command.

## 4. Workflows

```sh
archdev agents workflows run <name> --input "The bounded request" --output-format json
```

Named model-driven workflows load from project `.archdev/workflows` and user
`~/.archdev/workflows`; project definitions override same-named user definitions.
Read the existing definition and its referenced prompts before running it.
Use the ordinary agent session's bundled `docs` topics for declarative workflows/runners when authoring
one, and validate with `archdev check`. An external harness should consult the
installed/schema source rather than inventing a workflow format.

Workflow nodes own model/tool configuration. The shell command accepts input
and output-format options, not ordinary `--model`, `--resume`, or `--max-turns`.
Inspect the returned status/error/report rather than treating emitted prose
as completion. Review workflows have their own `reviews workflows run` route;
durable command pipelines have `jobs run`. Pick the owner matching the work.

## 5. Factory operation

Factory needs a registered repository, ArchDev user authentication, a stable
repository Task source, and an effective `pipeline_bindings.branch_update`
at committed HEAD. It warns about uncommitted config; a working-tree edit
alone does not change that preflight. Follow normal commit authorization and
validate configuration before starting.

```sh
archdev agents factory run --workers 3
archdev agents factory run --resume <factory-session-id>
```

1. Give the overseer the desired outcome and constraints through normal TUI
   interaction. It owns planning, dispatch, leases, worktrees, workers, private
   submission, verification, and recovery. Do not layer a shell scheduler or
   duplicate task list around it.
2. For Task graphs, use the native preview → exact-plan review → apply flow.
   Approved `plan_hash` must match the unchanged preview. Feedback that changes
   the graph requires a new preview/review; do not fabricate an approval hash.
3. Tasks are optional for session-led one-off work. Factory's `factory_workers`
   tool can start bounded workers with `delivery: pipeline` (private submission
   and exact-commit daemon verification) or `delivery: git` (one existing
   branch; worker remains alive until stopped). These are Factory tool actions,
   not invented shell commands such as `agents workers start`.
4. `factory.one_off_workers` is `confirm` by default, or can be `auto`/`disabled`.
   Honor the native exact-request approval flow. Do not change it to `auto`
   simply to avoid waiting for user input. Campaign work is for explicitly
   named existing PR branches, not permission to sweep every PR.
5. Lifecycle requests can return a queued receipt. Inspect `command_status`
   through the owning Factory control before claiming completion. `watch_job`
   provides host-owned notifications; use them rather than inventing another
   polling/supervision loop.
6. If workers are idle, inspect current dispatch diagnosis, claimability,
   prerequisite state, retry timing, and exact job input before intervening.
   A previously ready Task plus an idle worker does not establish a stall.
   Retry through the owning Factory/Jobs operation, preserving identities.

Keep automation within the user's scope, especially commits, upstream pushes,
and PR fixes. A Factory session may delegate work without the outer coding
harness spawning its own extra agent processes.

## 6. Worktrees and retained local work

```sh
archdev agents worktrees create feature/name ../feature-work --start-point origin/main
archdev agents worktrees remove ../feature-work
archdev --json agents work list
archdev --json agents work show <work-id>
archdev agents work clean <work-id>
```

1. Worktree creation invokes repository lifecycle hooks and prepares the runtime
   environment. A new branch defaults to HEAD unless `--start-point` is supplied;
   an existing branch keeps its own tip. Honor the user's branch policy rather
   than blindly copying the example. Use real fetched refs, not guessed ones.
2. ArchDev worktree operations require the local installation/state store.
   Direct `git worktree` calls bypass hooks/ownership bookkeeping; do not use
   them as a workaround for failed preparation.
3. Remove only intended worktrees. `remove --force` can discard dirty content;
   do not use it merely because ordinary removal rejected valuable work.
4. `work list/show` exposes durable local bindings, retained worktrees, and
   dead-letter reasons. `work clean` selects terminal eligible work and retains
   active/unpublished work. Inspect protected/failed entries; command success
   does not imply everything was deleted. Task-backed cleanup may need auth.
5. `agents work reset --yes` permanently discards this project's managed work,
   including unpublished changes and local planning/inbox records. Use only
   for explicitly authorized reset, not ordinary troubleshooting.
6. There is no `agents work retry`. For dead-letter Factory preparation, inspect
   the work, repair its prerequisite, and use Factory's task restart control.
   For a failed daemon job use `jobs retry <job-id>` when eligible. Changing
   Task status to open alone does not clear execution recovery state.
