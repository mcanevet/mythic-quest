# Walkthrough6 Postmortem — Control Group Baseline

Run: 2026-09-15, `test/walkthrough6/`, "Lamplight of the Storm" (ad-hoc
prompt), lumo-max, old harness (loose perms, no one-pass discipline, no
context-economy, no TestPlayer harness, pre-8be4802 skills).

Outcome: **SUCCESS** — 7 nights game shipped; all 12 molecule beads + gates
closed; rachel found 4 real bugs, poppy fixed all 4 in-session, ian and
pootie passed. This is the baseline the 4rl/57s/s40 ports must beat.

## Headline numbers

| Metric | Value |
|---|---|
| Wall-clock (first useful session → close) | ~5h47m (17:43 → 23:30) |
| Sessions | 23 (build 5 — 3 of them throwaway) |
| Total input tokens (non-cache) | **13.73M** |
| Total output tokens | 134K (reasoning 54K inside) |
| Cache-read | 13.47M |
| Tool calls | 1,106 |
| Reasoning parts | 276 |
| Bugs found → fixed → re-verified | 4 → 4 → pass |
| Compaction events | **0** |

## Per-agent breakdown

| Agent | Sessions | Input tok | Tools | Notes |
|---|---|---|---|---|
| poppy | 11 | 4.95M | 476 | one session alone 2.0M (core build) |
| rachel | 1 | 2.46M | 144 | 88 run_script, 9 screenshots |
| pootie | 1 | 2.05M | 130 | 43 get_ui_elements, 49 simulate_input |
| stephen | 1 | 1.27M | 88 | 50KB of re-reads |
| build | 5 | 1.57M | 155 | ~210 min blocked in sync Task waits |
| phil | 2 | 0.94M | 78 | paired with gustavo, disjoint |
| ian | 1 | 0.38M | 44 | **the model to copy** — cheapest gatekeeper |
| gustavo | 1 | 0.12M | 21 | lean |

## Dominant cost driver

No compaction anywhere. Every turn re-sent the whole transcript: rachel =
142 turns × ~800KB context ≈ 2.5M input for 13K output. Persistent-context
items (screenshots ~60KB each, ~10KB of live commentary text parts, full
`get_ui_elements` trees ~2-10KB) got re-sent 100+ times each.

## Incident log (with costs)

1. **3 throwaway build sessions** (~35 min): `bd mol pour` flailing,
   three differently-titled molecules poured before the real one.
2. **Wrong-bead typo in fix dispatch** (~17 min): build hand-typed
   "zzn.2/3/4" instead of "urf.2/3/4" into poppy's prompt — poppy chased
   closed beads, detected + re-dispatched at 22:06.
3. **Parallel attach_script race** (~8 min debugging): 5 concurrent
   `godot_attach_script` calls in poppy's core session, last-write-wins
   lost 4 attachments; recovered via manual .tscn editing.
4. **Blind input flailing** (pootie ~4 min, rachel ~10 script cycles):
   both fought the pour-station/stairs proximity collision blind via
   `simulate_input`+`get_ui_elements` before switching to scripted calls.
5. **Wall-clock watching** (rachel 3 ship-watch cycles, pootie 4 dawn
   waits, 30-60s each): ian compressed time inside a single run_script
   instead — the cheap pattern, unused by the other two.
6. **bd friction, every agent**: `bd update --claim` denied by permission
   allowlist (rachel burned 4 calls at start); first non-force `bd close`
   rejected ~8× across agents → habitual `--force` retry.
7. **Grooming latency**: rachel filed bugs 21:46:46, build groomed at
   21:48:58 — ~2 min (fine); the perceived 14-min gap was rachel's own
   test phase during which build was correctly blocked on the sync Task.
8. **Redundant reads**: stephen re-read main.tscn/keeper.gd ~3×;
   rachel dumped the same `main.gd` source 4 consecutive times.

## Top improvement levers (ranked by measured impact)

1. **Compaction or turn caps for verifier sessions** — rachel+pootie+
   stephen = 5.8M input for 165 tool calls; ian achieved comparable
   verdict quality at 0.38M by deciding "I have enough evidence" at 40
   turns. Teach gatekeepers ian's evidence-sufficiency cutoff.
2. **Suppress subagent live commentary** (rachel 65, pootie 58 visible
   chatter parts ≈ 10-15KB permanent each) — think privately, report once.
3. **Serial-vs-parallel dispatch**: build serialized 3 poppy batches +
   stephen that were domain-disjoint (~30-40 min recoverable); the one
   deliberate parallel (phil+gustavo) was clean. Default: parallel when
   assignees differ, serialize on shared-file conflicts.
4. **Programmatic bead references in prompts** — "fix open children of
   urf", never hand-typed bead IDs (kills incident 2).
5. **Pull-mode or shorter dispatch batches** — build spent ~210 min
   blocked inside synchronous Task waits with zero polling; smaller
   dispatch granularity (2-bead cap from 57s aligns) shrinks the
   blocked-window serial chain.
6. **Deterministic positioning after 2 failed blind inputs** — codifies
   the lesson from incident 4.
7. **Time compression inside run_script** for cycle-based checks
   (nights/dawns) — ian's pattern.

## Baseline row (for benchmarks/README.md)

| Date | Prompt | Model | Result | Notes |
|---|---|---|---|---|
| 2026-09-15 | walkthrough6 (ad-hoc, "Lamplight of the Storm") | lumo-max | PASS (4 QA bugs found+fixed) | CONTROL: old harness. 5h47m, 13.73M input, 23 sessions, 1,106 tools, 0 compactions, 3 throwaway build sessions, 17-min typo re-dispatch, ~8 min race-condition recovery |
