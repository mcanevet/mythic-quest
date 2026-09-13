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
| `lint-audit` | all files (excluding `.beads/`, external skills, symlinks) | Periodic audit, milestones |

Mechanical orchestration (discovery, wisp creation, fan-in edges) is done by
[`scripts/lint-wisp.sh`](scripts/lint-wisp.sh) — invoke it, don't replicate it.

## Procedure

The lint run is a **wisp molecule** (ephemeral): one child bead per file,
worked in parallel by subagents, then aggregated and burned.

### 1. Orchestrate

```bash
scripts/lint-wisp.sh dev     # or: scripts/lint-wisp.sh audit
```

The script discovers targets, creates the wisp epic, one child per file,
an aggregate child gated on all file children (`bd dep add` fan-in), and
prints the wisp ID, aggregate ID, and the child→file list.

### 2. Judge in parallel (subagent workers)

Dispatch parallel harness subagents, one batch per ~4 children. Each worker:

1. Claims its child: `bd update <child-id> --claim`
2. Reads the target file (path from the child title/description)
3. Loads `.agents/lint/rules.yaml`, applies each rule's prompt to the file
   (the agent is the judge — semantic review, respecting `applies_to`)
4. Posts exactly one comment summarizing findings (or PASS):
   `bd comment <child-id> "<file>:<line>: <rule-id>: <why> (confidence: ...)"`
5. Closes: `bd close <child-id> --reason "PASS"` or `"FINDINGS: <n>"`

If the file matches no rule's `applies_to`, close with
`--reason "NO APPLICABLE RULES"`.

### 3. Aggregate (fan-in)

When all file children close, the aggregate child becomes ready
(`bd ready --mol <wisp-id>`). Claim it and read the children's comments:

```bash
bd update <aggregate-id> --claim
for c in <child-ids>; do bd comments "$c"; done
```

Render the findings table (file | line | rule | message | confidence) from
the comments **before** burning — comments are deleted with the wisp.

### 4. Report and gate

- **PASS**: no findings → `bd close <wisp-id> && bd mol burn <wisp-id> --force`
- **FINDINGS**: report the table. Fix or get explicit user waiver before
  committing. After resolution, burn the wisp.
- If the run surfaced something worth keeping (e.g., a systemic issue),
  `bd mol squash <wisp-id>` preserves a digest before burning.

## Changing rules

1. Edit `.agents/lint/rules.yaml` only — never restate rules in other files
2. Run `lint-audit` (rules changed = full scope) and fix any violations

## Exit semantics

A confirmed finding means the gate fails: do not proceed to commit without
fixing or getting explicit user waiver.
