---
name: lint
description: Run the governance lint before committing. Two modes: lint-dev (changed files, pre-commit gate) and lint-audit (all files, periodic audit). Parallelized via a beads wisp molecule — one child per file, judged by parallel subagents. Use when editing files under .agents/, before committing, or when auditing the repo.
---

# Lint

Governance lint. Rules live in `.agents/lint/rules.yaml` — the single
source of truth. Other files must not restate them (single-source-of-truth
rule).

## Modes

| Mode | Scope | When |
|------|-------|------|
| `lint-dev` | git-changed files; all files if `.agents/lint/rules.yaml` changed | Pre-commit, pipeline-dev sessions |
| `lint-audit` | all files (excluding `.git/`, `.beads/`) | Periodic audit, milestones |

## Procedure

The lint run is a **wisp molecule** (ephemeral): one child bead per file,
worked in parallel by subagents, then aggregated and burned.

### 1. Discover targets

- **`lint-dev`**: `git diff --name-only HEAD` + untracked files, excluding `.git/`, `.beads/`, `.agents/skills/beads/` (external), and symlinks. If `.agents/lint/rules.yaml` is among the changed files, fall back to full scope.
- **`lint-audit`**: all files in the repo, excluding `.git/`, `.beads/`, `.agents/skills/beads/` (external), build artifacts, and symlinks.

### 2. Create the wisp

**Manual mode** (works on all beads versions):
```bash
WISP_ID=$(bd create "Lint-dev $(date +%Y%m%d-%H%M%S)" -t epic --ephemeral --json | jq -r '.id')
```

**Graph mode** (beads ≥1.3.0): create the whole wisp atomically:
```bash
# Write a plan.json with nodes for the epic + N file children
bd create --graph plan.json --ephemeral
WISP_ID=$(bd create --graph plan.json --ephemeral --json | jq -r '.ids.epic')
```

### 3. Spawn children (one per file)

**Manual mode**:
```bash
for f in $(discover_files); do
  bd create "Lint $f" --parent "$WISP_ID" \
    --description "Apply all rules in .agents/lint/rules.yaml to $f" \
    --ephemeral
done
```

**Graph mode**: the plan.json already contains all children (step 2 created them).

### 4. Fan-in: add aggregate dependencies

Create an aggregate child, then add a `blocks` edge from it to each file child:

```bash
AGG_ID=$(bd create "Aggregate lint findings" --parent "$WISP_ID" \
  --description "Read children's comments and render findings table" \
  --ephemeral --json | jq -r '.id')

for c in $(bd list --parent "$WISP_ID" --status=open --json | jq -r '.[].id'); do
  # Skip the aggregate itself
  [[ "$c" == "$AGG_ID" ]] && continue
  bd dep add "$AGG_ID" "$c"
done
```

The aggregate step becomes **ready** only when all file children close — this is the declarative fan-in gate.

### 5. Judge in parallel (subagent workers)

Dispatch parallel harness subagents. Each worker:

```bash
# Pick a ready file child and claim it
CHILD=$(bd ready --mol "$WISP_ID" --json | jq -r '[.[].issue | select(.type == "task" and .title | startswith("Lint "))][0].id // empty' | grep -v "^$" )
bd update "$CHILD" --claim

# Read the file (path is in the child's description), load .agents/lint/rules.yaml,
# apply each rule's prompt to the file (agent is the judge — semantic review)

# Post findings as comments
bd comment "$CHILD" "<file>:<line>: <rule-id>: <why> (confidence: high/medium/low)"

# Close
bd close "$CHILD" --reason "PASS"  # or "FINDINGS: <count>"
```

If the file has no applicable rules (matches no `applies_to`), close with `--reason "NO APPLICABLE RULES"`.

Note: closing the last file child may auto-close the wisp epic — post findings to child comments BEFORE closing the last child, or rely on aggregate (comments survive burn-adjacent reads).

### 6. Aggregate (fan-in)

When all file children close, the aggregate step (step 4) becomes ready:

```bash
bd ready --mol "$WISP_ID" --plain   # aggregate appears once children are closed
```

Claim the aggregate step and render the findings table from children's comments:

```bash
bd update "$AGG_ID" --claim
for c in $(bd list --parent "$WISP_ID" --status=closed --json | jq -r '.[].id'); do
  bd comments "$c"
done
# Table columns: file | line | rule | message | confidence
```

### 7. Report and gate

- **PASS**: no findings → close the wisp epic and burn:
  ```bash
  bd close "$WISP_ID" && bd mol burn "$WISP_ID"
  ```
- **FINDINGS**: report the table. Fix or get explicit user waiver before committing. After resolution, burn the wisp.
- If a wisp surfaced something worth keeping (e.g., a systemic issue), `bd mol squash "$WISP_ID"` promotes it to a persistent digest before burning.

## Changing rules

1. Edit `.agents/lint/rules.yaml` only — never restate rules in other files
2. Run `lint-audit` (rules changed = full scope) and fix any violations

## Exit semantics

A confirmed finding means the gate fails: do not proceed to commit without
fixing or getting explicit user waiver.
