# Walkthrough7 Results — RallyWall (New Harness)

Run: 2026-09-16 19:01–21:28 UTC (~2h27m), `test/walkthrough7/`, RallyWall
(benchmarks/prompts/rallywall.md), lumo-max, **new harness** (pinned
godot-mcp-runtime@3.7.0, committed 2b6afe2), `caffeinate -dimsu`.

Outcome: **PASS** — molecule closed RELEASE. 14 groomed dev beads + 1
spec-restoration bug + 3 consumer-gate bugs all fixed and verified. Gates:
QA clean (rachel 6/6 spec reqs, 0 violations), Vision aligned (ian),
Consumer ACCEPT (pootie, after re-test).

## Metrics

| Metric | walkthrough6 (control) | walkthrough7 | Delta |
|---|---|---|---|
| Wall-clock | 5h47m | **2h27m** | −58% |
| Total input tokens (non-cache) | 13.73M | **7.08M** | −48% |
| Output tokens | 134K | 75K | −44% |
| Sessions | 23 | 18 | −22% |
| Tool calls | 1,106 | 747 | −32% |
| Reasoning parts | 276 | 205 | −26% |
| Compaction | 0 | 0 | — |
| Throwaway build sessions | 3 | **0** | mol pour first try |
| Wrong-bead typo re-dispatches | 1 | 0 | — |
| QA bugs found | 4 | 0 (rachel clean) | +pootie found 3 |
| Parallel dispatches | 1 | 4 (gustavo+stephen, poppy+phil, ian retries, consumer-gate fixes) | 2-bead cap cited in reasoning |

Caveat: RallyWall is a smaller game than Lamplight (~6 mechanics vs a
7-night survival sim) — the token/time deltas conflate harness
improvements with game size. Per-batch and per-verifier numbers are the
comparable units.

## Per-agent input tokens

| Agent | w6 | w7 |
|---|---|---|
| poppy | 4.95M (11 sess) | 2.62M (8 sess) |
| build | 1.57M (5 sess) | 2.02M (1 sess) |
| ian | 0.38M | 0.67M (3 sess — 1 permission-rejected dispatch, retried) |
| rachel | **2.46M** | **0.51M** (−79%!) |
| stephen | 1.27M | 0.49M |
| pootie | 2.05M | 0.35M (2 sess, incl. re-acceptance) |
| gustavo | 0.12M | 0.29M |
| phil | 0.94M (2 sess) | 0.14M |

Standouts: **rachel −79%** (2.46M→0.51M — evidence-sufficiency + report
economy working), **pootie −83%** (2.05M→0.35M incl. a full re-test),
phil −85%. Poppy roughly halved despite the extra bug-fix cycles.
build's single-session cost rose (2.02M vs 1.57M across 5 w6 sessions) —
one continuous session holds full history; net still favorable.

## Harness features observed working

- `bd mol pour` succeeded first try (w6: 3 throwaway sessions)
- 2-bead delegation cap explicitly cited in build's reasoning
- Parallel dispatch on disjoint roles (gustavo+stephen, poppy+phil)
- Consumer-gate bug beads reparented to dev-loop with `skill:playtest` label
- v3.7.0 cold-import: no import failures on fresh sandbox
- close-with-evidence reasons throughout (QA, releases cite reports/screenshots)

## Incidents

1. **Ian dispatch rejected by permission rule once** (Task tool pattern
   mismatch?) — build retried once and it succeeded. Unclear root cause;
   possibly nondeterministic permission matching. Candidate bead.
2. **Epic closed with 2 pipeline-dev beads open** (57s, dyh visible in
   sandbox ledger listing — scope bleed between the game ledger and the
   pipeline ledger view). Cosmetic here (those beads belong to the parent
   repo) but worth checking why `bd list` in the sandbox shows them.

## Validation of in-progress beads

- **4rl (playtest/TestPlayer)**: poppy's bug fixes ran playtest-mode
  verification; rachel's QA passed 6/6 with zero violations. Criterion
  satisfied for this run.
- **57s (context-economy)**: −48% total input, rachel −79%, pootie −83%
  vs control. Criterion satisfied (token-reduction measured), though
  game-size caveat applies.
- **s40 (one-pass discipline)**: zero BLOCKED escalations needed; poppy's
  fix batches closed clean on first or second verification pass. The
  dep-driven blocking flow was NOT exercised live (no deterministic
  failure occurred) — criterion partially validated.
