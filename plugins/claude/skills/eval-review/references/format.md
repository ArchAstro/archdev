# Eval file format

One JSON object: `title`, `criteria` and `items`. `scripts/serve.mjs <file> --check`
reports every problem in a file in these terms.

## Top level

| Field | Type | Meaning |
|---|---|---|
| `title` | string | The eval's name, shown as the page title |
| `criteria` | array, at least 1 | The questions asked of every item |
| `items` | array, at least 1 | What is rated, in the order shown |

## Criterion

| Field | Type | Meaning |
|---|---|---|
| `key` | string, unique | The key its answer is saved under |
| `title` | string | The question |
| `hint` | string, optional | A line under the title; an item's own hint replaces it |
| `options` | array of 2 to 9 | `{ "value", "label" }`; values unique. Option N is answered with key N |
| `follow` | object, optional | Option value to a prompt. Choosing that option asks for one line of text |

Every criterion is single choice. For a scale, list its points as options. For
"which of these apply", ask one yes/no criterion per thing.

## Item

| Field | Type | Meaning |
|---|---|---|
| `key` | string, unique | The key its rating is saved under |
| `title` | string | The card's heading |
| `tag` | string, optional | A short category shown as a badge |
| `subtitle` | string, optional | A line under the heading |
| `href` | http(s) URL, optional | An "Open" link on the card |
| `hints` | object, optional | Criterion key to a hint for this item |
| `exhibit` | object or null, optional | What is being rated; see below |
| `parts` | array, optional | `{ "id", "label", "ref"? }`: things in the exhibit a reviewer can flag. `ref` names a reference that shows where the part lives |
| `references` | array, optional | What the item points at; see below |
| `description` | Markdown, optional | Shown beside the card. Raw HTML is not rendered |
| `files` | array, optional | `{ "filename", "status", "additions", "deletions", "patch" }`: the item's code, one entry per file. `patch` is that file's unified diff from its first `@@` line. `status` is `added`, `removed` or `modified` |

## Exhibits

Every kind may carry `headline` and `problem`, two short lines shown above it.
A missing `kind` is `image`.

### `image`

```json
{ "kind": "image", "mediaType": "image/svg+xml", "data": "<svg xmlns=\"http://www.w3.org/2000/svg\" …>", "alt": "What it shows" }
```

`mediaType` is `image/svg+xml` with the SVG as text, or `image/png` with base64
data. The picture is shown as an image, so nothing in an SVG runs and it sees
no page styles: give it `xmlns`, put its styles in a `<style>` element inside
it, and draw on a light background. It is shown on white in every theme.

### `compare`

```json
{ "kind": "compare", "options": [
  { "id": "a", "label": "A", "image": { "mediaType": "image/png", "data": "…", "alt": "Candidate A" } },
  { "id": "b", "label": "B", "image": { "mediaType": "image/png", "data": "…", "alt": "Candidate B" } }
] }
```

Two to four candidates side by side under your labels. The shell does not
shuffle or hide anything: for a blind comparison, decide the order per item
yourself, label the candidates neutrally, and write which is which to a file
the reviewer does not see. Ask about them by label ("Which is clearer?" with
options A, B, Equal, Neither).

### `frame`

```json
{ "kind": "frame", "html": "<style>…</style><div>…</div><script>…</script>", "data": { "anything": "json" }, "height": 320 }
```

Your own HTML, styles and script, run in a sandboxed frame: no network, no
access to the ArchDev page, no storage. Use it for an exhibit the reviewer
clicks inside, or a layout the other kinds cannot draw. `height` is the
starting height in pixels; the frame then follows its content.

Your script gets one global, `evalHost`:

| Member | What it does |
|---|---|
| `evalHost.data` | The `data` you put on the exhibit |
| `evalHost.rating` | The rating so far: `{ answers, why, flagged, note }` |
| `evalHost.flag(id)` | Flags or unflags a part |
| `evalHost.answer(criterion, value)` | Chooses an option of a criterion |
| `evalHost.open(ref)` | Opens one of the item's references |
| `evalHost.onRating(fn)` | Calls `fn(rating)` when the rating changes |

A clickable list where each line can be flagged:

```html
<style>li{cursor:pointer;padding:6px}li.flag{background:#fdecec}</style>
<ul><li data-id="claim-1">First claim</li><li data-id="claim-2">Second claim</li></ul>
<script>
  const paint = (rating) => {
    for (const li of document.querySelectorAll("li"))
      li.classList.toggle("flag", rating.flagged.includes(li.dataset.id));
  };
  for (const li of document.querySelectorAll("li"))
    li.addEventListener("click", () => evalHost.flag(li.dataset.id));
  paint(evalHost.rating);
  evalHost.onRating(paint);
</script>
```

Rules for a frame:

1. List the same ids in the item's `parts`, so flags also show as chips under
   the exhibit and survive in the ratings file with a label.
2. Everything must be inline. Images are `data:` URLs only; fetches, external
   scripts and stylesheets are blocked.
3. Draw on a light background with your own text colours.
4. Do not rebuild the criteria inside the frame. The rows under the exhibit are
   how every eval is answered; `evalHost.answer` is for a shortcut that belongs
   to the exhibit, such as "pick this candidate".

## References

```json
"references": [
  { "id": "pr", "kind": "pull", "label": "storefront #482", "href": "https://…", "description": "Markdown shown above the code" },
  { "id": "charge", "kind": "code", "label": "charge.ts", "path": "src/charge.ts", "startLine": 41, "endLine": 58, "side": "modified" },
  { "id": "spec", "kind": "link", "label": "Design spec", "href": "https://…" }
]
```

| Kind | Opens |
|---|---|
| `pull` | The side panel, with `description` above all the item's `files` and an "Open" link to `href` |
| `code` | The side panel on that file, at the hunk containing `startLine`-`endLine` (or the file's first hunk). `path` must be one of the item's `files`. `side` is `modified` (default) or `original` |
| `link` | `href` in a new tab |

## Ratings file

`<file>.ratings.json`, rewritten after every change:

```json
{ "<item key>": { "answers": { "<criterion key>": "<option value>" }, "why": { "<criterion key>": "text" }, "flagged": ["<part id>"], "note": "text", "at": "ISO time" } }
```

An item is fully rated when `answers` has every criterion. `why` only holds
text for answers that asked for it.

## Size

The session's item list is sent once and each item's exhibit, description and
files are sent when its card opens, so a file with hundreds of items is fine.
Keep one item's diff to what the reviewer needs; very large patches are slow to
draw.
