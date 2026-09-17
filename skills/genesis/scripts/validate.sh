#!/bin/bash
# Genesis validation — operates on cwd (project root)
# Usage: ./scripts/validate.sh
# Exit codes: 0 = pass, 1 = fail
#
# Beads-ledger mode: validates the ledger (not GAME_STATE.md) + VISION.md + README.md.
set -e

errors=0

echo "=== Genesis Validation ==="

# Check 1: beads ledger exists and opens
if ! bd list --json >/dev/null 2>&1; then
    echo "❌ FAIL: beads ledger not initialized or unreadable (bd list failed)" >&2
    errors=$((errors+1))
else
    echo "✓ OK: beads ledger opens (bd list)"
fi

# Check 2: ≥ 10 open task-type beads, all with core|optional|future label
if bd list --json >/dev/null 2>&1; then
    bead_stats=$(bd list --json | python3 -c '
import json, sys
beads = json.load(sys.stdin)
tasks = [b for b in beads if b.get("issue_type") == "task" and b.get("status") in ("open", "in_progress")]
unlabeled = [b["id"] for b in tasks if not ({"core","optional","future"} & set(b.get("labels", [])))]
print(f"{len(tasks)} {len(unlabeled)}")
')
    task_count="${bead_stats%% *}"
    unlabeled_count="${bead_stats##* }"
    if [ "$task_count" -lt 10 ]; then
        echo "❌ FAIL: only $task_count open task beads (need ≥ 10)" >&2
        errors=$((errors+1))
    else
        echo "✓ OK: $task_count open task beads"
    fi
    if [ "$unlabeled_count" -gt 0 ]; then
        echo "❌ FAIL: $unlabeled_count task bead(s) missing core|optional|future label" >&2
        errors=$((errors+1))
    else
        echo "✓ OK: all task beads labeled (core|optional|future)"
    fi
fi

# Check 3: VISION.md exists with required sections
if [ ! -f "VISION.md" ]; then
    echo "❌ FAIL: VISION.md missing" >&2
    errors=$((errors+1))
else
    sections_ok=true
    grep -q "^## Vision" VISION.md || { echo "❌ FAIL: VISION.md missing '## Vision'" >&2; sections_ok=false; errors=$((errors+1)); }
    grep -q "^## Core Mechanics" VISION.md || { echo "❌ FAIL: VISION.md missing '## Core Mechanics'" >&2; sections_ok=false; errors=$((errors+1)); }
    if $sections_ok; then
        echo "✓ OK: VISION.md (sections present)"
    fi
fi

# Check 4: README.md exists
if [ ! -f "README.md" ]; then
    echo "❌ FAIL: README.md missing" >&2
    errors=$((errors+1))
else
    echo "✓ OK: README.md exists"
fi

# Final result
if [ "$errors" -gt 0 ]; then
    echo ""
    echo "❌ Genesis validation FAILED ($errors errors)" >&2
    exit 1
else
    echo ""
    echo "✓ Genesis validation PASSED"
    exit 0
fi
