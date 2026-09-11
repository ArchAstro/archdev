# Author review metadata yourself

Use this path when no model access or ArchDev session is available, or when
the human wants your judgment on the diff rather than a model's. You freeze
the change set, write sparse risk, theme, and note annotations against it, and
serve them through the same `inspect local` browser flow. The CLI validates
every annotation against the frozen diff; you supply what a reviewer must look
at. Only publishing the same file to a pull request needs a login.

## 1. Freeze and read the change set

```sh
"$archdev" inspect manifest --base origin/main > manifest.json
```

The manifest captures committed, staged, unstaged, and non-ignored untracked
changes against the merge base of `--base` and HEAD, the same snapshot rules
as `inspect local`. It prints `files[]` and `changes[]`: the annotatable text
ranges with `path`, `side`, 1-based `start_line` and `end_line`, and their
`patch`. Binary, rename-only, and mode-only changes appear in `files[]`
without a range and cannot carry annotations. Keep `diff_sha256`; it fences your
metadata to this exact tree.

Read the patches before annotating. Open the file when a patch is not enough
to judge a change. Do not annotate from memory of what you intended to change,
and do not edit any file between this step and step 3.

## 2. Write the metadata file

Write one UTF-8 JSON file outside the repository, for example in the harness
scratch directory, with schema `archdev.review-metadata.v1`. Read
`"$archdev" inspect guide` for the installed CLI's exact contract; it wins
when this page and the CLI disagree.

```json
{
  "schema": "archdev.review-metadata.v1",
  "diff_sha256": "<copied from manifest.json>",
  "summary": {
    "intent": "One paragraph: what the change does and why.",
    "overall_risk": "medium"
  },
  "pull_request": {
    "title": "Short title",
    "body_markdown": "PR body a reviewer would want.",
    "draft": false
  },
  "annotations": [
    { "kind": "risk", "path": "src/auth.ts", "side": "modified", "start_line": 10, "end_line": 22, "risk": "high", "note": "Audience is compared before the issuer is verified." },
    { "kind": "semantic_group", "path": "src/auth.ts", "side": "modified", "start_line": 30, "end_line": 41, "semantic_group": "Auth boundary", "note": "Callback validation and its tests." },
    { "kind": "semantic_group", "path": "test/auth.test.ts", "side": "modified", "start_line": 5, "end_line": 40, "semantic_group": "Auth boundary", "note": "Covers the rejected-audience path." },
    { "kind": "note", "path": "src/legacy.ts", "side": "original", "start_line": 3, "end_line": 3, "note": "Removed export had no remaining callers." }
  ]
}
```

Rules the CLI enforces, and how to satisfy them:

1. Every annotation must overlap a `changes[]` entry on the same `path` and
   `side`. `modified` is the new file for added or changed lines; `original`
   is the old file for removed lines. A rejected file names the failing index.
2. `risk` is `critical`, `high`, `medium`, or `low`, and its `note` states a
   concrete way the change can be wrong: auth, data loss, concurrency,
   compatibility, cost. Do not label a range high risk without such a reason.
3. Ranges that belong together across files share one `semantic_group`
   label. The reviewer can accept a whole group at once, so group by what one
   person would verify in one sitting.
4. `note` carries context the diff cannot show: an invariant, a follow-up, a
   reason a suspicious-looking change is safe.
5. Cover every path listed in `changes[]` with at least one entry; the CLI
   rejects a file that leaves a changed path unannotated. For generated or
   mechanical files add one `note` saying why they need little review.
   Beyond that, be sparse: annotate what a reviewer must look at, not every
   hunk.
6. `summary` and `pull_request` are optional for a local review.
   `pull_request` is required for publishing. `overall_risk` defaults to the
   highest annotation risk when `summary` is absent.

## 3. Serve it

```sh
"$archdev" inspect local --base origin/main --metadata metadata.json --feedback-format jsonl --no-open
```

`--metadata` replaces model generation: no `auth status`, no provider, no
`--model`. The server starts with the analysis already ready, and the browser
shows your summary banner, the risk labels, and the themes. From the `ready`
record onward, follow the main skill's launch, listen, and iterate steps
unchanged. Rerun steps 1 to 3 for another pass after edits.

If the CLI reports that the working tree changed since the manifest ran,
regenerate the manifest and the metadata; do not edit the fence by hand.
`inspect local --no-metadata` serves the diff with no annotations when the
human only wants to read the change.

## 4. Publish the same file to a pull request

Publishing writes GitHub and ArchDev's hosted review store, so it needs
`"$archdev" auth login` and a working `gh auth status`. With `pull_request`
present in the file:

```sh
"$archdev" inspect publish --base main --metadata metadata.json
```

Publish validates the annotations against the exact PR head, sets the PR
title and body from `pull_request`, and stores the annotations for the hosted
reviewer. The `diff_sha256` fence is checked here too: publish rejects the
file before pushing when the committed diff differs from the diff you
reviewed. Committing identical content keeps the digest valid. If content
changed, regenerate the annotations and the digest together; copying a new
digest onto old annotations defeats the fence. Publish sets the title and
body only for a PR it creates, and does not replace annotations already
stored for the same head. Tell the human before running it that it pushes
the branch, and follow the repository's own commit and push rules.

Never put secrets, tokens, or customer data in annotations, summaries, or PR
bodies.
