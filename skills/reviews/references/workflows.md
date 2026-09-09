# AI review workflows

Use review workflows for repeatable model-driven inspection of a Git snapshot.
They are separate from the human `reviews local` browser session: running a
workflow does not open that browser or collect its comments, and opening local
review does not automatically execute a chosen review DAG.

## 1. Discover and run

```sh
archdev --json reviews workflows list
archdev --json reviews workflows show default
archdev reviews workflows run default --target current-files --output-format json
archdev reviews workflows run default --target branch-commits --output-format json
```

1. Effective definitions come from project `.archdev/reviews/*.json`, user
   `~/.archdev/reviews/*.json`, and the built-in `default`. Project overrides
   same-named user definitions. `review.default_workflow` selects the default;
   inspect the reported source rather than assuming which file wins.
2. The built-in default runs correctness and security review, followed by
   synthesis. Reuse it or a repository workflow when it fits; do not create a
   new graph simply to invoke review.
3. Headless execution requires an explicit target. **Current files** reviews
   staged/unstaged/non-ignored untracked changes against HEAD. **Branch commits**
   reviews committed changes against the resolved repository base and excludes
   current file changes. This differs from local browser review's aggregate
   snapshot against its `--base`.
4. Workflow nodes own models, dependencies, and access. There is no ordinary
   `--model`, `--resume`, or `--max-turns` flag on this command. Configure models
   in the workflow/aliases and verify account access through `settings provider`
   and ArchDev auth. Use the Agents skill for BYO setup when available.
5. Text output prints the selected summary and full-results path. JSON includes
   `result.summary` and `result.full_results_file`. Inspect error/exit status,
   node outcomes, artifacts, and snapshot freshness before claiming a clean
   review. Empty prose is not proof of no defects.

In an ordinary `agents start` TUI, `/review [name]` offers target selection.
`/review team --target current-files` runs directly; `/review --list` and
`/review --explain <name>` inspect discovery/compiled configuration. These are
TUI slash commands, not additional shell flags. Factory has its own tool surface.

## 2. Author a static DAG

Start from the repository's working definition and its actual review needs.
Use the ordinary ArchDev agent's bundled `docs` tool for review/declarative
workflow schema details when available. External harnesses can use this
reference, inspect an existing definition, and validate the result with
`archdev check`; there is no shell `archdev docs` command.

For a small independent correctness/security review with explicit synthesis,
create `.archdev/reviews/team.json`:

```json
{
  "version": 1,
  "name": "team",
  "description": "Review correctness and security with evidence-based synthesis",
  "limits": {"concurrency": 2, "maxAgents": 6},
  "nodes": [
    {
      "id": "correctness",
      "type": "agent",
      "model": "$session",
      "prompt": "Establish author intent. Inspect the captured diff and unchanged callers for correctness and test gaps. Refute candidate findings; report only concrete defects with severity and file:line evidence."
    },
    {
      "id": "security",
      "type": "agent",
      "model": "$session",
      "prompt": "Inspect authorization, privacy, input handling, and trust boundaries. Refute candidate findings; report only concrete defects with severity and file:line evidence."
    },
    {
      "id": "summary",
      "type": "agent",
      "role": "synthesizer",
      "model": "$session",
      "inputs": {
        "correctness": "$nodes.correctness.output",
        "security": "$nodes.security.output"
      },
      "prompt": "Deduplicate and rank the supplied evidence, rejecting unsupported claims. Preserve severity, file:line and reviewer provenance. Say explicitly if no findings remain.\nCorrectness: {{inputs.correctness}}\nSecurity: {{inputs.security}}"
    }
  ],
  "output": {
    "node": "summary",
    "presentation": {
      "format": "template",
      "template": "## {{workflow}}\n\n{{output}}\n\nReport: {{reportRef}}\nSnapshot: {{snapshotStatus}}"
    }
  }
}
```

`$session` inherits the runtime model selection; replace it with an existing
alias or provider/model when a reviewer requires a different model. Do not
invent model IDs. Aliases and ordered selector lists support provider/model
fallback; availability and permission still depend on the connected accounts.

### Dataflow and concurrency

- Each node publishes text at `$nodes.<id>.output`. Named `inputs` both create
  dependencies and supply `{{inputs.<name>}}` prompt values. Use inputs when a
  node needs another node's evidence, not an opaque scratch-file handoff.
- `dependsOn` supports ordering without named data inputs and preserves legacy
  dependency evidence. The compiler rejects missing/self references, cycles,
  and undeclared prompt inputs.
