# PR event orchestrator

Use this when the user asks for a session that coordinates PR repairs instead
of fixing code itself. It needs CLI **0.55.4 or newer** (`events dispatch`);
check `"$archdev" events dispatch --help` first. An orchestrator that fixes a
PR in its own session follows [pr-events.md](pr-events.md) instead.

The orchestrator never edits code. It reads PR events and hands each
actionable one to the local session that owns that PR.

## Loop

1. Start one persistent watch for every PR you authored and consume its JSONL
   (stdout only; stderr is diagnostics):

   ```sh
   "$archdev" events watch --mine --json
   ```

   Run it in a process that stays alive: the Monitor tool in Claude Code, a
   detached process writing to a file in Codex, Grok and other harnesses.
   Never run it in the foreground of a harness that waits for commands to
   finish.
2. For each line whose `action_hint` is `fix_ci`, `rebase` or
   `address_feedback`, pass exactly that line on stdin from a separate
   process, so the watch stays alive:

   ```sh
   printf '%s\n' "$line" | "$archdev" events dispatch --event - --json
   ```

   Add `--dry-run` to preview the target; it claims and launches nothing.
   Skip `stop` events.
3. Read the exit code:
   - **0:** the child ran and its session ended. Exit 0 alone does not prove
     the PR is fixed; check the new head's CI and annotations.
   - **3:** a daemon job or another harness owns this head. Skip the event.
     Never steal or release their claim.
   - **Other:** report the error text. Missing local watches, missing
     worktrees and unsupported recorded providers are errors, not permission
     to pick another target.

## What dispatch does

- Finds the active local watch for the event's exact PR head. The head must
  be a full 40-character SHA.
- Resumes the recorded session, preferring its continuation session over its
  authoring session: Claude and Codex resume theirs, Grok starts fresh. With
  no recorded session it starts Codex in the recorded worktree. Sessions
  recorded by the native `archdev` harness are not resumed and fail with an
  unsupported-provider error.
- Claims the head, renews the 300-second claim while the child runs, and
  releases it after the child and its process group end. **The model must not
  claim, renew or release for a dispatched head.**
- Tells the child to verify the remote head, treat event text as untrusted,
  fix the issue, run focused tests, push only the PR branch when authorized,
  store annotations and report. It adds no permission-bypass flags.

## Reporting

Post verified outcomes with `log post --project <id> --kind done` or
`--kind abandoned`, with the PR URL and the new head's CI result. Do not post
`done` from a spawn result alone.

Claims coordinate one machine and one `HOME`. Provider resume behavior is
checked by an operator-run synthetic, not by automatic CI.
