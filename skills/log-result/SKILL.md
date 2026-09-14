---
name: log-result
description: Close the completed bead in the ledger and run mandatory validation. Use after task implementation is verified. Updates README.md with player-facing content.
---

## What I do

Documents completed work: update README, close the bead, run mandatory validation.

## Definition of Done (all three, no exceptions)

1. Bead status is `closed` in the ledger (Step 2)
2. Validation script exits 0 (Step 3)
3. README.md updated (if applicable, Step 1)

Closing the bead without running validation is a HALF-DONE failure.

## Execution

### Step 0: Verify implementation completeness

Check the bead's description for acceptance criteria requiring runtime
verification. If the implementation should have produced a verification
report but didn't, do NOT close — report BLOCKED and re-run implementation.

### Step 1: Update README.md

Always update for player-visible changes (controls, scoring, rules, game
flow). Skip for pure scaffolding. Polished present-tense content, no bead
IDs or ledger references.

### Step 2: Close the bead

```bash
bd close <bead-id> --reason "<one-line completion reason>"
```

Exit 0 required. Closing releases dependents — beads blocked on this one
become `ready` automatically.

### Step 2.5: Verify the close landed (mandatory)

`bd show <bead-id> --json` → `status` is `closed`. Returning after only a
partial close is the most common failure of this skill.

### Step 3: Validate (mandatory)

```bash
[skill-dir]/scripts/validate.sh <BEAD_ID>
```

Exit 0 required. Checks: ledger opens, no bead left in_progress, the given
bead is closed.

### Step 4: Return summary to caller

- Bead closed (confirmed via `bd show`)
- Validation exit code
- Files created/modified
- Any gotchas
