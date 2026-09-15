# MCP Tool Usage Patterns

## Tool Selection (Default Strategy)

Use **batch operations first**, individual tools for simple cases:

- **3+ nodes** → `godot-mcp-runtime:batch_scene_operations` (saves ~3s per operation)
- **1-2 nodes** → `godot-mcp-runtime:create_scene` + `godot-mcp-runtime:add_node`
- **Update properties** → `godot-mcp-runtime:set_node_properties` (primitives, Vector/Color dicts, and Resource-typed dicts — `{type: "ClassName", ...props}` constructs the resource inline, including nested resources; `res://` paths load saved ones. Type-incompatible assignments return an explicit error as of godot-mcp-runtime v3.2.4; inline construction per SKILL.md Step 5a)
- **Attach script** → `godot-mcp-runtime:attach_script`
- **Check hierarchy** → `godot-mcp-runtime:get_scene_tree`
- **Wire signals** → `godot-mcp-runtime:connect_signal`
- **Verify connections** → `godot-mcp-runtime:get_node_signals`
- **Validate files** → `godot-mcp-runtime:validate` (before runtime)
- **Debug errors** → `godot-mcp-runtime:get_debug_output` (after runtime failures)

## Tool Boundaries (Pick the Right One)

| Pair | Which to use | Why |
|------|--------------|-----|
| `run_project` vs `attach_project` | `run_project`, **always** | Happy-path-only policy: never launch Godot yourself and never use `attach_project`. Manual-launch + attach looks equivalent but bypasses the sanctioned verification path (no captured debug output, unsanctioned infra, observed: a subagent built tmp launch/kill scripts and attached-mode tested after 4 bridge timeouts instead of reporting BLOCKED — benchmarks/results/2026-09-06-rallywall-lumo-lite-medium-shipped.md). If `run_project` fails after the recovery procedure below, report BLOCKED — do not manufacture attachability |
| `validate` vs `run_script` | `validate` for static checks | `validate` parses files headlessly; `run_script` executes in the live process and requires an active runtime session |
| `get_node_signals` vs `get_scene_tree` | `get_node_signals` for wiring; `get_scene_tree` for hierarchy | Signals ops need the signal+method names; the tree gives structure only |


## Path Conventions

| Context | Format | Example |
|---------|--------|---------|
| MCP `scenePath` param | Relative, no `res://` | `"scenes/main.tscn"` |
| MCP `projectPath` param | "." (CWD is project root) | `"."` |
| Inside `.tscn` ext_resource | Godot `res://` path | `"res://scripts/player.gd"` |
| Inside `.gd` preload() | Godot `res://` path | `preload("res://scenes/player.tscn")` |
| MCP `parentNodePath`/`nodePath` | Scene-root-relative: `root` for the root node, `root/<Child>` for descendants; bare child names (`"Entity1"`) and `root/<RootName>` also resolve | `"root/Player"` |

**Common mistake:** Root node cannot have `parent="."` — remove it or scene fails to parse.

## Batch Operations Template

```bash
# Pseudo-code showing batch pattern:
godot-mcp-runtime:batch_scene_operations(
  operations=[
    {operation: "add_node", nodeName: "Entity1", nodeType: "Area2D", properties: {...}},
    {operation: "add_node", nodeName: "CollisionShape2D", parentNodePath: "Entity1", nodeType: "CollisionShape2D"},
    {operation: "save"}
  ]
)
```

> ⚠️ **Gotcha — auto-save persists partially-failed batches:** even when some
> ops in the batch error (e.g. a dropped `operation` or `scenePath` key), the
> remaining ops run and the scene's accumulated mutations are auto-saved on
> process exit — a half-built scene can land on disk silently. Two defenses:
> 1. Pass `abortOnError: true` for multi-op scene builds so one malformed op
>    doesn't leave partial mutations to be auto-saved.
> 2. **Check every entry in `results[]`**, not just the last one — each op is
>    tagged with its own `success`/`error`. A batch "completes" even when ops
>    inside it failed.
>
> Also: every op object must carry its own `operation` and `scenePath` keys —
> omitting either produces `Unknown batch operation: ` /
> `scene_path required for add_node` errors that are easy to miss among
> sibling successes.

## MCP Health Check (mandatory before any engine work)

Before the first engine tool call in a session, call `godot-mcp-runtime:get_project_info()`.

