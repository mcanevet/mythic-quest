# Run 8: RallyWall E2E — SHIPPED (lumo-lite / medium: fork-pinned MCP, first inline-resource build; sleep-poll incident dominates the cost profile) (2026-09-06 06:49 → 11:32)

**Harness revision**: `0323c7c` (Phase-14 retirement sweep: typed-dict Resource construction via MCP tools, poppy `.tscn` exception narrowed) — with `opencode.jsonc` pointing at the fork branch `mcanevet/godot-mcp-runtime#feat/inline-resource-construction` (dist includes `_construct_inline_resource`).
**Prompt**: `benchmarks/prompts/rallywall.md` (verbatim).
**Model**: lumo-lite (proton-lumo), variant **medium**.
**Host**: no host-sleep gaps observed until the final quiet tail; wall-clock otherwise clean.

## Executive Summary

**Status: SHIPPED — 12/12 tasks, 0 blocked, 0 human interventions.** Ian's vision QA passed at MEDIUM-HIGH alignment, Pootie's consumer critique returned SHIP, and the merged QA gauntlet closed at **0 invariant violations** with numeric verification of the speed ramp (420 × 1.05¹⁵ = 873.15 px/s exact) and full win/lose/restart path probes.

**Phase 14 worked in production:** all CircleShape2D instances landed in `scenes/main.tscn` as `shape = SubResource(...)` via the MCP `add_node`/`set_node_properties` path — **zero shape-path parse errors session-wide, zero direct `.tscn` edits**. The retirement sweep's sanctioned path was followed throughout.

