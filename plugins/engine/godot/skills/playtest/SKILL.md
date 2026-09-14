---
name: playtest
description: Run Godot headless to verify a scene. Close the bead with PASS/FAIL verdict.
---

## What I do

Runs the game to verify a built feature, then closes the bead.

## Execution

### Step 1: Run headless

```bash
godot --headless res://scenes/<scene>.tscn --quit-after 60
```

Capture stdout/stderr. Script error = FAIL.

### Step 2: Check results

- No script errors → PASS
- Errors → FAIL (report the error)

### Step 3: Close the bead

```bash
bd close <bead-id> --reason "PASS: scene loads cleanly"
# or
bd close <bead-id> --reason "FAIL: script error on line X"
```

No report files. Verdict lives in the close reason and bead metadata.
