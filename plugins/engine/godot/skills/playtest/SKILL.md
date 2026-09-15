---
name: playtest
description: Verify a built feature using the MCP runtime (or headless fallback), then close the bead with PASS/FAIL.
---

## What I do

Runs the game and verifies behavior, then closes the bead.

## Execution

### Step 1: Run the game

Prefer the MCP runtime (godot server):

```text
run_project → launches with bridge (background: true avoids stealing focus)
get_debug_output → capture stdout/stderr — script errors = FAIL
```

If MCP tools are unavailable or hang (retry at most once), fall back to this
skill's helpers (all non-interactive, headless):

- `scripts/run_headless.sh <scene> [seconds]` — wraps
  `godot --headless res://scenes/<scene>.tscn --quit-after <seconds>` (default 60)
- `scripts/stop_engine.sh` — stops a leftover engine safely (PID-file first,
  narrow path-bound pattern; never a broad kill)

### Step 2: Verify behavior, not just absence of errors

Headless-no-errors is a weak oracle. Use what the feature offers:
- **Test hooks** — invoke `_on_test_verify()` / `_on_test_get_state()` via
  `run_script` and assert the returned state matches expectations
- **Input simulation** — `simulate_input` with the actions the feature uses;
  observe state change (score incremented, position moved, resource consumed)
- **Debug output** — `get_debug_output` catches parse errors that
  `--check-only` misses
- **Screenshot** — `take_screenshot` to visually confirm rendering

### Step 3: Close the bead

```bash
bd close <bead-id> --reason "PASS: beam rotates on simulate_input; flare count decremented"
# or
bd close <bead-id> --reason "FAIL: script error on line X"
```

Verdicts in close reasons. No report files. Only close PASS for behavior you
actually observed — "stubs ready" or "non-breaking" are FAIL or not-done.
