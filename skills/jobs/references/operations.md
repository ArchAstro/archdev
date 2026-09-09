# Inspect and recover daemon automation

Start with the actual repository, job ID, input SHA, and failed stage. Use the
public CLI rather than editing SQLite, refs, attempt counters, or journals.
Commands below use `archdev` for the bootstrapped executable. Prefer global
`--json` when parsing results.

## 1. Locate the failure

```sh
archdev --json jobs runner status
archdev --json jobs runner doctor
archdev --json jobs list
archdev --json jobs show <job-id>
archdev jobs logs <job-id>
archdev jobs logs <job-id> --step <step-id> --attempt <number>
```

`show` exposes input, attempts, steps, pipeline snapshot, outputs, result SHA,
report paths, and cleanup errors. `logs` reads persisted stdout/stderr, including
prior attempts. Correlate the submitted commit with the job; a successful push
or worker exit alone does not establish durable success.

| Symptom | Evidence and next action |
| --- | --- |
| Private ref moved, no job | Check runner status/doctor, registration, committed event binding and managed receive-hook health. Repair ingestion before repeatedly pushing the same ref. Startup reconciliation can discover existing refs. |
| Runner stopped | Determine whether the user stopped it deliberately or cleanup stopped it. Use `jobs runner start` within the requested operation, then verify readiness. Do not delete stop markers manually. |
| Broken service after upgrade | `jobs runner doctor` diagnoses registration/readiness; `doctor --repair` repairs a verified registration. `jobs runner install --existing-only` refreshes/restarts an existing managed daemon. |
| Executable/dependency missing | Inspect the actual job's runtime environment and worktree preparation. Native-service PATH differs from the interactive shell; fix repository preparation/environment rather than restarting repeatedly. |
| Check passes, job uses old config | Compare the committed input/pipeline snapshot with the edited checkout. Named retries retain their input; mutable local overlays are not exact-commit job policy. |
| Failed verification or model call | Read the failing attempt's full output; fix the command, code, credentials, or capacity at the owning layer. Choose retry versus new input deliberately. |
| PR not being fixed yet | Check eligibility, runner/GitHub health, exact-head checks still running, and retry deadline. The watcher batches settled feedback and can be in backoff. |
| Job finished but checkout unchanged | Inspect result SHA and latest branch result; use `jobs repo sync`. Named jobs have independent result snapshots; they do not promise branch synchronization. |
| Missing persisted log / cleanup error | Preserve the error and inspect returned paths/ownership. Do not describe absent evidence as a passing step or delete retained work to conceal the failure. |

Production daemon events live in `~/.archdev/logs/archdev.log`. Follow returned
paths for other runtime scopes; correlate `watchId`, `jobId`, `attempt`,
`workerId`, and `pollId`. Redact credentials/customer content when sharing logs.

There is no `jobs runner restart` verb. If an ordinary restart is warranted,
use `jobs runner stop` then `jobs runner start`, and verify status. This is a
shared machine runner, so account for other active work before stopping it.
Do not replace native supervision with a shell background process.

## 2. Retry the right unit

```sh
archdev jobs retry <failed-job-id>
archdev jobs cancel <queued-or-running-job-id>
```

1. Only a `failed` job can retry. Succeeded or cancelled work needs a new
   authorized run, not a forged state transition.
2. Named jobs retain their independent `source_ref` and original committed
   snapshot on retry. If source/config fixes are needed, commit them when
   authorized and use `jobs run <pipeline>` for a new job.
3. Branch jobs require the private ref still to match the failed job's input;
   retry rebases that private branch against current upstream main. If newer
   work moved the ref, follow the newer job or submit the intended new input.
   Do not force the ref backward to satisfy the guard.
4. PR workers cannot be manually retried through `jobs retry` or manufactured
   with `jobs trigger`. Their supervisor owns retries and frozen-head leases.
5. After recovery, inspect the new attempt and terminal result. Do not equate
   a successful retry request with a successful job.

