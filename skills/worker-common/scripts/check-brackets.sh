#!/usr/bin/env bash
# Bracket balance checker for GDScript probes (wt16: error-43 recurrence fix)
# Usage: check-brackets.sh <script-file>
# Exit 0 if balanced, exit 1 with error message if unbalanced.

if [ $# -ne 1 ]; then
  echo "Usage: check-brackets.sh <script-file>" >&2
  exit 1
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "File not found: $FILE" >&2
  exit 1
fi

CONTENT=$(cat "$FILE")
OPEN_SQUARE=$(echo "$CONTENT" | grep -o '\[' | wc -l | tr -d ' ') || OPEN_SQUARE=0
CLOSE_SQUARE=$(echo "$CONTENT" | grep -o '\]' | wc -l | tr -d ' ') || CLOSE_SQUARE=0
OPEN_CURLY=$(echo "$CONTENT" | grep -o '{' | wc -l | tr -d ' ') || OPEN_CURLY=0
CLOSE_CURLY=$(echo "$CONTENT" | grep -o '}' | wc -l | tr -d ' ') || CLOSE_CURLY=0

ERRORS=""
if [ "$OPEN_SQUARE" -ne "$CLOSE_SQUARE" ]; then
  ERRORS="${ERRORS}Square brackets unbalanced: ${OPEN_SQUARE}[ vs ${CLOSE_SQUARE}]\\n"
fi
if [ "$OPEN_CURLY" -ne "$CLOSE_CURLY" ]; then
  ERRORS="${ERRORS}Curly braces unbalanced: ${OPEN_CURLY}{ vs ${CLOSE_CURLY}}\\n"
fi

if [ -n "$ERRORS" ]; then
  echo "Bracket imbalance detected in $FILE:" >&2
  printf "%b" "$ERRORS" >&2
  echo "Fix before submitting to godot_run_script — each failure = 1 wasted turn + full context re-send." >&2
  exit 1
fi

echo "Brackets balanced in $FILE" >&2
exit 0
