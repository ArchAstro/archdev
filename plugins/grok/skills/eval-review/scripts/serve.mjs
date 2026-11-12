#!/usr/bin/env node
// Hosts one eval, described by a JSON file, as an ArchDev eval review session on loopback and prints the
// link a person opens to rate it. Node 18 or newer; no dependencies.
//
//   node serve.mjs <eval.json>              serve it and open the browser
//   node serve.mjs <eval.json> --no-open    serve it and only print the link
//   node serve.mjs <eval.json> --check      validate the file and exit
//   node serve.mjs <eval.json> --summary    print what has been rated so far and exit
//
// Options: --port <n> (default: any free port), --origin <url> (default https://archdev.ai).
// Ratings are written beside the file as <eval.json>.ratings.json, keyed by item, after every change.
// The file format is in ../references/format.md.
import { createServer } from "node:http";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, renameSync } from "node:fs";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const option = (name, fallback) => { const i = args.indexOf(`--${name}`); return i >= 0 && args[i + 1] ? args[i + 1] : fallback; };
const valued = new Set(["--port", "--origin"]);
const file = args.find((a, i) => !a.startsWith("--") && !valued.has(args[i - 1]));
if (!file) { console.error("usage: node serve.mjs <eval.json> [--check | --summary] [--no-open] [--port <n>] [--origin <url>]"); process.exit(2); }
const path = resolve(file), ratingsPath = `${path}.ratings.json`;
const origin = option("origin", "https://archdev.ai").replace(/\/$/, "");

const isRecord = (v) => typeof v === "object" && v !== null && !Array.isArray(v);
const isText = (v) => typeof v === "string" && v.length > 0;
const isWebLink = (v) => { try { return ["https:", "http:"].includes(new URL(v).protocol); } catch { return false; } };
const isImage = (v) => isRecord(v) && isText(v.data) && (v.mediaType === "image/svg+xml" || v.mediaType === "image/png");

// Every problem in the file, in the words of the file's author. An empty list means the web app will accept it.
function problems(def) {
  const out = [];
  if (!isRecord(def)) return ["the file is not a JSON object"];
  if (!isText(def.title)) out.push("title: missing");
  const criteria = Array.isArray(def.criteria) ? def.criteria : [];
  if (criteria.length === 0) out.push("criteria: at least one is required");
  const criterionKeys = new Set();
  criteria.forEach((c, i) => {
    const at = `criteria[${i}]${isRecord(c) && isText(c.key) ? ` (${c.key})` : ""}`;
    if (!isRecord(c) || !isText(c.key) || !isText(c.title)) return out.push(`${at}: needs a key and a title`);
    if (criterionKeys.has(c.key)) out.push(`${at}: key is used twice`);
    criterionKeys.add(c.key);
    const options = Array.isArray(c.options) ? c.options : [];
    if (options.length < 2 || options.length > 9) out.push(`${at}: needs two to nine options (one number key each)`);
    if (!options.every((o) => isRecord(o) && isText(o.value) && isText(o.label))) out.push(`${at}: every option needs a value and a label`);
    const values = options.map((o) => o?.value);
    if (new Set(values).size !== values.length) out.push(`${at}: an option value is used twice`);
    for (const k of Object.keys(isRecord(c.follow) ? c.follow : {})) if (!values.includes(k)) out.push(`${at}: follow names "${k}", which is not an option value`);
  });
  const items = Array.isArray(def.items) ? def.items : [];
  if (items.length === 0) out.push("items: at least one is required");
  const itemKeys = new Set();
  items.forEach((item, i) => {
    const at = `items[${i}]${isRecord(item) && item.key !== undefined ? ` (${item.key})` : ""}`;
    if (!isRecord(item) || !isText(String(item.key ?? "")) || !isText(item.title)) return out.push(`${at}: needs a key and a title`);
    if (itemKeys.has(String(item.key))) out.push(`${at}: key is used twice`);
    itemKeys.add(String(item.key));
    if (item.href !== undefined && !isWebLink(item.href)) out.push(`${at}: href must be an http(s) link`);
    for (const k of Object.keys(isRecord(item.hints) ? item.hints : {})) if (!criterionKeys.has(k)) out.push(`${at}: hints names "${k}", which is not a criterion`);
    const e = item.exhibit;
    if (e !== undefined && e !== null) {
      const kind = isRecord(e) ? e.kind ?? "image" : null;
      if (kind === "image") { if (!isImage(e)) out.push(`${at}: an image exhibit needs mediaType image/svg+xml or image/png, and data`); }
      else if (kind === "compare") {
        const options = Array.isArray(e.options) ? e.options : [];
        if (options.length < 2 || options.length > 4) out.push(`${at}: a compare exhibit needs two to four options`);
        if (!options.every((o) => isRecord(o) && isText(o.id) && isText(o.label) && isImage(o.image))) out.push(`${at}: every compare option needs an id, a label and an image`);
      } else if (kind === "frame") { if (!isText(e.html)) out.push(`${at}: a frame exhibit needs html`); }
      else out.push(`${at}: exhibit kind must be image, compare or frame`);
    }
    const files = new Set((Array.isArray(item.files) ? item.files : []).map((f) => f?.filename));
    const refs = new Set();
    (Array.isArray(item.references) ? item.references : []).forEach((r, j) => {
      const where = `${at} references[${j}]`;
      if (!isRecord(r) || !isText(r.id) || !isText(r.label)) return out.push(`${where}: needs an id and a label`);
      refs.add(r.id);
      if (r.kind === "pull") { if (r.href !== undefined && !isWebLink(r.href)) out.push(`${where}: href must be an http(s) link`); }
      else if (r.kind === "code") { if (!isText(r.path)) out.push(`${where}: a code reference needs a path`); else if (!files.has(r.path)) out.push(`${where}: path ${r.path} is not among the item's files, so there is no code to open`); }
      else if (r.kind === "link") { if (!isWebLink(r.href)) out.push(`${where}: a link reference needs an http(s) href`); }
      else out.push(`${where}: kind must be pull, code or link`);
    });
    (Array.isArray(item.parts) ? item.parts : []).forEach((p, j) => {
      if (!isRecord(p) || !isText(p.id) || !isText(p.label)) out.push(`${at} parts[${j}]: needs an id and a label`);
      else if (p.ref !== undefined && !refs.has(p.ref)) out.push(`${at} parts[${j}]: ref "${p.ref}" is not one of the item's references`);
    });
    (Array.isArray(item.files) ? item.files : []).forEach((f, j) => { if (!isRecord(f) || !isText(f.filename)) out.push(`${at} files[${j}]: needs a filename`); });
  });
  return out;
}

