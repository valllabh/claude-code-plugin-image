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
image(path, intent)
```

Where `intent` is a free form instruction, the same way a `WebFetch` prompt is free form. Examples:

- `image("err.png", "extract every word of visible text")`
- `image("ui.png", "list UI components and their rough positions")`
- `image("chart.png", "give me the data as a markdown table")`
- `image("a.png", "diff against b.png")`
- `image("design.png", "critique the visual hierarchy")`
- `image("screen.png", "what error or state is shown")`

Under the hood the skill spawns a Haiku worker. The worker loads the image, runs the intent, and returns text. The main agent context never sees the pixels.

## Cache

A naive `(path, intent) -> answer` cache is too narrow. The same image gets asked many different questions over time, and recomputing each one wastes tokens.

The cache is layered as an image profile, written once per image and grown over use:

```
~/.claude/cache/image-profiles/<sha256>.md
```

Each profile holds facets:

- `text`     every word visible, OCR style dump
- `structure`     outline, headings, UI tree, table cells
- `elements`     components or objects with rough regions
- `metadata`     dimensions, type, dominant colors
- `summary`     short semantic gist
- `answers`     log of past `(intent, answer)` pairs
- `source`     original path

Routing on a new call:

1. Hash the image bytes.
2. If a profile exists, try to answer the intent from the relevant facet, or from a past answer.
3. If the intent needs pixels (spatial precision, novel question), spawn the Haiku worker, return the answer, and append it to `answers`.
4. The profile gets smarter the more it is used.

## How This Addresses the Problem

- Pixels stay out of the main context. Only text answers come back.
- Many small focused calls cost less than one large general call, because Haiku handles the pixel work.
- Repeat questions on the same image hit the cache and skip the model entirely.
- The main agent context window is preserved for the actual coding task.
- The cache compounds value across sessions, not just within one.

## Status

Scaffold only. Skill definition and worker prompt live under `skills/image/`.
