---
name: worker-common
description: Shared protocol for every role worker in a game-build session — claim/close actor identity, engine health probe, escalation and pre-close discipline. Load before starting any assigned bead.
---

# Worker common protocol

Every role agent follows this protocol; role-specific workflows come after
these steps.

## Claim and close with your actor identity

Your harness actor identity defaults to the **human user**, not your
role. Every actor-identifying bd write must pass the flag:

- Claim: `bd --actor <role> update <id> --claim`
- Claim + reparent (when routed from raw-backlog): `bd --actor <role>
  update <id> --claim --parent <dev-loop-id>` (one call, atomic)
- Close: `bd close <id> --actor <role> --reason ...`

Without `--actor`, claims on beads assigned to your role are refused
("already assigned to \<role\>"; 23 refusals observed pre-adoption).

- Claim beads assigned to your role only: `bd ready --assignee <role>`;
  one claim per bd invocation — `&&` chains strand the second bead.
- **Heartbeat on long beads**: lease TTL is 5m, `bd reclaim` can fire at
  10m. On verification/gauntlet work, `bd heartbeat <id>` every few
  minutes of elapsed work.
- **Claim refused with "already claimed: assigned to build"**: the
  orchestrator routed without releasing its claim — expected, not a
  blocker. Proceed and close; the assignee may close regardless of the
  claim holder. No claim-recovery turns (wt12: ian burned 5). If the
  holder is NOT the orchestrator, report it — stale dead-worker claim
  for `bd reclaim`.

## Engine health probe (mandatory, first action)

Call the engine health-check tool (named in the engine plugin's skills)
before any engine work. Absent from your toolset or bridge down →
`⛔ BLOCKED: engine MCP tools unavailable`, STOP. Do NOT diagnose the
cause; do NOT silently downgrade to static-only work — runtime evidence
is required for every close (false-PASS laundering observed).

## Escalation contract (one-pass discipline)

- Deterministic errors (schema quirks, missing scaffolds, permission
  denials) → STOP: `⛔ BLOCKED: <cause> / Evidence / Action required`.
  Never retry.
- Transient infra → one bounded retry, then escalate.
- Blocking on a fix: wire `bd dep add <your-bead> <fix-bead>` — your
  bead auto-shows blocked and resumes when the fix closes.
- Each BLOCKED becomes a prevention fix: gotcha entry, scaffold
  addition, or upstream bead (`bd create ... --deps discovered-from:<id>`).

## Pre-close check

`bd children <id>` before any close/gate-resolve. Open children =
deterministic refusal: close them first or report
`⛔ BLOCKED: open children prevent close` with IDs. No retries, no --force.

## Pre-edit check

`grep -n <anchor> <file>` before `edit` — confirm exactly one hit. Both
edit refusals (not-found, multi-match) are stale-context symptoms
(wt13: 4); each re-feeds the whole stack. One grep pays for itself.

## GDScript type annotation discipline (wt14: 111 infer-errors)

Godot's GDScript cannot infer types from Variant-returning calls
(`dict.get()`, `node.call()`, `get_meta()`, `get_node()`). Always use
explicit type annotations for locals derived from such calls:

- ❌ `var x := dict.get("key", 0)` → "Cannot infer the type of x"
- ✅ `var x: int = dict.get("key", 0)`
- ✅ `var x: Node = get_node("path")` (or untyped `var x = ...` if you don't need type safety)

This is the single largest compile-error class in wt14 (111 occurrences
in run_script inputs, 4 runtime errors). The fix is a one-line habit
change; apply it to every probe script you author.

## run_script pre-flight checklist (wt14: 16 avoidable model turns)

Before submitting ANY `godot_run_script` probe, check three things
(each failure = one wasted model turn + full context re-send):

1. **Balanced brackets**: count `[`/`]` and `{`/`}` pairs, especially
   in nested dictionary literals. wt14: 9 bracket-mismatch retries.
2. **RefCounted context**: your script extends `RefCounted` and
   receives `scene_tree: SceneTree` as an ARGUMENT. Never call
   `get_tree()` or reference bare `root` — use `scene_tree.root` /
   `scene_tree.current_scene`. wt14: 4+3 such retries.
3. **Declared identifiers**: every identifier you reference must be a
   parameter, local, or class member — no undefined `root`, `game`,
   `score` shortcuts from memory.

## Self-verify before close (fixers especially)

An unvalidated fix bounces back as a re-verify session — cold start +
re-derived context, ~10m each (wt13: ~60m across 6 round-trips). Before
closing a fix/repair bead: run **delta-verify** (playtest SKILL.md,
"Delta-verify") — 15-30s scenario covering only the invariants the fix
touches. Full gauntlets belong to the qa-gate owner. If you cannot
delta-verify, say so in the close reason — never claim it silently.

## Self-created strays (one move, no deliberation)

A file YOU mistakenly created (wrong path, aborted scaffold): file an
unassigned cleanup bead naming the path and continue. No deletion, no
rule interpretation — zero deliberation turns (10+ once burned deciding).

## bd surface and output shaping — see [reference.md](reference.md)

Exact flags (`--set-labels`/`--add-label`/heredoc comments/`-d`),
jq projection recipes, and the granted pipeline-segment list live in
[reference.md](reference.md). Core rules:

- Project bd JSON through jq before it lands; never dump raw
  `bd list --json` (10-60kB) into context.
- Segment matcher: pipes/chains are checked per segment; `python3 -c`
  downstream segments are denied — use jq.
- Read reference.md once when you first need flag details, not per bead.

## Reporting

- Verdicts cite observed runtime behavior, never intentions.
- If a step cannot produce runtime evidence, say so explicitly; never
  substitute static analysis silently.

## Context economy (measured waste, from session traces)

- **Read a file once, fully.** Re-deriving a symbol you already read:
  grep it, don't re-pay the payload. Re-read only after the file
  demonstrably changed under you.
- **Range-read, don't full-read**: offset/limit around the target
  symbol; full read only for files you will substantially edit.
- **Search before reading**: one grep beats reading whole files to find
  a symbol.
- **Trust the dispatch file-map**: orientation comes from the dispatch
  prompt; read only files you will EDIT or need exact contents of. The
  map includes each file's public surface (signals, exports, method
  signatures) — that IS the API documentation; do not read a file merely
  to discover what the map already states (wt14: ball.gd read by 5
  agents, mostly for signal discovery the map could have carried).
- **Batch-debug**: one run script asserting ALL outstanding behaviors
  per fix round — never edit→run→edit→run on single assertions
  (input tokens grow quadratically with turns; 30 turns ≈ 400-550k).
- **Scenario cheat sheet**: bots, built-in invariants, custom invariant
  type rules — [reference.md](reference.md), read once when authoring.

## Runtime-lock discipline (parallel dispatch enabler)

- **Mutation workers** (create/apply-level skills): NEVER run the
  project or hold the runtime. Mutate files, batch-validate, report.
- **Verification workers** (playtest): the only roles that hold the
  runtime. Before your first probe/input/state-read on a live engine,
  read the playtest skill's `reference/live-engine-driving.md` — its
  facts were each re-derived at 10-60m cost by specialists lacking it.
- This split enables parallel mutation dispatch on disjoint file
  scopes; verification runs after mutations complete.
