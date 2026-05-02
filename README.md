# claude-code-plugin-image

Let Claude Code work with images without burning your context window.

## What it does

Pass an image path and what you want to know. Get text back. Your main session never holds the pixels. By default the worker uses the same model as your session, but you can dial it down to Haiku in one line for cheap, fast image work.

```
Image("err.png", "what error is shown")
Image("chart.png", "give me the data as a table")
Image("design.png", "list the UI sections")
Image("a.png", "diff against b.png")
```

Same shape as Claude Code's built in `WebFetch(url, prompt)`. A subagent looks at the image, runs your question, returns plain text. Your context only sees the answer.

## Why it matters

Reading an image directly puts ~1000 to 1700 tokens of pixel data into your main context, and it stays there for the whole session. Open ten screenshots in one task and you have lost a third of your context window before you have done any work.

| approach | tokens added to your main context | sticks around |
|---|---|---|
| `Read` an image directly | 1000 to 1700 | yes, for the rest of the session |
| `Image(path, intent)` | 50 to 300 (just the answer) | yes, but cheap |
| `Image(path, intent)` again on the same image | 50 to 300 | served from cache, no model call |

Rule of thumb: at two or more images in a session, this plugin pays for itself. At ten, it is the difference between finishing the task and hitting context limits.

## When to use it

Reach for `Image(...)` whenever you would otherwise call `Read` on an image:

- Many screenshots in one session.
- One screenshot you keep coming back to with new questions.
- Long sessions where context is precious.
- The user wants text understanding, not pixel level judgement.

Skip it when:

- A single throwaway question on a single image.
- The user explicitly says to look at the image yourself.
- You need pixel precise reasoning that a text answer cannot capture.

## Install

Works on macOS, Linux, and Windows (WSL or Git Bash). Needs `sha256sum`, `shasum`, or `python3` on PATH (all three ship by default on the supported platforms).

```bash
git clone https://github.com/valllabh/claude-code-plugin-image.git
cd claude-code-plugin-image
make link
```

Restart Claude Code. From then on, when the user asks about an image, Claude Code routes the question through `Image(path, intent)` automatically. To remove: `make unlink`.

## How it works

Two pieces:

- `skills/image/SKILL.md`  the recipe the main agent follows. Tiny: hand the path and intent to the worker, return the worker's text.
- `agents/image-worker.md`  the subagent that actually looks at the image and owns a small markdown cache. Model is configurable via the `model:` line in its frontmatter. Default `inherit` (use the session's model). Set to `haiku` for the cheapest, fastest path.

The cache lives at `~/.claude/cache/image-memory/<id>.md`, one file per unique image (id is sha256 of bytes). Each file has a `## profile` block written once (text, summary, kind, dims, elements) and a `## answers` log appended over time. Common questions get answered straight from the profile without re-reading the image. There is no index file. The cache directory is its own index.

Every entry carries a `ts:` timestamp and the file tracks `last_accessed:`. The skill accepts an optional `max_age:` (e.g. `1h`, `7d`, `never`) and a `force:` flag, so time sensitive questions or model upgrades can bypass stale answers. Default is `never` because most images are static (a screenshot from yesterday is the same screenshot today).

For full design notes including the why behind each choice, see `CLAUDE.md`.

## Evals

`evals/MANIFEST.md` lists test scenarios across screenshot styles, paraphrased intents, novel questions, two image comparisons, and an end to end loop using `agent-browser` to capture a fresh page and ask the skill about it. Runs are logged under `evals/runs/`.

Latest observed numbers:

| path | tool calls | image read by worker |
|---|---|---|
| cold (first question on a new image) | 6 to 10 | yes |
| warm (intent maps to a profile field) | 4 to 6 | no |
| warm (exact prior intent repeated) | 4 to 6 | no |
| novel (new question on cached image) | 14 to 16 | yes |

Open follow ups: chart and photo coverage, two image diff coverage, embedding based intent matching, cache eviction policy.
