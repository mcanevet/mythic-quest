---
name: genesis
description: Invent a game and produce VISION.md + raw (unassigned) task beads under the raw-backlog step. Do NOT assign, route, or wire dependencies.
---

## What I do

Creates the creative foundation for a new game project:
1. **VISION.md** — Title, vision statement, core mechanics, art style
2. **README.md** — player-facing skeleton ([readme-skeleton.md](reference/readme-skeleton.md)): copy it, substitute title + one-line description, keep the `*Filled in as...*` placeholders — implementers replace them as features land
3. **Raw task beads** — 10-20 unassigned children of the `raw-backlog` step

**Critical constraint**: I am the **creative director**, not the orchestrator. I spawn **raw, unrouted** children — no assignee, no skill label, no dependencies. The orchestrator's backlog-grooming stage decides routing (assignee + skill) for each child.

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

### Step 2b: Copy README skeleton

Copy `reference/readme-skeleton.md` to `README.md` at the project root, substituting `[Game Title]` and the one-line description. Leave all `*Filled in as...*` placeholders intact — implementers replace them as features land.

### Step 3: Spawn raw task beads

Locate the `raw-backlog` step BEFORE creating anything:
```bash
bd list --json | jq -r '.[] | select(.title=="Raw backlog (unassigned)") | .id'
```
**If no `raw-backlog` step exists, STOP** — the orchestrator has not poured
the molecule yet. Report back "molecule not poured; cannot attach raw
backlog" instead of creating your own container (observed wt14: a
self-created container forked the tree and forced a 17-bead re-parenting
detour).

For each task, create an unassigned child of the `raw-backlog` step:

```bash
bd create "[Imperative title]" \
  --parent <raw-backlog-step-id> \
  -t task \
  -p <0|1|2> \
  --description "[Concrete implementation detail]"
```

**Rules**:
- Titles are **imperative verbs** ("Create X", "Implement Y", "Add Z")
- Priorities: `0` (core loop, first 7 tasks), `1` (secondary features), `2` (future polish)
- Descriptions are **implementation-ready** (not vague; an engineer can execute)
- Exactly 10-20 tasks total; first 7 must form a playable loop
- **NO assignee** — grooming decides (poppy/rachel/ian/pootie)
- **NO skill labels or "Use skill:" prefixes** — grooming decides routing
- **NO dependencies between siblings** — grooming wires those

### Step 4: Validate genesis output (mandatory, deterministic exit-0)

Run the validation script before returning success:

```bash
.agents/skills/genesis/scripts/validate.sh
```

Run this from the project root (your session CWD). NEVER construct `../` escapes or absolute paths to a parent repo — everything you need is inside the sandbox. If that invocation fails with "no such file", do not improvise path traversal; locate the script with `ls .agents/skills/genesis/scripts/`.

Exit code must be 0. The script checks:
- Beads ledger initialized (`bd list` succeeds)
- ≥10 open task beads with core/optional/future labels
- VISION.md has required sections (Vision, Core Mechanics, Art Style)
- README.md exists

If validation fails, fix the issues and re-run. Do not return success with a non-zero exit.

## Done when

- VISION.md exists with all required sections (title, vision, mechanics, art)
- README.md skeleton exists (with `*Filled in as...*` placeholders)
- 10-20 raw task beads exist as children of the `raw-backlog` step
- Every bead is unassigned and unrouted (no labels, no deps)
- I have **not** groomed anything — assignment/routing is the orchestrator's job
- `.agents/skills/genesis/scripts/validate.sh` exits 0 (deterministic gate)
