# plugin-gen

Generates every harness plugin in this repository from one harness-agnostic
catalog, `catalog/archdev.json`:

| Catalog field | What it is |
|---|---|
| `skills` | Skill directories at the repository root (also what `npx skills add ArchAstro/archdev` installs) |
| `mcp` | The remote ArchDev MCP server |
| `hooks` | The `archdev repo hook <action> --harness <h> --spec <n>` wiring, per abstract event |
| `harnesses.<h>.hooks` | Which events a harness gets, its CLI harness name and tool matcher; or `hooksUnsupported` with the reason |

`src/harnesses/<h>.ts` turns the catalog into that harness's files. Output goes
to `plugins/<h>/`, the marketplace files at the repository root
(`.claude-plugin/`, `.agents/plugins/`, `.github/plugin/`, `.cursor-plugin/`,
`.grok-plugin/`) and the root `package.json` Pi reads. `plugins/README.md` is
the install guide.

```sh
npm ci
npm run build      # regenerate after changing the catalog or a skill (git add new skill files first: only tracked files are copied)
npm run check      # CI: fails when committed output differs from the catalog
npm test           # harness contracts, hooks, Pi/OpenCode code, and all SKILL.md descriptions (<=1024 characters)
npm run e2e        # installs each plugin with the real harness CLI (local; skips missing CLIs)
```

The hook wiring mirrors the CLI's `src/ts/archdev/src/reviews/hooks/harnesses.ts`
in firstlanding: `hooks.spec`, the actions and the matchers must be supported
by the tagged CLI. The catalog's `version` versions the generated bundle;
it does not need to advance for CLI releases that leave that bundle unchanged.

## Release

The CLI release process creates `v<version>` on this repository's current main
without updating the catalog. Install commands pin that tag. Change the catalog
and run `npm run build` when the bundle needs updating, not for every CLI tag.

The tag push runs `.github/workflows/publish-opencode.yml`. It requires a
commit from main, a valid version tag, and committed package/catalog consistency,
then reruns the plugin CI. Only after those checks pass does
`scripts/opencode-release-version.mjs --prepare` set the npm artifact's version
to the release tag's version. The catalog and bundled code/skills stay unchanged.
It publishes `@archastro/archdev-opencode@<version>` through npm trusted
publishing with provenance.

Run the workflow by hand with `dry_run` to pack and validate without publishing.
On a branch, dry runs use the catalog version; on a tag, they use the tag version.
Both get an unpublished `-dryrun.<run>.<attempt>` version before registry checks.
Non-dry-run publication requires a tag. Rerunning an old failed run still uses
that tag's old workflow; merging a workflow fix applies to future release tags,
not retroactively to existing tags.

One-time npm setup by an `@archastro` owner: from the repository root at the
release tag, run `node scripts/opencode-release-version.mjs --prepare` with
`GITHUB_REF=refs/tags/v<version>` and `GITHUB_REF_TYPE=tag`, then publish the
prepared package (`npm publish ./plugins/opencode --access public`). Connect
this workflow with
`npm trust github @archastro/archdev-opencode --repository ArchAstro/archdev --file publish-opencode.yml`
or the package's Trusted Publisher settings on npmjs.com.

## Agent instruction scope

Describe the actions an agent needs for its workflow. Do not introduce unrelated
capabilities merely to tell the agent not to use them; that adds distracting
context and can prompt unwanted exploration. Keep capture configuration and
release constraints in their dedicated documentation. Remove obsolete
obligations when behavior changes.
