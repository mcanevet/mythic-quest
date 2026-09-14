---
name: playtest
description: Run the game headless, verify scene integrity, capture screenshots. Use to validate that a built feature works in the running game.
---

## What I do

Runs the game to verify a built feature:
- Headless run with automated invariant checks
- Screenshot capture for visual verification
- Playtest report persisted to reports/

## Execution

### Step 1: Determine target scene

From the claimed bead's description: the main scene or the feature scene to verify.

### Step 2: Headless run

```bash
godot --headless res://scenes/<scene>.tscn --quit-after 60
```

Capture stdout/stderr; any script error is a failure.

### Step 3: Integrity checks

Deterministic checks after the run:
- Scene loads without script errors
- Test hooks callable (if the entity provides them)
- Expected groups present

### Step 4: Screenshots (when visual verification is needed)

Render-based screenshot run; save to `reports/screenshots/`.

### Step 5: Report

Persist the playtest outcome to `reports/playtest-<bead-id>.md`:
- Verdict: PASS / FAIL (with failing checks)
- Stdout excerpt if failed
- Screenshot references
