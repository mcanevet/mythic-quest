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
(observed: walkthrough9, 2026-09-18 — 23 claim refusals across roles
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
false-PASS laundering, 2026-09-17).

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

## Context economy (measured waste, wt9 2026-09-18)

- **Read a file once, fully.** Shifted-offset re-reads of the same file
  burned 5× reads on one scene in a single session. If the file changed
  under you (rare), re-read then — not speculatively.
- **Batch mutations.** Prefer one `batch_scene_operations` call over many
  single-property edits (14 separate edits observed on one bead).
- **Validate once, at the end of a logical unit** — not after every edit
  (7 validate cycles on 14 edits observed). Validation covers the
  accumulated change set.
- **Search before reading**: one grep to locate beats reading whole files
  to find a symbol (20 reads + 11 greps observed for one bead).
