# Adding a rule from a session

Use this flow when a user wants to brainstorm a repository rule from a correction. A useful rule states one obligation a reviewer can see violated in a PR diff. A mechanical check may instead inspect the PR title or description. Ask for the concrete failure and expected change when they are missing. Push back on session-process instructions and pure style preferences: a diff reviewer cannot reliably check them. Do not turn an inferred preference into policy.

The checker judges each rule from the PR diff, its title and description, and the list of changed file paths. It does not read unchanged repository files such as CI workflows, build targets, or test runner configuration. Write the obligation so a violation is visible in those inputs. If compliance depends on files the PR usually leaves untouched, or only on what the description claims, narrow the rule to what the diff shows or push back on it.

## Draft the pair

Run `archdev --json rules --repository <owner/repo>` and follow an existing rule's `md`/`jev` pair if one fits. Keep drafts in a temporary directory, not in the repository.

The `.md` frontmatter has `name`, `description`, and `date`. The name identifies the rule: adding a pair whose name matches an existing rule edits that rule. Do not write a `sources` key: `archdev rules add` records the correction as the rule's evidence. In particular, `type: instruction_file` would falsely identify this rule as an instruction-file draft and can cause a retirement proposal when the rule is absent from `AGENTS.md`. The body states the obligation, why it matters, what violates it, what complies, scope and exclusions, good and bad examples with real paths or PR references when available, and an Enforcement note. Exclude secrets and unrelated transcript.

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

## Add and check

Only after the user explicitly asks to add the rule, run:

```sh
archdev rules add --repository <owner/repo> --md-file <draft.md> --jev-file <draft.jev> --correction "<the motivating correction>"
archdev rules --repository <owner/repo>
```

Adding needs the user's own GitHub write access to the repository. Keep `--correction` to the user's relevant steer, without secrets or unrelated conversation. The rule is active as soon as it is added and applies to later PRs; it does not edit repository files. `rules add` prints `added: <name> (<rule_id>) active`, or `edited: …` when a rule with that name already existed. Confirm the listing shows the rule as `active`. If a write's outcome is uncertain, list the rules before retrying.

## Change a rule

Use the `rl_…` id from the listing. Each command needs GitHub write access and changes later PR checks, so run it only when the user asks:

```sh
archdev rules edit <rule_id> --repository <owner/repo> --md-file <draft.md> --jev-file <draft.jev>
archdev rules disable <rule_id> --repository <owner/repo>
archdev rules enable <rule_id> --repository <owner/repo>
archdev rules revert <rule_id> --repository <owner/repo>
```

`revert` drops edits and disables made through ArchDev and returns the rule to its source; it fails when the rule has no source to return to. Rules from repository files (source `repository`, id is the file path) cannot be changed from the CLI; edit the file in a PR instead. An edit cannot rename a rule.
