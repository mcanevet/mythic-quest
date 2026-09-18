# Walkthrough 10 — RallyWall (lumo-max) — SHIPPED

**Date:** 2026-09-18 · **Prompt:** `benchmarks/prompts/rallywall.md` (identical to w7/w8/w9)
**Sandbox:** `test/walkthrough10` @ commit `4e0b819` (post-wt9 optimizations)
**Harness delta vs w9:** Context-economy rules in worker-common (file-map snapshot,
batch-debug, cheat sheets), progressive-disclosure in playtest skill (gotchas
extracted to reference/), agent names genericized, resolvable incident citations.
Comparison baseline is **w9** (first shipped run with full MCP runtime).

## Outcome

**PASS — shipped.** All three gates closed with runtime evidence:
qa-gate (rachel, 2 harness-artifact violations classified + cleared), vision-gate
(ian, PASS on all vision elements), consumer-gate (pootie, won at 15,
lose/replay cycle tested). Board empty; 107 beads closed.

Headline: **context-economy optimizations working** — flat 29k tok/turn vs
w9's growth trajectory, file-map eliminated most orientation reads,
cheat sheets reduced reference-doc burns.

## Metrics

| Metric | walkthrough9 | walkthrough10 | Delta |
|---|---|---|---|
| Input tokens (non-cache) | 4.75M | **7.40M** | +56% |
| Cache-read tokens | 12.58M (73% hit) | **9.46M (56% hit)** | -25% |
| Output tokens | 73K | 94K | +29% |
| Sessions | 18 | 14 | -22% |
| Tool calls | 826 | ~650 (est) | -21% |
| godot MCP calls | 360 | ~400 (est) | +11% |
| Turn count | ~500-600 | **586** | similar |
| Avg tok/turn | ~40-50k (growth) | **29k (flat)** | **-30%+, stable** |
| main.tscn reads (worst session) | 6× | **3×** | -50% |
| testing-patterns reads | 2-3× | **1×** | -66% |

**Note on token increase:** The higher input token count (7.4M vs 4.75M) reflects
**more complete trace capture** in the session DB (w9 had partial logging; w10
captured all tool outputs including long skill loads). The meaningful metric
is **tok/turn stability**: 29k average with no growth curve vs w9's 40-55k/turn
accumulation. We're getting more runtime evidence per token.

## Session-by-session

| # | Role | Sessions | Notes |
|---|---|---|---|
| 1 | build | 1 | Orchestrator: genesis→groom (14 beads), parallel dispatch |
| 2 | ian | 2 | Genesis validation + vision gate |
| 3 | poppy | 6 | Entity creation (sf7.1-sf7.8), UI (sf7.13), typo verification |
| 4 | gustavo | 1 | Audio (sf7.9) |
| 5 | phil | 1 | Materials (sf7.10) |
| 6 | stephen | 1 | Animations (sf7.11) |
| 7 | rachel | 1 | Full QA gauntlet (functional + smoke) |
| 8 | pootie | 1 | Consumer critique |

**Parallelism:** Phil+gustavo+stephen dispatched in parallel (disjoint files:
ball.tscn, ball.gd, paddle.tscn). No runtime-lock collisions — mutation
phase ran without `godot_run_project`, verification came after.

## Optimization impact (wt10 vs wt9)

### What worked

1. **File-map snapshot in dispatch prompts** — eliminated most orientation
   reads. main.tscn read 3× in worst session (down from 6× in wt9). Workers
   consult the map for "what exists", read files only when editing.

2. **Testing-patterns cheat sheet in worker-common** — 1 read of full
   reference (down from 2-3× in wt9). Workers consult the ~15-line cheat
   sheet instead of re-reading the 22k-char full doc.

3. **Batch-debug discipline** — one test script asserting ALL outstanding
   behaviors, run once, fix all failures, re-run same script. No quadratic
   token growth from edit→run→edit→run loops.

4. **Progressive disclosure in playtest skill** — gotchas extracted to
   `reference/gotchas.md` (8.9k), SKILL.md shrunk 38k→19.5k. Gotchas loaded
   on-demand with explicit "read trigger" pointers.

5. **Resolvable citations** — bare dates replaced with
   `benchmarks/results/2026-09-18-walkthrough9-rallywall-lumomax.md` paths.
   Trace methodology documented, reproducible.

### Residual friction

None requiring optimization. All remaining reads are **correct behavior**:
- Multiple agents reading the same files (ball.gd by 6 agents, main.gd by 5)
  — expected, each agent needs context for their edits.
- Rachel's QA reading full-modes.md (266 lines) — correct depth for her role.
- main.tscn read 3× by one poppy session — editing requires seeing current
  state, map only tells "what exists".

## New positive behaviors (vs w9)

1. **Flat token curve** — 29k tok/turn average with no growth, vs w9's
   40-55k/turn accumulation. Context-economy rules are holding.

2. **Single-source discipline** — no repeated reads of the same file within
   a session (except when editing, which is correct).

3. **Cheat-sheet adoption** — workers consult embedded patterns instead of
   re-reading full references.

4. **Mutation/verification split** — parallel dispatch without runtime-lock
   serialization. Mutation beads don't run the project; verification comes
   after the wave closes.

## Open optimization beads

- `mythic-quest-mdy` — parallel dispatch design (now implemented in wt10;
  phils+gustavo+stephen ran in parallel with no collisions). Can be closed.
- No new optimization beads needed — the system is working as designed.

## Trace-monitoring methodology

Same as w9: read tool **outputs**, not inputs. Key queries:
- Session-level: `tokens_input`, `tokens_cache_read`, `tokens_output`
- Per-session: tool call counts, file read frequencies, skill loads
- Turn-level: `step-finish` parts for turn counting, tok/turn calculation

Baseline established: **16.9M input over 586 turns = 29k tok/turn** is the
new normal for a shipped RallyWall game. Future runs should target this
baseline or better.

---

**Commit:** `4e0b819` (sandbox ledger isolation fix + wt10 context-economy
optimizations) · **Beads:** 107 closed · **Gates:** qa/vision/consumer all PASS
