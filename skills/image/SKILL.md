---
name: image
description: Work with a local image without loading pixels into the main context. Pass an image path and a free form intent (extract text, list UI elements, read a chart, compare two images, classify, locate, identify error, critique). Returns text only. Use whenever the user asks anything about an image file, screenshot, design, mockup, chart, diagram, photo, or any visual artifact on disk. Prefer this over reading the image directly.
---

# image

Shape: `Image(path, intent)`. Modeled after `WebFetch`. Delegate to the `image-worker` subagent. Worker loads pixels, manages the cache, returns text. Your context never sees the bytes.

## Invoke when

The user asks anything about a local image and you would otherwise call `Read` on it. Skip if the user only wants to view the image.

## How

Spawn `image-worker` with one message:

```
path:      <absolute path, or two paths separated by newline for diff>
intent:    <user request, verbatim, do not paraphrase>
cache_dir: ~/.claude/cache/image-memory
max_age:   <optional. e.g. 1h, 7d, never. Default: never.>
force:     <optional. true to bypass cache. Default: false.>
```

Pass `max_age` when the user's question is time sensitive (e.g. asking about a dashboard screenshot of live data, or after a model upgrade where you want fresh answers). Pass `force: true` when the user explicitly says "re-look" or you suspect the cached answer is wrong. Otherwise omit both and the cache lives forever, which is correct for static images like screenshots.

Return the worker's text to the user as is. No summarizing, no prefix, no annotation.

## Rules

- Never `Read` an image directly.
- Always pass absolute paths. Never base64.
- For comparisons, pass two paths.
- Surface worker errors as is. Do not retry blindly.
