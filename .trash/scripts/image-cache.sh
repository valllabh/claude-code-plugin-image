#!/usr/bin/env bash
# image-cache.sh  markdown only memory cache for the image plugin
#
# Layout under $IMAGE_MEMORY_DIR (default ~/.claude/cache/image-memory):
#   index.md       one row per image, table form
#   <sha256>.md    per image memory with ## profile and ## answers sections
#
# Subcommands:
#   key   <image-path>                 print sha256 of image bytes
#   path  <image-path>                 print memory file path, init if missing, register in index
#   has-profile <image-path>           exit 0 if ## profile section present, else exit 1
#   write-profile <image-path> <file>  write contents of <file> as the ## profile body, once
#   find  <image-path> <intent>        print prior answer if a matching ## intent block exists, else exit 1
#   append <image-path> <intent> <file> append contents of <file> as a new ### intent block
#   tag   <image-path> <tag>           add a tag to the index row for this image
#   list                               cat index.md
#
# Notes:
# - intent matching is normalized: lowercased, whitespace collapsed, then exact compare.
# - answers are appended, never rewritten. profile is written once and never rewritten.

set -euo pipefail

CACHE_DIR="${IMAGE_MEMORY_DIR:-$HOME/.claude/cache/image-memory}"
INDEX="$CACHE_DIR/index.md"

cmd="${1:-}"
shift || true

die() { echo "$1" >&2; exit "${2:-2}"; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "need sha256sum or shasum on PATH"
  fi
}
need_img() {
  if [[ -z "${1:-}" ]]; then die "image path required"; fi
  if [[ ! -f "$1" ]]; then die "image not found: $1"; fi
  return 0
}

normalize_intent() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//'
}

ensure_index() {
  mkdir -p "$CACHE_DIR"
  if [[ ! -f "$INDEX" ]]; then
    {
      echo "# image-memory index"
      echo
      echo "| sha | sources | kind | dims | created | tags |"
      echo "|-----|---------|------|------|---------|------|"
    } > "$INDEX"
  fi
}

index_has() {
  local sha="$1"
  grep -q "^| ${sha} " "$INDEX" 2>/dev/null
}

index_add() {
  local sha="$1" src="$2"
  ensure_index
  if index_has "$sha"; then
    # append source to existing row if not already listed
    if ! awk -v sha="$sha" -v src="$src" -F'|' '
      $0 ~ "^\\| " sha " " { if (index($3, src) > 0) { found=1 } }
      END { exit (found ? 0 : 1) }
    ' "$INDEX"; then
      # append to sources cell
      tmp="$(mktemp)"
      awk -v sha="$sha" -v src="$src" '
        BEGIN { OFS="|" }
        $0 ~ "^\\| " sha " " {
          # parse cells, append src to sources column
          n = split($0, c, "|")
          # cells: "" sha sources kind dims created tags ""
          gsub(/^ | $/, "", c[3])
          if (c[3] == "") c[3] = src; else c[3] = c[3] ", " src
          printf "| %s | %s | %s | %s | %s | %s |\n", c[2], c[3], c[4], c[5], c[6], c[7]
          next
        }
        { print }
      ' "$INDEX" > "$tmp" && mv "$tmp" "$INDEX"
    fi
  else
    echo "| $sha | $src |  |  | $(date -u +%Y-%m-%dT%H:%M:%SZ) |  |" >> "$INDEX"
  fi
}

mem_path_for() {
  local sha="$1"
  echo "$CACHE_DIR/$sha.md"
}

ensure_mem() {
  local sha="$1" img="$2"
  local mem; mem="$(mem_path_for "$sha")"
  if [[ ! -f "$mem" ]]; then
    {
      echo "---"
      echo "sha256: $sha"
      echo "sources:"
      echo "  - $img"
      echo "created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "---"
      echo
      echo "## answers"
      echo
    } > "$mem"
  else
    # add img to sources list if not present
    if ! grep -qE "^\s*- $(printf '%s' "$img" | sed 's/[\\&/]/\\&/g')$" "$mem"; then
      tmp="$(mktemp)"
      awk -v img="$img" '
        BEGIN { in_src=0; added=0 }
        /^---$/ { print; if (in_front) { in_front=0 } else { in_front=1 } ; next }
        in_front && /^sources:/ { print; in_src=1; next }
        in_front && in_src && /^[^ ]/ && !/^---/ { if (!added) { print "  - " img; added=1 } in_src=0; print; next }
        { print }
        END { }
      ' "$mem" > "$tmp" && mv "$tmp" "$mem"
    fi
  fi
  echo "$mem"
}

