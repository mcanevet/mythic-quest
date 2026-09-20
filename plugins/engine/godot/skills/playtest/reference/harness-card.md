# TestPlayer harness interface card

Symbol map for `scripts/test_player.gd` (the project-root copy, ~720
lines). Read THIS card instead of the file when you need a call pattern
or a symbol location; grep the file only when editing harness internals.
(A QA session cumulatively re-read the full file for ~229kB across 4
sessions — this card exists to collapse that.)

## Public API (everything you call from run_script)

| Symbol | Line† | Purpose |
|---|---|---|
| `start_test(scenario)` | 42 | Begin a run. Validates scenario (rejects bool/string values under below/above — a rejection is a scenario defect, fix the JSON). Reports `unbound_action` violations for defined-but-unbound InputMap actions on FIRST call. Returns `{"status": "started"}`. |
| `await_test_done(max_wait_s=120)` | 177 | Await the configured `duration_s`; returns the report. Always `await` inside ONE run_script call. |
| `get_test_report()` | 198 | Poll report mid-run (`status: running/complete`, `violations`, `metrics`). |
| `finish_test()` | 159 | Early stop. |

`start_test` takes positional args only inside an awaited expression
(`await f(x = 1)` is a parse error — pass positionally).

## Report shape (from await_test_done / get_test_report)

```
{ "status": "running"|"complete"|"rejected",
  "violations": [ {rule, node, detail, first_frame, last_frame, count} ],
  "metrics": { start_frame, end_frame, input_count, crash_detected,
              frame_times, frame_ms_p99, worst_frame_ms,
              fps_floor_violations, stall_ticks_over_100ms, warmup_resets } }
```

Violations are aggregated per `rule|node` in `_violation_counts`;
`_violations` (legacy array) is NOT the count source — read
`_violation_counts` or the report.

## Custom invariant resolution (`_resolve_test_value`, ~673)

- `path: "_meta.<field>"` → harness metric (`frame_ms_p99`, etc.)
- `path: "/root/<node path>:<prop>"` → walks from SceneTree root THROUGH
  your scene-root node's own name (root node named `root` ⇒
  `/root/root/Game:score`); if the node implements `get_test_state()`,
  the prop resolves from its dict first. Prefer `get_test_state()` keys
  when available — they sidestep path-base mistakes.
- Missing node ⇒ one warn per path naming the closest existing node's
  children (diagnostic; the invariant itself no-ops — nulls are
  violations of a different kind: check `Test path ... not found` in
  debug output).

## Scenario schema (start_test input)

```
{ "bot": {"type": "chaos"|"pursuit"|"replay"|"nav_agent", "seed": 42,
          "input_rate_hz": 10, ...},
  "duration_s": 15,
  "invariants": [ {"name", "rule", ...params} ] }
```

Rule types: `no_fatal_errors`, `nodes_finite`, `nodes_in_bounds`
(x/y[/z] min/max), `no_null_refs`, `frame_time_p99_below(ms)`,
`fps_floor(n)`, `custom` (path/check/value[, max_delta_per_sec]).
`nodes_in_bounds` targets enforce EXISTENCE — a missing node path or
empty group is a violation, not a green no-op. Custom invariants also
take `after_s`/`before_s` (time window, seconds from scenario start)
and scenarios take `setup.calls` ([{path, method, args}] invoked before
the bot starts — JSON-side game-state reset).

Type rule: `below`/`above` need numerics; bools/strings need `equals`
(rejected at load otherwise). Counters need `max_delta_per_sec`.

## Internals index (grep targets, editing only)

`_physics_process` 185 (tick driver; warmup 3 ticks before timing),
`_check_invariants` 459 (dispatch), `_report_violation` 441,
bots: chaos 250 / pursuit 274 / replay 321 / nav_agent 337+384,
`_compute_p99` 433, `_track_custom_delta` 639 (rate windows).

† Line numbers drift with edits — the symbol names are the stable
anchor; use grep, not line offsets, when navigating.
