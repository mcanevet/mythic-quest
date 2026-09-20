# Worker-common extended reference

Loaded on demand. The core SKILL.md carries the always-needed protocol;
this file holds the scenario-testing cheat sheet and expanded rationale.
A worker authoring or debugging test scenarios should read this once
per session; verifiers can rely on the playtest skill.

## Scenario authoring cheat sheet (TestPlayer)

Observed waste motivating this cache: 2 full 22k-char reads of the same
testing-patterns reference in one worker session. This sheet is the
condensed form; the full reference lives in the engine plugin
(`skills/init-project/reference/testing-patterns.md` — locate it under
the mounted engine plugin).

### Bot types
- chaos (random inputs), pursuit (follows target), replay (replays
  recorded path), nav_agent (pathfinding)

### Built-in invariants
- `no_fatal_errors`, `nodes_finite`, `nodes_in_bounds(min_x/max_x/min_y/max_y)`,
  `no_null_refs`, `frame_time_p99_below(33.3ms)`, `fps_floor(30)`

### Custom invariants
- `path + check + value` where path is `_meta.<field>` (harness metric)
  or `/root/<node>:<key>` (game state)
- **Type rule**: `below`/`above` need NUMERIC values — booleans and
  strings must use `equals`. A mismatched scenario is REJECTED at
  `start_test` (status "rejected" with a directed error); a rejection is
  a scenario-config defect: fix the JSON, do not report a game bug.
- **Rate-of-change guard**: add `max_delta_per_sec` to every counter
  (score, currency, ammo) sized to a plausible human ceiling — catches
  re-firing handler bugs that point-in-time checks miss

## Extended rationale for the context-economy rules

The skill's batch-debug rule ("one run per fix round") exists because
input tokens grow quadratically with turn count: each iteration re-sends
the full conversation, so 30 turns cost 400-550k input tokens while the
final context is only ~25-35k (measured: 18 script-run calls in one
session, each failure re-feeding a tall context stack). The same math
motivates single-full-reads, batch mutations, and validate-at-unit-end.

## Extended rationale for the runtime-lock discipline

Mutation workers forgo runtime verification so that mutation waves can
run CONCURRENTLY on disjoint file scopes (the runtime serializes —
observed: disjoint-file batches serialized because each both mutated
scenes AND ran the project for verification). Verification workers
should read the live-engine-driving reference before their first probe
on a running engine; its facts were each re-derived at 10-60 min cost
by specialists who lacked it.
