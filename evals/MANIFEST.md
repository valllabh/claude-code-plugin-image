# evals

How to verify the `image` skill across image styles. Each row is a test the agent can run inside a Claude Code session by invoking `Image(path, intent)` and judging the output. No external test runner. The agent is the runner.

The image set is intentionally not bundled. We do not assume any image generation tool (ImageMagick, etc.) is installed. Use real images from your own machine. On macOS the user keeps screenshots in `~/Screenshots`. On other systems use any local images.

## Run one round

For each row below, the test agent should:
1. Resolve a real image path that fits the `style` column.
2. Invoke `Image(path, intent)`.
3. Verify the answer against the `expect` column. Pass / fail / partial.
4. Record the result in `evals/runs/<iso-timestamp>.md`.

The first call on any image is cold (worker spawned). The second identical call should be served from the cache. A paraphrase of the same intent that maps to a profile field should also avoid spawning the worker. Verify both.

## Test rows

| id | style | intent | expect |
|----|-------|--------|--------|
| t1 | UI screenshot, sidebar nav | extract every word of visible text | every visible word, no hallucinations |
| t2 | UI screenshot | what kind of application is this | one paragraph, names visible app sections |
| t3 | UI screenshot, with a visible error or alert | what error or warning is shown | exact error text or [none visible] |
| t4 | dense text document or article | give me the body text as plain text | full body, paragraph order preserved |
| t5 | chart or graph | give me the data as a markdown table | table with axis labels and values, marked approximate where unclear |
| t6 | architecture or flow diagram | list the nodes and the edges between them | bulleted nodes, edges as `A -> B` |
| t7 | photo with no text | what is in this photo | one paragraph description |
| t8 | mockup or wireframe | list UI components and their rough positions | bulleted regions like top bar, left rail, modal center |
| t9 | screenshot containing a code snippet | extract the code verbatim | code block, indentation preserved |
| t10 | two related screenshots, before and after | diff against <other-path>, list only what changed | bulleted differences only |

## Cache hit checks

After running t1 once:
- Re-run t1 verbatim. Worker should not be spawned. Result returned from `## answers`.
- Run "read all the text" on the same image. Should serve from `## profile.text` field, no worker.
- Run "summarize this" on the same image. Should serve from `## profile.summary`, no worker.

## End to end with agent-browser

This loop exercises the skill against fresh, unfamiliar UI:

1. Use `agent-browser --cdp 9222` to navigate to a URL the test author has not opened before. Suggested:
    - github.com/anthropics/claude-code
    - the local Claude Code docs page
    - a random open issue page
2. Take a screenshot via agent-browser, save to `/tmp/eval-shot.png`.
3. Invoke `Image("/tmp/eval-shot.png", "what is this page about, three lines")`.
4. Verify the summary names the actual page subject.
5. Invoke `Image("/tmp/eval-shot.png", "list the primary navigation links")`.
6. Verify links match what is visible on the page.
7. Re-invoke step 3 verbatim. Confirm cache hit (no worker spawn in the trace).

## Runs log

Each run writes `evals/runs/<iso-timestamp>.md` with one row per test, the answer received, and pass/fail. Failing runs become input for the next iteration on `SKILL.md` or `image-worker.md`.
