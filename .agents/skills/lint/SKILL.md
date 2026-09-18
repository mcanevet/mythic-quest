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

### 2. Judge (worker sessions)

Dispatch one worker per child (or small batches). Workers may be harness
subagents or the main session acting as judge — use whichever reliably
executes the protocol below. Give each worker: the child IDs and their
file paths, this worker protocol, and the requirement to **report
anomalies instead of improvising**.

Worker protocol:

1. Claims its child: `bd --actor lint update <child-id> --claim`
2. Reads the target file (path from the child title/description)
3. Loads `.agents/lint/rules.yaml`, applies each rule's prompt to the file
   (the agent is the judge — semantic review, respecting `applies_to`)
4. Posts exactly one comment summarizing findings (or PASS). Use a heredoc so
   backticks and quotes in the verdict are never interpreted by the shell:
   ```bash
   bd comment <child-id> <<'EOF'
   <file>: <line>: <rule-id>: <why> (confidence: ...)
   EOF
   ```
5. Closes: `bd close <child-id> --reason "PASS"` or `"FINDINGS: <n>"`

Worker discipline:

- **The comment must match the analysis.** If your reasoning identifies
  violations, the verdict and close reason must reflect them — do not soften
  findings into a PASS after the fact.
- **Report, don't improvise.** If reality contradicts your instructions
  (child bead missing, title mismatch, unexpected state), stop and report the
  discrepancy in your result. Never create or modify beads beyond
  claim/comment/close on your assigned children.
- If the file matches no rule's `applies_to`, close with
  `--reason "NO APPLICABLE RULES"`.

### 3. Aggregate (fan-in)

When all file children close, the aggregate child becomes ready
(`bd ready --mol <wisp-id>`). Claim it and read the children's comments:

```bash
bd --actor lint update <aggregate-id> --claim
for c in <child-ids>; do bd comments "$c"; done
```

Render the findings table (file | line | rule | message | confidence) from
the comments **before** burning — comments are deleted with the wisp.

### 4. Report and gate

- **PASS**: no findings → `bd close <wisp-id>` then `bd purge --force`
- **FINDINGS**: report the table. Fix or get explicit user waiver before
  committing. After resolution, purge the wisp.
- If the run surfaced something worth keeping (e.g., a systemic issue),
  `bd promote <wisp-id>` preserves a digest before purging.
- **Update the incremental cache** (audit mode only, skip for wisp whose
  target file list was cached-filtered away): for each judged file, append
  `{"file": "<path>", "hash": "$(git hash-object <path>)", "result": "clean"|"dirty"}`
  to `.beads/lint-cache.jsonl` — clean only when the child closed PASS.
  Prune superseded entries for the same file first (keep the latest line
  per file). Clean files are skipped by the next audit run.

## Changing rules

1. Edit `.agents/lint/rules.yaml` only — never restate rules in other files
2. Run `lint-audit` (rules changed = full scope) and fix any violations

## Exit semantics

A confirmed finding means the gate fails: do not proceed to commit without
fixing or getting explicit user waiver.
