# Rule candidate capture

When the user gives a standing never/always correction or repeats a correction,
draft a reusable rule pair from that correction. Follow the repository's
`rules/README.md` when present. Otherwise use Markdown frontmatter containing
`name`, `description`, and `date`, with cited good/bad examples. Its sibling
`.jev` uses `jev-latest`, exactly the Noul questions `applicable` and `complies`,
and `state.diff` and `state.context` placeholders starting `REPLACE_BEFORE_USE:`.
Keep the supplied constraint and examples; do not infer unrelated policy.

Read `.archdev/rules.yaml` for `adopt_to` (default `.archdev/rules/`). Choose
its appropriate language folder: `elixir`, `go`, `typescript`, `python`, `rust`,
or `technologies`, and a lowercase hyphenated Markdown filename. Offer to add
the pair at that path, then capture the supplied correction:

```sh
archdev rules propose --repository owner/repo --md-file <draft.md> --jev-file <draft.jev> --proposed-path <adopt_to/language/name.md> --correction <text>
archdev rules candidates --repository owner/repo
```

These commands require the Rust CLI release containing `rules` and deployed
candidate storage. If unavailable, retain the draft and report that limitation;
do not substitute the frozen TypeScript CLI or install anything without consent.
Use the current signed-in organization and the repository's installed identity.

Proposals append immutable caller-owned answers. Recall shows the summary,
complete drafts, proposed path, status, and evidence; your unfolded proposals
are marked pending and are visible only to you until automation folds them.
Do not automatically retry an uncertain write. Recall first and report any
uncertainty. Store no secrets or unrelated transcript.

Candidates do not activate policy. Do not edit, commit, or adopt repository
policy without the user's authorization. Human adoption is a PR adding the
Markdown/Jev pair. After approval, `rules adopt` can record that PR or commit
as adoption evidence; `rules dismiss` records a reason for dismissal. These
commands append human decisions for automation to fold; they do not add files
or change candidate status directly. No backtesting is required.
