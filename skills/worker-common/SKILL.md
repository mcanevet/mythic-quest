---
name: worker-common
description: Shared protocol for every role worker (poppy/rachel/ian/pootie/phil/stephen/gustavo) in a game-build session — claim/close actor identity, engine health probe, blocked reporting. Load before starting any assigned bead.
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
"already assigned to \<role\>", and beads never enter in_progress.

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
work: runtime evidence is required for every close.

## Reporting

- Verdicts cite observed runtime behavior, never intentions.
- If a step cannot produce runtime evidence, say so explicitly rather
  than substituting static analysis.
