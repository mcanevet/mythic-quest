#!/bin/bash
# Log-result validation — operates on cwd (project root)
# Usage: ./validate.sh [BEAD_ID]
# Exit codes: 0 = success, 1 = failure
#
# Beads-ledger mode: validates bead closure state (not GAME_STATE.md).
# BEAD_ID argument optional:
#   - given: that bead must be closed; other in_progress beads are INFO only
#   - absent: no bead may remain in_progress (global check)
set -e

BEAD_ID="${1:-}"
errors=0

echo "=== Log-Result Validation ==="

# Check 1: beads ledger exists and opens (hard requirement — log-result always operates on it)
if ! bd list --json >/dev/null 2>&1; then
    echo "❌ FAIL: beads ledger not initialized or unreadable (bd list failed)" >&2
    exit 1
fi
echo "✓ OK: beads ledger opens (bd list)"

# Helper: list in_progress bead IDs (comma-separated)
inprogress_ids() {
    bd list --json --status in_progress | python3 -c '
import json, sys
beads = json.load(sys.stdin)
print(",".join(b["id"] for b in beads))'
}

# Check 2: no bead should still be in_progress after log-result ran.
# Scope: beads OTHER than the one being logged (batched delegations legitimately
# groom + claim the next bead before validating the current one — that claim is
# another worker's legitimate in_progress, not a failure). With BEAD_ID given,
# only THAT bead being still in_progress is a failure. Without BEAD_ID, any
# in_progress bead fails (unchanged global check).
inprog="$(inprogress_ids)"
if [ -n "$BEAD_ID" ]; then
    if printf '%s' "$inprog" | tr ',' '\n' | grep -qx "$BEAD_ID"; then
        echo "❌ FAIL: Bead ${BEAD_ID} still in_progress — log-result did not complete its close" >&2
        errors=$((errors+1))
    else
        others=$(printf '%s' "$inprog" | tr ',' '\n' | grep -c . || true)
        if [ "$others" -gt 0 ]; then
            echo "ℹ️  INFO: $others other bead(s) in_progress (batched delegation) — not a Bead ${BEAD_ID} failure" >&2
        fi
        echo "✓ OK: Bead '${BEAD_ID}' not left in_progress"
    fi
else
    if [ -n "$inprog" ]; then
        echo "❌ FAIL: ledger still has in_progress bead(s): ${inprog} — log-result did not complete the close" >&2
        errors=$((errors+1))
    else
        echo "✓ OK: No bead left in_progress"
    fi
fi

# Check 3: If BEAD_ID provided, that bead must be closed
if [ -n "$BEAD_ID" ]; then
    status=$(bd show "$BEAD_ID" --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, list): d = d[0] if d else {}
print(d.get("status", ""))' 2>/dev/null || echo "")
    if [ -z "$status" ]; then
        echo "❌ FAIL: bead '${BEAD_ID}' not found in ledger" >&2
        errors=$((errors+1))
    elif [ "$status" != "closed" ]; then
        echo "❌ FAIL: bead '${BEAD_ID}' status is '${status}', expected closed" >&2
        errors=$((errors+1))
    else
        echo "✓ OK: bead '${BEAD_ID}' closed"
    fi
else
    echo "ℹ️  INFO: No BEAD_ID provided, skipping bead-specific status check" >&2
fi

# (plans/ markdown mode removed — bead closure is the sole completion state)

echo ""
if [ "$errors" -gt 0 ]; then
    echo "❌ Log-result validation FAILED ($errors errors)" >&2
    exit 1
else
    echo "✓ Log-result validation PASSED"
    exit 0
fi
