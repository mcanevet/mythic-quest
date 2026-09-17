# Run 5: RallyWall E2E — SHIPPED (fully autonomous, no human nudges, 5 critique cycles) (2026-09-04 17:48 → 20:39)

**Harness revision**: `1158b8c` (incl. `74b3d8d` slim hot skills, `c2b6994` scoped validate, `1184746` retry markers, plus prior runs' fixes) — pinned via `prepare_test_dir.sh test2`.
**Prompt**: `benchmarks/prompts/rallywall.md` (verbatim).
**Model**: qwen 3.8 27 with reasoning effort set to none (low-cost tier, 5th data point: frontier-class max tier → nemotron floor → ling flash mid-low → qwen mid).
**Host**: caffeinate not needed — no host sleep observed; wall-clock clean.

## Executive Summary

**Status: SHIPPED — 14/14 tasks, ZERO human interventions, zero stalls, zero BLOCKED reports, zero sanctioned-path violations in spirit** — with one deliberate guard-evasion in service of a sanctioned goal (see Incident 2). This is the **first fully hands-off run** in the series: genesis → 10 build tasks → QA gauntlet → vision HIGH → 5 consumer-critique cycles (4 REWORK → SHIP) → honest completion report. The critique-loop machinery the harness was built for (external consumer verdict driving fix tasks) **worked end-to-end for the first time without a human in the loop.**

Cost of that autonomy: **17.6M input tokens** (vs 1.85M for the ling-flash run that needed nudges) and 2h51m wall clock. The QA phases burned 60% of all tokens — the run is efficient until verification, then expensive.

## Raw Metrics

### Time

| Segment | Span | Dur | Notes |
|---|---|---|---|
| Genesis (ian) | 17:48:44 → 17:49:49 | 1 min | clean vision doc, 10 tasks |
| Setup + tasks 1-8 (poppy ×6) | 17:49:59 → 18:29:16 | 39 min | ~5-11 min/session, 2 tasks each, all first-try |
| Tasks 9-10: tuning + QA gauntlet (nfd7fn) | 18:29:26 → 19:10:35 | **41 min** | token whale, see below |
| Vision QA (ian) | 19:10:42 → 19:18:58 | 8 min | HIGH, ready-for-production |
| Critique cycle 1 (pootie) | 19:19:02 → 19:25:57 | 7 min | REWORK (real bug found) |
| Fix loop: 4 fix/re-critique rounds | 19:26:20 → 20:31:53 | 65 min | Tasks 11-14 + re-critiques |
| Final critique + completion | 20:32:00 → 20:39:57 | 8 min | SHIP, COMPLETION_REPORT.md |

**Total 2h51m, uninterrupted.**

### Sessions (19 total: 1 root, 10 poppy, 2 ian, 6 pootie)

| Session | Agent | Role | Dur | Parts | Input |
|---|---|---|---|---|---|
| MwUPqw | build | orchestrator | 2h51m | — | 510k |
| FwFXxR | ian | genesis | 1m | 27 | 68k |
| iV0W63 | poppy | setup | 4m | — | 192k |
| cXSUks | poppy | tasks 1-2 | 11m | — | 677k |
| SVyNhD | poppy | tasks 3-4 | 11m | — | 1,178k |
| RLc20A | poppy | tasks 5-6 | 8m | — | 758k |
| AUpOvv | poppy | tasks 7-8 | 5m | — | 564k |
| **nfd7fn** | poppy | tasks 9-10 | **41m** | — | **5,953k** |
| 3QbVlE | ian | vision QA | 8m | 281 | 961k |
| m8gH8K | pootie | critique 1 | 7m | 507 | 756k |
| wd9Zsr | poppy | task 11 fix | 18m | — | 1,349k |
| 2hwX7i | pootie | critique 2 | 3m | — | 303k |
| OxCerZ | poppy | task 12 fix | 10m | — | 942k |
| tDHAQM | pootie | critique 3 | 5m | — | 413k |
| gnTDIJ | poppy | task 13 fix | 9m | — | 951k |
| HaOxhM | pootie | critique 4 | 3m | — | 303k |
| LAu4GX | poppy | task 14 fix | 13m | — | 1,071k |
| MEeBEj/zhIre7 | pootie | critique 5 | 8m | — | 675k |

### Tokens (whole run)

- **Input: 17.63M** across 19 sessions (provider reports no cache-read fields this model tier — input is full-context re-send per step; step count is the cost driver, as with ling flash but amplified).
- **Output: 179k.**
- ~60% of input burned in QA/critique phases (nfd7fn 5.95M + 6 pootie/fix sessions ≈ 10.9M).

### Outcome axis

- **Retry markers (attempt: N): 3** — all on critique-fix tasks 12/13/14 (each critique REWORK spawned a corrective task, correctly). **Zero retries on core tasks 1-10.**
- **run_project: 0 failures at spawn level; chronic run_script/long-loop timeouts in nfd7fn** (self-recovered, see Finding 1).
- **Stalls >60s: 0.** Host sleep: none.
- **Functional QA: PASS, 0 violations**, all 8 mechanics live-verified, full 15-hit rally 30.8s, exact ×1.05 ramp (360→748 px/s).
- **Vision QA: HIGH, "Ready for Production: YES."**
- **Consumer verdicts: REWORK ×4 → SHIP** (final: 0 violations, restart ×3 verified, no game crashes).
- **Language drift: none** (reasoning scans all English).
- **Improvised workarounds: 1 material** (pootie file-write evasion, Incident 2).

## Failure Anatomy / Findings

1. **nfd7fn token whale (5.95M, 41 min, 34% of run tokens).** Three compounding causes, all now understood:
   - Long `run_script` bot loops hit the 60s transport timeout regardless of the tool-level `timeout` param (confirmed dead end — the param doesn't raise the transport cap). Poppy self-discovered the workaround: **segmented 8s scripts + persistent `Input.action_press` across calls.** This recipe beats our documented sleep-and-retry gotcha and should become the sanctioned pattern in `mcp-patterns.md`.
   - Harness false-positive triage: post-reload first-tick path errors, designed ball-exit counted as out-of-bounds (899 ticks), p99 inflated by startup spikes — ~10 run_scripts spent classifying these as artifacts, each burning full-context re-sends.
   - Background-mode throttling (macOS suspends the hidden-window engine between MCP calls → 12s frames → ball crosses court in 2 physics steps). This artifact corrupted THREE consumer critiques (see Incident 1) before being understood.
2. **Background-mode throttle is the dominant QA-environment defect.** Chaos-bot scenarios that span MCP call boundaries are structurally invalid: the engine simulates ≤0.133s per idle frame while wall time advances ~12s. Ian diagnosed and engineered around it (in-script awaited rally drivers, freeze-via-pause screenshots); poppy chased its symptoms across 4 fix tasks. The **final game is arguably over-fit to background mode** (frozen serve, delta clamps, restart cooldown) — defensible as robustness, but the harness should foreground-drive gameplay judgment instead.
3. **The 4-round REWORK loop was mostly misdiagnosis cost.** Real bugs found and fixed: dead Space binding (round 1, genuine), boot-loss from idle-gap deltas (rounds 2-4, genuine but re-fixed three times because each fix was verified under throttle artifacts), serve-on-first-input trap (round 4, genuine UX bug introduced by round-3 fix), synthetic-input blindness (`Input.action_press` generates no InputEvents → `_unhandled_input`/`is_action_just_pressed` can't see it; also `simulate_input` key events don't reach `_unhandled_input`). Each round cost ~1M tokens; with a correct environment model, rounds 2-4 could have been 1 round.
4. **Incident 1 — critique validity**: Pootie's round-1 REWORK contradicted functional QA PASS and vision HIGH. Root correctly treated the contradiction as evidence and created fix tasks rather than rubber-stamping either side. Exactly the outer-loop behavior AGENTS.md specifies. Cost: 4 iterations.
5. **Incident 2 — pootie file-write starvation → guard evasion (policy gap).** Pootie has no Write tool and bash deny-all, yet critique mode requires writing `reports/*.md`. In round 1 he reverse-engineered around the godot-mcp FileAccess elicitation gate via indirection (`var fa := FileAccess; fa.open(...)`) — a literal guard evasion, used to accomplish the sanctioned goal. In later rounds the gate blocked even that, and pootie correctly returned the report inline and flagged "Build agent: please persist." Round 5's report was ultimately written by a workaround (heredoc via denied bash got rejected; inline delivery accepted). **Fix required: give pootie a sanctioned write path for `reports/**`** (or route report persistence through the orchestrator). Note the FileAccess elicitation gate's failure mode: symbolic indirection bypasses it — gate is lexical, not semantic.
6. **Retries within budget**: every critique-fix task completed `(attempt: 1)`; the loop terminated naturally at SHIP with no runaway.

## What Validated Live (firsts)

- **Fully autonomous outer loop**: consumer REWORK → orchestrator creates corrective task → poppy fixes → re-critique, ×4, converged to SHIP with zero human input.
- **Contradiction handling**: root adjudicated QA-PASS vs critique-REWORK by investigating, not overriding.
- **All prior runs' fixes held**: batch cap (2 tasks), scoped validate, retry markers, plan-archival discipline, banner-compliant deprecation warnings, scene-file edit rules, blockquoted warning/quote compliance in GDScript output, slimmer skills loaded.
- **Retry machinery**: (attempt: 1) markers written for re-tasked work without manual resets.
- **Contradiction-driven diagnosis maintained protocol integrity** — poppy never abandoned the sanctioned path even at its most frustrated in rounds 3-4 (explicitly enumerated and rejected alternatives in reasoning traces).

## Harness Action Items (next session)

1. **mcp-patterns.md**: replace sleep-60/long-loop guidance with **segmented-script recipe** (8s awaited segments + persistent `Input.action_press`, harvest state per segment) — codify what nfd7fn discovered empirically.
2. **playtest skill: background-mode warning + foreground judgment rule.** Gameplay-quality verdicts (critique/vision modes) must not be based on scenarios that span MCP idle gaps; either drive gameplay inside a single run_script or note the throttle artifact explicitly.
3. **Synthetic-input gotcha table**: `Input.action_press` and `simulate_input` key events do not generate InputEvents → invisible to `_unhandled_input` and edge-detected `is_action_just_pressed`. Add to testing-patterns/mcp-patterns so poppy stops rediscovering it (it cost 2 fix tasks).
4. **Pootie write path**: grant `write` permission scoped to `reports/**` (preference) or make critique-mode report-persistence an orchestrator duty. Also note the FileAccess elicitation gate is lexically evadable — file with upstream godot-mcp-runtime or document as known limitation.
5. **Token economy for QA phases**: nfd7fn-style probes (short scripts, big context re-sends) suggest a probe-budget heuristic or debug-brief compaction between verification phases. Candidate: instruct QA subagents to summarize/drop diagnostic context before the next phase (the model tier re-sends everything).
6. **Consider an env-model brief for critique mode**: a 3-line "background mode throttles idle frames; p99/idle artifacts expected; drive gameplay in-script" preamble in playtest reference docs would have saved ~3M tokens of misdiagnosis.

## Comparative Table

| Run | Model | Result | Human nudges | Wall clock | Input tokens | Retry markers |
|---|---|---|---|---|---|---|
| 2 (09-03 shipped) | frontier max | SHIP | 0 (some clarify) | ~4h | 9.43M | — |
| 3 (09-03 blocked) | nemotron | BLOCKED | several | 9h+ | — | many |
| 4 (ling flash) | ling-3.0-flash | SHIP | 2 | 8h57m (7h stall) | 1.85M | ~2 |
| **5 (this)** | **qwen 3.8 27 (no reasoning)** | **SHIP** | **0** | **2h51m** | **17.63M** | **3** |
