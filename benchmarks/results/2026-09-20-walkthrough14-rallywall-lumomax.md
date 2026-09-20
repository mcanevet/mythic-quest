# Walkthrough 14 — RallyWall (lumo-max) — SHIPPED

**Date:** 2026-09-20 · **Sandbox:** `test/walkthrough14`  
**Pipeline commit:** `826cc3e` (skills: consumer-canonical paths, `bd` ledger init, pin @ `2634031`; includes frontier model `c182c6b`, permission fixes `ffcd76b`, self-verify `53852ed`, doc compression `075a88c`, harness fixes `3c9fccc`)  
**godot-mcp-runtime:** `mcanevet/godot-mcp-runtime#1b28f3f` (shader-material fix; PR #58 pending upstream)

## Outcome

**SHIPPED.** All gates passed. Consumer critique initially rejected (audio unassigned, victory screen overlap), fixes applied, re-acceptance passed. QA gauntlet clean (0 violations), vision re-validation PASS (11/11).

## Headline

**Frontier model dispatch collapsed the orchestrator's dead time but not enough to meet the sub-45m target: 4h47m wall from genesis to ship, orchestrator active 28m of 267m span (10%), but the run carried a heavier debug tail (120 tool errors, 37 permission denials, 2 harness-defect repairs) that inflated subagent time to 267m. Peak concurrency 2, avg 1.01 — parallel waves didn't materialize beyond occasional overlap. Session sprawl 23 sessions (25 total minus 2 stray stubs), down from wt13's 28. Zero denials on core `bd` commands thanks to read-only grants.**

## Metrics

| Metric | wt13 (frontier-prep) | wt14 (frontier live) | wt14 vs wt13 |
|---|---|---|---|
| Outcome | COMPLETE, SHIP-BLOCKED | **SHIPPED** | +1 gate |
| Input tokens (non-cache) | 9.73M | **15.34M** | +58% |
| Cache-read tokens | 12.25M (56%) | **18.53M (55%)** | +51% |
| Output tokens | 102K | **138K** | +35% |
| Sessions | 28 | **23** | -18% |
| Tool calls | 776 | **1,300** | +68% |
| Real-game bugs found+fixed | 1 (win→restart) | **4** (audio×4, layout, lives, difficulty) | +3 |
| End-to-end wall | 3h46m | **4h47m** | +27% |
| Orchestrator active time | 29.2m / 225.7m (13%) | **28m / 267.6m (10%)** | -3% |
| Avg / peak subagent concurrency | 0.92 / 3 | **1.01 / 2** | +0.09 / -1 |
| Gates | 2/3 PASS | **3/3 PASS** | +1 |
| Permission denials | — | **37** | new metric |
| Tool errors | — | **120** | new metric |

**Notes:**
- wt14 wall (4h47m) is **higher** than wt13 (3h46m) despite frontier model: the run fought a heavy QA-debug tail (120 tool errors from permission-denied patterns, 37 denials on non-whitelisted bash commands, 2 harness-defect repairs) and duplicated genesis sessions (2 stray stubs at 12:16/12:17, then proper genesis at 12:35).
- Orchestrator pathology improved but not eliminated: 267.6m span, 28m active (10%), **18 gaps >3min totaling 239m** — classic blocking-await persists. The frontier model's parallel-wave dispatch didn't collapse the wait because the build agent still serialized `bd ready --mol` polls (26 distinct poll commands, 105 `bd` invocations).
- Token split: build 2.53M (16%), poppy 5.95M (39%), rachel 2.01M (13%), ian 1.68M (11%), pootie 2.13M (14%), gustavo 0.60M (4%), stephen 0.34M (2%). Poppy's 11 sessions dominated (5.95M input, 7.95M cache).
- Top re-read tax: `game.gd` 22×, `ball.gd` 18×, `main.tscn` 14×, `player_paddle.gd` 12×, `ball.json` 10× — QA loop re-reads persist.
- Permission denials: 36 skill/read denials on `.agents/skills/worker-common/SKILL.md` (agent profile hole), 1 `bd close --actor` denial (rachel denied closing poppy's bead).
- Tool errors: 120 bash denials for commands outside the whitelist (`ls` without pattern, `bd` commands not matching `bd ready*`, `bd list*`, etc.).

## Pipeline Fixes Shipped Post-Run

| Finding | Fix | Commit |
|---|---|---|
| Orchestrator dead time (blocking `bd` polls) | Frontier model (parallel waves) — partially effective | `c182c6b` |
| Permission denials on `ls`, `bd *` | Read-only grants (`for *`, `ls *`, `cat *`, `awk *`, `sed -n *`) | `ffcd76b` |
| Agent profile read denials | Add `for *` bash grant to build profile | *pending* |
| Harness subpath bug (`node.get('position:x')`) | Documented; engineering fix in dev territory | *out of scope* |
| Duplicate genesis sessions | Sandbox init hygiene (one genesis per run) | *process* |

## Comparison to wt13 (Direct Predecessor)

- **Outcome:** SHIPPED vs SHIP-BLOCKED (wt13's consumer bug blocked release; wt14 fixed audio/layout/lives/difficulty).
- **Wall time:** 4h47m vs 3h46m (+27%) — wt14 ran a heavier QA-debug tail (120 tool errors, 2 harness repairs, duplicate genesis) fighting permission holes and harness defects.
- **Token efficiency:** 15.34M input vs 9.73M (+58%); cache tax 18.53M vs 12.25M (+51%) — re-reads persisted despite `harness-card.md`.
- **Gate success:** 3/3 PASS vs 2/3 PASS — consumer gate passed after re-fix.
- **Concurrency:** avg 1.01 / peak 2 vs 0.92 / peak 3 — frontier model didn't unlock parallelism; build still serialized polls.

## Optimization Opportunities for wt15

**Parallel-wave dispatch (c182c6b):** Collapse 18 blocking gaps >3min (239m idle). Target: reduce orchestrator span from 267.6m to ≤45m wall. Requires:
- Build agent to dispatch bead waves in parallel (`bd ready --mol` → batch dispatch, not serial `bd update` per bead).
- Permission grants to cover batch patterns (`for *`, `bd batch`).

**Permission hygiene:** Add `for *` bash grant to build profile to eliminate 120 denials. Register `types.custom` in sandbox init to avoid human-type flattening warnings.

**Harness defect:** Fix `_resolve_test_value` subpath parsing (split `:` and chain access) in dev territory; document as known defect.

**Session sprawl:** 23 sessions vs wt13's 28 — improved, but duplicate genesis (2 stubs) wasted 27m. Enforce single-genesis discipline in `sandbox-init`.

**Read-tax reduction:** Top 5 files re-read 76 times total. Mitigations:
- Enforce pre-edit grep discipline (already in `53852ed`).
- Consider caching godot_validate outputs per-file across adjacent turns.
- Add `README.md` to cold-start bundle (read repeatedly).

## Next Steps

1. **Add `for *` bash grant to build profile** — eliminates 120 tool errors.
2. **Register `types.custom` in sandbox init** — avoids human-type flattening warnings.
3. **Fix harness subpath bug** — engineering change in dev territory.
4. **Run wt15:** Validate parallel-wave gains (target: wall ≤45m, orchestrator <15m, sessions ≤18, zero denials).

---

**Trace:** `~/.local/share/opencode/opencode.db` (25 sessions, 1,300 tool calls, 1,183 steps).  
**Reports:** `test/walkthrough14/reports/` (functional, vision, consumer, fix-scenarios).
