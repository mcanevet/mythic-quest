---
name: worker-common
description: Shared protocol for every role worker in a game-build session — claim/close actor identity, engine health probe, escalation and pre-close discipline. Load before starting any assigned bead.
---

# Worker common protocol

Every role agent follows this protocol. Role-specific workflows come after
these steps.

## Claim and close with your actor identity

Your harness actor identity defaults to the **human user**, not your role
name. Every bd write that identifies an actor must pass the flag:

- Claim: `bd --actor <role> update <id> --claim`
- Close: `bd close <id> --actor <role> --reason ...`

Without `--actor`, claims on beads assigned to your role are refused with
"already assigned to \<role\>", and beads never enter in_progress
(observed: 23 claim refusals across roles
before the flag was adopted).

- Claim beads assigned to your role only: `bd ready --assignee <role>`
- Claim one bead per bd invocation — chained `&&` commands stop at the
  first error and leave the second bead unclaimed.
- **Heartbeat on long beads**: a claim's lease expires after 5 minutes
  (default TTL); `bd reclaim` can revert it after 10. If your bead runs
  long (any verification/gauntlet work), refresh between work steps —
  `bd heartbeat <id>` — roughly every few minutes of elapsed work. Cheap
  insurance against a mid-flight reclaim causing double-dispatch; no-op
  on short beads.
- **If your claim is refused with "already claimed: assigned to \"build\"/
  another dispatcher**": the orchestrator routed the bead to you without
  releasing a claim — this is expected, not a blocker. Proceed with the
  work and close with `bd close <id> --actor <role> --reason ...`;
  the assignee (you) is allowed to close regardless of who holds the
  claim. Do NOT spend turns on claim recovery, do NOT report BLOCKED
  (observed wt12: ian burned 5 turns on this exact refusal). If the
  holder is NOT the orchestrator, report it — that's a dead-worker
  stale claim for the orchestrator's `bd reclaim`.

## Engine health probe (mandatory, first action)

Call the engine's health-check tool (its name is in the engine plugin's
skills) before touching any engine work. If it is absent from your toolset
or reports the bridge down:

Report `⛔ BLOCKED: engine MCP tools unavailable` and STOP.

Do NOT diagnose the cause (server death vs toolset race — diagnosis
belongs to the human). Do NOT silently downgrade to static/code-only
work: runtime evidence is required for every close (observed: false-PASS laundering).

## Escalation contract (one-pass discipline)

- Deterministic errors (schema quirks, missing scaffolds, permission
  denials) → STOP immediately, report
  `⛔ BLOCKED: <cause> / Evidence / Action required`. Never retry.
- Transient infra (transport timeout, bridge glitch) → one bounded retry;
  still failing → escalate via `⛔ BLOCKED`.
- Blocking on a fix: create the prevention-fix bead (or find it), wire
  `bd dep add <your-bead> <fix-bead>` — your bead auto-shows ● blocked and
  resumes when the fix closes. Mention the link in your report.
- Each BLOCKED becomes a prevention fix: gotcha entry, scaffold addition,
  or upstream doc/fix bead (`bd create ... --deps discovered-from:<id>`).

## Pre-close check (avoid close-refusal round-trips)

Before `bd close` (or `bd gate resolve`), confirm no open children or
blocking gates — `bd children <id>` first. If anything is open, that
refusal is deterministic, not transient: do NOT retry or use --force.
Either close the children first or report
`⛔ BLOCKED: open children prevent close` with the child IDs.

## Pre-edit check (one grep beats two refused edits)

Before `edit`, `grep -n <anchor> <file>` the unique line you're about to
match — confirm exactly one hit. The two edit refusals (oldString not
found; multiple matches) are stale-context symptoms: your snapshot of
the file predates a sibling's mutation. Grep, adjust the anchor with
surrounding lines, edit once. Each refusal re-feeds the whole context
stack, so a 1-second grep pays for itself the first time it fires
(wt13: 4 refused edits across poppy/stephen sessions).

## Self-verify before close (fixers especially)

A bead whose fix isn't validated before close WILL bounce back as a
re-verify session — cold-start plus re-derived context, ~10m wall each
(wt13: 6 such round-trips, ~60m total). Before closing a fix/repair
bead: run **delta-verify** (playtest SKILL.md, "Delta-verify") — a
minimal 15-30s scenario covering only the invariants your fix touches.
Full gauntlet runs belong to the qa-gate owner, not to you. If you
cannot delta-verify (no engine access, blocked dependency), say so in
the close reason — don't claim it silently.

## Self-created strays (one move, no deliberation)

A file YOU mistakenly created (wrong path, aborted scaffold, duplicated
intermediate) is handled by exactly one move: **file an unassigned
cleanup bead** naming the stray path and continue with the real task.
Do not attempt deletion yourself, do not weigh rule interpretations —
one decision, zero deliberation turns (a worker once burned 10+
reasoning turns deciding whether deleting its own stray violated the
sanctioned-paths rule before landing on this exact move).

## bd flag surface (stop guessing flags)

Exact supported forms used in this workflow — anything else is an
unknown flag and a wasted turn:

- Labels: `bd update <id> --set-labels a,b` (replace),
  `bd update <id> --add-label <label>` (singular add)
