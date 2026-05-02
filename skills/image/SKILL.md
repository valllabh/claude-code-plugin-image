---
name: image
description: Work with a local image file without loading pixels into the main context. Pass an image path and a free form intent (extract text, list UI elements, read a chart, compare two images, critique a design, classify, locate, identify error). Returns text only. Use this whenever the user asks anything about an image file, screenshot, design, mockup, chart, diagram, photo, or any visual artifact on disk. Prefer this over reading the image directly with the Read tool.
---

# image

Shaped like `WebFetch`. The user facing call is `Image(path, intent)`. You never read the pixels yourself. You delegate to the `image-worker` subagent. The worker loads the image, manages a small markdown memory cache, and returns text. Your main context never sees the bytes.

## When to invoke

Whenever the user request involves a local image and you would otherwise call `Read` on it. Examples:

- "what does this screenshot show"
- "extract the error from screen.png"
- "what columns are in this table image"
- "diff these two design exports"
- "give me the chart values"

If the user only wants to view the image themselves, do not invoke this. Only invoke when text understanding is needed.

## How to invoke

Spawn the `image-worker` subagent with a single message containing:

```
path:      <absolute path to the image, or two paths separated by a newline for comparisons>
intent:    <free form instruction, exactly what the user asked, do not paraphrase>
cache_dir: ~/.claude/cache/image-memory
```

The worker does everything from there. It returns plain text. Return that text to the user as is. Do not summarize, prefix, or annotate it unless the user asked you to.

## Rules

- Never call `Read` on an image directly.
- Always pass absolute paths.
- Never pass base64 image data inside the prompt. Only the path.
- For comparisons, pass two paths. The worker picks one as the cache anchor.
- If the worker reports an error, surface it as is. Do not retry blindly.
