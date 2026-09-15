#!/usr/bin/env bash
# Headless fallback playtest run (used only when MCP tools are unavailable).
# Usage: scripts/run_headless.sh <scene-path> [quit-after-seconds]
# Non-interactive, no network, no focus stealing (headless).
set -euo pipefail

readonly PROJECT_DIR="${GODOT_PROJECT_DIR:-$PWD}"

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/run_headless.sh <scene-path> [quit-after-seconds]" >&2
  exit 2
fi

readonly SCENE="$1"
readonly QUIT_AFTER="${2:-60}"

if [[ ! -f "$PROJECT_DIR/project.godot" ]]; then
  echo "ERROR: no project.godot found in $PROJECT_DIR (set GODOT_PROJECT_DIR)" >&2
  exit 2
fi

cd "$PROJECT_DIR"

exec godot --headless "$SCENE" --quit-after "$QUIT_AFTER"
