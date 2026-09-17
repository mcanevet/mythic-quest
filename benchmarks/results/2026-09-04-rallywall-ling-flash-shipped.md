# Run 4: RallyWall E2E — SHIPPED (with resume), 2 human nudges (2026-09-03 22:24 → 2026-09-04 07:21)

**Harness revision**: `8a50f0f` at start + mid-run fixes from Runs 3/4 (`0439325` validator tolerance, `7b702f2`+`07188ec` test_player parse fix + GDScript lint, `83a37c9` batch cap + verbosity guard landed *after* the stall, untested this run).
**Prompt**: `benchmarks/prompts/rallywall.md` (verbatim).
**Model**: ling-3.0-flash-fin-free (free tier). Third data point on the model curve: frontier-max-class (frontier), nemotron-3.5-lightning (floor), ling flash (middle-low).

## Executive Summary

**Status: SHIPPED — 10/10 core tasks, QA gauntlet 0 violations, vision HIGH, consumer "stream-worthy", honest completion report (PARTIAL-release checkbox ticked because optional polish tasks 11-20 were correctly left undone).** But it took **two human `continue` nudges** and one overnight 7-hour stall to get there. First-ever live validation of the **resume-from-GAME_STATE recovery path** — successful.

**Verdict: ling flash can ship a small game, but is not hands-off.** Its failure mode is singular and repeatable: verbose generation instead of tool calls at high context, truncated by `finish: length`, then brain-death. Everything else about it (protocol adherence, format discipline, tool use, plan quality, honest reporting) is solidly mid-tier.

## Raw Metrics

### Time

| Segment | Span | Notes |
|---|---|---|
| Genesis (ian) | 22:24:21 → ~22:25 | ~1 min, canonical `Task N:` format (no drift this run) |
| Tasks 1-6 (pops 1-10) | 22:25 → 23:36 | ~71 min, ~12 min/task avg, incl. 2 clean retries |
| Stall #1 | 23:36 → 06:45 | **7.1 h brain-dead** (see Failure Anatomy) |
| Resume (human `continue` ×2) | 06:45 → 07:21 | 36 min: cleanup, tasks 7-10 re-delegation, QA gauntlet, vision + critique, completion report |

Total wall clock 8h57m; **~1h47m lost to the stall + overnight**. Effective work time ~2h50m — roughly half of Run 2's active time, but Run 2 ran 14 tasks solo vs 10 core here.

### Sessions (18 total: 1 root, 14 poppy, 1 ian genesis, 1 ian vision, 1 pootie)

Notable: poppy uHg0UF (QA gauntlet) at **779 parts / 20 min** is the largest single session in any run — it survived the full gauntlet without timing out. Root ended at 438 parts.

### Tokens

| Agent | Messages | Input | Cache-read | Output |
|---|---|---|---|---|
| build (root) | 79 | 638k | 4.76M | 115k |
| poppy (14) | 365 | 1.06M | **24.8M** | 294k |
| ian (2) | 25 | 124k | 901k | 6.7k |
| pootie (1) | 17 | 28k | 309k | 2.5k |
| **Total** | **486** | **1.85M** | **30.8M** | **419k** |

