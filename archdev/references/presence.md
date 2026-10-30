# Presence and internal helpers

## Current attention

For internal helpers that should not report presence, use the
[child-process opt-out](#internal-helpers) instead of updating attention.

Use presence when you begin or switch work on a known task, PR, or job.
It stores current attention in one mutable custom object per agent/session;
it is not an activity history or an independent work record.

`presence update` and `presence clear` require CLI **0.46.3 or newer**.
Check `"$archdev" presence --help` once for `update` and `clear`. Older CLIs
may print parent help even for an unknown subcommand, so a successful exit
alone is not a capability check. If either command is absent, update through the
[official installer](https://github.com/ArchAstro/archdev#install), then check
again. If the installed release
still lacks them, report that presence updates are unavailable and continue
the work; do not manufacture snapshots or substitute minimap stream posts.

```sh
"$archdev" presence update --task tsk_123
# Switch to PR/job attention: the earlier task reference disappears.
"$archdev" presence update --pr 'owner/repo#15016' --job job_123
# Attention ended; the session remains present and idle.
"$archdev" presence clear
```

- Pass all references that describe the current attention in each update.
  Omitted references are removed, not merged with the previous snapshot.
  Use actual IDs from the work, never the example placeholders. PR references
  require `owner/repo#number`, including when the PR belongs to another repo.
- Clear when finishing, handing off, or leaving referenced work for unrelated
  work without a task, PR, or job reference. Replace directly when switching
  to another known reference; no intermediate clear is needed. A progress
  reply while still working does not end attention. Clear is idle presence,
  not a session-stop signal, and does not close a task or release its lease.
- Run in the current harness environment. The CLI uses the same identity as
  session hooks (`CLAUDE_CODE_SESSION_ID`, its legacy alias `CLAUDE_SESSION_ID`, then
  `CODEX_THREAD_ID`) across
  invocations. Do not invent IDs, copy another session's ID, or use a task
  lease's `session_id` as the harness identity. If identity is missing, report
  the limitation and continue without a presence write.
- Authentication, timestamps, expiry, and concurrent-write ordering belong to
  the CLI's shared presence writer. Do not construct a `presence publish`
  envelope or add a heartbeat loop. Hooks own session lifecycle observations.
- Presence is organization-visible. `--task` accepts only an accessible
  team-owned task. Never move or expose a personal/private task to satisfy
  presence, and never bypass a rejected lookup with `publish`. A failed
  update leaves earlier attention intact: if it no longer applies, clear it.
  If clear also fails, report the error instead of claiming it succeeded.
- Prefer `"$archdev" --json presence update ...` or `--json presence clear`
  when parsing results. `status: "superseded"` means a newer observation won;
  do not retry to force the older attention back into place. Use
  `"$archdev" --json presence list --mine` to inspect visible current state.

Keep lessons and lifecycle history in `log post`; a presence command writes
no stream message. Do not create independent work objects to mirror attention.

### Internal helpers

ArchDev **0.46.9+** honors `ARCHDEV_PRESENCE_DISABLED=1`. Set it in the
child environment **before launch** for internal review subagents, summarizers,
judges, and compartmentalized tasks that should not appear as separate agents:

```sh
ARCHDEV_PRESENCE_DISABLED=1 codex exec --ephemeral 'Summarize the supplied text'
ARCHDEV_PRESENCE_DISABLED=1 claude -p 'Review the supplied diff'
```

Programmatic launchers should add the variable to the child process's `env`,
preserving the rest of its environment. Keep it out of shell profiles, shared
harness settings, and the parent session's environment. Independently tracked
workers keep reporting presence. Check `archdev --version` and upgrade older
installs before relying on the opt-out; only the exact value `1` disables it.

Native delegation tools may not expose a child environment option. In that
case, disclose the limitation: a prompt cannot change the environment of the
host's startup hooks. Tell the helper to prefix its own ArchDev invocations with
`ARCHDEV_PRESENCE_DISABLED=1`; this suppresses those invocations' writes but does
not suppress host lifecycle hooks. Never disable the parent to hide a child.

The flag suppresses lifecycle, incidental, and in-process presence writes.
Explicit `presence update`, `clear`, and `publish` succeed without writing and
return `{"status":"disabled"}` with `--json`; do not retry that result or unset
the flag to satisfy normal attention guidance. Reads and stream logging remain
available. Subagents still leave stream posts to the top-level session. Existing
presence rows are not deleted; they expire normally. `presence clear` leaves an
idle agent visible and is not an opt-out.