- **It succeeds** → proceed normally.
- **The tool is absent from your toolset** (no `godot-mcp-runtime_*` tools available) → **STOP IMMEDIATELY.** Return `⛔ BLOCKED: engine tools missing from toolset. Only the human can fix this by restarting the entire opencode process; re-delegating or spawning a new subagent inherits the same dead toolset (subagents share the parent's MCP connections). Do not retry, do not re-delegate, do not build shell-based workarounds` (custom validators, headless drivers, screenshot scripts) — that masks a broken harness and silently degrades verification quality (observed, 09-06 run: subagents ran for extended spans with no engine tools, building parallel test infra nobody sanctioned — see the Task-7/8 sleep-poll account in benchmarks/results/2026-09-06-rallywall-lumo-lite-medium-shipped.md). The MCP server is a child of the primary opencode process; no agent action can restart it.
  - **Report the likely cause, not just the symptom** (two causes share this symptom):
    - *Server death* — opencode logged `MCP connection closed`, earlier sessions had the tools. Wording: `MCP server down`.
    - *Toolset-snapshot race* — this session started within ~seconds of opencode boot; the async MCP handshake (npx cold-start → connect → listTools) hadn't finished when the toolset was snapshotted. Server process is alive; LATER sessions have the tools. Wording: `likely toolset-snapshot race at opencode boot`. Same fix (restart), but this tells the human the server itself is fine and they should not debug the MCP server config.

## Error Recovery Pattern

> ℹ️ **Runtime phase and parallel subagents.** Within one opencode session all
> subagents share a single MCP server, which serializes `run_project` calls
> internally — concurrent runtime phases are safe (verified during the 09-01
> relative-`projectPath` workup, docs/upstream-backlog.md: two
> parallel `run_project` calls through one server both succeed). Other engine
> commands (`run_script`, `take_screenshot`, `simulate_input`, …) are **NOT
> queued** — if another command is in flight, the server rejects with
> "another command ('X') is in flight"; just re-issue after the current
> command completes (e.g. `take_screenshot` rejected during a
> long `run_script`). The one real hazard is *two opencode sessions* running
> engine tools against the same project simultaneously (each session gets
> its own MCP server and both re-inject the bridge autoload): the server
> detects this and reports "Another MCP client likely re-injected
> concurrently" with the expected vs on-disk port. Treat that error as a
> coordination problem — let one session finish its runtime phase before the
> other starts. File writes (implementation) always run freely in parallel.

> ℹ️ **Long `run_script` bodies are safe as of godot-mcp-runtime v3.2.4.** The
> server emits `notifications/progress` heartbeats every 20s for the lifetime
> of every tool call, so clients that set `resetTimeoutOnProgress` (opencode
> does) keep long-running scripts (simulations, playtests, empirical tuning)
> alive past the SDK's 60s default. Write long-bodied scripts as a single
> awaited call — including the tool-level `timeout` parameter when you want an
> explicit cap. The historical segmented-script recipe (multiple ~8s bodies
> with state carried across calls) is **retired**: the MCP client timeout it
> worked around no longer applies (fix merged upstream in v3.2.4, PR #30;
> validated under sustained load in the 09-05 GLM benchmark run — zero client
> timeouts across 5h of long QA sims). Legacy hazard note: on runtimes older
> than v3.2.4, a timed-out long script kept executing server-side and held
> the single command slot; if you ever see `MCP error -32001` on
> `run_script` again, that indicates a pre-3.2.4 runtime or a non-heartbeat
> client — report it rather than working around it with segmentation.

> ⚠️ **GDScript compile errors (error 43) in probe scripts.** A failing
> `run_script` costs a full engine round-trip (~10–30s). Before the FIRST
> `run_script` call, lint the probe script (`validate.sh` or headless
> `--check-only`). If the same script fails with error 43 twice: STOP
> iterating on edits — write the script to a file, lint it, confirm zero
> syntax errors, THEN re-run. Two sessions have burned 5+
> repeated run_script round-trips on successive syntax guesses.

**If `godot-mcp-runtime:run_project` fails (bridge timeout, "did not respond", "process exited"):**
1. Call `godot-mcp-runtime:get_debug_output()` immediately — read actual error
2. Kill lingering engine process: `bash("<skill-path>/../create-entity/scripts/stop_engine.sh")` — the blessed stop script (kills only `godot --path …`, waits for port release). **NEVER run pkill yourself** (see warning below)
3. Fix specific issue in source files
4. Retry once. If same error → **STOP** and report to caller: `⛔ BLOCKED: runtime phase failed after sanctioned recovery (debug → stop_engine → fix → retry). Do not self-launch Godot or use attach_project.`
   - **DO NOT invent workarounds**: manual launch scripts, `attach_project`, custom validation hooks, shell-based test runners, or "background mode" hacks. These look equivalent but bypass the sanctioned verification path (no captured debug output, unsanctioned infra; mimo run 5, Task 11 subagent built tmp launch/kill scripts and attached-mode tested after 4 bridge timeouts instead of reporting BLOCKED).

