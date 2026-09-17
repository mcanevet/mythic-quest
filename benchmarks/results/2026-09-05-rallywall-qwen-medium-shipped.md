# Run 6: RallyWall E2E — SHIPPED (qwen reasoning=medium: single critique pass, lowest token burn of the series) (2026-09-05 06:35 → 08:18)

**Harness revision**: `25d1717` (rule-registry lint skill, agent-authoring skill, widened semantic review) — pinned via `prepare_test_dir.sh test` (new default sandbox, production submodule layout).
**Prompt**: `benchmarks/prompts/rallywall.md` (verbatim).
**Model**: qwen 3.8 27B, reasoning effort **medium** — 6th data point; direct controlled comparison against run 5 (same model, reasoning=none) to isolate the reasoning variable.
**Host**: no host-sleep gaps observed; wall-clock clean.

## Executive Summary

**Status: SHIPPED — 12/12 tasks, zero human interventions, zero stalls, zero BLOCKED reports.** First run in the series to ship with **a single consumer-critique pass** (no REWORK cycles at all): one QA-driven polish task appended from Pootie's outer loop, then straight to SHIP. Run 5 needed 5 critique cycles (4 REWORK) for the same prompt; run 6 needed one.

Token cost dropped proportionally: **12.5M input** (vs 17.6M in run 5, −29%), with the reduction concentrated exactly where reasoning was hypothesized to help — fewer critique round-trips and fewer re-verification passes.

Quality held or improved: merged QA gauntlet at **0 violations** (11 invariants × 3600 ticks, p99 18–22ms), numeric speed-ramp verification (300 × 1.05¹⁵ = 623.68 px/s exact), and two suspected bugs correctly diagnosed as **harness artifacts** via real input-event probes ("unresponsive title screen" and "instant game over" both traced to the test driver, not the game) — the judgment quality that run 5 lacked.

## Raw Metrics

### Time (total 1h43m — vs 2h51m run 5)

| Segment | Span | Dur | Notes |
|---|---|---|---|
| Genesis (ian) | 06:35:20 → 06:35:41 | 21s | fastest genesis yet |
| Setup + tasks 1–4 (poppy ×4) | 06:35:51 → 07:00 | 24 min | ~5–7 min/session |
| Tasks 5–8 (poppy ×4) | 07:00 → 07:24 | 24 min | incl. 2 silent-death respawns (recovered, see Incidents) |
| Tasks 9–11 (poppy ×4) | 07:25 → 07:48 | 23 min | task 11 = QA gauntlet session (1.4M tokens) |
| Vision QA (ian ×2) | 07:48 → 07:59 | 11 min | HIGH alignment, 0 violations; cosmetic title-clip flag |
| Consumer critique (pootie ×2) | 07:59 → 08:11 | 12 min | verdict SHIP; probe-verified artifact vs bug |
| Title-clip fix + re-verify (poppy ×2) | 08:12 → 08:17 | 6 min | screenshot-confirmed fix, regression-clean |

### Sessions (18 subagents: 12 poppy, 3 ian, 3 pootie; root 684k input)

| Session | Agent | Role | Dur | Input |
|---|---|---|---|---|
| fAQQS1 | ian | genesis | 21s | 61k |
| Q4wOgf | poppy | setup | 2m | 339k |
| 2q8IzY | poppy | tasks 1–2 | 7m | 973k |
| AZUkKE | poppy | tasks 3–4 | 5m | 715k |
| H60YlW | poppy | tasks 5–6 | 7m | 790k |
| yvdT1r | poppy | task 7 + QA portion | 10m | 1,056k |
| xlQ62a | poppy | task 8 (respawn) | 5m | 696k |
| Hz5oJR | poppy | tasks 9–10 | 10m | 1,071k |
| OChdgG | poppy | task 11 QA (respawn) | 1m | 277k |
| QkE1jM | poppy | QA cont. | 5m | 630k |
| 24g0Jf | poppy | QA cont. | 6m | 653k |
| SKtspA | poppy | QA gauntlet | 12m | 1,417k |
| EB2Hyw | ian | vision QA | 7m | 607k |
| 4jEnPx | ian | vision follow-up | 4m | 368k |
| fTH9ho | pootie | critique 1 | 5m | 472k |
| wbqBVV | pootie | critique cont. | 7m | 553k |
| Bm4l2o | poppy | title-clip fix | 2m | 475k |
| dgfGkE | poppy | fix re-verify | 3m | 634k |

*(Session IDs are `ses_f8f…` prefixes; wall times UTC.)*

### Tokens (whole run)

- **Input: 12.48M** (root 684k + subagents 11.8M) — vs 17.63M run 5 (−29%), vs 1.85M ling-flash run 2.
- **Output: 191k.**
- QA + critique + fix phases ≈ 4.9M (~39% of burn) — vs ~60% in run 5. The run is proportionally less verification-dominated.

### Outcome axis

- **Invariant violations: 0** (merged gauntlet, 11 invariants × 3600 ticks, p99 18–22ms, no crash).
- **Speed ramp verified numerically exact**: 300 × 1.05¹⁵ = 623.68 px/s live readback.
- **Only defect**: cosmetic title-prompt clipping — caught by Ian's vision pass, fixed, screenshot-verified, regression-checked. Entirely self-contained loop.
- **Artifact-vs-bug discrimination**: 2/2 correct (title "unresponsive", "instant game over" → both harness/test-driver artifacts, proven via `parse_input_event` Space probe and driven run to score 15).

## Comparison Table (series to date)

| Run | Model / reasoning | Result | Critique cycles | Input tokens | Wall clock |
|---|---|---|---|---|---|
| 1 (09-02) | frontier max tier | SHIPPED (with nudges) | — | — | — |
| 3 (09-03) | nemotron (floor) | BLOCKED early | — | — | — |
| 4 (09-04) | ling flash | SHIPPED (with nudges) | — | 1.85M | — |
| 5 (09-04) | qwen 3.8 27B / none | SHIPPED | 5 (4 REWORK) | 17.6M | 2h51m |
| **6 (09-05)** | **qwen 3.8 27B / medium** | **SHIPPED** | **1 (0 REWORK)** | **12.5M** | **1h43m** |

**Controlled-variable conclusion (5 → 6):** reasoning=medium on the same model bought −39% wall clock, −29% tokens, 5×→1× critique cycles, and better artifact discrimination — with the same SHIP outcome and a zero-violation gauntlet. On this one comparison, reasoning effort more than pays for itself on cost *and* quality.

## Incidents

1. **Two silent-death respawns (poppy, tasks 8 and 11).** Both subagents died mid-task and were respawned by the orchestrator with **full work reuse** — no lost steps, no duplicated effort. This is the recovery machinery working as designed, not a quality regression; worth watching the respawn *rate* across runs, not just occurrence.
2. **Title-clip cosmetic defect** — real bug found by vision QA, fixed (font_size 32 + autowrap), re-verified by screenshot + 15s chaos re-run + Space-serve regression probe. Textbook polish loop.

## Next Steps

- Next datapoint candidates: qwen reasoning=max (native xhigh — the only higher tier; is the effort curve monotonic?), or the cross-family GLM 5.3 comparison. Note (2026-09-06): GLM has no native medium — requesting medium executes native high — so a true effort-matched GLM run would use its native low tier. Run 7 ultimately tested GLM-high; see its correction note.
- Watch item for future runs: silent-death respawn rate (2 this run, 2 in run 5's tail). If it's stable, the respawn path is healthy; if it grows, investigate the MCP-suicide class in `failure-modes.md`.
