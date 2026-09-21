# Worker-common extended reference

Loaded on demand. The core SKILL.md carries the always-needed protocol;
this file holds the bd CLI surface, jq recipes, the scenario-testing
cheat sheet, and expanded rationale. Read once when you first need any
section — not per bead.

## bd flag surface (stop guessing flags)

Exact supported forms — anything else is an unknown flag and a wasted
turn:

- Labels: `bd update <id> --set-labels a,b` (replace),
  `bd update <id> --add-label <label>` (singular add)
- Comment: `bd comment <id> <<'EOF' ... EOF` (heredoc; there is no
  `--comment` flag anywhere)
- Description update: `bd update <id> -d "<text>"` (not `--note`,
  not `--message`)
- Claim: `bd --actor <role> update <id> --claim`

## Shaping bd JSON output (jq, not python)

```bash
bd list --json | jq -r '.[] | [.id, .status, .title] | @tsv'
bd show <id> --json | jq '.priority'
bd list --json | jq '[.[] | select(.status=="open")] | length'
```

**Always project, never dump.** Raw `bd list --json` / `bd show --json`
is 10-60kB (full descriptions, timestamps, deps — 66kB accumulated in
one run); every byte persists in context for the rest of the session.
Default to `jq -r '.[] | [.id,.status,.title] | @tsv'` for lists; for
`show`, extract only the fields you need.

**Pipeline segment matcher**: opencode splits piped/chained bash into
segments matched separately against your permission grants. Read-only
segments granted to every worker: `jq`, `head`, `grep`, `cat`, `ls`,
`awk`, `sed -n`. `python3 -c` is NOT — a `bd … | python3 -c …` pipe
denies whole and wastes the turn. (rachel additionally holds `for *`
for read-only sweeps; loop bodies still need their own grants.)

## Scenario authoring cheat sheet (TestPlayer)

Condensed harness facts below; the FULL symbol map and report shape are
in the playtest skill's `reference/harness-card.md` (read that instead
of the 720-line test-harness player script). The full testing-patterns reference
lives in the engine plugin (`skills/init-project/reference/testing-patterns.md`).

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