- Comment: `bd comment <id> <<'EOF' ... EOF` (heredoc; there is no
  `--comment` flag anywhere)
- Description update: `bd update <id> -d "<text>"` (not `--note`,
  not `--message`)
- Claim: `bd --actor <role> update <id> --claim`

## Shaping bd JSON output (use jq, not python)

`bd` emits machine-readable JSON with `--json`. Filter and format it with
**jq**, never inline python one-liners:

```bash
bd list --json | jq -r '.[] | [.id, .status, .title] | @tsv'
bd show <id> --json | jq '.priority'
bd list --json | jq '[.[] | select(.status=="open")] | length'
```

**Always project, never dump.** Raw `bd list --json` / `bd show --json`
output is large (full descriptions, timestamps, deps — 66kB accumulated
across one run's sessions) and every byte persists in context for the
rest of the session. A jq projection is one keystroke-cheaper per call:
default to `jq -r '.[] | [.id,.status,.title] | @tsv'` shapes for lists,
and for `show` extract only the fields you need (`.description`,
`.status`, `.[].title` for arrays). `bd ready --json` counts too —
project it unless you need full descriptions.

Piped bash commands are permission-checked **per pipeline segment**
(opencode splits the command into segments and matches each against
the allow rules independently). Read-only text segments granted to
every worker role: `jq`, `head`, `grep`, `cat`, `ls`, `awk`,
`sed -n`; `python3 -c` is not — a `bd … | python3 -c …` pipe is denied
as a whole and wastes the turn. (rachel additionally holds `for *` for
read-only scenario sweeps — loop bodies still need their own grants.)

## Reporting

- Verdicts cite observed runtime behavior, never intentions.
- If a step cannot produce runtime evidence, say so explicitly rather
  than substituting static analysis.

## Context economy (measured waste, from session traces)

- **Read a file once, fully.** Shifted-offset re-reads of the same file
  burned 5× reads on one scene in a single session. If you need a symbol
  you already read, grep it — a targeted `grep -n <symbol>` is one cheap
  call; a re-read re-pays the whole payload. Re-read only if the file
  demonstrably changed under you (post-mutation read-backs), not to
  "refresh memory".

## Output economy (30kB reads are a turn-cost multiplier)

Tool outputs persist in context forever. The largest reads observed
(30kB) were whole-file dumps where the agent needed one section:

- **Range-read, don't full-read**: use the read tool's offset/limit to
  fetch the 50 lines around your target symbol, not the file. Full read
  only for files you will substantially edit.
- **Pipe bd JSON through jq before it lands** (see the jq rule above) —
  unshaped `bd list --json` is 10-60kB.
- **Scene trees**: prefer a scoped `get_scene_tree` (subtree/path filter)
  over the full-tree dump when you only need one branch.
- **Batch mutations.** Prefer one engine batch scene-operations call over many
  single-property edits (14 separate edits observed on one bead).
- **Validate once, at the end of a logical unit** — not after every edit
  (7 validate cycles on 14 edits observed). Validation covers the
  accumulated change set.
- **Search before reading**: one grep to locate beats reading whole files
  to find a symbol (20 reads + 11 greps observed for one bead).
- **Trust the dispatch file-map**: your dispatch prompt carries a
  file-map snapshot (paths, purposes, key node paths). Use it for
  orientation; only read a file when you will EDIT it or need its exact
  contents — not to learn what exists.
- **Scenario-testing cheat sheet**: bots (chaos/pursuit/replay/nav_agent),
  built-in invariants (`no_fatal_errors`, `nodes_finite`, `nodes_in_bounds`,
  `no_null_refs`, `frame_time_p99_below`, `fps_floor`), custom invariants
  (`path + check + value`), rate-of-change guards — condensed details and
  the type rules in [reference.md](reference.md) (read it once when
  authoring scenarios; do not re-read per bead).
- **Batch-debug: one run per fix round** (same-session tool-call telemetry
  measured: 18 script-run calls in a single session, each failure re-feeding a tall
  context stack). Write one test script that asserts ALL outstanding
  behaviors, run it once, fix every failure it reports, then re-run the
  same script. Never loop edit→run→edit→run on individual assertions —
  each iteration re-sends the full conversation, so input tokens grow
  quadratically with turn count, and 30 turns cost 400-550k input tokens
  while the final context is only ~25-35k.

## Runtime-lock discipline (parallel dispatch enabler)

- **Mutation workers** (create-level, create-entity, create-ui, apply-*):
  DO NOT run the project or hold the runtime. Mutate files, batch-validate,
  report PASS/FAIL. Runtime verification is deferred to a dedicated
  verification batch.
- **Verification workers** (playtest): run the project, execute test
  scenarios, report results. Only verification workers hold the runtime.
  Before your first probe/input/state-read on the running engine, read the
  engine plugin's live-engine-driving reference (playtest skill,
  `reference/live-engine-driving.md`) — it fixes the channel for each
  need (scenario vs probe vs simulate_input vs screenshot) and its facts
  were each re-derived at 10-60 min cost by specialists who lacked it.
- This separation enables parallel mutation dispatch on disjoint file
  scopes; verification runs after mutations complete.
