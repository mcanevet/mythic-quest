# Upstream Contribution Backlog

Local memory of improvements we owe to external dependencies (godot-mcp-runtime,
opencode, providers). Workarounds live in skills/agents with upstream-status
citations; this file is the master list so they get retired when fixes ship.

Each entry follows this lifecycle:
**observed → repro → fix-bead (in this ledger, labeled `upstream:*`) →
fork branch / PR → release → RETIRE the workaround + repoint config +
delete the gotcha from skills.**

Never mix this with game-build ledgers — upstream work is pipeline-dev
territory, filed in THIS repo's ledger with `--deps discovered-from:<bead>`.

Entries:
- Observed (incident + evidence: session ID, report path, commit SHA)
- Proposed upstream fix
- Status (observed only / repro in hand / branch ready / PR open / released)
- Retire (condition under which the workaround and gotcha get deleted)

Conventions (from HARNESS_BEADS heritage):
1. Every closed bead cites its evidence — report path, commit SHA, or
   validation run — in the close reason.
2. Incidents become beads: any run failure with a root cause and fix gets
   a bug bead filed (and closed same-session once fixed).
3. Stale scopes get deferred, not force-fit: if the world changed under a
   bead (deleted wrapper, unreleased version), defer with the reason and
   revisit condition.
4. Failure patterns worth codifying route into the lint registry
   (`.agents/lint/rules.yaml`) — the bead is the incident record; the
   registry is the enforcement.

## godot-mcp-runtime

### attach_script ext_resource persistence + parallel-call racing + running-engine overwrite
- **Observed:** walkthrough6 2026-09-15 (session ses_f59622bb4ffevu6iFE02nHpLLN):
  (1) `attach_script` reported success but did not persist ext_resources
  into the `.tscn` — scripts missing after save; (2) parallel `attach_script`
  calls raced and clobbered each other's ext_resources; (3) a running
  engine process overwrote scene files edited on disk. 5/11 attach_script
  calls errored outright; the agent fell back to hand-editing the `.tscn`
  (which its permission profile denies — bash heredoc bypasses edit deny).
- **Proposed upstream fix:** serialize scene-mutation tools; ensure
  attach_script writes ext_resource entries atomically; refuse or warn
  when an engine process is running against the target scene.
- **Status:** observed only (repro in the walkthrough6 session trace).
  Bead: mythic-quest-mzx.
- **Retire:** in-harness mitigations to delete once fixed: the
  stop_project-before-edit gotcha (create-entity SKILL.md) narrows to a
  note, and poppy's `.tscn` fallback scrutiny relaxes.

### Property-value schema undocumented in tool descriptions
- **Observed:** walkthrough6 2026-09-15 — colors, scripts, polygons, and
  other property values follow non-obvious schemas (float-dict colors not
  hex strings; plain `res://` paths not nested objects; point arrays for
  polygons). The tool descriptions don't document any of this, so every
  implementer rediscovers it through failure.
- **Proposed upstream fix (doc-only, small PR):** document the expected
  property-value schema in `set_node_properties` / `add_node` /
  `attach_script` tool descriptions — the exact shapes the value coercer
  accepts.
- **Status:** observed only. Bead: mythic-quest-9qc (this issue also
  motivated the Gotchas section in create-entity SKILL.md — that section
  is the in-harness workaround).
- **Retire:** the create-entity Gotchas entries marked "schema quirks"
  shrink to a pointer at the (now-documented) upstream schema.