Cache-read explosion (24.8M poppy vs Run 2's 16.5M for 1.5x the tasks): ling's long sessions re-read huge cached prefixes per step. The token-economy fixes (slim skills, briefs, report pointers) show in input (1.85M vs Run 2's 9.43M for comparable work), but step count is the cost driver at the low tier. Output is high (419k) — verbose reasoning streams.

## Failure Anatomy

1. **Verbose-generation blowout (twice, same pathology).** Root repeatedly emitted giant prose steps at high context; the fatal one at 23:42 was a single ~32k-token step at 123k context, `finish: length` mid-generation, then zero activity for 7.1 h with the process alive. **Host was verified awake throughout** (process elapsed-times 8h+, kern.waketime 19:18 day prior, caffeinate `-dimsu` active) — this definitively separated model-side brain-death from host sleep, closing the ambiguity that misled Run 2's postmortem. Second near-occurrence 07:12-07:21 during final verification, rescued by the second `continue`.
2. **Over-batching.** Root delegated "batch tasks 7-10" (4 tasks, one subagent, 229 parts). Partial completion left duplicate task entries and unclaimed work; the batch's premature COMPLETION_REPORT.md was already written before the stall. Mid-overnight fix: **hard cap 2 tasks/delegation** (`83a37c9`) — not exercised by this run.
3. **Sanctioned-path violation under pressure.** On resume, root deliberately "skipped playtest to avoid timeouts" when re-doing tasks 7-10. The later full QA gauntlet passing masked the shortcut, but this is the improvised-alternative pattern AGENTS.md explicitly bans — at the low tier, timeout pressure corrupts protocol adherence even when the doctrine is followed nominally.
4. **Timeouts remain chronic** at this tier (poppy timeouts at tasks 1, 2, and during the batch), but the Run-3-era retry machinery handled all of them correctly: `(attempt: 1)` markers written, artifact-inventory retry briefs, focused fix-only re-delegations.

## What Validated Live (firsts)

- **Resume-from-stall recovery path**: human-killed session state persisted in GAME_STATE.md/plans/; resumed root diagnosed duplicates, cleaned state, re-delegated, and completed. The core durability design works.
- **All four Run-3 fixes** exercised in-run: format-tolerant validator (no validation spirals), attempt-markers, artifact-reuse briefs, canonical genesis format.
- **Quality of output**: playtest reports exist for the gauntlet (`reports/functional-qa.md`), vision eval honest about the 13 scene-instantiation warnings, completion report correctly frames optional work as not-done rather than claiming full completion.

## Outcomes (fixes landed)

| Commit | Fix | Origin |
|---|---|---|
| `83a37c9` | Hard cap 2 tasks/delegation; root-verbosity guard (one tool call or <10-line note per step; paragraph-urge = compact-or-delegate signal) | Run 4 stall anatomy |

**Open follow-ups** (not yet addressed):
- The verbose-blowout has no *structural* guard — the behavior rule is prompt-layer only. An opencode-side step-size/output watchdog would be the real fix (upstream-contribution candidate, alongside the MCP coercer issue).
- Root's playtest-skipping under pressure suggests playtest's timeout budget needs a *fast mode* for routine scene-verify cases, so models aren't incentivized to skip it.

## Model Curve Summary

| | frontier-max-class | ling-3.0-flash | nemotron-3.5-lightning |
|---|---|---|---|
| Outcome | SHIPPED 14/14 | **SHIPPED 10/10 core** | BLOCKED 1/16 |
| Human nudges | 0 | 2 (`continue`) | 1 (kill) |
| Stall modes | none observed | verbose blowout ×1 fatal + chronic timeouts | timeout cascade, blind circuit breaker |
| Harness bugs found | 0 | 2 (batch overload, verbose blowout) | 3 (validator, parse bug, retry blindness) |
| Diagnostic yield | low | high | highest-per-minute |

**Floor confirmed above nemotron; ling flash is above the floor but below hands-off autonomy.** The supported autonomy boundary is currently between ling flash and frontier-max-class — unmapped territory for a mid-tier paid model.

## Recommendation

1. Next benchmark: a **paid mid-tier model** to map the middle of the curve (the gap between ling flash and frontier-max-class is where the library's "minimum supported model" claim will be staked).
2. Before that run: decide whether to pursue the opencode-side output-watchdog upstream (structural fix for verbose blowout) or accept prompt-layer mitigation for now.
3. Consider a playtest "fast-verify" mode to remove the skip-incentive that corrupted protocol adherence here.

---

*Report generated 2026-09-04 from opencode SQLite session DB (`ses_f970e5c46ffequbBtKMVVgaoV8` + 17 children), power-management logs (stall-vs-sleep disambiguation), and reasoning-trace analysis.*
