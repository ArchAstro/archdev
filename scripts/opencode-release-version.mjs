// Run from the repository root. Validate committed source before stamping the
// npm artifact; CLI release tags do not update the plugin catalog on main.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';

assert.ok(process.argv.length === 2 || (process.argv.length === 3 && process.argv[2] === '--prepare'),
  'Usage: node scripts/opencode-release-version.mjs [--prepare]');

const numeric = '(?:0|[1-9]\\d*)';
const prerelease = '(?:0|[1-9]\\d*|\\d*[A-Za-z-][0-9A-Za-z-]*)';
// Absolute end, including for refs containing a trailing newline. Build metadata
// is deliberately excluded, as npm does not distinguish it in package versions.
const semver = new RegExp(`^${numeric}\\.${numeric}\\.${numeric}(?:-${prerelease}(?:\\.${prerelease})*)?(?![\\s\\S])`);
const catalog = JSON.parse(readFileSync('catalog/archdev.json', 'utf8'));
const packagePath = 'plugins/opencode/package.json';
const pkg = JSON.parse(readFileSync(packagePath, 'utf8'));
assert.equal(pkg.name, '@archastro/archdev-opencode', 'Unexpected OpenCode package name');
assert.equal(pkg.version, catalog.version, 'plugins/opencode is out of date with the catalog');
assert.match(catalog.version, semver, 'Invalid catalog version');

const ref = process.env.GITHUB_REF || '';
let version;
if (process.env.GITHUB_REF_TYPE === 'tag') {
  assert.ok(ref.startsWith('refs/tags/v'), 'Publishing requires a version tag: refs/tags/v<semver>');
  version = ref.slice('refs/tags/v'.length);
  assert.match(version, semver, 'Publishing requires a version tag: refs/tags/v<semver>');
} else {
  assert.ok(process.env.DRY_RUN === 'true' && process.env.GITHUB_REF_TYPE === 'branch' && ref.startsWith('refs/heads/'),
    'Publishing requires a version tag; only branch dry runs may use the catalog version');
  version = catalog.version;
}

if (process.argv[2] === '--prepare') {
  // Only the artifact's package version changes. Source consistency is checked
  // against the catalog above, and the generated bundle is tested before this.
  writeFileSync(packagePath, JSON.stringify({ ...pkg, version }, null, 2) + '\n');
}
console.log(version);
