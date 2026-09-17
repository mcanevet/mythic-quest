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

### Auto-verify signal connections (replace manual verification procedure)
- **Observed:** walkthrough6 & 7 — every signal-wiring task required a 4-point
  manual check (connection list, handler naming, manual firing test, common
  failure patterns). Agents burned 10-15 min per entity re-deriving the
  procedure; regressions slipped when steps were skipped.
- **Proposed upstream fix:** Add `verify_node_connections(node_path: str)` tool.
  - Reads the scene file (or live state via remote debugger) to list all
    connected signals for the target node.
  - Compares against `_on_<node>_<signal>` methods in the attached script
    (via `GDScriptAnalyzer` or script reflection).
  - Returns: `{connected: [{signal, target, method}], orphan_handlers: [method],
    missing_connections: [{signal, expected_handler}]}`.
  - Optional: `--auto-fix` flag to connect missing signals if the handler exists.
- **Status:** proposed (no repro needed — this is a capability gap, not a bug).
  Bead: mythic-quest-8nk (new).
- **Retire:** delete the "Signal wiring verification procedure" section from
  create-entity SKILL.md; replace with "Run `verify_node_connections` and
  assert zero missing/orphaned". The 4-point procedure becomes obsolete.

### Structural scene validation (replace manual shape/node checks)
- **Observed:** walkthrough6 — `validate.sh` only checks if a scene *loads*;
  it doesn't verify required nodes exist (e.g., `CollisionShape2D` with a
  `shape` property set). Agents had to write custom `text-validate.sh` scripts
  or manually inspect `.tscn` files.
- **Proposed upstream fix:** Add `validate_scene_structure(scene_path: str,
  schema: dict)` tool.
  - Schema format: `{"type": "CharacterBody2D", "children": [{"type":
    "CollisionShape2D", "has_property": "shape"}, {"type": "Sprite2D"}]}`.
  - Runs headless, loads the scene, traverses the tree, and validates each
    node against the schema (type, required properties, child structure).
  - Returns: `{valid: bool, missing_nodes: [{path, expected_type}],
    missing_properties: [{path, prop}], errors: [str]}`.
- **Status:** proposed (capability gap). Bead: mythic-quest-a0m (new).
- **Retire:** delete the "CollisionShape shape-presence check" gotcha and
  the validator pair rule from create-entity reference; replace with a
  single `validate_scene_structure` call in the skill's "Done when" section.

### Automated UI interaction testing (replace click_element strategy)
- **Observed:** walkthrough7 — UI validation required ad-hoc `simulate_input`
  sequences + manual screenshot analysis. Every button/slider required
  custom scripting; no standard pattern existed.
- **Proposed upstream fix:** Add `click_ui_element(ui_path: str,
  button: str = "pressed")` tool.
  - Uses Godot's `Control` node hierarchy to find the target by path/name.
  - Detects node type (`Button`, `CheckBox`, `Slider`, etc.) and emits the
    appropriate event (`mouse_button_clicked`, `focus_entered`, value change).
  - Returns: `{clicked: bool, signal_emitted: str, new_value: any}`.
  - Optional: `--wait-for-response` to block until a signal fires or timeout.
- **Status:** proposed (capability gap). Bead: mythic-quest-8p5 (new).
- **Retire:** delete the "UI click_element validation strategy" section from
  create-ui SKILL.md; replace with "Run `click_ui_element` on each button
  and assert expected signal/value changes".

### Auto-recover from dead bridge (replace manual health check)
- **Observed:** every skill's "Step 0" requires `get_project_info` to verify
  the MCP bridge is alive; agents waste cycles on dead bridges before
  escalating.
- **Proposed upstream fix (two options):**
  - **Option A (auto-recovery):** When a tool call fails due to a missing
    bridge, the runtime automatically attempts to restart the engine (if
    allowed by config) or re-inject the bridge, then retries the call once.
  - **Option B (health tool):** Add `check_health()` tool returning detailed
    status: `{bridge_loaded: bool, bridge_version: str, engine_version: str,
    active_session: bool, diagnostics: [str]}`.
- **Status:** proposed (capability gap). Bead: mythic-quest-xki (new).
- **Retire:** delete the "MCP health check" Step 0 from create-entity/
  create-level/create-ui SKILL.mds; replace with "Runtime auto-recovers
  from dead bridges; report `⛔ BLOCKED` only after 2 automatic retries fail".

---
*New entries added 2026-09-17. Each represents a runtime contribution that
eliminates a procedural knowledge requirement from our skills.*