case "$cmd" in
  key)
    img="${1:-}"; need_img "$img"
    sha256_of "$img"
    ;;

  path)
    img="${1:-}"; need_img "$img"
    sha="$(sha256_of "$img")"
    ensure_index
    index_add "$sha" "$img"
    ensure_mem "$sha" "$img"
    ;;

  has-profile)
    img="${1:-}"; need_img "$img"
    sha="$(sha256_of "$img")"
    mem="$(mem_path_for "$sha")"
    [[ -f "$mem" ]] && grep -q '^## profile' "$mem"
    ;;

  write-profile)
    img="${1:-}"; body_file="${2:-}"
    need_img "$img"
    [[ -f "$body_file" ]] || die "profile body file not found: $body_file"
    sha="$(sha256_of "$img")"
    ensure_index; index_add "$sha" "$img"
    mem="$(ensure_mem "$sha" "$img")"
    if grep -q '^## profile' "$mem"; then
      die "profile already written for $sha; profile is write-once"
    fi
    # insert ## profile section right after frontmatter, before ## answers
    tmp="$(mktemp)"
    awk -v body_file="$body_file" '
      BEGIN { fm=0; inserted=0 }
      /^---$/ { print; fm++; next }
      fm < 2 { print; next }
      !inserted && /^## answers/ {
        print "## profile"
        print ""
        while ((getline line < body_file) > 0) print line
        close(body_file)
        print ""
        inserted=1
      }
      { print }
      END {
        if (!inserted) {
          print ""
          print "## profile"
          print ""
          while ((getline line < body_file) > 0) print line
          close(body_file)
        }
      }
    ' "$mem" > "$tmp" && mv "$tmp" "$mem"
    echo "$mem"
    ;;

  find)
    img="${1:-}"; intent="${2:-}"
    need_img "$img"; [[ -z "$intent" ]] && die "intent required"
    sha="$(sha256_of "$img")"
    mem="$(mem_path_for "$sha")"
    [[ -f "$mem" ]] || exit 1
    norm_query="$(normalize_intent "$intent")"
    awk -v q="$norm_query" '
      function norm(s) { s=tolower(s); gsub(/[ \t]+/, " ", s); sub(/^ /,"",s); sub(/ $/,"",s); return s }
      BEGIN { hit=0; buf="" }
      /^### intent: / {
        if (hit) { print buf; exit 0 }
        line = norm(substr($0, 13))
        if (line == q) { hit=1; buf=""; next }
        next
      }
      /^## / { if (hit) { print buf; exit 0 } }
      hit { buf = buf $0 "\n" }
      END { if (hit) { print buf; exit 0 } else { exit 1 } }
    ' "$mem"
    ;;

  append)
    img="${1:-}"; intent="${2:-}"; body_file="${3:-}"
    need_img "$img"; [[ -z "$intent" ]] && die "intent required"
    [[ -f "$body_file" ]] || die "answer body file not found: $body_file"
    sha="$(sha256_of "$img")"
    ensure_index; index_add "$sha" "$img"
    mem="$(ensure_mem "$sha" "$img")"
    {
      echo
      echo "### intent: $intent"
      cat "$body_file"
      echo
    } >> "$mem"
    echo "$mem"
    ;;

  tag)
    img="${1:-}"; tag="${2:-}"
    need_img "$img"; [[ -z "$tag" ]] && die "tag required"
    sha="$(sha256_of "$img")"
    ensure_index; index_add "$sha" "$img"
    tmp="$(mktemp)"
    awk -v sha="$sha" -v tag="$tag" '
      $0 ~ "^\\| " sha " " {
        n = split($0, c, "|")
        for (i=1;i<=n;i++) gsub(/^ | $/, "", c[i])
        if (c[7] == "") c[7] = tag
        else if (index(", " c[7] ", ", ", " tag ", ") == 0) c[7] = c[7] ", " tag
        printf "| %s | %s | %s | %s | %s | %s |\n", c[2], c[3], c[4], c[5], c[6], c[7]
        next
      }
      { print }
    ' "$INDEX" > "$tmp" && mv "$tmp" "$INDEX"
    ;;

  list)
    [[ -f "$INDEX" ]] && cat "$INDEX" || echo "(empty)"
    ;;

  profile)
    img="${1:-}"; need_img "$img"
    sha="$(sha256_of "$img")"
    mem="$(mem_path_for "$sha")"
    [[ -f "$mem" ]] || exit 1
    awk '
      /^## profile/ { hit=1; next }
      /^## / && hit { exit }
      hit { print }
    ' "$mem"
    ;;

  field)
    img="${1:-}"; field="${2:-}"
    need_img "$img"; [[ -z "$field" ]] && die "field name required"
    sha="$(sha256_of "$img")"
    mem="$(mem_path_for "$sha")"
    [[ -f "$mem" ]] || exit 1
    awk -v f="$field" '
      /^## profile/ { in_p=1; next }
      /^## / && in_p { exit }
      in_p && $0 ~ "^" f ":" {
        sub("^" f ":[ \t]*", "")
        print
        capturing=1
        next
      }
      in_p && capturing && /^[a-z][a-zA-Z0-9_-]*:/ { exit }
      in_p && capturing { print }
    ' "$mem"
    ;;

  *)
    die "usage: image-cache.sh {key|path|has-profile|write-profile|find|append|tag|list} ..."
    ;;
esac
