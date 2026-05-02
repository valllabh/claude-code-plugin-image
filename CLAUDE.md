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
- Worker model is configurable via `model:` in `agents/image-worker.md` frontmatter. Default is `inherit` (matches the calling session). `haiku` is the recommended override when cost or volume matters. Cache is model agnostic, so swapping models does not invalidate prior answers; use `force: true` or `max_age` to refresh.
- The cache is markdown only. One file per image at `<id>.md` under `~/.claude/cache/image-memory/`. No index file. The cache directory IS the index. The file's own frontmatter lists every path alias for the same bytes.
- Each `<id>.md` has two sections. `## profile` is written once on first touch and never rewritten. `## answers` is append only.
- Every entry carries a `ts:` timestamp and a `model:` line (the model that produced it). The frontmatter tracks `last_accessed:`. These exist so the skill can reason about freshness and provenance, not for analytics. Per entry model tracking means model upgrades do not require nuking the cache; selective regeneration is possible.
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

## Plugin authoring reference

Authoritative answers from the Claude Code docs, captured here so we do not re-research them.

**Manifest files**
- `.claude-plugin/marketplace.json` is REQUIRED for `/plugin marketplace add` to work. Required fields: `name`, `owner`, `plugins`. Each plugin entry needs `name` and `source`. Optional: `version`, `ref`, `sha`, `description`, `homepage`, `keywords`.
- `.claude-plugin/plugin.json` is OPTIONAL but recommended. If present, only `name` is required. Optional: `version`, `description`, `author`, `homepage`, `repository`, `license`, plus component path overrides.
- Docs: https://code.claude.com/docs/en/plugins-reference.md

**Component locations** (live at plugin root, NOT under `.claude-plugin/`)
- Skills: `skills/<name>/SKILL.md`. Required frontmatter: `description`. Optional: `disable-model-invocation`.
- Subagents: `agents/<name>.md`. Frontmatter: `name`, `description`, `model`, `effort`, `maxTurns`, `disallowedTools`, `skills`, `memory`, `background`, `isolation`.
- Hooks: `hooks/hooks.json` with event matchers like `PreToolUse`, `PostToolUse`.
- MCP / LSP servers: `.mcp.json` / `.lsp.json`.
- Monitors: `monitors/monitors.json`.

**Subagent `model:` values**
- `inherit` (default, uses calling session's model)
- aliases: `haiku`, `sonnet`, `opus`
- full ids: `claude-opus-4-7`, `claude-haiku-4-5`, etc.
- Docs: https://code.claude.com/docs/en/sub-agents.md

**Install flow users run**
1. `/plugin marketplace add <owner/repo|url|path>` Claude Code fetches `marketplace.json` and caches it.
2. `/plugin install <plugin-name>@<marketplace-name>` clones to `~/.claude/plugins/cache/<id>/`.
3. Components activate immediately. No restart required.
4. `/plugin update` is offered when `version:` in plugin.json is bumped.

**Versioning**
- Set `version: "x.y.z"` in plugin.json (semver). Bump on any user visible change. Skip the bump and Claude Code uses the git SHA as the version (one new version per commit, useful for dev).
- Docs: https://code.claude.com/docs/en/plugins-reference.md#version-management

**Local dev shortcut**
- `make link` symlinks the repo to `~/.claude/plugins/image` so edits show up without going through the marketplace flow.
- Use `/reload-plugins` to pick up changes mid session when running with `--plugin-dir`.

## What not to do

- Do not call `Read` on an image directly from the main agent. Always go through the skill.
- Do not pass base64 image data inside prompts. Always pass an absolute path.
- Do not add image generation features. This plugin is comprehension only. There are other plugins for generation.
- Do not add MCP servers, hooks, or settings.json changes unless the user asks.
- Do not rename `CLAUDE.md`.
- Do not add emojis to any file in this repo.
