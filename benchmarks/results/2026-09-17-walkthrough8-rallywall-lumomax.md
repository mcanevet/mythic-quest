# Walkthrough8 Postmortem — RallyWall (RallyWall prompt)

Run: 2026-09-17, `test/walkthrough8/`, "RallyWall" (benchmarks/prompts/rallywall.md),
lumo-max, opencode, Godot 4.3 plugin, pipeline @ 512fa5a (post-lint-fix commit).

Outcome: **PARTIAL** — game shipped (SceneTree-based, no .tscn), all beads +
gates closed, good process mechanics (2-bead cap perfect, bead-ID integrity
flawless, gate chain honest). BUT: **zero MCP tool calls across all 19
sessions** — nobody played or tested the game at runtime; all verification
was static code review. Central promise of the run (MCP-driven playtesting)
never engaged.

## Headline numbers

| Metric | Value |
|---|---|
| Wall-clock | ~70 min |
| Sessions | 19 (build 1 + genesis 1 + roles 17) |
| Tool calls | 323 (bash 130, read 69, edit 54, glob 26, task 18, write 21, grep 5) |
| Bash denials | 43 (permission probe tax) |
| Write denials | 3 (VISION.md ×2, .tscn) |
| MCP tool calls | **0** |
| Bugs found → fixed → re-verified | 3 → 3 → pass (all found by static review) |
| P0 crash shipped through self-graded PASS | 1 (get_node("FinalScore") wrong path) |

## Key findings (drove beads mythic-quest-hg9/uzu/704/6ct/7bm/7oy/6iy)

1. **MCP tools configured but never invoked** — server healthy in
   opencode.json; orchestrator asserted "no engine run possible" (false)
   after early .tscn denial and propagated it to all dispatches.
2. **Scenario contract dead** — poppy authored zero tests/scenarios/*.json
   across all 5 sessions.
3. **Formula pour failed** — proto not persisted at init; orchestrator
   hand-rolled skeleton (~8 wasted calls).
4. **Verdict laundering** — rachel's "PASS 0 violations (static trace)"
   borrowed invariant-run vocabulary with no backing data; pootie accepted
   a code-blind caveat.
5. **VISION.md split-brain** — genesis denied → ian re-invented palette →
   2 avoidable vision-gate bugs.
6. **Environment rediscovery tax** — 43 bash denials re-learning grants
   per session; `--actor` flag discovered independently by every role.
7. **Parallel dispatch conflict** — gustavo‖phil both hooked Main.gd;
   caught only because gustavo parse-checked via headless godot CLI
   (the only real engine verification in the run, alongside stephen's).

## Positives preserved

- 2-bead cap + bead-ID integrity perfect across ~14 dispatches
- rachel's static review found the P0 with line-level evidence
- gustavo/stephen's headless parse-check culture (norm to generalize)
- escalation discipline on denials (genesis exemplary)
- poppy's unprompted README definition-of-done fills
