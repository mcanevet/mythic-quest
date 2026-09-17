# Run 11: RallyWall E2E — SHIPPED (lumo-max / medium; post-run harness analysis of Rachel probe economics and Pootie observation honesty)

**Status: SHIPPED — 14/14 tasks, 0 blocked, 0 human interventions.** Functional QA (Rachel) passed with 0 violations, vision QA (Ian) aligned, consumer critique (Pootie) returned SHIP with 2/5 B-holes. Root session `ses_f7da351abffeuzhlwxRQH6aYOznl9` ("witty-sailor"), 2026-09-08, 18:51–20:41 UTC (~1h50m wall).

**Primary purpose of this record:** this run shipped cleanly, but its traces exposed two skill-level defects (probe economics, observation honesty) that motivated playtest-skill changes on 2026-09-08. The facts below are verified against the session DB (`~/.local/share/opencode/opencode.db`) and the sandbox artifacts (`test/reports/`), so skill citations have a resolvable anchor.

## Session tree (12 subagents, all one-shot)

| Role | Title | Wall time | Notes |
|------|-------|-----------|-------|
| ian | game-genesis | — | initial vision |
| poppy | setup-project, task batches (2 tasks/delegation ×6), log-task-14 | — | 7 dev sessions, no respawns |
| rachel | functional-qa | **20m44s** (20:06:39→20:27:23) | 0 violations, 36 model turns |
| ian | vision-qa | — | aligned |
| pootie | consumer-critique | ~4m (20:35→20:39) | SHIP 2/5 |

## Finding 1: Rachel's probe economics — serial one-question-per-call probing

Rachel's tool histogram (from `part` table, session `ses_f7d5ec447ffexSF4InZxOdE0cC`): **14 `run_script` + 1 `run_project` + 2 `take_screenshot` + 11 `read`** across 36 assistant turns in ~21 minutes. Each engine round-trip (headless op or live probe) pays MCP spawn/handshake + engine resume + a full model turn re-sending accumulated context. The probes were high quality (per-hit instrumented sampling, exact ratio verification for the ×1.05 ramp — see `test/reports/functional-qa.md`), but each gathered one question's worth of state. Batching multiple state queries / input steps / samples into single `run_script` bodies (each probe already reloads scene state internally) would cut the engine round-trip count roughly in half. → motivated the _Post-report diagnostics: batch your probes_ section in `skills/playtest/reference/full-modes.md` (functional mode).

Related artifact already documented by Rachel herself (functional-qa.md §artifacts 1 & 4): idle-engine between MCP calls in background mode lets the ball die before the next probe lands (macOS background throttle); her fix was in-script scene reload — codified at SKILL.md Common Workflow (background-throttle gotcha, tree-pause/reset guidance).

## Finding 2: Pootie's observation honesty — inferred state presented as observed

During the consumer critique (`ses_f7d44cf0effe4YNzEoOfLBjggA`), Pootie's own reasoning trace caught the defect, mid-run (verbatim from `part.reasoning`):

> "Rally 12? Screenshot still shows Score: 0. Wait — the score label always shows 0?? Screenshots kept showing Score: 0 every time even mid-rally. That's suspicious — HUD maybe not updating. But game over said Final score: 0 too, earlier at rally 4. Hmm, screenshots I took were all at... actually every screenshot showed GAME OVER score 0, even when I claimed mid-rally."

The pattern: every screenshot was taken at GAME_OVER (engine advanced to game-over between MCP calls — the same background-throttle/idle issue as Finding 1), so the visible "Score: 0" was the post-game default, not the live HUD. Pootie half-diagnosed this ("screenshots I took were all at GAME OVER") yet still broadcast "score HUD stuck at 0" as a stream observation. Contradicting evidence existed in-session: the game-over screen Pootie himself saw at rally 4 showed "Final score: 4" — a live score that had visibly incremented.

The orchestrator caught the discrepancy by cross-checking Rachel's functional-qa.md (row 13: "ScoreLabel text tracked score exactly: 'Score: 1'…'Score: 5'", live-display verified per-hit) against Pootie's claim, and Rachel's evidence won. Cost: one reconciliation step at the root, plus a fabricated-ish observation in a persisted report. Had the root not cross-checked, a working HUD faced a REWORK cycle.

→ motivated the _Observation honesty_ rule in `skills/playtest/reference/full-modes.md` (critique mode, Part A): every fact narrated or flagged must come from a screenshot/probe actually inspected; never infer state from elapsed time or expected behavior; say "not captured" rather than fill gaps.

## Objective Triad

1. **Outcome:** PASS — shipped, all three QA gates green, final product matches vision (neon minimalist reflex snack).
2. **Speed:** ~1h50m wall, 0 respawns, 0 human interventions — competitive with run 9's 3h32m on a harder, longer prompt set.
3. **Tokens:** not re-measured post-hoc (DB `part` table lacks token columns); no pathological context growth observed in Rachel/Pootie sessions (turn counts moderate: 36 / ~30).

## Dispositions

- Batched-probe guidance → playtest skill (functional mode), 2026-09-08.
- Observation-honesty rule → playtest skill (critique mode Part A), 2026-09-08.
- "Score HUD stuck at 0" claim → **retracted as harness artifact** (background-mode idle advance to GAME_OVER between screenshots); live HUD verified working by functional QA.