`jobs trigger <type> --payload <json>` is an advanced event-job interface,
not the normal way to run a named pipeline. It requires the current committed
HEAD to exist at the same private branch ref and a valid event payload/binding.
Use `jobs run` or `jobs repo submit` for ordinary work rather than inventing
internal payloads or invoking hidden worker commands.

## 3. Understand automatic PR watching

1. The runner discovers eligible open PRs authored by the authenticated GitHub
   user in registered repositories. Successful `archdev reviews publish` also
   registers its exact published PR head. Use `gh auth status`, repository
   remote/registration, and the PR's author/state/head to diagnose eligibility.
   Do not post comments merely to wake the watcher.
2. The PR supervisor owns its workers separately from branch execution. It
   collects CI and review feedback for the exact head and waits for checks to
   settle before dispatching fixes. Rebase conflicts have a separate pipeline.
3. Built-in feedback workers operate on disposable detached worktrees. They
   address supported feedback, run focused tests, and commit; a deterministic
   host-owned finalizer handles pushing or rerunning CI. Do not add direct
   `git push` or `reviews publish` calls to their agent prompt.
4. Head/base fences prevent stale work from overwriting a newer PR. A moved
   head is a reason to inspect current ownership/input, not to disable leases.
   Restart recovery stops recorded old worker process groups before replacements.
5. Failed remediation backs off (default ten minutes, capped at one hour,
   without an attempt cap). Default discovery polling is thirty seconds.
   Check events for the actual retry deadline instead of repeatedly restarting
   the runner or adding an independent fix loop.
6. Closed/merged PRs stop being watched. Linked Task completion depends on
   merge of the exact published head; failed settlement remains retryable.
   Factory-associated work retains Factory's lifecycle ownership.

Watching is not passive reporting: it can mutate the PR. Honor the user's
scope before registering/enabling automation. The CLI has no public per-PR
watch/unwatch command. If asked to stop one PR specifically, explain that
limitation and choose an authorized alternative; do not silently stop every
repository's shared runner or edit its database.

## 4. Identify what “DLQ” means

Daemon job states do not include a separate dead-letter queue, and there is no
`jobs dlq` command. Ask for or inspect the actual failed record before choosing
recovery. Factory can retain dead-letter assignments after repeated workspace
preparation failures; Rooms also has its own outbox failures. These are distinct
owners, not aliases for failed Jobs.

For Factory-owned dead-letter work:

```sh
archdev --json agents work list
archdev --json agents work show <work-id>
```

1. Inspect `deadLetter` reason, attempts, retained worktree, and linked Task.
   Repair the actual preparation prerequisite; preserve any unpublished work.
2. If cleanup is required and authorized, use `agents work clean <work-id>`
   for that specific owned resource after reviewing what will be removed.
3. Restart through Factory's supported task-control flow. Its `update_task`
   control distinguishes `restart` from `restart_clean`; this is an agent/Factory
   control, not a public CLI `tasks restart` command. If the current harness
   cannot access that control, hand off the exact work/Task ID and repaired
   prerequisite to the user's Factory session rather than inventing a command.
4. `tasks update --status open` changes status only. It does not clear execution
   recovery state and is not a substitute for restart.

## 5. Clean only when deletion is the task

Normal recovery should preserve attempts, logs, refs, and useful worktrees.
For requested cleanup, inspect `jobs clean --help` and the exact matching
records first. `jobs clean` normally removes terminal jobs under ownership
checks. `jobs clean --all` can include active work, stops the daemon, and leaves
it stopped after successful cleanup; `--yes` confirms that deletion.

`agents work reset --yes` can discard all project-managed work, including
unpublished changes. `jobs runner uninstall --purge` permanently deletes
private repositories and the database. `jobs repo disable --delete-repo`
removes the private repo. None is a routine retry or health repair. Obtain
specific deletion authorization unless the user already supplied it.
Plain runner uninstall preserves data. There is no general age/count history
retention policy to assume; retained history is not itself a failure.
