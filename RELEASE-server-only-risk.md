# Server-owned PR grading distribution

Task D prepares public plugin version 0.49.7. This file records source work,
not a published artifact. Runtime A/B/C shipped in CLI 0.49.6; a CLI version
number alone does not establish that these skill changes are installed.

Canonical sources are root `archdev/`, `tasks/` and `tasks-execute/`.
Firstlanding commit `9b708c4338` removed the duplicate embedded skill bundles;
both CLIs now install the public repository archive. Regenerate plugins with
`npm run build` in `tools/plugin-gen`; never edit generated copies.

`.github/workflows/plugins.yml` runs typecheck, `npm test`, and `npm run check`
on every PR and push to main. The generator test `every plugin carries every
skill byte for byte, with its mode` covers all eight distributions. The
server-ownership test checks the real root instructions; the nudge process
suite runs generated shell hooks for PR creation, update, closure and push.
The bootstrap workflow separately checks Bash and PowerShell capability and
scope behavior. CLI archive fixtures in firstlanding prove transport, not
that a particular public revision was installed.

After review, humans merge the coordinated PRs. Before publication, record both
implementation commit SHAs and verify they are ancestors of the respective
release sources. CLI release owners must include firstlanding's D commit in
both Rust `archdev` and TS `archdev-old` releases. Record their source SHAs and
artifact checksums; run setup/upgrade smoke against those exact artifacts.
Record the public commit behind plugin version 0.49.7 and verify installed
files match it. If a release cuts first, select a new version and regenerate;
do not treat a version-only bump as inclusion evidence.

The public OpenCode package publishes through `.github/workflows/publish-opencode.yml`
on a matching `v*` tag; catalog and package versions must match that tag.
Other harnesses use their documented marketplace/plugin update paths. Publishing
or tagging is a separate release operation, not performed by this PR.
Hosted MCP instructions require the corresponding firstlanding deployment and
verification through the served skill resource. Task E owns published-artifact
and deployed-MCP verification.

An actual CLI upgrade refreshes installed user/current-checkout skills; the
already-latest path exits before refresh. With the existing consent boundaries,
use `archdev setup --skills --scope user --refresh` or `--scope repository`
for the intended checkout and scoped hook repair when needed. Other checkouts,
plugin caches, and loaded sessions are not swept. Update plugins and restart
sessions carrying the old contract, then inspect the installed files.

Capture absent means off; explicit on/off remain unchanged. On still requires
server eligibility and a valid subject/session link. Activity reporting and
plan/task risk remain. PR reports neither fetch nor attach grades, and no
historical fallback, partial-head repair or PR capture bridge is added.
