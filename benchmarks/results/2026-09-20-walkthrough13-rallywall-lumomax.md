# Walkthrough 13 — RallyWall (lumo-max) — COMPLETE, SHIP-BLOCKED

**Date:** 2026-09-20 · **Sandbox:** `test/walkthrough13`  
**Pipeline commit:** `4bc2ad1` (includes frontier model `c182c6b`, permission fixes `ffcd76b`, self-verify `53852ed`, doc compression `075a88c`, harness fixes `3c9fccc`)  
**godot-mcp-runtime:** `mcanevet/godot-mcp-runtime#1b28f3f` (shader-material fix; PR #58 pending upstream)

## Outcome

**COMPLETE, SHIP-BLOCKED.** All 11 beads completed (100%), but a critical bug found in the consumer critique blocks release: the victory screen's "Play Again" button hides the UI but never restarts the game (dead arena, score stuck). Filed as `walkthrough13-e9f` (game-build ledger).

## Headline

**Serial orchestration dominates: 3h46m wall, of which the orchestrator was active only 29m — the rest was 68 blocking `bd` poll-await cycles while one subagent at a time worked (avg concurrency 0.92, peak 3).** Subagent compute itself totaled just 208m of contiguous sessions; the frontier model's parallel-wave dispatch should collapse most of the idle. Build quality high (0 violations in final gauntlet), but the harness had silent-no-op holes patched mid-run. wt13 is the **pre-optimization baseline** for wt14.

## Metrics

| Metric | wt10 (default) | wt11 (medium) | wt12 (medium) | wt13 (frontier-prep) | wt13 vs wt12 |
|---|---|---|---|---|---|
| Outcome | SHIPPED | SHIPPED | SHIPPED | **COMPLETE, SHIP-BLOCKED** | = (except bug) |
| Input tokens (non-cache) | 7.40M | 15.37M | 6.99M | **9.73M** | +39% |
| Cache-read tokens | 9.46M (56%) | 10.31M (40%) | 6.56M (48%) | **12.25M (56%)** | +87% |
| Output tokens | 94K | 124K | 58K | **102K** | +77% |
| Sessions | 14 | 26 | 17 | **28** | +65% |
| Tool calls | 717 | 868 | 633 | **776** | +23% |
| Turns (step-finish) | 586 | 746 | 550 | **829** | +51% |
| Real-game bugs found+fixed | 0 | 2 | 1 | **1** (win→restart) | +1 |
| End-to-end wall | ~2.5h | ~16.6h† | 2h52m | **3h46m** | +31% |
| Orchestrator active time | — | — | — | **29.2m / 225.7m (13%)** | N/A |
| Avg / peak subagent concurrency | — | — | — | **0.92 / 3** | N/A |
| Gates | 3/3 PASS | 3/3 PASS | 3/3 PASS | **2/3 PASS** (consumer blocked) | −1 gate |

† wt11 wall inflated by overnight idle; wt12/13 ran contiguous. All wt13 figures recomputed from the session DB (step-finish token sums, part timestamps) — earlier estimates withdrawn.

**Notes:**
- wt13 wall (3h46m) is **higher** than wt12 (2h52m) and tokens higher (+39%): the run carried a heavy QA-debug tail (8 rachel sessions, 106.4m combined; 4 poppy repair dispatches) that wt12 didn't, fighting harness no-op holes and the softlock/win-restart bugs.
- Orchestrator pathology, quantified: build session spanned 225.7m but was **active 29.2m**, issuing **68 `bd` invocations with 17 poll gaps >3min** — classic blocking-await, avg subagent concurrency 0.92 (peak 3). This is precisely what `c182c6b`'s parallel-wave dispatch targets.
- Token split: build 2.10M (21%), rachel 3.41M (35%), poppy 2.28M (23%), others 1.94M. Rachel+poppy debug tail alone (~5.7M) exceeds wt12's entire run.
- Top re-read tax: `ball.gd` 16×, `game.gd` 16×, `ball.json` 12×, `test_player.gd` 12×, `main.tscn` 11× — the QA loop re-reads the same five files each dispatch; `harness-card.md` covers only the harness portion.
- bash usage is bd-dominated (220 of 253 commands overall; in the orchestrator 68/70): poll-wait choreography, not shell friction.

## Pipeline Fixes Shipped Post-Run

| Finding | Fix | Commit |
|---|---|---|
| Dispatch awaits (92% dead time) | Frontier model (parallel waves) | `c182c6b` |
| Bash segment denials | Read-only grants (`cat`, `ls`, `awk`, `sed -n`, `for *`) | `ffcd76b` |
| Path-base false positives | Gotcha docs + `get_test_state` preference | `ffcd76b` |
| Empty-target no-ops | Existence enforcement in `nodes_in_bounds` | `3c9fccc` |
| Null-path spam | Warn-once diagnostics with nearby paths | `feefce9` |
| Cold-start doc tax | Densified `worker-common`, added `harness-card.md` | `075a88c` |
| Re-verify round-trips | Delta-verify + self-verify discipline | `53852ed` |

## Comparison to wt12 (Direct Predecessor)

- **Wall time:** 3h46m vs 2h52m (+31%) — wt13 ran a heavier QA-debug tail (8 rachel sessions, 106.4m; 4 poppy repair dispatches) fighting harness no-ops and softlock/win-restart bugs.
- **Token efficiency:** 9.73M input vs 6.99M (+39%); cache tax 12.25M vs 6.56M (+87%) — re-reads of `ball.gd`, `game.gd`, `ball.json`, `test_player.gd` each dispatch.
- **Bug discovery:** 1 critical bug (win→restart) vs 1 (score offset) — similar real-game defect rate, but wt13's harness missed the win→restart until consumer gate.
- **Gate failure:** Consumer gate blocked (dead arena) vs wt12's full pass — the harness's silent no-ops let the bug slip through automated QA.

## Optimization Opportunities for wt14

**Frontier model dispatch (c182c6b):** Collapse 68 blocking `bd` poll cycles (17 gaps >3min) by parallelizing bead waves. Target: reduce orchestrator span from 225.7m to ≤45m wall (current active 29.2m + coordination overhead).

**Read-tax reduction:** Top 5 files re-read 67 times total (ball.gd 16×, game.gd 16×, ball.json 12×, test_player.gd 12×, main.tscn 11×). Mitigations:
- `harness-card.md` already cuts harness introspection (covers test_player.gd portion).
- Add `VISION.md` + `README.md` to cold-start bundle (both read repeatedly).
- Enforce pre-edit grep discipline (already in `53852ed`) to avoid multi-match retries.
- Consider caching godot_validate outputs per-file across adjacent turns.

**QA loop contraction:** Rachel's 8 sessions (106.4m) were all debug/repair/verify. With fixes applied (existence enforcement, null-path warnings, delta-verify), expect 30–50% reduction in re-verify round-trips.

**Session sprawl:** 28 sessions vs wt12's 17 — driven by orchestrator polling and repair dispatches. Frontier model + fix-forward policy should compress this toward 15–18 sessions.

## Next Steps

1. **Fix ship-blocking bug:** Address `walkthrough13-e9f` in game-build session.
2. **Run wt14:** Initialize fresh sandbox with current pipeline, validate frontier-model gains (target: wall ≤45m, orchestrator active time <15m, sessions ≤18).
3. **Monitor triggers:** Watch for rolling-gates condition (rachel idle >10m during dev) to activate `mythic-quest-17a`.

---

*Report generated from wt13 trace analysis, post-fix audit, and consumer critique.*
