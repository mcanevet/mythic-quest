---
name: genesis
description: Invent a game and produce VISION.md + BACKLOG.md. Do NOT create beads directly.
---

## What I do

Creates the creative foundation for a new game project:
1. **VISION.md** — Title, vision statement, core mechanics, art style
2. **BACKLOG.md** — Structured task list (not beads yet) for the orchestrator to wire

**Critical constraint**: I am the **creative director**, not the orchestrator. I produce **content**, not ledger structure. The orchestrator (session following AGENTS.md) will pour the molecule epic and parent my tasks as children.

## Execution

### Step 1: Invent the game (autonomous — no questions)

- **Memorable title** (not "My Game" or generic names)
- **One-sentence vision** (emotional core: what feeling does this evoke?)
- **3-7 core mechanics** (concrete, testable behaviors)
- **Art style direction** (visual language, palette, mood)
- **10-20 concrete tasks** (first 7 = playable loop; rest = polish/features)

### Step 2: Write VISION.md

```markdown
# [Game Title]

## Vision
[One sentence capturing the emotional core]

## Core Mechanics
- [Mechanic 1]: [brief description]
- [Mechanic 2]: [brief description]
- [Mechanic 3]: [brief description]

## Art Style
[Visual direction: palette, mood, reference aesthetics]
```

### Step 3: Write BACKLOG.md

Format is strict — the orchestrator parses this to create beads:

```markdown
# Backlog for [Game Title]

## P0 - Core Loop (first 7 tasks, playable)

### Task 1: [Imperative title]
**Label**: core
**Description**: [Concrete implementation detail]

### Task 2: [Imperative title]
**Label**: core
**Description**: [Concrete implementation detail]

...

## P1 - Secondary Features

### Task 8: [Imperative title]
**Label**: optional
**Description**: [Concrete implementation detail]

...

## P2 - Future Polish

### Task 15: [Imperative title]
**Label**: future
**Description**: [Concrete implementation detail]
```

**Rules**:
- Titles are **imperative verbs** ("Create X", "Implement Y", "Add Z")
- Labels: `core` (P0), `optional` (P1), `future` (P2)
- Descriptions are **implementation-ready** (not vague; an engineer can execute)
- Exactly 10-20 tasks total; first 7 must form a playable loop
- No dependencies in BACKLOG.md — the orchestrator wires those

## Done when

- VISION.md exists with all required sections (title, vision, mechanics, art)
- BACKLOG.md exists with 10-20 well-formed tasks
- Both files are **self-contained** (no references to beads, epics, or workflow)
- I have **not** created any beads myself — that is the orchestrator's job
