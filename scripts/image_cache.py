#!/usr/bin/env python3
"""
image_cache.py  small cross platform helper for the image plugin.

Mechanical operations only. Decisions about what to extract from an image and
what counts as a cache hit live in the image-worker subagent, not here.

Subcommands:
    id      <image-path>                  print sha256 of image bytes
    path    <image-path> [cache-dir]      print cache file path, mkdir cache-dir
    register <id> <source-path> [cache-dir]
                                          add or merge a row in index.md
    list    [cache-dir]                   cat index.md or print "(empty)"

Defaults:
    cache-dir = $IMAGE_MEMORY_DIR or ~/.claude/cache/image-memory

Works on macOS, Linux, Windows. Requires Python 3.7+.
"""

import hashlib
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def cache_dir(arg=None):
    if arg:
        return Path(arg).expanduser()
    env = os.environ.get("IMAGE_MEMORY_DIR")
    if env:
        return Path(env).expanduser()
    return Path.home() / ".claude" / "cache" / "image-memory"


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ensure_index(cdir):
    cdir.mkdir(parents=True, exist_ok=True)
    idx = cdir / "index.md"
    if not idx.exists():
        idx.write_text(
            "# image-memory index\n\n"
            "| id | sources | kind | dims | created | tags |\n"
            "|----|---------|------|------|---------|------|\n"
        )
    return idx


def register(image_id, source, cdir):
    idx = ensure_index(cdir)
    lines = idx.read_text().splitlines()
    out = []
    found = False
    for line in lines:
        if line.startswith(f"| {image_id} "):
            cells = [c.strip() for c in line.strip("|").split("|")]
            # cells: id, sources, kind, dims, created, tags
            sources = [s.strip() for s in cells[1].split(",") if s.strip()]
            if source not in sources:
                sources.append(source)
            cells[1] = ", ".join(sources)
            out.append("| " + " | ".join(cells) + " |")
            found = True
        else:
            out.append(line)
    if not found:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        out.append(f"| {image_id} | {source} |  |  | {ts} |  |")
    idx.write_text("\n".join(out) + "\n")


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    cmd = argv[1]

    if cmd == "id":
        if len(argv) < 3:
            print("usage: image_cache.py id <image-path>", file=sys.stderr)
            sys.exit(2)
        print(sha256_of(argv[2]))
        return

    if cmd == "path":
        if len(argv) < 3:
            print("usage: image_cache.py path <image-path> [cache-dir]", file=sys.stderr)
            sys.exit(2)
        cdir = cache_dir(argv[3] if len(argv) > 3 else None)
        cdir.mkdir(parents=True, exist_ok=True)
        image_id = sha256_of(argv[2])
        print(cdir / f"{image_id}.md")
        return

    if cmd == "register":
        if len(argv) < 4:
            print("usage: image_cache.py register <id> <source-path> [cache-dir]", file=sys.stderr)
            sys.exit(2)
        cdir = cache_dir(argv[4] if len(argv) > 4 else None)
        register(argv[2], argv[3], cdir)
        return

    if cmd == "list":
        cdir = cache_dir(argv[2] if len(argv) > 2 else None)
        idx = cdir / "index.md"
        if idx.exists():
            sys.stdout.write(idx.read_text())
        else:
            print("(empty)")
        return

    print(f"unknown command: {cmd}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
