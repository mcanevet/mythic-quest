# Walkthrough 9 — RallyWall (lumo-max) — SHIPPED

**Date:** 2026-09-18 · **Prompt:** `benchmarks/prompts/rallywall.md` (identical to w7/w8)
**Sandbox:** `test/walkthrough9` @ commit `4996480` + live patches
**Harness delta vs w7:** MCP pin `ea75a0d` (dist-committed server — the wt8 root
cause), health-probe step 0 + runtime-evidence verdict contracts, scenario
deliverables, genesis→ian, proto persistence, frontmatter unification.
Comparison baseline is **w7** (w8 was broken — zero MCP calls; see
[2026-09-17-walkthrough8-rallywall-lumomax.md](2026-09-17-walkthrough8-rallywall-lumomax.md)).

## Outcome

**PASS — shipped.** All three gates closed with runtime evidence:
qa-gate (rachel, 0 violations, 17 dev children live-verified), vision-gate
(ian, 1 typography child filed+fixed), consumer-gate (pootie, won at 15,
lose/replay cycle tested). Board empty; release bead closed.

Headline: **first run where the game is genuinely played at runtime** —
360 godot MCP tool calls (w8: 0), pkill-free, live debugging of a real
compile error (autoload-in-headless-editor, see below).

## Metrics

| Metric | walkthrough7 | walkthrough9 | Delta |
|---|---|---|---|
| Wall-clock | 2h27m | **2h12m** | −10% |
| Input tokens (non-cache) | 7.08M | **4.75M** | −33% |
| Cache-read tokens | — | 12.58M (73% hit) | — |
| Output tokens | 75K | 73K | −3% |
| Sessions | 18 | 18 | — |
| Tool calls | 747 | 826 | +11% |
| godot MCP calls | ~30 (smoke only) | **360** | ×12 |
| Compaction | 0 | 0 | — |
| Claims ok/failed | (actor bug latent) | 18 / 23 | fixed post-run (`--actor`) |
| Skill-not-found errors | — | 1 (gustavo, `apply-audio`) | fixed post-run (skills.paths) |
| Gate-resolve misfires | — | 5× (await_id vs bead ID) | fixed post-run |
| QA bugs found | 0 (rachel clean) | 0 (rachel clean) | pootie 1 (typo, false pos.) |

The +11% tool calls against −33% input tokens is the shape we wanted:
more *acting* (runtime probes, screenshots, input simulation) for less
context burn. Caveat: token deltas also reflect agent-profile rewording
(deduplicated contracts), so harness-code and behavior changes are
conflated.

## Session-by-session

| # | Role | Dur | godot | Notes |
|---|---|---|---|---|
| 1 | build | 132m | 2 | orchestrator span |
| 2 | ian genesis | 10m | 2 | VISION.md + 15 raw beads, validated |
| 3 | poppy arena | 5m | — | MCP scene build (create_scene/set_node_properties) |
| 4 | poppy ball | 17m | ~20 | script-drop debugging: autoload not compiled in headless editor — found root cause via runtime probing |
| 5 | poppy lose/win | 9m | | live-run drove lose condition; found score-not-reset-on-reload |
| 6 | poppy deflect | 5m | | |
| 7 | poppy serve | 5m | | closed with 20 sampled launch angles as evidence |
| 8 | phil art | 6m | | concurrent with gustavo (first parallel pair) |
| 9 | gustavo audio | 5m | | `skill apply-audio` not found → improvised from file |
| 10 | stephen flash | 5m | | |
| 11 | stephen polish | 8m | 36 | runtime confetti + tween sampling |
| 12 | poppy ? | 1m | | micro-session |
| 13 | rachel smoke | 6m | 22 | `bd close` denied → `--status closed` escape |
| 14 | rachel qa | 16m | 24 | measured ×1.05 speed growth; spotted score-17-past-15 overrun, cleared it |
| 15 | ian vision | 5m | 19 | filed typography child |
| 16 | phil font | 8m | | Godot 4.7 enum compat |
| 17 | pootie consumer | 5m | 17 | won at 15, replay cycle |
| 18 | poppy typo-fix | 4m | 13 | verified typo didn't exist (grep + label assertions + screenshots) |

## New positive behaviors (vs w7)

1. **Runtime debugging with hypotheses**: poppy hit script-persistence
   failures, formed and tested a causal theory (autoload identifiers fail
   to compile in headless scene-editing processes), fixed with dynamic
   lookup — then the same knowledge was reused in later sessions.
2. **Measured evidence in close reasons**: serve delay verified at
   "exactly 60 physics frames"; speed growth "exact ×1.05"; 20-sample
   launch-angle distributions. QA verdicts cite observations, not vibes.
3. **Self-healing against tool failures**: chained `&&` bd claims broke
   on first-leg errors — agents noticed, switched to single calls.
4. **False-positive resilience**: pootie's "PLAY AGIN" typo critique was
   re-verified by poppy (grep + runtime assertions + screenshots) before
   closing no-change — the consumer loop didn't blindly trust the critic.

## Residual friction (all diagnosed live, fixed post-run)

| Friction | Count | Fix (commit) |
|---|---|---|
| `--claim` refusals (actor mismatch) | 23 | `bd --actor <role> update --claim` in 7 profiles (`96caee6`) |
| `skill apply-audio` not found | 1 | `skills.paths` registration in sandbox-init (`2623e17`) |
| `bd gate resolve <await_id>` misfires | 5 | teach gate bead ID from `bd gate list` (`9b32e2e`) |
| `bd close` verb denied (rachel) | 1 | grant added (`9b32e2e`) |
| Serialized dispatch (idle specialists) | whole run | filed `mythic-quest-mdy` (needs runtime-lock design first) |

Trace-monitoring methodology born here: read tool **outputs**, not inputs
(trace-watch skill; the claim-refusal pattern was invisible until outputs
were audited).

## Open optimization beads

- `mythic-quest-mdy` — parallel dispatch on disjoint file scopes (biggest win, ~25% wall-clock; blocked on runtime-lock serialization)
- `mythic-quest-qh6` — redundant re-reads of main.tscn at shifted offsets (10–20% context burn)
- `mythic-quest-0cn` — Godot theme-property cheat sheet for create-ui
