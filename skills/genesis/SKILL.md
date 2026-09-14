---
name: genesis
description: Initialize a new game project with VISION.md, README.md, and a flat task backlog as beads. Use when starting a new game project to define what gets built.
---

## What I do

Creates the project's tracking state — a **beads ledger** — plus the player-facing README:

1. **VISION.md** — Game title, vision statement, core mechanics (3-7), art style. Small, stable, read often.
2. **README.md** — Player-facing manual with empty section skeletons, filled as features land.
3. **Task backlog** — 10-20 concrete tasks as **flat beads** (no epics), in priority order.

## Execution

### Step 1: Invent the game concept

Autonomous — execute without questions:

1. Memorable game title (not "My Game")
2. Vision statement — one sentence capturing emotional core
3. 3-7 core mechanics serving the vision
4. Art style direction (pixel/vector/minimalist)
5. 10-20 concrete tasks prioritized by dependency; first 7 create the playable loop

### Step 2: Write VISION.md

```markdown
# [Game Title]

## Vision
[One sentence capturing emotional core]

## Core Mechanics
- [Mechanic 1]
- [Mechanic 2]

## Art Style
[Visual direction]
```

### Step 3: Create README.md

Copy [reference/readme-skeleton.md](reference/readme-skeleton.md) verbatim,
substituting the game title and one-line description. The README is
player-facing: no task numbers, no WIP markers, no ledger references.

### Step 4: Create task beads

One `bd create` per task:

```bash
bd create "Create Player entity with movement and collision" \
  -t task -l core -p 1 \
  -d "Concrete description of what done looks like" \
  --silent
```

Conventions (load-bearing):
- **Flat backlog only** — no epics, no `--parent`
- **Title** = imperative and concrete, not vague
- **Labels**: `core`, `optional`, or `future`
- **Priority**: P0 for the first 7 (playable loop), P1 for the rest, P2 for future
- **Dependencies**: `bd dep add <blocked-id> <blocking-id>` wires "B blocked-by A" — only when priority order alone won't enforce the sequence

### Step 5: Validate (mandatory)

```bash
[skill-dir]/scripts/validate.sh
```

Exit 0 required before declaring success. It checks: ledger opens, ≥10 open
task beads all labeled `core|optional|future`, VISION.md sections, README.md
exists.

## Critical Rules

1. Execute without questions — invention happens autonomously
2. Flat backlog only
3. Concrete, independently implementable tasks
4. Playable loop first (first 7 tasks)
