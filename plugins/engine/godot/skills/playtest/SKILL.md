---
name: playtest
description: >-
  Run automated playtesting with scenario-based invariants for game development QA. Use after
  implementing features, during development checks, or for final quality assurance. Supports six
  modes: fast-verify (cheapest — mandatory per-task smoke check), scene-verify (quick dev checks after scene creation),
  functional (exhaustive mechanic verification), vision (creative alignment assessment), critique (player experience
  evaluation), and perf (pre-ship performance gate — frame-time and hot-function profiling).
---

> **Screenshot workflow:** `godot-mcp-runtime:take_screenshot()` → `read(path)` → write analysis (`Scene`/`Entity`/`Issues`/`Verdict`/`Next`). Do not substitute `godot-mcp-runtime:run_script` structural checks for `read()` — that's a known failure mode. (Screenshots are for aesthetics/layout; STATE reads go through `run_script`/node text — see `reference/live-engine-driving.md`.)

> **Analysis template (write in your response after every screenshot):**
> ```
> - **Scene:** <what is rendered>
> - **Entity:** <entity: name, position, color, shape>
> - **Issues:** <none> or <describe>
> - **Verdict:** PASS or FAIL
> - **Next:** <next action>
> ```

## What I do

Six execution modes (perf, fast-verify, scene-verify, functional, vision, critique), each with a distinct evaluator lens. **Always uses `background=true`** (invisible window — deterministic screenshots, no display interference with the agent's own environment).

### Performance mode (perf)

**When:** Pre-ship gate, after functional/vision/critique pass.  
**Purpose:** Objective performance invariant — detect regressions in frame time, worst-case spikes, and hot functions. Uses godot-mcp-runtime v3.4+ profiler API.

**Workflow**
1. Ensure engine running (same as common workflow step 2)
2. Start profiler: `godot-mcp-runtime:start_profiler(projectPath=".")`
3. Run gameplay scenario (60s recommended): `start_test(scenario={...})`. A returned `{"status": "rejected", "error": ...}` means the SCENARIO CONFIG is defective (e.g. bool value with a numeric `below`/`above` check) — that is a test-harness defect, not a game bug: fix the scenario JSON (or file a bug bead routing it to dev per your agent profile), do not run the scenario.
4. Stop profiler + capture: `godot-mcp-runtime:stop_profiler(projectPath=".")` → returns `{frameMs, worstFrame, perFunctionBreakdown}`
5. Assert invariants:
   - `frameMs < 16.7` (60fps target)
   - `worstFrame < 50` (no >3x spike)
   - No single function > 20% of frame time
6. Report PASS/FAIL with metrics table; on FAIL, screenshot the profiler output

**Integration:** the QA/vision agent profiles reference perf mode in their QA checklists; benchmarks/README metrics table includes a perf column for each results file.

### Step 0: MCP Health Check (MANDATORY)

Before any MCP tool call, verify bridge availability:

```
godot-mcp-runtime:check_project(projectPath=".")
```

If this returns an error or times out → **FAIL IMMEDIATELY**. Report "MCP bridge unavailable" and stop. No fallback.

**If the `godot-mcp-runtime_*` tools are absent from your toolset entirely** (you cannot even attempt the call — the tool names don't exist for you) → **STOP IMMEDIATELY and report exactly:**
`⛔ BLOCKED: engine tools missing from toolset.`
**Do NOT diagnose the cause** (server death, toolset race, bad pin, broken npx package — they share this one symptom), do NOT retry, do NOT re-delegate, and do NOT proceed with shell-based substitutes (headless drivers, custom validators, screenshot scripts): a missing MCP toolset means the harness is broken, and working around it silently degrades every downstream verification (observed twice: a run continued 11+ subagents without engine tools; another spent 19 sessions static-reviewing because a broken pin was never detected). Diagnosis belongs to the human, who checks the opencode log and the mcp.json pin.

| Mode | When | Purpose | Testing Method |
|------|------|---------|----------------|
| **functional** | After all tasks complete | Verify every mechanic works per spec | Scenario runner + invariant checker (automated, no screenshots needed unless violation) |
| **vision** | After functional passes | Does it match the creative vision? | Long-form scenario with pursuit/replay bot, 6-8 evenly spaced screenshots across the run |
| **critique** | After functional QA + vision gates pass | Is it fun? Would players care? | Agent-driven free play: the executing agent controls inputs themselves via `simulate_input` at their own pace; screenshots at moments of their choosing |

For quick dev checks during implementation, use `scene-verify` (launches single scene, runs chaos scenario, returns invariant report).

The framework uses genre-agnostic bots (chaos, pursuit, replay, nav_agent) and invariants — see `../init-project/reference/testing-patterns.md` for the configuration schema.

## Parameters

- **mode**: `"fast-verify"` \| `"scene-verify"` \| `"functional"` \| `"vision"` \| `"critique"`
- **scene**: Scene path — required for `scene-verify` only (e.g. `"res://scenes/player.tscn"`)
- **scenario**: Scenario config path — optional, overrides default scenario for mode

---

## Common Workflow

**Scenario-Based Execution** (replaces old simulate_input loop):

1. **Ensure harness autoload:** `godot-mcp-runtime:list_autoloads(projectPath=".")` → if `TestPlayer` is not registered, call `godot-mcp-runtime:add_autoload(projectPath=".", autoloadName="TestPlayer", autoloadPath="scripts/test_player.gd")`. The harness script is created by `init-project` (Step 3b) but deliberately NOT registered there. This start is idempotent — a cold start (re)registers it here, and teardown unregisters it (step 5), so the harness never survives a session. A KEPT engine (step 5 reuse) keeps the registration — check with `list_autoloads` and skip straight to `run_script` when the engine is already up and files unchanged.

2. **Launch with retry:** `godot-mcp-runtime:run_project(scene=scene, background=true)` → `start_test(scenario)` (Godot autoload) → Godot runs autonomously at 60Hz → final report via `await tp.await_test_done()` inside the SAME `run_script` call → structured JSON report (see _Waiting for a scenario_ under fast-verify: one awaited call, never sleep-poll). Exception: vision mode deliberately uses the running window for spot screenshots between calls; critique mode additionally drives input interactively (the critic plays).

3. **Verify invariants:** Report contains `violations[]` array and `metrics` dict. If `violations.is_empty()`, pass. Otherwise, take spot screenshots for each violation type for debugging.

4. **Generate formatted report:** pipe the JSON report file through `./scripts/render_report.py <report.json>` (exit 1 if violations present).

5. **Finish — teardown, or KEEP-RUNNING across consecutive verifications:** Default is `godot-mcp-runtime:stop_project()` + `godot-mcp-runtime:remove_autoload(autoloadName="TestPlayer")` so test infrastructure never ships. **Exception (engine reuse):** when the SAME task/session continues with another verification of the same project — e.g. fast-verify followed by scene-verify, or back-to-back scenarios on one scene — KEEP the engine running instead of tearing down: skip step 5's `stop_project`, and on the next verification skip step 1's re-registration and step 2's `run_project` entirely (the autoload is already registered; `start_test` resets all scenario state itself). Engine reuse eliminates a full boot + bridge handshake per extra verification (~15-30s wall + one `get_debug_output` health cycle each; measured ~2 boots per task, 29 boots in one run). **Mandatory restart overrides — a kept engine MUST be stopped and relaunched when ANY of these hold:**
   - **Any `.gd`/`.tscn`/`.godot` project file changed since the engine started** (script-staleness rule: Godot caches compiled bytecode; the live process reports stale errors at phantom line numbers — see the warning below)
     - **Scenario JSON files (`tests/scenarios/*.json`) are NOT staleness-relevant**: they are loaded from disk at `start_test` time inside your `run_script` call (a fresh `load()` each run), not cached at engine boot. Editing a scenario config does NOT require an engine restart. The restart rule covers `.gd`/`.tscn`/`.godot` only. (Note: to read a scenario JSON inside `run_script` you must `load("res://tests/scenarios/x.json")` with a literal path — dynamic/non-literal paths are blocked by the bridge's safety policy.)
   - A different `scene` parameter is needed
   - The next step is a DIFFERENT task's verification (teardown always happens before returning to the orchestrator — the running engine must never leak across `task()` boundaries; the Finish-at-return rule stands)
   - The engine has crashed or an unrecovered error occurred
   When in doubt whether a file changed: diff mtimes or just restart — a rebooted engine costs seconds; a stale-bytecode false verdict costs a REWORK cycle.

> **Gotchas and edge cases live in [reference/gotchas.md](reference/gotchas.md)** — read them BEFORE your first `run_project` retry, before any run_script debug loop, before triaging a violation, and before any critique-mode "unresponsive controls" verdict. They cover: run-recovery procedure (never blind-retry), engine-unresponsive signature + 5-min budget cap, never-pkill rule, background-frame throttling and state-advance traps, synthetic-input blind spots (event handlers, InputMap binding table), script-staleness under a live engine, probe budget + artifact ledger + compact probe returns, screenshots-vs-state-reads, and empirical-first triage.

---

## Mode: fast-verify

**When:** Immediately after creating/editing a scene or script, before logging the task complete. Default per-task verification — roughly one-third the cost of `scene-verify`.
**Purpose:** Catch load-time crashes, parse errors, and gross runtime breakage WITHOUT the full 15-second chaos gauntlet. This mode exists so that "playtest is slow" is never a reason to skip verification (observed 09-04, ling run: an orchestrator skipped playtest entirely on 4 tasks "to avoid timeouts" — a sanctioned-path violation born of cost pressure. The cheap sanctioned path removes that incentive).

**You MUST run at least this mode after every scene/script change before marking a task `[x]`.** Skipping verification entirely is prohibited — if even fast-verify cannot run (MCP down, engine won't start), the outcome is a `⛔ BLOCKED:` report, not an unverified `[x]`.

### Workflow

1. Ensure harness autoload (Common Workflow step 1)
2. Launch Godot with `background=true`, scene as `scene` parameter
3. Run a 5-second chaos scenario — same baseline invariants as scene-verify, shorter duration:
   ```
   start_test(scenario={
       "bot": {"type": "chaos", "seed": 42, "input_rate_hz": 10},
       "duration_s": 5,
       "invariants": [
           {"name": "no_crash", "rule": "no_fatal_errors"},
           {"name": "no_physics_blowup", "rule": "nodes_finite"},
           {"name": "fps_stable", "rule": "custom", "path": "_meta.frame_ms_p99", "check": "below", "value": 33.3}
       ]
   })
   ```
4. `get_test_report()` → if `violations.is_empty()`, PASS
5. Finish per Common Workflow step 5 — teardown OR keep-running if another verification of the same unchanged project follows immediately

### Waiting for a scenario: ONE awaited run_script, never sleep-poll

`start_test` returns immediately and the scenario runs autonomously. To obtain the report, hold **one** `run_script` call open for the whole scenario — start it, await completion, return the final report — with the tool's `timeout` parameter sized to `duration_s` plus ~30s margin:

```gdscript
extends RefCounted
func execute(scene_tree: SceneTree) -> Variant:
    # Load the scenario from a LITERAL path — non-literal load() paths are
    # blocked by the bridge's safety policy.
    var scenario: Dictionary = load("res://tests/scenarios/basic.json").data
    var tp = scene_tree.root.get_node_or_null("TestPlayer")
    if tp == null:
        return {"success": false, "error": "TestPlayer autoload not found"}
    tp.start_test(scenario)
    var duration: float = float(scenario.get("duration_s", 15))
    # NOTE: positional args only — `await tp.await_test_done(max_wait_s = 45)`
    # does not parse ("Assignment is not allowed inside an expression").
    var report = await tp.await_test_done(duration + 30)
    return {"success": true, "report": report}
    # Compact-return discipline: probe/report scripts return minimal
    # {key: value} summaries — e.g. return {"violations": len(report.violations), "sample": first_violation_summary},
    # never the full report dict or scene-tree dumps. Big returns persist in
    # context for the REST of the session (observed: 17kB single probe outputs).
```

**NEVER poll a running scenario across separate tool calls** — no `bash sleep` between `get_test_report()` checks. Sleep-polling was observed burning 2+ hours and 100+ model steps on a single 15s scenario: every wake-up re-sends the whole diagnostic context for a one-line status check, the engine idles (macOS background-throttles idle frames to 10-12s each, so a 15s sim can stretch past every reasonable deadline), and the loop can outlive the session's usefulness. The awaited form holds the call open so the engine services the scenario, and the client-side 60s transport cap is not a factor for calls with progress heartbeats (godot-mcp-runtime ≥ v3.2.4). Caveat: holding the call open prevents idle-throttling but does NOT guarantee full-rate frames — frame advance inside an awaited script under background throttle remains irregular, which is one more reason timing questions belong in TestPlayer scenarios, not manual awaits (see `reference/live-engine-driving.md`). A `bash sleep` wait is permission-denied — and improvising a different idle-wait is the same violation in another coat. If `await_test_done()` is missing from the deployed TestPlayer (version mismatch after a `init-project` upgrade), that is a harness defect: report `⛔ BLOCKED: await_test_done() unavailable on deployed TestPlayer — re-install scripts/test_player.gd via init-project`, do not improvise an alternative wait loop.

### Scope and limits

- Covers: parse errors, autoload failures, crash-on-load, NaN/Inf blowups, FPS floor
- Does NOT cover: gameplay logic, score/rate invariants, mechanics correctness — those need `scene-verify` (per-scene) or `functional` (pre-ship)
- A fast-verify PASS is necessary but not sufficient for task completion when the task added interactive mechanics — follow with `scene-verify` in the same delegation if the entity has invariants in `tests/scenarios/`

### Success Criteria
- Scene loads, 5s scenario completes, zero violations
- Verdict reported (PASS/FAIL)

---

## Mode: scene-verify

Quick check after creating a single scene. Pass the scene path via the `scene` parameter.

### Workflow

1. Launch Godot with `background=true`
2. Run chaos scenario via `start_test(scenario={
    "bot": {"type": "chaos", "seed": 42, "input_rate_hz": 10},
    "duration_s": 15,
    "invariants": [
        {"name": "no_crash", "rule": "no_fatal_errors"},
        {"name": "no_physics_blowup", "rule": "nodes_finite"},
        {"name": "stay_on_screen", "rule": "nodes_in_bounds", "min_x": -200, "max_x": 1480, "min_y": -200, "max_y": 920},
        {"name": "fps_stable", "rule": "custom", "path": "_meta.frame_ms_p99", "check": "below", "value": 33.3}
    ]
})`
> **Bounds rationale:** the defaults above are an ILLUSTRATION sized to a 1280×720 viewport plus a generous margin — for each game, derive bounds from the project's actual viewport settings (plus margin), or use the bounds the task's plan specifies; never assume this resolution. Entities legitimately leaving the screen during normal play (camera-follow games, wrap-around fields) violate this — that is a *finding about the game's current state*, not a validator bug: before ship, either walls/camera logic confines actors or the scenario widens bounds DELIBERATELY (with a note in the report), never by silently dropping the invariant. *(observed in a 09-04 benchmark run, see git log "Three learnings from mimo run 5"):* default scene-verify passed while a wall-less ball flew to (3510, −2510) — a "clean PASS" that actually meant "physics runs, containment not yet built."
3. Get report via ONE awaited `run_script`: `tp.start_test(scenario)` then `await tp.await_test_done(duration_s + 30)` (see _Waiting for a scenario_ under fast-verify)
4. If `violations.is_empty()`, PASS. Otherwise, take 1-2 screenshots for each violation type.

### Success Criteria
- Scene launches without FATAL errors
- Invariant checker runs for full duration
- Report generated with zero violations (or documented violations)
- Verdict reported in task result (PASS/FAIL based on violation count)

---

## Documentation

Write the full report to `reports/<mode>-<subject>.md` in the game project (evidence tables, violation details, screenshot analysis) — the report write is a sanctioned `write` to `reports/**` where your permission config grants it. In your task result return ONLY:
- Verdict (PASS/FAIL or HIGH/MEDIUM/LOW) + violation count
- One-sentence cause for any FAIL
- The report file path

**Findings become beads (one-time modes):** in functional/vision/critique modes, actionable failures are additionally filed into the ledger as beads with provenance, so the dev loop can pick them up — run once per failure group:

```bash
bd create "<title>" -p 1 --description "<one-paragraph description with repro>" --deps discovered-from:<parent-bead-id>
```

The parent is the bead representing the game (or the milestone epic if one exists); the helper wires `discovered-from` provenance and loop labels automatically. Report-filing and bead-filing are complementary: the report holds evidence, the bead holds the actionable queue entry. Per-task fast-verify/scene-verify FAILs do NOT file beads — the verdict returns to the caller (the build orchestrator) inline, who retries within the task's attempt budget.

If no file-write path exists in your session (write denied or tool absent), do NOT improvise writes through engine primitives (ConfigFile/FileAccess indirection) — return the verdict plus full report inline and state explicitly: "report could not be persisted; no write path." The caller will persist it. The orchestrator reads the file only on FAIL or when evidence is needed — a full report inline in the task result accumulates in every upstream session's context.

---

## One-Time Modes: functional, vision, critique

These run **once per game** (after all tasks complete), not per task — not before. Each has its own workflow, report format, and success criteria:

- **functional** — exhaustive mechanic verification: collect per-entity invariants via `glob("tests/scenarios/*.json")` + `read()`, apply the counter sanity gate (every game-economy counter needs a `max_delta_per_sec` rate invariant — a counter without a rate invariant is an unverified counter), then run a 60s chaos scenario with merged invariants. `start_test` returns immediately; the simulation runs autonomously between MCP calls.
- **vision** — creative-alignment check: 90s pursuit-bot observation, 6-8 evenly spaced screenshots (`responseMode: "preview"`) analyzed with the template above, rate each vision element ✅/⚠️/❌.
- **critique** — player-experience evaluation: the executing agent launches the game and drives it with **their own simulated inputs** (no scenario harness, no bots — `Input.is_action_pressed`-style polled controls are the reliably drivable pattern; see gotcha below), playing at a natural consumer pace for roughly 2-3 minutes; screenshots at moments of the agent's choosing; first-person present-tense narration grounded in captures; per the executing agent's role, README.md may be the only context consulted — never sources.

Full workflows, scenario configs, and report templates: [reference/full-modes.md](reference/full-modes.md). Harness API cheat-sheet (symbols, report shape, path resolution — read instead of test_player.gd): [reference/harness-card.md](reference/harness-card.md).

**Delta-verify (post-fix spot-check):** When re-verifying a *single* fix (bead title contains "fix" or "repair"), extract the affected invariant names from the bead description or the fix's commit message, then run a **minimal scenario** targeting only those invariants (15-30s duration, 3-5 invariants max). Do NOT re-run the full functional gauntlet — that's the qa-gate owner's job (rachel) on the *final* release chain. Delta-verify eliminates the verify→fix→re-verify round-trip (wt13: 60m wasted across 6 sessions).

**Rate-limitation gotcha:** start_test invariants are checked for `duration_s` of gameplay — do not confuse run_script probe timeouts (MCP client-side) with the scenario clock. As of godot-mcp-runtime v3.2.4, long in-engine waits in `run_script` bodies are safe (server heartbeats keep the request alive) — see `../create-entity/reference/mcp-patterns.md`.