**But the cost profile is dominated by one harness failure this run exposed:** the Task-7/8-era QA loop sleep-polled a fire-and-forget scenario — **87 `bash sleep` calls and 79 full report-poll cycles** across the run — and one poppy session burned **2h36m wall / 10.0M input (44% of the run's total)** on a 15-second scenario, compounded by macOS background-throttling (idle engine frames stretch to 10–12s, so the sim barely advances between polls). The run *still shipped* — outcome axis intact — but at 54.3M total tokens (input+output+cache) and 4h43m wall vs run 6's 12.5M/1h43m on the comparable tier. Fix already landed post-run: `86476b4` (`await_test_done()` + playtest skill mandate + `bash sleep` permission removal).

## Raw Metrics

### Time (total 4h43m)

| Segment | Span | Dur | Notes |
|---|---|---|---|
| Genesis (ian) | 06:49 → 06:50 | ~1m | |
| Setup + tasks 1–6 (poppy ×6) | 06:50 → 07:31 | 41m | normal cadence, ~0.4–1.5M each |
| Tasks 7–8 era (poppy) | 07:32 → 10:08 | **2h36m** | **the sleep-poll session** (10.01M input, 266 tools) |
| Tasks 9–12 (poppy ×5) | 10:08 → 11:05 | 57m | recovered to normal cadence after re-dispatch |
| Vision QA (ian) | 11:05 → 11:11 | 6m | MEDIUM-HIGH, 0 violations |
| Consumer critique (pootie ×2) | 11:11 → 11:31 | 20m | verdict SHIP |

### Sessions (16 subagents: 11 poppy, 2 ian, 2 pootie + root; root 384k input)

| Session | Agent | Span | Input | Notes |
|---|---|---|---|---|
| …DsQNXK | ian | 06:49–06:50 | 0.08M | genesis |
| …nSsJzx…U05ubK | poppy ×3 | 06:50–07:00 | 1.46M | setup + early tasks |
| …rUYFT4 | poppy | 07:00–07:12 | 1.14M | |
| …JKtPMI | poppy | 07:12–07:25 | 1.51M | |
| …0D53cO | poppy | 07:25–07:31 | 0.85M | |
| **…iQmf2k** | **poppy** | **07:32–10:08** | **10.01M** | **sleep-poll QA loop; 266 tool calls** |
| …4OMB38…c9tnwg | poppy ×3 | 10:08–10:50 | 3.54M | tasks 9–11 |
| …4ftWAX | poppy | 10:51–11:05 | 1.40M | task 12 QA gauntlet (0 violations) |
| …trcFp6 | ian | 11:05–11:11 | 0.64M | vision QA |
| …875kHy, …qByzP9 | pootie ×2 | 11:11–11:31 | 0.80M | critique → SHIP |

### Tokens (whole run, all 17 sessions)

- **Input: 22.56M** (root 384k + subagents 22.18M; single worst session 10.01M = 44%)
- **Output: 281k · Cache read: 31.41M · Total processed: 54.26M**
- 1,008 model steps; 87 `bash sleep` calls; 79 completed playtest poll cycles.
- vs run 6 (qwen/medium, comparable tier): 12.5M input / 1h43m — **this run: +81% input, +172% wall**, almost entirely attributable to the single loop session (9.3M and 2h36m of it).

### Outcome axis

- **Invariant violations: 0** — merged 60s gauntlet + targeted probes (13-row verification matrix, all green).
- **Speed ramp exact**: 420 × 1.05¹⁵ = 873.149835 px/s live readback.
- **Full end-to-end behavior verified**: paddle clamp exact (100.0/1180.0), score/HUD equality at 15 hits, win/lose mutual exclusion, exactly-once terminals, Enter-restart from both screens, restart burst safety (10 rapid Enters → 1 restart), replay symmetry.
- **Artifact-vs-bug discrimination: strong** — every suspected defect traced to harness artifacts or probe-script bugs (idle-frame spike, mid-freeze label reads), matching run 6's pattern; none mis-diagnosed as game bugs.
- Known pre-flagged drift items from the loop session (bottomless-arena during interim states, fps-throttle artifact in one early pass) were resolved by the final gauntlet.

## Comparison Table (series to date)

| Run | Model / reasoning | Result | Critique cycles | Input tokens | Wall clock |
|---|---|---|---|---|---|
| 4 (09-04) | ling flash | SHIPPED (nudges) | — | 1.85M | — |
| 5 (09-04) | qwen 3.8 27B / none | SHIPPED | 5 (4 REWORK) | 17.6M | 2h51m |
| 6 (09-05) | qwen 3.8 27B / medium | SHIPPED | 1 (0 REWORK) | 12.5M | 1h43m |
| 7 (09-05) | glm / native high | (see its report) | — | — | — |
| **8 (09-06)** | **lumo-lite / medium** | **SHIPPED** | **1 (0 REWORK)** | **22.6M** | **4h43m** |

Not directly comparable to run 6: different model family *and* this run carried a live harness defect (sleep-poll) that run 6's sessions did not exhibit. Excluding the single loop session, the run would land at ~12.5M input / ~2h07m — statistically indistinguishable from run 6's efficiency profile despite the model change and the new MCP code path.

## Incidents

1. **Sleep-poll QA loop (dominant).** Task-7 poppy (…iQmf2k) polled `get_test_report()` across separate MCP calls with `bash sleep 100` in between — 266 tool calls, 10.01M input, 2h36m. Root causes stacked: (a) `start_test` is fire-and-forget and the skill never mandated an awaited wait; (b) macOS background-throttles the idle engine to 10–12s frames, so wall-time hugely exceeded sim-time; (c) every poll re-sent the accumulated diagnostic context. **Fix landed post-run as `86476b4`**: `await_test_done(max_wait_s)` on TestPlayer, playtest skill now mandates a single awaited `run_script` per scenario (timeout = duration + 30s), `bash "sleep *"` permission removed from poppy/ian/pootie, backlog entry records the upstream `run_scenario` blocking-tool candidate. Effect on any same-model rerun: that session collapses from 266 calls / 10.0M / 2h36m to ~1 call / ~0.9M / ~15s.
2. **No silent deaths, no respawns** — first run since run 4 with zero subagent respawns; the MCP bridge stayed up for all 4h43m including the long-lived loop session.
3. **Inline-resource production verification** — first benchmark on the Phase-14 fork pin. Poppy passed `"shape": {"type": "CircleShape2D", "radius": N}` through batch `add_node`; all 5 SubResource shape bindings persisted in the final `main.tscn` via the MCP write path. Zero shape-construction errors session-wide. The `.tscn` fallback exception was never invoked.

## Next Steps

- Rerun the same model/prompt on harness `86476b4` to quantify the sleep-poll fix (predicted: ~12.5M input, ~2h wall, unchanged SHIP outcome).
- Phase 14 evidence complete (unit + integration + production run); PR-ready for godot-mcp-runtime on consent.
- Phase-15 candidate logged: blocking `run_scenario` engine tool in godot-mcp-runtime.
