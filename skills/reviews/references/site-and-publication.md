# Site access, review features, and publication

Use this reference for hosted repository review and the transition from local
feedback to an actual PR. The configured portal owns the web experience; CLI
commands return its URL. Production is `https://archdev.ai` (ArchCode).

## 1. Connect GitHub through the site

1. Open the portal's `/login` in the human's main browser profile. On production,
   use [Sign in with GitHub](https://archdev.ai/login). Let the human complete
   GitHub sign-in/consent; do not collect passwords or OAuth codes in chat.
2. Open [GitHub repository settings](https://archdev.ai/settings/github).
   Install the **ArchDev GitHub App** on the intended GitHub user/organization
   and grant the intended repositories. Organization installation or expanded
   permissions may require an administrator's approval. Do not grant every
   repository just to avoid choosing the requested one.
3. Return to settings, click **Refresh from GitHub**, select the repositories,
   and **Save repositories**. Initial onboarding may already have selected
   visible repos; inspect the actual selection before changing it.
4. Reopen the intended inbox/PR and verify access. A connected GitHub identity
   alone does not grant all repository access. For a missing repo, check App
   installation/account, repository selection, permission updates, and the
   site's refreshed saved selection. A disconnected integration may require
   signing out and signing in with GitHub again.

Keep these boundaries distinct:

| Boundary | Authentication |
| --- | --- |
| ArchDev CLI/model-backed local review | `archdev auth login` plus usable model access |
| Hosted repository visibility and user-attributed review actions | Site GitHub login and App/repository access |
| CLI publication to GitHub | Local `gh auth status` / `gh auth login`, checked independently |

`gh auth login` does not connect the hosted site's GitHub integration. Signing
in on the site does not authenticate a terminal's `gh`. Local snapshots do not
need a GitHub App installation: the `/local-review` shell reads their local
capability server. Do not block local-only review on granting repository access.

## 2. Open the inbox or PR

```sh
archdev reviews inbox
archdev reviews open <owner/repo#123>
archdev --json reviews open <PR-number-or-URL>
```

`reviews` alone opens the Needs review inbox. `open` accepts a positive PR
number (resolved through the checkout's GitHub `origin`), `owner/repo#123`, or
a GitHub/ArchCode PR URL. Pass a full identity when outside its repository.
The CLI hands off to ArchCode; it does not download/review the PR itself.

`--no-open` prints the URL. JSON output includes `url`, `opened`, and resolved
PR identity and does not automatically open the browser. If using JSON, open
the returned URL explicitly in the user's browser. Share ArchCode PR links,
not a local capability URL or an inferred PR number.

## 3. Review workspace features

Both local snapshots and hosted PRs use the review workspace:

- Changed-file navigation and tabs; split/unified diffs and scroll-through
  review; hunk-level acceptance/reopening to track progress.
- Rendered previews for supported file types and semantic hunk annotations
  when metadata exists. Missing annotations are not missing code: inspect the
  actual diff and surrounding context.
- Inline line/range comments on original or modified code. Preserve side and
  range when interpreting feedback; a deleted line belongs to the original side.
- Path, review-status, coverage, risk, and theme filters for navigating hunks.
  Filters can hide code; inspect the hidden-change indicator and use **Show all**
  when validating overall coverage instead of treating a filtered queue as the
  complete change.
- Archie-assisted exploration of the current review and selected code/hunks.
  Keep questions grounded in the selected revision. If a saved code reference
  points at an older revision, recheck the current lines before acting on it.
  Assistant commentary does not replace review, approval, or verification.
- Private browser-local notes, separate from ordinary draft comments.
- Revision-scoped progress and keyboard shortcuts. Press `?` for current help;
  `]c`/`[c` navigate hunks, `]f`/`[f` files, `]b`/`[b` tabs. Ctrl+Enter accepts
  a hunk; Ctrl+Shift+Enter reopens it.

Hunk acceptance is review-progress bookkeeping, not GitHub approval, a code
edit, or a merge. Inspect all relevant changes before marking progress.

### Local snapshot

Use **ordinary inline comments** for feedback intended for the coding agent.
Drafts sync to the CLI; **Send feedback** submits the complete set and shows
**Feedback sent**. Private comments remain in browser-local storage and are
not returned to the agent. Tell the human this before they leave private notes
expecting the agent to act on them.

Local source has no GitHub review submission, thread reply/resolution, merge,
ready-for-review, update-branch, attachments, editable PR description,
commit-specific diffs, or live remote updates. The displayed local PR number
is a placeholder, not a GitHub identity. Re-run the CLI after edits to review
a new immutable snapshot.

### Hosted PR

Depending on repository permissions/state, hosted review supports:

- Commit-specific diffs, live revision updates, description editing, and
  attachments.
- Conversation replies, review-thread resolution, and reviewer requests.
- **Finish review** with **Comment**, **Approve**, or **Request changes**, plus
  pending inline comments. The connected GitHub identity is shown before
  submission; actions are attributed to that human.
- Ready-for-review, update-branch, and merge controls when available.

Before submitting a review, replying, requesting reviewers, editing metadata,
or merging, confirm that action is within the user's authorization. Opening
or inspecting a PR does not itself authorize posting as the human. If the head
changes, refresh/revalidate progress and review the changed revision; do not
carry old acceptance blindly onto new code. Use the enabled UI controls rather
than bypassing a disabled finish/merge action through another endpoint.

## 4. Generate metadata without publishing

```sh
archdev reviews generate pull-request --base main --remote origin
archdev reviews generate metadata --base main --remote origin
```

These produce validated JSON without publishing. `pull-request` generates
PR title/body/draft state; `metadata` generates semantic hunk review metadata
and accepts `--pull <number>` when needed. Both accept `--model`,
`--context <path>` (`-` for stdin), and explicit `--fallback`.

Keep exact generated artifact schemas and revision identities. These are
separate artifacts; do not assume either output alone is the complete bundle
accepted by `publish --metadata`. Inspect the installed CLI contract before
supplying a pre-generated bundle. Do not invent hunk IDs, revision hashes, or
claims of executed verification in model-generated PR prose.

Generation can consume model usage and inspect GitHub context, even though it
does not publish. Explicit fallback permits degraded generation; report that
condition rather than describing deterministic fallback prose as an AI review.

## 5. Publish when authorized

```sh
archdev reviews publish --base main --remote origin
```

1. Inspect the intended committed branch, current head, remote/base, and working
   state. Preserve the user's branch/commit policy; commit only when authorized.
   Check ArchDev/model access and `gh auth status`, logging in at the missing
   boundary. Review-only operations do not require Jobs setup.
2. `reviews publish` publishes/updates the branch PR and its sparse source
   annotations. Use `--pull <number>` to explicitly identify an existing PR
   when needed. Tasks are optional; `--task <id>` links one and `--task none`
   explicitly skips inferred Task association.
3. `--context <path>` supplies pipeline evidence. `--metadata <path>` supplies
   a pre-generated complete bundle. `--review-bundle-fallback` permits publishing
   without annotations after invalid generation; do not add it merely to hide
   a metadata problem. Verify resulting title/body/draft state and annotations.
4. Advanced `--force-with-lease <head-sha>` and
   `--expected-base-ancestor <base-sha>` fence a specific old head/base lineage.
   Use only observed identities and authorized history replacement. Never
   weaken these fences or fill them with guessed values to force a publish.
5. Inspect the returned PR identity and exact published head before reporting
   success. A failure after PR creation may leave an existing PR; inspect it
   before retrying instead of creating a duplicate. Hand back the ArchCode URL.

Standalone publication need not enable automation for an unregistered repo.
When a registered project/configured watcher is present, publication registers
the exact head with the daemon. Explicit watcher bindings without valid project
registration produce an error; do not invent local identity/configuration.

## 6. Hand ongoing PR management to Jobs

When the user wants automatic CI/review fixes, use the installed Jobs skill;
if absent, follow the public commands here and their help instead of requiring
a sibling skill file that may not be installed.

1. Before `jobs setup`, explain that repository registration enables discovery
   of eligible authored open PRs. A running daemon can remediate them.
   `publish.auto: false` only disables automatic branch publication, not PR
   watching. There is no public per-PR watch/unwatch command.
2. Configure event bindings through project `archdev.json` as needed:
   `pull_request_feedback` and `pull_request_rebase_conflict`. Prefer the
   built-in pipelines and their host-owned finalizer. Run `archdev check`.
3. Check `jobs runner status`, `jobs list`, and `jobs show <id>`/`logs <id>`.
   The watcher waits for checks on the exact head to settle before batching
   feedback; failed remediation has backoff. An idle interval is not proof
   of a stalled job.
4. Let the watcher own retries, frozen-head/base fencing, commits, publication,
   and cleanup. `jobs retry` rejects PR worker jobs. Do not run a second coding
   agent fix/push loop or call hidden worker/finalizer commands on the same PR.
5. Closed/merged PRs stop watching. Linked Task completion depends on the exact
   published head being merged; Factory keeps ownership of its associated work.
   Read Jobs' recovery guidance for daemon failures and destructive cleanup.