- Independent nodes run concurrently within `limits.concurrency` and
  `limits.maxAgents`. Roles such as reviewer/synthesizer express intent; the
  top-level output selection controls the actual final summary.
- `required: false` marks an optional node. Inspect its status explicitly;
  optional failure is not a successful review or completed fix.
- There is no default total deadline for model-driven review. Add
  `limits.timeoutSeconds` only for a required hard deadline; progress does not
  extend it. Agent counts, output, graph and iteration bounds still apply.

## 3. Tool access and isolated prototype fixes

Agent nodes default to read-only `read`, `grep`, `find`, `ls`, `git`, and
guarded `bash`. An explicit `access.tools` can narrow repository tools.
Every review agent call receives `review_diff` for the immutable diff,
including agents launched by a JavaScript node. Bash nodes have no agent tool
surface. Teach reviewers to inspect unchanged callers while grounding findings
in the captured change.

An agent node that writes must use an isolated worktree:

```json
{
  "id": "prototype",
  "type": "agent",
  "model": "$session",
  "required": false,
  "inputs": {"findings": "$nodes.summary.output"},
  "prompt": "Prototype only supported fixes in your isolated worktree. Report the patch and verification; do not claim the parent checkout changed.",
  "access": {
    "mode": "read-write",
    "isolation": "worktree",
    "tools": ["read", "grep", "git", "bash", "edit", "write"],
    "writePaths": ["src/**", "tests/**"],
    "forbidPaths": [".env*", "infra/**"]
  }
}
```

This is an optional node to add to a graph, not a complete workflow. Its output
can feed a later assessment node. The parent session owns integrating a
supported patch into the active checkout. An isolated writer does not
implicitly modify that checkout; its Bash/Git tools remain mutation-guarded.
Use paths appropriate to the repository, and preserve authorization boundaries.

## 4. Bash and JavaScript nodes

Review workflows also support executable nodes from the declarative workflow
model. These are materially different from read-only reviewer agents:

- **Bash:** a `type: "bash"` node runs its `command` in the active workflow
  directory. Stdout becomes node output; a nonzero exit fails it and records
  stderr. Named inputs arrive through `ASTRODEV_WORKFLOW_INPUTS`; invocation
  input uses `ASTRODEV_WORKFLOW_INPUT`. Bash remains bounded to 15 minutes.
- **JavaScript:** a `type: "javascript"` node runs a `script` with `args.input`,
  `args.inputs`, and dependency evidence. It can use `agent()`, `parallel()`,
  `pipeline()`, `phase()`, and `log()`, including bounded per-item agent loops.
  Returned text/JSON becomes node output. The script itself cannot directly
  import modules, access filesystem/network, generate runtime code, or use
  nondeterministic APIs.

Both node types are write-capable and reject an `access` field. Relative writes
modify the active workflow checkout and persist between executable nodes.
Bash and agents launched by JavaScript have host authority and can explicitly
address paths outside it. Do not describe the whole workflow as read-only
because its ordinary reviewer nodes are guarded. Review executable code and
its authority before running it; avoid deployments/live infrastructure in a
routine review workflow.

## 5. Outputs, reports, freshness, and fixing

Top-level `output.node` selects whose output becomes the summary. It is not an
automatic combination of every leaf node; use an explicit synthesis node when
that is required. Presentation supports `default`, `raw`, and `template`.
Template variables are `output`, `workflow`, `reportRef`, `runId`,
`snapshotStatus`, and `stale`.

Reports contain captured patches, resolved node inputs, node results and
isolated-writer metadata under the owning session's review-results directory.
Follow the returned full-results path instead of inventing storage paths.
Interactive review uses the active transcript session; each headless run gets
its own artifact scope. Concurrent reviews must not mix their evidence.

The report marks whether the snapshot remains current. If stale, inspect what
changed and rerun against the intended revision before applying old line-based
findings or claiming it passed. An AI review result is evidence, not human
approval. In an ordinary parent TUI, the configured presentation is appended
to the conversation; the parent can then address accepted findings through its
normal edit/test flow. After fixes, rerun the relevant workflow and, when human
review was requested, open a new `reviews local` snapshot.

Run `archdev --json check` before executing a new/changed definition. This
validates/compiles effective workflows and model selectors; it does not prove
that inference, tests, or executable nodes succeeded. Use a focused authorized
run and inspect its actual report for that proof.
