#!/usr/bin/env bash
# lint-wisp: orchestrate a parallel lint run as a beads wisp molecule.
# Usage: lint-wisp.sh <mode>  (mode: dev | audit)
# Requires: bash 3.2+, bd >= 1.3 (graph apply), jq, git
set -euo pipefail

MODE="${1:?usage: lint-wisp.sh <dev|audit>}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

RULES=".agents/lint/rules.yaml"
CACHE=".beads/lint-cache.jsonl"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Incremental cache: skip files whose git blob hash matches the last PASS.
# Only used in audit mode (dev mode already scopes to changed files).
cache_hash() {
  git hash-object "$1" 2>/dev/null || echo "nocache:$1"
}

filter_cached() {
  # Reads stdin (file list), writes stdout (uncached files).
  # Lines whose cached hash equals current hash AND whose last result was
  # CLEAN are skipped. A dirty cache entry (violations found) never skips.
  [ -f "$CACHE" ] || { cat; return; }
  local f h cached
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    h=$(cache_hash "$f")
    cached=$(jq -r --arg f "$f" --arg h "$h" \
      'select(.file == $f and .hash == $h and .result == "clean") | .hash' "$CACHE" 2>/dev/null | head -1)
    if [ -n "$cached" ]; then
      continue  # unchanged + clean → skip
    fi
    printf '%s\n' "$f"
  done
}

record_cache() {
  # Called post-run by the wisp closer; records {file, hash, result} lines.
  # Kept here for symmetry; actual recording happens when children close.
  :
}

discover_files() {
  if [ "$1" = "audit" ]; then
    git ls-files
  else
    { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
  fi
}

filter_files() {
  # Scopes to agents/, skills/, plugins/; excludes .beads/, external skills, symlinks. Reads stdin, writes stdout.
  local f skip
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    skip=0
    case "$f" in
      agents/*|skills/*|plugins/*) skip=0 ;;
      *) skip=1 ;;
    esac
    [ "$skip" -eq 0 ] && [ -L "$f" ] && skip=1
    if [ "$skip" -eq 0 ]; then
      printf '%s\n' "$f"
    fi
  done
}

# Discover targets -----------------------------------------------------------
FILTERED="$(discover_files "$MODE" | filter_files)"

# Incremental cache (audit mode only): skip unchanged-clean files
if [ "$MODE" = "audit" ]; then
  FILTERED="$(printf '%s\n' "$FILTERED" | filter_cached)"
fi

# Deterministic GDScript pre-pass (always runs, non-blocking)
if [ -n "$FILTERED" ] && printf '%s\n' "$FILTERED" | grep -qE '\.(gd|md)$'; then
  echo "Running GDScript parse pre-pass..."
  bash ".agents/skills/lint/scripts/lint-gdscript-check.sh" || true
fi

# rules.yaml changed => full scope. Checked out here (not in filter_files)
# because command substitutions run in subshells where variable writes vanish.
if [ "$MODE" = "dev" ] && printf '%s\n' "$FILTERED" | grep -qxF "$RULES"; then
  MODE="audit"
  FILTERED="$(discover_files "$MODE" | filter_files)"
fi

if [ -z "$FILTERED" ]; then
  echo "No files to lint."
  exit 0
fi

N=$(printf '%s\n' "$FILTERED" | wc -l | tr -d ' ')
echo "Lint mode: $MODE, $N file(s)"

# Build graph plan: epic + one child per file + aggregate gated on all files.
# One bd invocation creates the whole molecule atomically.
PLAN=$(mktemp -t lint-wisp-plan)
trap 'rm -f "$PLAN"' EXIT

{
  printf '{\n  "commit_message": "Lint-%s %s",\n  "nodes": [\n' "$MODE" "$STAMP"
  printf '    {"key": "epic", "title": "Lint-%s %s", "type": "epic", "ephemeral": true}' "$MODE" "$STAMP"
  i=0
  AGG_DEPS=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    i=$((i+1))
    # Edge semantics: a "deps" entry lives on the DEPENDENT. Children carry
    # no deps; the aggregate depends on all of them (fan-in).
    AGG_DEPS="${AGG_DEPS}{\"type\": \"blocks\", \"target\": \"f${i}\"}, "
    printf ',\n    {"key": "f%d", "title": "Lint %s", "type": "task", "parent_key": "epic", "ephemeral": true, "description": "Apply all rules in %s to %s"}' \
      "$i" "$f" "$RULES" "$f"
  done <<< "$FILTERED"
  AGG_DEPS="${AGG_DEPS%, }"
  printf ',\n    {"key": "agg", "title": "Aggregate lint findings", "type": "task", "parent_key": "epic", "ephemeral": true, "description": "Read children comments and render findings table", "deps": [%s]}\n' "$AGG_DEPS"
  printf '  ],\n  "edges": []\n}\n'
} > "$PLAN"

RESULT=$(bd create --graph "$PLAN" --json)

WISP_ID=$(echo "$RESULT" | jq -r '.ids.epic')
AGG_ID=$(echo "$RESULT" | jq -r '.ids.agg')

echo "Wisp: $WISP_ID"
echo "Aggregate: $AGG_ID (ready when all children close)"
echo "Children:"
i=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  i=$((i+1))
  echo "  $(echo "$RESULT" | jq -r ".ids[\"f$i\"]")  $f"
done <<< "$FILTERED"
