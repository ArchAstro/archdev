import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

// The released-CLI workflow supplies the executable; generation-only jobs do
// not claim command acceptance from a source-text assertion.
test("the monitor's ordinary completion example is accepted by the released CLI", {
  skip: !process.env.ARCHDEV_CLI_UNDER_TEST,
}, () => {
  const root = mkdtempSync(path.join(tmpdir(), "archdev-lifecycle-example-"));
  try {
    const config = path.join(root, ".config", "archdev");
    mkdirSync(config, { recursive: true });
    const app = "dap_033y70rWJriCRNyb9uL0Pm";
    writeFileSync(path.join(config, "config.json"), JSON.stringify({ authMode: "org", defaultApp: app }));
    // Synthetic on-disk session, not a real credential. Dry-run must not
    // contact this deliberately unreachable loopback destination.
    writeFileSync(path.join(config, "credentials.json"), JSON.stringify({
      apps: {}, server: "http://127.0.0.1:1", orgSessions: {
        [app]: { accessToken: "example-test-only", appId: app, appName: "ArchDev", appSlug: "archdev",
          email: "agent@example.test", orgId: "org_test", orgName: "Test Org", userId: "usr_test" },
      },
    }));
    const monitor = readFileSync(new URL("../../../archdev/references/monitor.md", import.meta.url), "utf8");
    const example = monitor.split("\n").find(line => line.startsWith('"$archdev" log post') && line.includes("--kind done"));
    assert.ok(example, "the executable completion example exists");
    const result = spawnSync("bash", ["--noprofile", "--norc", "-c", `${example} --json --no-meta --dry-run`], {
      cwd: root, encoding: "utf8",
      env: {
        PATH: process.env.PATH, HOME: root, USERPROFILE: root,
        SystemRoot: process.env.SystemRoot, TMPDIR: root,
        ARCHDEV_NO_UPDATE_CHECK: "1", ARCHDEV_PRESENCE_DISABLED: "1",
        archdev: process.env.ARCHDEV_CLI_UNDER_TEST,
      },
    });
    assert.equal(result.status, 0, result.stderr);
    const post = JSON.parse(result.stdout);
    assert.equal(post.metadata.post_type, "done");
    assert.equal(post.metadata.event ?? "agent.message", "agent.message");
    assert.equal(post.metadata.pull_request, undefined);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