let definition;
try { definition = JSON.parse(readFileSync(path, "utf8")); } catch (e) { console.error(`${file}: ${e.message}`); process.exit(1); }
const found = problems(definition);
if (found.length) { console.error(`${file} has ${found.length} problem${found.length === 1 ? "" : "s"}:\n${found.map((p) => `  - ${p}`).join("\n")}`); process.exit(1); }
const items = new Map(definition.items.map((item) => [String(item.key), item]));
const allowed = new Map(definition.criteria.map((c) => [c.key, new Set(c.options.map((o) => o.value))]));
const readRatings = () => (existsSync(ratingsPath) ? JSON.parse(readFileSync(ratingsPath, "utf8")) : {});
const complete = (rating) => definition.criteria.every((c) => rating?.answers?.[c.key]);

if (flag("check")) { console.log(`${file}: ok · ${items.size} items · ${definition.criteria.length} criteria`); process.exit(0); }
if (flag("summary")) {
  const ratings = readRatings(), rated = [...items.keys()].filter((k) => complete(ratings[k]));
  console.log(`${definition.title}: ${rated.length} of ${items.size} rated${existsSync(ratingsPath) ? ` · ${ratingsPath}` : " · nothing saved yet"}`);
  for (const c of definition.criteria) console.log(`  ${c.title}\n    ${c.options.map((o) => `${o.label} ${[...items.keys()].filter((k) => ratings[k]?.answers?.[c.key] === o.value).length}`).join(" · ")}`);
  const flagged = Object.values(ratings).reduce((n, r) => n + (r.flagged?.length ?? 0), 0), notes = Object.values(ratings).filter((r) => r.note || Object.keys(r.why ?? {}).length).length;
  console.log(`  ${flagged} parts flagged · ${notes} items with a note or an explanation`);
  const open = [...items.keys()].filter((k) => !complete(ratings[k]));
  if (open.length) console.log(`  not rated: ${open.join(", ")}`);
  process.exit(0);
}

// Keeps only answers the criteria offer, so a bad write cannot poison the saved file.
function clean(rating) {
  const r = isRecord(rating) ? rating : {}, answers = {}, why = {};
  for (const [k, values] of allowed) if (values.has(r.answers?.[k])) { answers[k] = r.answers[k]; if (typeof r.why?.[k] === "string" && r.why[k]) why[k] = r.why[k].slice(0, 2000); }
  return { answers, why, flagged: Array.isArray(r.flagged) ? r.flagged.filter(isText).slice(0, 100) : [], note: typeof r.note === "string" ? r.note.slice(0, 8000) : "" };
}
function store(key, rating) {
  const all = readRatings(), at = new Date().toISOString();
  all[key] = { ...clean(rating), at };
  writeFileSync(`${ratingsPath}.tmp`, JSON.stringify(all, null, 1) + "\n");
  renameSync(`${ratingsPath}.tmp`, ratingsPath);
  return at;
}

