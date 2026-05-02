# CLAUDE.md  claude-code-plugin-image

Project specific guidance for any Claude Code session working in this repo.

## What this project is

A Claude Code plugin that exposes a single logical call, `Image(path, intent)`, modeled after `WebFetch(url, prompt)`. A Haiku worker loads the pixels, runs the intent, returns text. The main agent context never holds image bytes. A per image memory cache makes repeat questions free.

Read `README.md` for the full problem statement and design rationale before changing anything.

## Layout

```
.claude-plugin/plugin.json       plugin manifest
skills/image/SKILL.md            the skill the main agent invokes
agents/image-worker.md           Haiku subagent that loads pixels and owns the cache
evals/MANIFEST.md                test cases for an in-session agent runner
Makefile                         link, unlink
```

## Naming conventions

- The user facing call is written `Image(path, intent)` with a capital `I`, matching the shape of `Read`, `Edit`, `WebFetch`.
- Cache directory name is `image-memory`, never `image-profiles`.
- Hash is sha256 of raw image bytes. Cache key is the hash, not the path. Same bytes at multiple paths share one memory entry.

## Design rules

- Pixels never enter the main agent context. The skill must always go through the `image-worker` subagent.
- Worker model is Haiku. Do not switch to Sonnet or Opus without a written reason.
- The cache is markdown only. One file per image at `<id>.md` under `~/.claude/cache/image-memory/`. No index file. The cache directory IS the index. The file's own frontmatter lists every path alias for the same bytes.
- Each `<id>.md` has two sections. `## profile` is written once on first touch and never rewritten. `## answers` is append only.
- Every entry carries a `ts:` timestamp. The frontmatter tracks `last_accessed:`. These exist so the skill can reason about freshness, not for analytics.
- The skill accepts `max_age:` and `force:`. Default is no expiry. Invalidation is opt in, not automatic, because most cached images are static.
- Lookups consult `## profile` first (cheap, no model call), then `## answers`, then read the image as a last resort.
- Do not introduce an index file. If cross image queries become a real need, add it then. Premature now.
- Two image comparisons share one memory file, keyed off the first image. Reference the second image by path inside the answer.

## Build, run, test

Use the Makefile. Do not invent new commands.

```
make link      symlink this repo into ~/.claude/plugins/image
make unlink    remove the symlink
```

Evals are run by an agent inside a Claude Code session against `evals/MANIFEST.md`. There is no external test runner. Failing rows feed the next prompt iteration.

## What not to do

- Do not call `Read` on an image directly from the main agent. Always go through the skill.
- Do not pass base64 image data inside prompts. Always pass an absolute path.
- Do not add image generation features. This plugin is comprehension only. There are other plugins for generation.
- Do not add MCP servers, hooks, or settings.json changes unless the user asks.
- Do not rename `CLAUDE.md`.
- Do not add emojis to any file in this repo.
