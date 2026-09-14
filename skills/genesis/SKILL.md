---
name: genesis
description: Create VISION.md and 10-20 flat task beads for a new game project.
---

## What I do

Creates the project's initial state:
1. **VISION.md** — Title, vision statement, 3-7 core mechanics, art style
2. **10-20 task beads** — Flat backlog (no epics), labeled `core|optional|future`, P0-P2 priorities

## Execution

### Step 1: Invent the game

Autonomous — execute without questions:
- Memorable title (not "My Game")
- One-sentence vision (emotional core)
- 3-7 core mechanics
- Art style direction
- 10-20 concrete tasks (first 7 = playable loop)

### Step 2: Write VISION.md

```markdown
# [Game Title]

## Vision
[One sentence]

## Core Mechanics
- [Mechanic 1]
- [Mechanic 2]

## Art Style
[Direction]
```

### Step 3: Create task beads

```bash
bd create "Create Player entity with movement and collision" \
  -t task -l core -p 1 -d "Concrete description" --silent
```

Conventions:
- **Flat only** — no `--parent`
- **Titles** = imperative, concrete
- **Labels**: `core`, `optional`, `future`
- **Priority**: P0 for first 7, P1 rest, P2 future
- **Dependencies**: `bd dep add <blocked> <blocking>` only when priority won't enforce order

## Done when

- VISION.md exists with required sections
- ≥10 open task beads created, all labeled
- Beads ordered by dependency (P0 first)