const session = randomBytes(16).toString("hex"), token = randomBytes(32).toString("base64url");
const bearer = Buffer.from(`Bearer ${token}`);
const authorized = (header) => { const given = Buffer.from(String(header ?? "")); return given.length === bearer.length && timingSafeEqual(given, bearer); };
const cors = { "access-control-allow-origin": origin, "access-control-allow-headers": "authorization, content-type", "access-control-allow-methods": "GET, POST, OPTIONS", "access-control-max-age": "600", vary: "Origin, Access-Control-Request-Private-Network" };
const send = (res, code, body) => { res.writeHead(code, { ...cors, "content-type": "application/json", "cache-control": "no-store" }); res.end(JSON.stringify(body)); };
const MAX_BODY = 1024 * 1024;
const readBody = (req) => new Promise((ok, fail) => { let s = ""; req.on("data", (d) => { s += d; if (s.length > MAX_BODY) { fail(Object.assign(new Error("The request is too large"), { status: 413 })); req.destroy(); } }); req.on("end", () => ok(s)); req.on("error", fail); });

const server = createServer(async (req, res) => {
  try {
    if (req.method === "OPTIONS") { res.writeHead(204, { ...cors, ...(req.headers["access-control-request-private-network"] ? { "access-control-allow-private-network": "true" } : {}) }); return res.end(); }
    // Only the web app's origin may call, and only with this session's token.
    if (req.headers.origin !== origin) return send(res, 403, { error: "This origin may not read the eval session" });
    if (!authorized(req.headers.authorization)) return send(res, 401, { error: "The eval link's capability is missing or wrong" });
    const url = new URL(req.url, "http://127.0.0.1");
    if (req.method === "GET" && url.pathname === "/v1/session") return send(res, 200, {
      schema: "archdev.eval-session.v1", id: session, title: definition.title, criteria: definition.criteria,
      items: definition.items.map(({ key, title, tag, subtitle, href, hints }) => ({ key: String(key), title, tag, subtitle, href, hints })),
      ratings: Object.fromEntries(Object.entries(readRatings()).filter(([key]) => items.has(key))),
    });
    const key = /^\/v1\/items\/(.+)$/.exec(url.pathname)?.[1];
    const item = key && items.get(decodeURIComponent(key));
    if (req.method === "GET" && item) return send(res, 200, { schema: "archdev.eval-item.v1", key: String(item.key), exhibit: item.exhibit ?? null, parts: item.parts ?? [], references: item.references ?? [], description: item.description, files: item.files ?? [] });
    if (req.method === "POST" && url.pathname === "/v1/feedback") {
      let body;
      try { body = JSON.parse(await readBody(req)); } catch (e) { return send(res, e.status ?? 400, { error: e.status ? e.message : "The rating is not valid JSON" }); }
      if (body?.schema !== "archdev.eval-feedback.v1" || body.session !== session || !items.has(body.item)) return send(res, 400, { error: "The rating names a different session or item" });
      return send(res, 200, { ok: true, at: store(body.item, body.rating) });
    }
    return send(res, 404, { error: "Not found" });
  } catch (e) {
    send(res, 500, { error: String(e?.message ?? e) });
  }
});

server.listen(Number(option("port", "0")), "127.0.0.1", async () => {
  const link = `${origin}/local-review?kind=eval#endpoint=http://127.0.0.1:${server.address().port}&session=${session}&token=${token}`;
  // The web app serves /eval-frame only once it has eval review; a development server serves the file itself.
  const supported = await Promise.any(["/eval-frame", "/eval-frame.html"].map(async (p) => { const r = await fetch(origin + p, { redirect: "manual" }); if (r.status !== 200) throw new Error(String(r.status)); })).then(() => true, () => false);
  if (!supported) console.error(`warning: ${origin} did not serve /eval-frame, so it may not have eval review yet. The link below will show a local diff review error if so.`);
  console.log(`${definition.title} · ${items.size} items · ratings in ${ratingsPath}`);
  console.log(link);
  console.log("Keep this running while the review is open. A restart makes a new link; saved ratings are kept.");
  if (!flag("no-open")) {
    const [cmd, argv] = process.platform === "darwin" ? ["open", [link]] : process.platform === "win32" ? ["cmd", ["/c", "start", "", link.replace(/&/g, "^&")]] : ["xdg-open", [link]];
    spawn(cmd, argv, { stdio: "ignore", detached: true }).on("error", () => console.error("Could not open a browser; open the link above by hand.")).unref();
  }
});
