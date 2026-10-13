# Rule candidate capture

Use this flow when a user wants to brainstorm a repository rule from a correction. A useful rule states one obligation a reviewer can see violated in a PR diff. A mechanical check may instead inspect the PR title or description. Ask for the concrete failure and expected change when they are missing. Push back on session-process instructions and pure style preferences: a diff reviewer cannot reliably check them. Do not turn an inferred preference into policy.

## Draft the pair

Read `.archdev/rules.yaml` in the target repository. Its `adopt_to` directory defaults to `.archdev/rules/`; choose a language or topic folder under it and follow an existing `.md`/`.jev` pair in that folder if available. Keep drafts in a temporary directory, not in the repository. The proposed path is where a later human-approved PR would place the Markdown file.

The `.md` frontmatter has `name`, `description`, and `date`. Do not write a `sources` key: `archdev rules propose` stamps the session answer source. In particular, `type: instruction_file` would falsely identify this rule as an instruction-file draft and can cause a retirement proposal when the rule is absent from `AGENTS.md`. The body states the obligation, why it matters, what violates it, what complies, scope and exclusions, good and bad examples with real paths or PR references when available, and an Enforcement note. Exclude secrets and unrelated transcript.

The sibling `.jev` is JSON with `model`, `state.diff`, `state.context`, and exactly two Noul questions, `applicable` and `complies`. Follow an existing pair's model and state placeholders. `applicable` starts `Scope check only; do not judge compliance.` and names included and excluded paths. `complies` starts `Judge obligations only.` and states violations and compliant cases, including deletions and generalizations. Exclude test trees explicitly when the rule is for production code; otherwise tests can generate false violations.

```json
{
  "model": "jev-latest",
  "state": {
    "diff": "REPLACE_BEFORE_USE: PR diff",
    "context": "REPLACE_BEFORE_USE: repository and PR context"
  },
  "questions": {
    "applicable": {
      "type": "noul",
      "instructions": "Scope check only; do not judge compliance. Apply to <paths>; exclude <paths and test trees>."
    },
    "complies": {
      "type": "noul",
      "instructions": "Judge obligations only. Flag <violation>; accept <compliant change, deletion, or generalization>."
    }
  }
}
```

## Propose and inspect

Only after the user explicitly asks to propose the rule, run:

```sh
archdev rules propose --repository <owner/repo> --md-file <draft.md> --jev-file <draft.jev> --proposed-path <adopt_to/folder/slug.md> --correction "<the motivating correction>"
archdev --json rules candidates --repository <owner/repo>
```

Keep `--correction` to the user's relevant steer, without secrets or unrelated conversation. The proposal creates a session candidate; it does not edit repository files or activate a check. Confirm an `open` candidate of kind `add`, source `session`, at the proposed path. The CLI prints its candidate, pending answer, and full theme key; the JSON list's `.data[].theme_key` carries that key. The plain list prints full bodies, and an empty list currently exits 1. If a write's outcome is uncertain, inspect candidates before retrying.

## Open a rules PR

Only when the user explicitly asks to open the rules PR, pass the exact full theme key from the proposal or JSON list to:

```sh
archdev rules pr --repository <owner/repo> <theme-key> [<theme-key>...]
```

The CLI opens one PR as the signed-in user on an `archdev/rules-*` branch, carrying only the selected pairs, with the ArchCode link first. Confirm the candidate becomes `pr_open`. The user reviews and merges the PR; adoption automation then marks the candidate `adopted`, and future PR verdicts can use the rule. Never add the pair to the repository or open a separate adoption PR by hand.

For status inspection, `rules candidates --status` accepts one of `open`, `pr_open`, `adopted`, or `dismissed` per call; there is no `--status all`. If `rules pr` reports that opening the PR could not be confirmed, do not retry blindly. Report the error and inspect repository branches and candidate status first.
