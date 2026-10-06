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
npm test           # contracts for every harness's files, the hook guard, Pi and OpenCode code
npm run e2e        # installs each plugin with the real harness CLI (local; skips missing CLIs)
```

The hook wiring mirrors the CLI's `src/ts/archdev/src/reviews/hooks/harnesses.ts`
in firstlanding: `hooks.spec`, the actions and the matchers must match the
release named by `version`.

## Release

Set `version` in the catalog to the CLI release, run `npm run build`, and
merge before the CLI release tags `v<version>` on main. Install commands pin
that tag.

The tag push runs `.github/workflows/publish-opencode.yml`, which checks that
the tag matches the catalog, reruns the plugin CI, and publishes
`plugins/opencode` as `@archastro/archdev-opencode@<version>` through npm
trusted publishing with provenance. Run it by hand with `dry_run` to pack and
validate without publishing.

One-time npm setup by an `@archastro` owner: publish the first version by hand
(`npm publish plugins/opencode --access public` from the release tag), then
connect this workflow with
`npm trust github @archastro/archdev-opencode --repository ArchAstro/archdev --file publish-opencode.yml`
or the package's Trusted Publisher settings on npmjs.com.
