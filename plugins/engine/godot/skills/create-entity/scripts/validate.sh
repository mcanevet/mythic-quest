#!/usr/bin/env bash
# Validate a Godot project (and optionally a scene) headlessly.
# Usage: scripts/validate.sh [scene-path]
#   No argument  -> godot --headless --quit   (imports + boots the project)
#   Scene path    -> godot --headless <scene> --quit-after 1  (loads the scene)
# Exits 0 on success, non-zero on errors. Non-interactive, no network.
set -euo pipefail

readonly PROJECT_DIR="${GODOT_PROJECT_DIR:-$PWD}"

if [[ ! -f "$PROJECT_DIR/project.godot" ]]; then
  echo "ERROR: no project.godot found in $PROJECT_DIR (set GODOT_PROJECT_DIR)" >&2
  exit 2
fi

cd "$PROJECT_DIR"

if [[ $# -ge 1 ]]; then
  exec godot --headless "$1" --quit-after 1
fi

exec godot --headless --quit
