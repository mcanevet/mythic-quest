---
name: init-project
description: Scaffold a Godot project and install the TestPlayer harness. Use when starting a new Godot game.
---

## What I do

Creates the minimal Godot 4 project structure and the deterministic testing harness:

- `project.godot` — config (config_version=5, app name, viewport) with:
  - `run/main_scene` set (empty placeholder scene or first real scene)
  - input map: **EMPTY by default** (genre-agnostic). The first
    implementation task defines game actions from VISION.md and binds
    keys (`[input]` section or `InputMap.action_add_event`). Every defined
    action MUST have ≥1 bound event — the playtest harness reports
    `unbound_action` violations otherwise (observed shipped
    dead once despite green QA). Only `ui_*` built-ins come pre-bound.
- `icon.svg` — placeholder icon
- `.gitignore` — standard Godot ignores (`.godot/`, `*.import`)
- **TestPlayer harness** — `scripts/test_player.gd` (the autoload-backed
  remote-control console for scenario-based playtesting)
- `tests/scenarios/` — directory for per-entity invariant configs

Reference templates: [reference/project-godot-template.md](reference/project-godot-template.md),
[reference/testing-patterns.md](reference/testing-patterns.md) for the harness schema.

**Configuration rules (mandatory):**
- `config/name` in `project.godot` comes from **VISION.md's title** (first `#` heading) — never invent a name; read VISION.md first if it exists
- Discover the installed engine version via `godot-mcp-runtime:check_project` (or `godot --version`) — never hardcode a version anywhere; templates must work with whatever engine the MCP runtime serves

## Execution

1. Create the layout (skip entries that already exist)
2. Run the installer (idempotent):
   ```bash
   ./scripts/install_test_player.sh <project_root>
   ```
   This copies `scripts/test_player.gd` to `<project_root>/scripts/test_player.gd`
   but deliberately does NOT register the autoload — the playtest skill
   registers it at verification time and removes it at teardown.

## Done when

`scripts/validate.sh` runs without errors AND `scripts/test_player.gd` exists
in the project root AND `tests/scenarios/` directory exists.

## Gotchas

- The TestPlayer autoload is registered/unregistered at verification time,
  not here — it never ships with the game.
- Scenario JSONs are loaded at `start_test` time (fresh `load()` each run),
  not cached at engine boot — editing a scenario never requires an engine
  restart (but `.gd`/`.tscn` edits do; see playtest skill staleness rules).
