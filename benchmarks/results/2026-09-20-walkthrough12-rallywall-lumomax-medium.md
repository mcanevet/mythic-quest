# Walkthrough 12 — RallyWall (lumo-max, medium) — SHIPPED

**Date:** 2026-09-20 · **Prompt:** `benchmarks/prompts/rallywall.md` (identical to w7–w11)
**Sandbox:** `test/walkthrough12` · **Pipeline commit:** `07e2d43`
**godot-mcp-runtime:** `mcanevet/godot-mcp-runtime#c47994c` (combo integration
branch: origin/main + PRs #52, #48, #47, #54 — packed-array fix, `check_health`,
`click_ui_element`, `validate checks`). **First run on the integration pin.**
Harness otherwise unchanged vs wt11; comparison baselines are **wt11** (medium — direct predecessor at same
effort) and **wt10** (default — the reasoning-effort control).

## Outcome

**PASS — shipped.** All gates closed: qa-gate (rachel: functional 10/10,
1 QA-discovered bug found+fixed in a 2-minute repair dispatch), vision-gate
(ian: PASS, HIGH), consumer-gate (pootie: live-play ACCEPT, won at 15).
**No orchestrator anomaly** — build stayed disciplined (0.97M input vs wt11's
9.68M runaway) and never implemented anything itself.

## Headline

**Cleanest run on record: −54% input tokens vs wt11, parity with wt10
(default effort), zero orchestrator pathology — and unlike wt10, it shipped
with a working repair loop.** Total 6.99M input (wt11: 15.37M) with no session
above 2.0M (pootie, genuine playtime). Wall 2h52m (wt11: ~16.6h†, ~2.9h
active-equivalent). The wt11 orchestrator-polling class of bug did not recur —
whether by the medium-effort A/B maturing or run variance, the next
orchestrator-context bead stays open. New cost center: **pootie's acceptance
session (61m wall, 2128s tool-time, 113 calls)** — the single largest
controllable spend in the run.

## Metrics

| Metric | wt10 (default) | wt11 (medium) | wt12 (medium) | wt12 vs wt10 | wt12 vs wt11 |
|---|---|---|---|---|---|
| Outcome | SHIPPED | SHIPPED | SHIPPED | = | = |
| Input tokens (non-cache) | 7.40M | 15.37M | **6.99M** | **−6%** | **−54%** |
| — largest session | 1.23M (build) | 9.68M (build) | 2.00M (pootie) | +63% (real work, not runaway) | no runaway |
| Cache-read tokens | 9.46M (56%) | 10.31M (40%) | 6.56M (48%) | −31% | −36%, better hit-rate |
| Output tokens | 94K | 124K | 58K | −38% | −53% |
| Sessions | 14 | 26 | **17** | +21% | −35% |
| Tool calls | 717 | 868 | 633 | −12% | −27% |
| Turns (step-finish) | 586 | 746 | 550‡ | −6% | −26% |
| Real-game bugs found+fixed | 0 | 2 | 1 | harder than wt10 | = class |
| End-to-end wall | ~2.5h | ~16.6h† | **2h52m** | +15% | −83%† |
| Gates | 3/3 PASS | 3/3 PASS | 3/3 PASS | = | = |

† wt11 wall inflated by overnight idle; wt12 ran contiguous (16:32→19:24).
‡ wt12 turn count from step-finish parts; wt10/wt11 figures from their reports.

Three-way read:
- **vs wt10 (default effort):** essentially at parity on cost (−6% input,
  −12% tools, +15% wall) — but wt12 bought a *working repair loop* for it
  (wt10 shipped with zero real bugs found; wt12's rachel caught one and the
  system fixed it in 2 minutes). Medium effort no longer trades thoroughness
  for its token savings.
- **vs wt11 (medium):** everything improved — the wt11 totals were one
  orchestrator-runaway bug away from good, and wt12 shows the same model
  config performing at control-harness cost with no session discipline
  issues.
- **Session-count trade:** +3 sessions vs wt10 (17 vs 14) reflect the
  finer-grained dispatch waves + repair loop; per-session cost dropped
  accordingly (specialists median 6m).

## Session timeline (17 sessions)

| Agent | Sessions | Wall range | Notes |
|---|---|---|---|
| build | 1 | 172m (9915s tool†) | orchestrator; mostly idle waits, disciplined |
| ian | 2 | 5m, 12m | genesis, vision-gate |
| poppy | 7 | 1–9m | 4 P0 waves + repair + README |
| phil | 1 | 5m | neon materials |
| stephen | 1 | 5m | ball trail + juice |
| gustavo | 1 | 6m | audio cues |
| rachel | 3 | 9m, 29m, 3m | P0 verify, gauntlet, qa-gate resolve |
| pootie | 1 | **61m** | consumer acceptance — cost center |

† build tool-time is dominated by long-running task-child waits.

## What went well

1. **Orchestrator discipline** — 0.97M input, 54 calls, never touched game
   code, dispatched repairs precisely (dispatch → rachel FAIL verdict with
   REPRO → poppy fix → close). The wt11 anomaly class did not recur.
2. **Repair loop at speed** — rachel's P0 verify caught the game-over label
   path bug (game.gd:25 vs actual GameOverContent/FinalScoreLabel tree),
   filed a precise REPRO bead, orchestrator dispatched poppy, fixed+verified
   live in ~2 minutes. Textbook.
3. **Claims/`--actor` idiom institutionalized** — role agents closed with
   `--actor <role>` first-try throughout (wt11's emergent behavior now
   standard). Residual friction moved to the orchestrator side (see beads).
4. **Deterministic specialists** — every specialist session ≤12m wall, ≤1.2M
   input. Median specialist session 6m.
5. **Combo integration pin held** — first full run against
   `c47994c`: `check_health` used for preflight in every session,
   `validate checks` exercised in poppy's assembly wave, no packed-array
   corruption incidents (wt11's catastrophic `9aw` class).

## What cost us (filed as pipeline beads)

| Finding | Count | Bead |
|---|---|---|
| `godot_stop_project` "Operation not permitted" → forbidden `pkill` fallbacks | 15 denials, 6 tool fails | `60b` |
| Dispatcher-held claims → `--force` closes + claim-recovery turns | 6+ forces, ~2 turns/session | `2qb` |
| Literal `walkthroughN` paths in corpus → File-not-found reads | 4 | `6o1` |
| apply-audio gap → hallucinated `AudioStreamWAV.save_to_file()` | 4 SCRIPT ERRORs | `e43` |
| Pootie acceptance session cost | 61m / 2128s / 113 calls | `wsq` |

## Verdict

Medium effort is now the stable operating point: cheapest shipped run in
the series on both time and tokens, with the full gate chain exercised and
a genuine QA-driven repair. Remaining levers, in value order: (1) pootie's
acceptance-gate cost (`wsq` — likely split mechanic re-verification from
consumer-feel), (2) stop-project robustness (`60b`, upstream), (3)
claim-handoff friction (`2qb`, formula change).

## Methodology

Same trace source (`~/.local/share/opencode/opencode.db`), retrospective
via trace-watch scan.py + perf scan + per-session token aggregation
(step-finish part tokens). Watch was live during the run (genesis through
repair dispatch observed in real time).

---

**Sandbox:** `test/walkthrough12` · **Pipeline:** `07e2d43` · **MCP pin:** `c47994c`
**Open pipeline beads from this run:** 60b, 2qb, 6o1, e43, wsq
