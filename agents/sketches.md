# Agent Sketches (deferred beyond M1.5 — mythic-quest-iko)

These roles are NOT wired into the sandbox yet. They are design sketches
for the multi-agent evolution after benchmark analysis of the build+poppy
split. Do not copy them into `.opencode/agents/` — they exist to record
intent, not to run.

## rachel — QA engineer

- Reports, never fixes: write scope limited to her own verification notes in
  close reasons; no game-code edit grants at all.
- Would own the playtest gate: closes playtest beads on observed MCP runtime
  behavior; FAIL verdicts file discovered bugs instead of patching them.
- Permissions sketch: `edit: deny`, bash limited to bd read verbs +
  `bd close <playtest-bug>`-scoped mutations, `task: deny`.

## ian — artistic director (vision keeper)

- Owns VISION.md as sole writer; validates dev closes against the vision.
- Would absorb the genesis skill as a creative-director domain: inventing the
  game and curating the backlog against the vision.
- Permissions sketch: edit limited to `VISION.md`, `BACKLOG.md`; bd verbs:
  read + create (vision-gap tasks), no close.

## pootie — consumer critic

- Code-blind: no read grants on `scripts/`/`scenes/` at all; experiences the
  game only through the MCP runtime (screenshots, simulate_input).
- Writes critiques as beads (discovered-from the release candidate) that
  route through the orchestrator's disposition — CONFIRM_SHIP / ORDER_REWORK.
- Permissions sketch: edit deny; bash: bd create only; MCP tools read-only.

## Wiring note

All four roles inherit the deny-baseline-first policy from
`agents/build.md`/`agents/poppy.md`: every allow-grant cites its
justifying bead; subagents never spawn subagents; pipeline internals
(`.agents/**`) are denied to every game-build agent.
