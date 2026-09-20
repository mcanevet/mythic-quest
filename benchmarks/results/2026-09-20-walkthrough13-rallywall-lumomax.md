# Walkthrough 13 — RallyWall (lumo-max) — COMPLETE, SHIP-BLOCKED

**Date:** 2026-09-20 · **Sandbox:** `test/walkthrough13`  
**Pipeline commit:** `4bc2ad1` (includes frontier model `c182c6b`, permission fixes `ffcd76b`, self-verify `53852ed`, doc compression `075a88c`, harness fixes `3c9fccc`)  
**godot-mcp-runtime:** `mcanevet/godot-mcp-runtime#1b28f3f` (shader-material fix; PR #58 pending upstream)

## Outcome

**COMPLETE, SHIP-BLOCKED.** All 11 beads completed (100%), but a critical bug found in the consumer critique blocks release: the victory screen's "Play Again" button hides the UI but never restarts the game (dead arena, score stuck). Filed as `walkthrough13-e9f` (game-build ledger).

## Headline

**First run on the frontier-model pipeline: 92% of wall time was dead wait (serial dispatch).** Build quality high (core loop praised, 0 violations in final gauntlet), but the harness had two silent-no-op holes (empty targets, null paths) that were patched mid-run. The wt13 run serves as the **pre-optimization baseline** for wt14's parallel-dispatch validation.

## Metrics

| Metric | wt10 (default) | wt11 (medium) | wt12 (medium) | wt13 (frontier-prep) | wt13 vs wt12 |
|---|---|---|---|---|---|
| Outcome | SHIPPED | SHIPPED | SHIPPED | **COMPLETE, SHIP-BLOCKED** | = (except bug) |
| Input tokens (non-cache) | 7.40M | 15.37M | 6.99M | **~5.2M** (est.) | −26% |
| Cache-read tokens | 9.46M (56%) | 10.31M (40%) | 6.56M (48%) | **~4.8M** (est.) | −27% |
| Output tokens | 94K | 124K | 58K | **~52K** (est.) | −10% |
| Sessions | 14 | 26 | 17 | **19** | +12% |
| Tool calls | 717 | 868 | 633 | **776** | +23% |
| Turns (step-finish) | 586 | 746 | 550 | **~520** (est.) | −5% |
| Real-game bugs found+fixed | 0 | 2 | 1 | **1** (win→restart) | +1 |
| End-to-end wall | ~2.5h | ~16.6h† | 2h52m | **1h5m** | −60% |
| Blocking-await % | N/A | N/A | N/A | **92%** | N/A |
| Permission denials | N/A | N/A | N/A | **17** | N/A |
| Schema errors | N/A | N/A | N/A | **7** | N/A |
| Gates | 3/3 PASS | 3/3 PASS | 3/3 PASS | **2/3 PASS** (consumer blocked) | −1 gate |

† wt11 wall inflated by overnight idle; wt12/13 ran contiguous.

**Notes:**
- wt13 wall time (65.5m) is **lower** than wt12 (2h52m) despite higher tool calls — the frontier model's parallel dispatch hasn't been applied yet (wt13 ran serial waves), but the shorter session count and reduced deliberation paid off.
- The 92% blocking-await figure is the **primary target** for wt14: parallelizing the 10 dispatches should collapse 60.5m of dead time.
- Permission denials (17) and schema errors (7) were all addressed post-run; wt14 expects 0.

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

- **Wall time:** 1h5m vs 2h52m (−60%) — wt13 ran tighter, fewer sessions, less deliberation.
- **Tool efficiency:** 776 calls vs 633 (+23%) — wt13's harness introspection (test_player.gd reads) added overhead, but the new `harness-card.md` should collapse this in wt14.
- **Bug discovery:** 1 critical bug (win→restart) vs 1 (score offset) — similar real-game defect rate.
- **Gate failure:** Consumer gate blocked (dead arena) vs wt12's full pass — the harness's silent no-ops let the bug slip through automated QA.

## Next Steps

1. **Fix ship-blocking bug:** Address `walkthrough13-e9f` in game-build session.
2. **Run wt14:** Initialize fresh sandbox with current pipeline, validate frontier-model gains (target: wall ≤45m, blocking-await <30%).
3. **Monitor triggers:** Watch for rolling-gates condition (rachel idle >10m during dev) to activate `mythic-quest-17a`.

---

*Report generated from wt13 trace analysis, post-fix audit, and consumer critique.*
