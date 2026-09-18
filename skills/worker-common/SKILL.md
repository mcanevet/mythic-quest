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
(observed: walkthrough9 — benchmarks/results/2026-09-18-walkthrough9-rallywall-lumomax.md — 23 claim refusals across roles
before the flag was adopted).

- Claim beads assigned to your role only: `bd ready --assignee <role>`
- Claim one bead per bd invocation — chained `&&` commands stop at the
  first error and leave the second bead unclaimed.

## Engine health probe (mandatory, first action)

Call the engine's health-check tool (its name is in the engine plugin's
skills) before touching any engine work. If it is absent from your toolset
or reports the bridge down:

Report `⛔ BLOCKED: engine MCP tools unavailable` and STOP.

Do NOT diagnose the cause (server death vs toolset race — diagnosis
belongs to the human). Do NOT silently downgrade to static/code-only
work: runtime evidence is required for every close (observed: walkthrough8
false-PASS laundering — benchmarks/results/2026-09-17-walkthrough8-rallywall-lumomax.md).

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

## Reporting

- Verdicts cite observed runtime behavior, never intentions.
- If a step cannot produce runtime evidence, say so explicitly rather
  than substituting static analysis.

## Context economy (measured waste, benchmarks/results/2026-09-18-walkthrough9-rallywall-lumomax.md and wt10 opencode session traces)

- **Read a file once, fully.** Shifted-offset re-reads of the same file
  burned 5× reads on one scene in a single session. If the file changed
  under you (rare), re-read then — not speculatively.
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
- **Testing-patterns cheat sheet** (wt10 trace analysis,
  benchmarks/results/ — see the wt9 measurement file
  benchmarks/results/2026-09-18-walkthrough9-rallywall-lumomax.md for
  read-cost methodology; wt10 traces measured 2 full 22k-char reads of
  the same reference):
  - **Bot types**: chaos (random inputs), pursuit (follows target), replay
    (replays recorded path), nav_agent (pathfinding)
  - **Built-in invariants**: `no_fatal_errors`, `nodes_finite`,
    `nodes_in_bounds(min_x/max_x/min_y/max_y)`, `no_null_refs`,
    `frame_time_p99_below(33.3ms)`, `fps_floor(30)`
  - **Custom invariants**: `path + check + value` where path is
    `_meta.<field>` (harness metric) or `/root/<node>:<key>` (game state)
  - **Rate-of-change guard**: add `max_delta_per_sec` to every counter
    (score, currency, ammo) sized to a plausible human ceiling — catches
    re-firing handler bugs that point-in-time checks miss
  - Full reference: the engine plugin's testing-patterns doc
    (`plugins/engine/<engine>/skills/init-project/reference/testing-patterns.md`
    — locate it under the mounted engine plugin)
- **Batch-debug: one run per fix round** (wt10 opencode session traces,
  2026-09-18; same-session tool-call telemetry as the wt9 benchmark
  file: 18
  script-run calls in a single session, each failure re-feeding a tall
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
- This separation enables parallel mutation dispatch on disjoint file
  scopes; verification runs after mutations complete.
