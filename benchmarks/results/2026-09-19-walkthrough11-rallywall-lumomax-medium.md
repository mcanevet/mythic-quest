# Walkthrough 11 — RallyWall (lumo-max, reasoning effort: medium) — SHIPPED

**Date:** 2026-09-18 → 2026-09-19 · **Prompt:** `benchmarks/prompts/rallywall.md` (identical to w7–w10)
**Sandbox:** `test/walkthrough11`
**Harness delta vs wt10:** model variant **medium reasoning effort** (wt10
ran `default`). Harness/corpus otherwise unchanged. Comparison baseline is
**wt10** — first run of the reasoning-effort A/B.

## Outcome

**PASS — shipped.** All three gates closed:
qa-gate (rachel, 4-pass dev-loop: 2 real bugs found+fixed — ball world
offset, stripped-script regression — then green suite), vision-gate (ian,
PASS), consumer-gate (pootie, live-play PASS, won at 15). Animation beads
(agj.11–13, VISION-mandated ball trail among them) deferred by orchestrator
release decision — vision gate passed a game missing a VISION-mandated
visual (finding, see Routing).

## Headline

**Medium effort ships the same game at roughly half the per-session
latency and 12% fewer tokens — but the orchestrator pays for it in
deliberation volume.** Total input 15.4M vs 7.4M (+107%) is dominated by
one runaway build session (9.7M input, 43k output — mostly idle-wait poll
cycles re-reading a growing sandbox ledger); specialist totals are
*lower or equal* to wt10 (poppy 2.0M vs 2.4M, ian 0.65 vs 1.12, gustavo
0.12 vs 0.59). Excluding build: **5.7M vs 6.2M input (−8%), with 86%
more sessions and a dev-loop wt10 never entered.**

## Metrics

| Metric | wt10 (default) | wt11 (medium) | Delta |
|---|---|---|---|
| Model | lumo-max default | lumo-max **medium** | variant A/B |
| Outcome | SHIPPED | SHIPPED | = |
| Input tokens (non-cache) | 7.40M | **15.37M** | +107%* |
| — excluding build session | 6.17M | **5.69M** | **−8%** |
| Cache-read tokens | 9.46M (56%) | 10.31M (40%) | +9%, worse hit-rate |
| Output tokens | 94K | 124K | +32% |
| Sessions | 14 | **26** | +86% |
| Tool calls | 717 | **868** | +21% |
| Turns (step-finish) | 586 | 746 | +27% |
| Specialist avg tok/session | 438K | 356K | −19% |
| Real-game bugs found+fixed | 0 | **2** | harder run |
| End-to-end wall | ~2.5h | ~16.6h† | +570%† |

\* build session holds 9.68M (63% of run total) vs wt10's build 1.23M —
 see "Orchestrator anomaly" below.
† wall inflated by idle overnight waits and orchestrator poll cycles;
specialist sessions themselves were fast (median poppy session 4m).

## What medium effort did well

1. **Specialist efficiency** — every specialist's non-orchestrator session
   used fewer input tokens than its wt10 counterpart (poppy −18%, gustavo
   −80%, ian −42%). Reasoning passes are shorter; fewer re-deliberations
   per action.
2. **More thorough repair loop** — rachel found 2 real gameplay bugs
   (ball rendered outside arena coordinates; a fix that stripped
   game-director wiring) that wt10's QA never surfaced. More sessions ≠
   worse work: the dev-loop iterated honestly to green.
3. **Claim discipline held** — explicit `--claim --actor <role>` worked
   first-try across the run (wt10's idempotency refusals gone; the
   `--actor` idiom emerged organically).
4. **Speed per session** — poppy sessions median ~4m; specialists are
   clearly faster per session at medium effort.

## What medium effort cost

1. **Orchestrator runaway** — build: 9.68M input, 43k output across 258
   calls, 994m wall (mostly idle). The orchestrator at medium effort
   polls the ledger aggressively and its context grows unboundedly across
   the whole run (single session for ~16h). This is one bug-class: an
   orchestrator that never compacts/resets context. Fixes filed (see
   beads below).
2. **Orchestrator self-involvement in repairs** — at default effort wt10's
   build never implemented anything; wt11's build performed 6+ direct
   `--force` repair closes, edited scripts via run_script, and dispatched
   itself as finisher (contrary to "never implement yourself"). Lower
   effort → the orchestrator reaches for its own hands instead of
   crafting a precise dispatch.
3. **Vision-gate enforcement gap** — ian PASSed a game missing the
   VISION-mandated ball trail (agj.11 closed DEFERRED as "P2 polish"
   before gates ran). Not caused by medium effort, but compounded: the
   gate didn't cross-check mandated visuals against bead dispositions.
4. **Silent death** — phil's material session died mid-flight (PackedVec2
   corruption → improvised write-bypass → unbounded repair spiral);
   detected only via bead-close-actor mismatch. 48m wall, 3s tool-time.

## Incident classes (all filed as pipeline beads)

| Class | Count | Bead |
|---|---|---|
| Piped bash denied (v1 shell segment-splitting) | 38× | `cxq` |
| GDScript `:=` inference compile errors | ~19 calls | `anc` |
| Gate-close "blocked issue" refusals | 3/3 gates | `4c1` |
| Operation not permitted (`_process`) | every engine session | `tgu` |
| PackedVector2Array zero-write w/ success:true | 1, catastrophic | `9aw` |
| write-tool `*` allow bypassing edit deny-baseline | discovered, acted on | `4cy` |
| Self-created-stray deliberation spiral | 1 (20 reasoning fragments) | `se8` |
| bd flag guessing | ~6 variants | `qbs` |
| Human actor leak in ledger | 1 | `36z` |

## Verdict on medium effort

**Ship medium for specialists; keep default (or fix the polling) for the
orchestrator.** The specialists at medium were cheaper per session,
faster, and produced a game with *more* verified correctness (2 real
bugs caught by a genuinely exercised QA loop). The run's bloated totals
come almost entirely from the orchestrator's never-compacting session —
an architectural issue, not a model-effort one. Recommended next A/B:
medium everywhere + orchestrator context-reset per molecule phase
(build bead needed: checkpoint/reset orchestrator context between
dispatch waves; cap poll cadence).

## Methodology

Same trace source as w9/wt10 (`~/.local/share/opencode/opencode.db`);
this report also debutted the upgraded trace-watch retrospective
(checklist + waste lens + `scan.py --perf`), whose findings (38× bash
denials root-caused to opencode's per-pipeline-segment permission
matching; per-session wall/tool-time decomposition showing gates are
model-latency-bound, not tool-bound) are folded into the beads above.

Baseline for a shipped RallyWall at medium effort: **~21M input total
(~6M specialists + orchestrator), 750 turns, 3 QA passes** — expect the
orchestrator fix to cut the total by half.

---

**Sandbox:** `test/walkthrough11` · **Gates:** qa/vision/consumer all PASS
**Open pipeline beads from this run:** cxq, 4c1, 9aw, w41, jym, tgu, 0c9,
bsi, oqm, anc, 4cy, se8, qbs, 36z, a8x
