# Run 12: RallyWall E2E — SHIPPED (lumo-max / medium; post-run harness analysis of the permission-freeze deadlock and speculation-before-repro)

**Status: SHIPPED — 20/20 tasks (+ optional Task 13 & critique-loop Tasks 16), 0 blocked, 1 human intervention (resolved after 3h39m).** Full pipeline: ian genesis → poppy dev loop (tasks 1–14) → rachel functional QA (found real blocker: win didn't halt gameplay) → poppy bugfix + stale-scenario-config fix → ian vision ALIGNED → pootie consumer critique **REWORK** (real bug: death screen showed "Final score: 0") → poppy bug-hunt/fix → pootie re-critique **REWORK #2** (real bug: hitting 15 wins displayed GAME OVER — win-condition race) → poppy fix → rachel final QA **PASS, 0 violations** (flagged one held-key-through-grace edge, dispositioned as fabricated/by-design, plan 18) → ian vision re-check ALIGNED → pootie final critique **SHIP, 2 B-holes** (verified 15/15 YOU WIN on stream). Root session `ses_f7cfecc66ffemEh6i1gooToGPD` ("brave-nebula"), run id `44fa1ffc`, 2026-09-08 21:51 → 2026-09-09 06:44 UTC (8h53m wall; 5h14m excluding the frozen gap).

**Primary purpose of this record:** two defects worth encoding — a fatal interactive-permission deadlock (unanswered `ask` hangs headless runs) and speculation-before-repro in bug-hunt delegations. Both are now codified (rachel.md denial/boundary discipline, build.md freeze corollaries, playtest empirical-first rule, poppy rule #0 — committed 2026-09-09, `4f02728`); this record is their citation anchor.

## Session tree (25 sessions: root + 24 subagents, all one-shot)

Verified from session DB (recursive parent_id tree; wall = time_updated − time_created):

| Role | Session | Wall | Notes |
|------|---------|------|-------|
| build | brave-nebula (root) | 8h53m | 24 `task()` delegations, no respawns of the root |
| ian | silent-squid (genesis), glowing-mountain (vision-qa), proud-canyon (vision re-check) | — | all ALIGNED |
| poppy | 11 dev sessions | ≤10m each | eager-engine (difficulty tuning) **1h43m** — outlier |
| rachel | tidy-wizard (functional QA) 20m; quick-planet (QA rerun) **3h49m** ← the freeze; calm-eagle (final QA) 21m | — | see Finding 1 |
| pootie | calm-panda 4m (REWORK #1), clever-island 6m (REWORK #2), gentle-cactus 3m (SHIP) | — | all three drove real input; verdicts correct |
| poppy | mighty-wizard (bug-hunt, score-0) 32m; crisp-cabin (fix 15+16) 22m; quick-planet #2 (fix 17) 5m | — | see Finding 2 |

Totals: 10.66M tokens input / 131k output / 44k reasoning across the tree (DB `tokens_*`; input dominates — context re-send, consistent with prior runs).

## Finding 1: permission-freeze deadlock — an unanswered interactive `ask` froze the run for 3h39m

Timeline (all UTC, from `part` table, session `quick-planet` = `ses_f7c57366affecTrdO2kpaXpYQs`):

1. 00:54 — rachel delegated functional-qa rerun. The delegation required updating `GAME_STATE.md`, but rachel's permission config denies her `write`/`edit` on it (orchestrator-owned file).
2. Denied on the write, she explored for alternatives — and globbed `~/.config/opencode/*` (outside the sandbox worktree). Reading opencode's own config dir raises opencode's built-in `external_directory` **interactive permission ask** (`per_083b0fd16001mnwSrU8Suu28gY`, 01:03:29).
3. Nobody was watching. The ask sat unanswered until 04:42:38 when the human happened to notice and approve — **3h39m of wall-clock frozen on a yes/no dialog**. The orchestrator (build agent) cannot see or answer subagent asks; the run was dead-but-not-dead the whole time.
4. On resume, the QA itself completed in 11 minutes.

Root cause is layered: (a) the task gave rachel an obligation she had no permission to discharge; (b) the denial response doesn't say "this is permanent, escalate upward" loudly enough, so the model probes adjacent routes; (c) probing wandered **outside the worktree**, where opencode escalates to `ask` instead of `deny` — the only failure mode a headless run cannot survive.

→ Codified in commit `4f02728`: rachel.md gained "Denial and boundary discipline" (denials are facts to escalate, never puzzles to solve; never touch anything outside the worktree — there is no diagnostic value outside it; state bookkeeping belongs to the orchestrator), and build.md gained the orchestrator-side corollaries (flip checkboxes yourself; scope write permissions so agents can actually deliver what the delegation demands).

## Finding 2: speculation-before-repro — 150 reasoning paragraphs vs. one probe

The score-0 bug hunt (`mighty-wizard`, 32m, 1.35M tokens — largest session in the run): Pootie had reported "death screen shows Final score: 0" while rallies visibly reached 12+. Poppy's delegation mandated "write a proper reproduction first." Instead, the reasoning trace shows ~150 paragraphs of static enumeration — race conditions between scoring/reset, label binding, signal ordering, Godot input event timing — before, on the next step, running a single repro probe that **reproduced the bug immediately** and collapsed the hypothesis space to the real cause (two compound defects: the death handler read the live mutable score after `restart()` zeroed it, plus the restart lacked input grace). Root cause verified empirically; fixes (snapshot-at-transition + edge-triggered restart) went in via `crisp-cabin` (plans 15–17).

Cost estimate: a well-built probe would have falsified most hypotheses on step one; the speculation bought nothing the probe didn't. → Codified as the **empirical-first rule** (playtest SKILL.md gotcha; poppy.md Error Handling Protocol rule #0): repro probe before settling into analysis, static reasoning capped at ~3 rounds, orientation reads exempt.

Secondary observation, same family: `eager-engine` (difficulty tuning) ran 1h43m — longest healthy session in any recent run. Its reasoning shows sound iterative methodology (simulate → tune constants → re-simulate), but the value of a wall/time budget hint in the playtest skill for tuning-style tasks is worth watching on future runs.

## Validated prior changes (no action needed)

- **Instanced-child serialization fix (godot-mcp-runtime fork, PR #38 upstream)** performed correctly throughout: `test/scenes/arena.tscn:86` shows the Ball instanced child with persisted position + script overrides surviving save/load — the exact case dropped before the fix. Rachel's QA recorded 0 serialization violations.
- **Pootie observation-honesty oath (a568643)** held: all three critiques grounded claims in full-resolution captures, flagged ambiguity explicitly ("might genuinely be 0 hits… I couldn't confirm"), and both REWORK verdicts cited **real** bugs, confirmed and fixed downstream. Contrast run 11's false "HUD stuck" claim.
- **Playtest batch-probe guidance (56f0a95):** Rachel's final QA batched state queries per probe (session `calm-eagle`: 314 reasoning lines, clean 21-min pass with one new edge surfaced and correctly dispositioned).

## Harness/upstream outcomes from this run

- **PR #38 open upstream** (`Erodenn/godot-mcp-runtime#38`, branch `pr/instanced-child-serialization` @ `a8b677f`): batch scene operations with per-item schema + instanced-child override persistence; 1190/1190 tests, eslint/tsc/prettier clean. Local MCP pin stays until a release includes it (v3.4.0 does not).
- **Upstream candidate (next):** background-mode idle throttling on macOS lets the simulated world jump in huge single-frame deltas between MCP calls (10–12s frame times, 09-04 run) — contaminates gameplay QA evidence. Candidate: a `low_throttle` option (or documented caveat + tree-pause default) in `run_project`'s background mode. Needs investigation of which mechanism Godot honors headless/hidden.
- **Upstream candidate (opencode):** interactive permission `ask`s are fatal to headless subagent sessions (Finding 1). Candidate: configurable default-deny for subagent-raised `ask`s, or a headless mode that auto-resolves asks as structured denials.

## Objective Triad

1. **Outcome:** PASS — shipped; both consumer REWORKs were genuine bugs now fixed; final stream review verified the exact vision payoff (15/15 → YOU WIN) plus the juice layer (squash/stretch, gold flash, score pop).
2. **Speed:** 8h53m wall, but 5h14m productive — the 3h39m freeze was the single largest wall-time loss in any run to date, and it was preventable (Finding 1). Post-intervention pace (~2h) is on par with run 11.
3. **Tokens:** 10.66M input / 131k output across the tree. Largest single sessions: mighty-wizard 1.35M (Finding 2 — substantially avoidable), eager-engine 1.1M (healthy iterative tuning). No runaway loops or timeout ladders this run.