**⚠️ Engine/transport unresponsive — recognize it and bail FAST (run 10, 09-07 CoilUp: cost 4h58m).**

Signature: `get_debug_output()` **succeeds** (engine process alive, logs clean, McpBridge listening) while `run_script` **times out on a trivial probe** (`return {"ok": true}`) — and keeps timing out across engine restarts. This is NOT "is the game running?" (the tool error says that; it is lying) and NOT a game bug (the game code is irrelevant to a probe that never reaches the engine). Root cause observed in run 10: **host memory pressure** — the OS suspends the engine process under RAM exhaustion; a suspended process keeps its socket bound and its stdio readable but never services RPC. Engine restarts cannot fix a starved host, so every cycle is pure waste.

Hard rules:
1. Probe ONCE with a trivial script (small timeout, ≤30s). If it times out while `get_debug_output` works → declare the wedge.
2. **Escalation ladder is capped at ONE restart cycle**: stop_engine → run_project → one more trivial probe. Still wedged → `⛔ BLOCKED: MCP bridge/engine unresponsive (get_debug_output OK, run_script probes time out across restart). Likely host resource exhaustion — a fresh subagent or engine restart will inherit the same condition. Do not retry; do not restart the engine again.`
3. **Cumulative timeout budget: 5 minutes per verification phase.** Sum your `timeout` parameters. Past budget → BLOCKED per (2). Escalating timeout sizes (60s → 120s → 600s …) is sunk-cost spiral, not diagnosis: observed 17× 600s waits = 2.8h of pure waiting in run 10.
4. One documented recovery worth a single try before BLOCKED: `remove_autoload` TestPlayer → stop_engine → run_project → probe (run 10 tasks 12–13 escaped in minutes this way — though this may reflect eased host pressure rather than the unload itself).

Why this must be mechanical, not judgment: the per-call error message ("Is the game running? Check get_debug_output…") always suggests an actionable next step, so every retry feels justified individually. Prose stopping conditions fail exactly when errors look recoverable but aren't. Count restarts, not reasons.

> ⚠️ **Critical — never invoke pkill directly:** `npx godot-mcp-runtime` (the
> MCP server) contains "godot" in its command line, so any pattern broader than
> the exact engine invocation kills it — permanently, since no auto-reconnect
> exists. Worse, permission-allow patterns are string-matched, not
> argv-parsed: the allow rule `pkill -f *godot --path*` matched an *unquoted*
> `pkill -f godot --path`, which the shell splits into argv
> `["pkill","-f","godot","--path"]` — pkill binds the pattern `godot`,
> ignores `--path`, and kills the MCP server (observed: killed a live run at
> the exact second of the kill). The only sanctioned engine stop is the
> `stop_engine.sh` script, which encodes the safe pattern internally.

**Common errors and fixes:**
- `Parse Error: Expected '['` → malformed `.tscn` (check brackets, headers)
- `Invalid scene: root node X cannot specify a parent` → remove `parent="."` from root
- `Property 'X' does not exist` → wrong node type for the property
- `Resource file not found` → ext_resource path incorrect
- `Script not found` → path mismatch between scene and actual file
- Resource-typed property (e.g. `shape`) reads back as `null` after a `set_node_properties`/`add_node` → the value was probably not a recognized Resource form. Construct inline with a typed dict `{type: "RectangleShape2D", size: {x: 20, y: 100}}` or pass a `res://` path to a saved resource (see SKILL.md Step 5a). Inner-property type violations and wrong-class constructions return explicit errors naming the property. Historical note: before this capability, dict-shaped values silently no-oped and a paddle task burned ~8 min probing four serialization formats — **do not probe alternate dict formats**; >2 failed attempts = report `⛔ BLOCKED` with the tool error text.

**Validation strategy:**
- Before `run_project`: Call `godot-mcp-runtime:validate()` on all .tscn/.gd files
- After failure: Call `godot-mcp-runtime:get_debug_output()` before any retry
- If no debug output: Call `godot-mcp-runtime:list_autoloads` to check for broken autoloads
