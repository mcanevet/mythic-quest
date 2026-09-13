#!/usr/bin/env bash
# lint-wisp: orchestrate a parallel lint run as a beads wisp molecule.
# Usage: lint-wisp.sh <mode>  (mode: dev | audit)
# Requires: bash 3.2+, bd, jq, git
set -euo pipefail

MODE="${1:?usage: lint-wisp.sh <dev|audit>}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

RULES=".agents/lint/rules.yaml"
STAMP="$(date +%Y%m%d-%H%M%S)"

discover_files() {
  local mode="$1"
  if [ "$mode" = "audit" ]; then
    git ls-files
  else
    { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
  fi
}

filter_files() {
  # Excludes .beads/, external skills, symlinks. Reads stdin, writes stdout.
  local f ex skip
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    skip=0
    case "$f" in
      .beads/*|.agents/skills/beads/*) skip=1 ;;
    esac
    [ -L "$f" ] && skip=1
    [ "$f" = "$RULES" ] && RULES_CHANGED=1
    if [ "$skip" -eq 0 ]; then
      printf '%s\n' "$f"
    fi
  done
}

# Discover targets -----------------------------------------------------------
RULES_CHANGED=0
FILTERED="$(discover_files "$MODE" | filter_files)"

# rules.yaml changed => full scope
if [ "$MODE" = "dev" ] && [ "${RULES_CHANGED:-0}" -eq 1 ]; then
  MODE="audit"
  FILTERED="$(discover_files "$MODE" | filter_files)"
fi

if [ -z "$FILTERED" ]; then
  echo "No files to lint."
  exit 0
fi

N=$(printf '%s\n' "$FILTERED" | wc -l | tr -d ' ')
echo "Lint mode: $MODE, $N file(s)"

# Create wisp ----------------------------------------------------------------
WISP_ID=$(bd create "Lint-$MODE $STAMP" -t epic --ephemeral --json | jq -r '.id')

# Spawn children (one per file) + fan-in aggregate ---------------------------
AGG_ID=$(bd create "Aggregate lint findings" --parent "$WISP_ID" \
  --description "Read children's comments and render findings table" \
  --ephemeral --json | jq -r '.id')

LIST_FILE=$(mktemp -t lint-wisp)
trap 'rm -f "$LIST_FILE"' EXIT

while IFS= read -r f; do
  [ -z "$f" ] && continue
  child=$(bd create "Lint $f" --parent "$WISP_ID" \
    --description "Apply all rules in $RULES to $f" \
    --ephemeral --json | jq -r '.id')
  bd dep add "$AGG_ID" "$child" >/dev/null
  printf '%s\t%s\n' "$child" "$f"
done <<< "$FILTERED" > "$LIST_FILE"

echo "Wisp: $WISP_ID"
echo "Aggregate: $AGG_ID (ready when all children close)"
echo "Children (saved to $LIST_FILE):"
cat "$LIST_FILE"
