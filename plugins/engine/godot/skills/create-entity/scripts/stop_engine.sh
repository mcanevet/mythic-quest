#!/usr/bin/env bash
# Stop a running headless/MCP Godot engine for this project.
# Safety: PID-file first (.godot-engine.pid); fallback is a NARROW
# path-bound pattern confined to this project directory — never a broad pkill.
# Usage: scripts/stop_engine.sh
set -uo pipefail

readonly PROJECT_DIR="${GODOT_PROJECT_DIR:-$PWD}"
readonly PID_FILE="$PROJECT_DIR/.godot-engine.pid"

stopped=0

if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    # Only kill if the process cmdline references this project dir (path-bound).
    if ps -p "$pid" -o command= 2>/dev/null | grep -qF "$PROJECT_DIR"; then
      kill "$pid" 2>/dev/null || true
      stopped=1
    fi
  fi
  command rm -f "$PID_FILE"
fi

if [[ $stopped -eq 0 ]]; then
  # Narrow, path-bound fallback: only processes whose command line
  # mentions BOTH 'godot' and this exact project directory.
  pkill -f "godot.*$PROJECT_DIR" 2>/dev/null || true
fi

exit 0
