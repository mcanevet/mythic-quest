---
name: review-merge
description: Merge-review skill for Godot projects. Compile, consistency, and vision-alignment criteria; conflict-resolution rules for scenes/scripts; common pitfalls from Godot docs.
---

## What I do

Review per-worker worktree commits before merging to trunk:
- **Compile**: no parse errors, missing dependencies, type mismatches
- **Consistency**: no conflicting edits to the same file across workers
- **Vision alignment**: changes match VISION.md intent
- **Godot best practices**: node hierarchy, coupling, autoload discipline, naming conventions

## Reference files (read before review)

- **Godot architecture best practices** → [playtest/reference/godot-best-practices.md](../playtest/reference/godot-best-practices.md)
  - Hierarchy patterns, signal discipline, autoload lifecycle
- **Common gotchas** → [playtest/reference/gotchas.md](../playtest/reference/gotchas.md)
  - Type inference traps, scene-file clobbering, color formats
- **Testing patterns** → [init-project/reference/testing-patterns.md](../init-project/reference/testing-patterns.md)
  - Test hooks, scenario schema, entity state contracts
- **MCP tool patterns** → [create-entity/reference/mcp-patterns.md](../create-entity/reference/mcp-patterns.md)
  - Tool boundaries, path conventions, batch-operation schema
- **Godot docs (upstream)** → `~/src/github.com/godotengine/godot-docs/tutorials/best_practices/`
  - `scene_organization.rst`: loose coupling, dependency injection, signal patterns
  - `autoloads_versus_regular_nodes.rst`: when to use autoloads (rarely), preferring scene-local state
  - `project_organization.rst`: snake_case folders/files, PascalCase node names, `addons/` for third-party
  - `logic_preferences.rst`: set properties before adding to tree, preload vs load
  - `version_control_systems.rst`: ignore `.godot/`, `*.translation` files

## Review criteria

### Compile check

- **Parse errors**: MCP `godot-mcp-runtime:validate` tool (headless parse) — no `godot --check-only` CLI exists for whole projects
- **Missing dependencies**: all `ext_resource` paths resolve; all `preload()` calls succeed
- **Type mismatches**: no "cannot infer type" or "expected X but got Y" errors
- **Signal connections**: connected methods exist on target nodes

### Consistency check

- **Scene files (.tscn)**: serialize edits; if two workers edited the same scene, prefer the worker owning that entity's implementation
- **Scripts (.gd)**: parallelize; if two workers edited the same script, REJECT and re-dispatch with ownership split
- **project.godot**: overlapping autoload additions must be coordinated upstream; reject the second

### Vision alignment

- Read VISION.md; verify changes match stated intent
- Reject feature creep or deviations without explicit approval

### Godot best practices (spot-check)

- **Naming conventions**:
  - Folders/files: `snake_case` (e.g., `entities/player.tscn`, `scripts/game_state.gd`)
  - Node names: `PascalCase` (e.g., `Player`, `HealthBar`, `ScoreLabel`)
  - Signals: past-tense verbs (e.g., `score_changed`, `health_depleted`)
- **Autoload discipline**: prefer scene-local state; autoloads only for truly global services (audio, save system). Avoid "manager" singletons that create global state.
- **Dependency injection**: pass dependencies via arguments or parent context, not hardcoded `get_node("/root/Autoload")` calls
- **Property initialization**: set node properties *before* adding to scene tree (performance; avoids redundant setter calls)
- **Resource loading**: use `preload()` for compile-time resources, `load()` only for dynamic runtime lookups
- **File exclusions**: `.godot/` and `*.translation` should be in `.gitignore` (generated/imported files)

## Conflict resolution rules

1. **Scene files (.tscn)**: serialize — prefer the worker whose bead owns that entity's creation/modification
2. **Scripts (.gd)**: parallelize — if two workers edited the same script, reject both and re-dispatch with ownership split
3. **project.godot**: prefer the more fundamental change; reject overlapping autoload additions
4. **Shaders/materials**: prefer the worker whose bead owns that visual effect

## Common pitfalls (watch for these)

- **Colors as hex strings**: `{r: 27/255, g: 42/255, b: 65/255, a: 1}` not `"#1b2a41"`
- **Type inference**: `var x := dict.get("k")` fails; use `var x = ...` or `var x: int = ...`
- **Scene clobbering**: runtime writes overwrite scene edits; ensure `stop_project` before scene mutations
- **Group reliance**: identify instanced nodes by groups, not names
- **Autoload lifecycle**: autoloads register at boot; changes require restart
- **Hardcoded paths**: avoid `$Child/SubChild/DeepNode`; prefer signals or dependency injection
- **Global state**: rejecting "SoundManager.play()" patterns in favor of scene-local AudioStreamPlayers

## Verdict vocabulary

- **APPROVED**: compile clean, no conflicts, vision-aligned, follows Godot best practices
- **REJECTED: <worker> — <specific issue>** (cite file + line + expected vs actual)
- **DEFERRED**: need human decision on conflict resolution

Never hand-edit game code — reject precisely and let the orchestrator re-dispatch.
