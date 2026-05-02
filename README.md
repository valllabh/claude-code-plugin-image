# claude-code-plugin-image

A Claude Code plugin that lets the main agent work with images without loading pixels into its own context. Modeled after `WebFetch`: pass a path and an intent, get text back.

## The Problem

When Claude Code reads an image with the `Read` tool, the pixels enter the main conversation context. Each image consumes roughly 1000 to 1500 tokens, and large or numerous images push the session toward its context limit fast. Once an image is in context there is no clean way to evict it short of full compaction.

Observed pain in the wild:

- anthropics/claude-code#37461  Need ability to selectively remove images from context without full compaction
- anthropics/claude-code#25813  Image context handling causes premature context limit exceeded errors
- anthropics/claude-code#22374  Infinite retry loop in many image context
- anthropics/claude-code#14483  PDF with many images keeps context history bloated

The deeper issue is not just bloat. The main agent ends up doing every kind of image work itself: reading text, locating elements, extracting tables, classifying, comparing. Each of those is a focused task that a smaller, faster model can handle in isolation and return as plain text.

## The Pattern Already Exists for the Web

`WebFetch(url, prompt)` does not put HTML into the main context. It hands the URL and prompt to a small, fast model, which loads the bytes, runs the prompt, and returns text. The main agent only sees the answer.

There is no equivalent for images. This plugin fills that gap.

## The Solution

A single skill, `image`, with one shape:

```
Image(path, intent)
```

Where `intent` is a free form instruction, the same way a `WebFetch` prompt is free form. Examples:

- `Image("err.png", "extract every word of visible text")`
- `Image("ui.png", "list UI components and their rough positions")`
- `Image("chart.png", "give me the data as a markdown table")`
- `Image("a.png", "diff against b.png")`
- `Image("design.png", "critique the visual hierarchy")`
- `Image("screen.png", "what error or state is shown")`

Under the hood the skill spawns a Haiku worker. The worker loads the image, runs the intent, and returns text. The main agent context never sees the pixels.

## Cache

Markdown only. Two pieces: an `index.md` for cross image lookup, and one `<sha>.md` per image.

```
~/.claude/cache/image-memory/
  index.md             one row per image
  <sha256>.md          per image memory
```

`index.md` is a single markdown table. Linear scan is fine at the scales this cache operates at (hundreds, low thousands of images).

```
| sha | sources | kind | dims | created | tags |
|-----|---------|------|------|---------|------|
| ... | ...     | ...  | ...  | ...     | ...  |
```

Per image file has a fixed shape:

```
---
source(s):
  - /absolute/path/one.png
  - /absolute/path/two.png
sha256: ...
created: ...
---

## profile         (written once on first touch, never rewritten)
text:     every visible word, OCR style
summary:  one paragraph
kind:     screenshot | photo | diagram | chart | mockup | other
dims:     WxH
elements: short list of salient regions

## answers         (append only)
### intent: <intent string>
<answer>

### intent: <intent string>
<answer>
```

Routing on a new call:

1. Hash the image bytes. Add the path to `sources` in `index.md` if new.
2. If the `<sha>.md` file is missing or has no `## profile` section, spawn the worker once to populate `## profile`. Pays for itself across all future questions on this image.
3. Try to answer the intent from `## profile`. Most "what text", "what kind", "summarize" intents resolve here with no model call.
4. Else search `## answers` for a normalized match on the intent string. Hook for embeddings later.
5. Else spawn the worker. Append a new `### intent` block to `## answers`.

Why this shape:

- Markdown loads natively into the agent. No parser, no schema, no dependency.
- Same bytes at multiple paths share one memory file. Key is sha, not path.
- `## profile` carries canonical facets, so paraphrased questions hit cache instead of respawning the worker.
- `## answers` is append only. No rewrites means concurrent worker writes are safe enough for a single user local cache.
- Every piece is human inspectable and hand editable when something goes wrong.

## How This Addresses the Problem

- Pixels stay out of the main context. Only text answers come back.
- Many small focused calls cost less than one large general call, because Haiku handles the pixel work.
- Repeat questions on the same image hit the cache and skip the model entirely.
- The main agent context window is preserved for the actual coding task.
- The cache compounds value across sessions, not just within one.

## Install

Requires Claude Code. macOS, Linux, or Windows (WSL or Git Bash). Python 3.7 or newer is recommended for the cache helper. The worker falls back to `sha256sum` or `shasum` if Python is unavailable.

```bash
git clone https://github.com/valllabh/claude-code-plugin-image.git
cd claude-code-plugin-image
make link        # symlinks repo into ~/.claude/plugins/image
```

Restart Claude Code so the new skill and subagent are picked up. After that, the main agent will route any image question through `Image(path, intent)` automatically. To remove: `make unlink`.

## Layout

```
.claude-plugin/plugin.json   plugin manifest
skills/image/SKILL.md        the skill the main agent invokes
agents/image-worker.md       Haiku subagent that loads pixels and manages the cache
scripts/image_cache.py       cross platform helper for sha256, paths, index ops
evals/MANIFEST.md            test cases the agent can run inside Claude Code
Makefile                     link / unlink
CLAUDE.md                    project rules for any session working in this repo
```

## Evals

See `evals/MANIFEST.md`. The eval loop is itself agent driven: a Claude Code session walks the test rows, invokes `Image(path, intent)`, and writes results to `evals/runs/<timestamp>.md`. One of the loops uses `agent-browser` to take a fresh screenshot of an unfamiliar page, then asks the skill about it, exercising the skill against truly novel input.

## Status

End to end working with cache. Cold and warm paths verified on real screenshots. Iterating on prompt clarity and eval coverage.
