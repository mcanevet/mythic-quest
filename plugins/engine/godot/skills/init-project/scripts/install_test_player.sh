#!/usr/bin/env bash
# install_test_player.sh — byte-exact install of the canonical test framework
# autoload into the consumer game project (init-project Step 3b).
#
# A cp here guarantees fidelity that read-then-write cannot: the harness's
# GDScript parse gate (lint check 10) validates THIS copy, so the game project
# must receive identical bytes — a hand-copied variant can carry subtle parse
# errors into every later playtest.
#
# Usage: install_test_player.sh <game-project-root>
#   Creates <root>/scripts/ if needed, refuses to overwrite an existing
#   test_player.gd that differs from canonical (prevents drift both ways).
# Exit codes: 0 = installed/already identical, 1 = error (root missing, drift)
set -euo pipefail
UPGRADE=0
if [ "${1:-}" = "--upgrade" ]; then UPGRADE=1; shift; fi
CANON="$(cd "$(dirname "$0")" && pwd)/test_player.gd"
DEST_DIR="${1:?usage: install_test_player.sh [--upgrade] <game-project-root>}/scripts"
DEST="$DEST_DIR/test_player.gd"

[ -f "$CANON" ] || { echo "canonical test_player.gd missing next to installer" >&2; exit 1; }
mkdir -p "$DEST_DIR"

if [ -f "$DEST" ]; then
  if cmp -s "$CANON" "$DEST"; then
    echo "OK: $DEST already identical to canonical (no action)"
    exit 0
  fi
  if [ "$UPGRADE" -ne 1 ]; then
    echo "ERROR: $DEST exists and DIFFERS from canonical — inspect before replacing" >&2
    echo "       If the canonical copy advanced (skill upgrade), re-run with:" >&2
    echo "         install_test_player.sh --upgrade <game-project-root>" >&2
    exit 1
  fi
  echo "NOTE: --upgrade given — replacing drifted $DEST with canonical"
fi

cp "$CANON" "$DEST"
cmp -s "$CANON" "$DEST" || { echo "copy verification failed" >&2; exit 1; }
echo "OK: installed $DEST ($(wc -l < "$DEST" | tr -d ' ') lines, byte-identical to canonical)"
