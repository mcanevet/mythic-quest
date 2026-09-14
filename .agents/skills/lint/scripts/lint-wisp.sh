#!/usr/bin/env bash
# lint-wisp: orchestrate a parallel lint run as a beads wisp molecule.
# Usage: lint-wisp.sh <mode>  (mode: dev | audit)
# Requires: bash 3.2+, bd >= 1.3 (graph apply), jq, git
set -euo pipefail

MODE="${1:?usage: lint-wisp.sh <dev|audit>}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

RULES=".agents/lint/rules.yaml"
STAMP="$(date +%Y%m%d-%H%M%S)"

discover_files() {
  if [ "$1" = "audit" ]; then
    git ls-files
  else
    { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
  fi
}

filter_files() {
  # Excludes .beads/, external skills, symlinks. Reads stdin, writes stdout.
  local f skip
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    skip=0
    case "$f" in
      .beads/*) skip=1 ;;
    esac
    [ -L "$f" ] && skip=1
    if [ "$skip" -eq 0 ]; then
      printf '%s\n' "$f"
    fi
  done
}

# Discover targets -----------------------------------------------------------
FILTERED="$(discover_files "$MODE" | filter_files)"

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
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    i=$((i+1))
    printf ',\n    {"key": "f%d", "title": "Lint %s", "type": "task", "parent_key": "epic", "ephemeral": true, "description": "Apply all rules in %s to %s", "deps": [{"type": "blocks", "target": "agg"}]}' \
      "$i" "$f" "$RULES" "$f"
  done <<< "$FILTERED"
  printf ',\n    {"key": "agg", "title": "Aggregate lint findings", "type": "task", "parent_key": "epic", "ephemeral": true, "description": "Read children comments and render findings table"}\n'
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
