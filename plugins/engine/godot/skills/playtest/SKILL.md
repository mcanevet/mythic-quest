---
name: playtest
description: >-
  Run automated playtesting with scenario-based invariants for game development QA. Use after
  implementing features, during development checks, or for final quality assurance. Supports five
  modes: fast-verify (cheapest — mandatory per-task smoke check), scene-verify (quick dev checks after scene creation),
  functional (exhaustive mechanic verification), vision (creative alignment assessment), and critique (player experience evaluation).
---

> **Screenshot workflow:** `godot-mcp-runtime:take_screenshot()` → `read(path)` → write analysis (`Scene`/`Entity`/`Issues`/`Verdict`/`Next`). Do not substitute `godot-mcp-runtime:run_script` structural checks for `read()` — that's a known failure mode.

> **Analysis template (write in your response after every screenshot):**
> ```
> - **Scene:** <what is rendered>
> - **Entity:** <entity: name, position, color, shape>
> - **Issues:** <none> or <describe>
> - **Verdict:** PASS or FAIL
> - **Next:** <next action>
> ```

## What I do

Five execution modes (fast-verify, scene-verify, functional, vision, critique), each with a distinct evaluator lens. **Always uses `background=true`** (invisible window — deterministic screenshots, no display interference with the agent's own environment).

### Step 0: MCP Health Check (MANDATORY)

Before any MCP tool call, verify bridge availability:

```
godot-mcp-runtime:get_project_info(projectPath=".")
```

If this returns an error or times out → **FAIL IMMEDIATELY**. Report "MCP bridge unavailable" and stop. No fallback.

**If the `godot-mcp-runtime_*` tools are absent from your toolset entirely** (you cannot even attempt the call — the tool names don't exist for you) → **STOP IMMEDIATELY and return a hard failure.** This is NOT recoverable by any agent: the MCP server is a child process of the opencode primary process, and restarting *a subagent* (or asking the build agent to re-delegate) inherits the same dead toolset. The ONLY recovery is the human restarting the entire opencode process. Report: `⛔ BLOCKED: MCP server down — engine tools missing from toolset. I cannot continue; a new subagent will hit the same wall. The human must restart opencode (the primary process) to restore MCP; do not retry or re-delegate this task.` Do NOT proceed with shell-based substitutes (headless drivers, custom validators, screenshot scripts): a missing MCP toolset means the harness is broken, and working around it silently degrades every downstream verification (observed: a run continued 11+ subagents / several hours without engine tools, building unsanctioned parallel test infrastructure).

**Diagnostic precision matters — distinguish WHY tools are absent.** There are two different causes with the same symptom, and conflating them misleads the human:
- **Server death** (e.g. the engine-stop incident): a `MCP connection closed` event exists, or earlier sessions in the same opencode process HAD the tools. Restart is the fix.
- **Toolset-snapshot race** (upstream, see below): the session snapshotted its toolset before the async MCP handshake finished (npx cold-start). Sessions that start within seconds of opencode boot can be born without tools even though the server process is alive and later sessions have the tools. Restart ALSO fixes this, but the correct report wording is `⛔ BLOCKED: engine tools missing from toolset — likely toolset-snapshot race at opencode boot (server process may be alive). Human must restart opencode and avoid prompting within the first ~60s after boot, then re-verify via this health check.` Reporting "server down" when the server is up sends the human debugging the wrong layer. *(Upstream status: inherent to opencode's toolset snapshot-at-spawn behavior, no version-specific bug identified — retirement check: if a future opencode release defers toolset snapshots until MCP handshake completion, this race becomes impossible and this bullet can be deleted.)*

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

5. **Finish — teardown, or KEEP-RUNNING across consecutive verifications:** Default is `godot-mcp-runtime:stop_project()` + `godot-mcp-runtime:remove_autoload(autoloadName="TestPlayer")` so test infrastructure never ships. **Exception (engine reuse):** when the SAME task/session continues with another verification of the same project — e.g. fast-verify followed by scene-verify, or back-to-back scenarios on one scene — KEEP the engine running instead of tearing down: skip step 5's `stop_project`, and on the next verification skip step 1's re-registration and step 2's `run_project` entirely (the autoload is already registered; `start_test` resets all scenario state itself). Engine reuse eliminates a full boot + bridge handshake per extra verification (~15-30s wall + one `get_debug_output` health cycle each; the 09-05 qwen run measured ~2 boots per task, 29 boots in one run — see benchmarks/results/2026-09-05-rallywall-qwen-medium-shipped.md). **Mandatory restart overrides — a kept engine MUST be stopped and relaunched when ANY of these hold:**
   - **Any `.gd`/`.tscn`/`.godot` project file changed since the engine started** (script-staleness rule: Godot caches compiled bytecode; the live process reports stale errors at phantom line numbers — see the warning below)
     - **Scenario JSON files (`tests/scenarios/*.json`) are NOT staleness-relevant**: they are loaded from disk at `start_test` time inside your `run_script` call (a fresh `load()` each run), not cached at engine boot. Editing a scenario config does NOT require an engine restart. The restart rule covers `.gd`/`.tscn`/`.godot` only. (Note: to read a scenario JSON inside `run_script` you must `load("res://tests/scenarios/x.json")` with a literal path — dynamic/non-literal paths are blocked by the bridge's safety policy.)
   - A different `scene` parameter is needed
   - The next step is a DIFFERENT task's verification (teardown always happens before returning to the orchestrator — the running engine must never leak across `task()` boundaries; the Finish-at-return rule stands)
   - The engine has crashed or an unrecovered error occurred
   When in doubt whether a file changed: diff mtimes or just restart — a rebooted engine costs seconds; a stale-bytecode false verdict costs a REWORK cycle.

> **If `godot-mcp-runtime:run_project` fails** (bridge timeout, "did not respond", or "process exited"): **Do NOT retry immediately.** Follow the run-recovery procedure in `../../create-entity/reference/mcp-patterns.md` (_Error Recovery Pattern_): read `godot-mcp-runtime:get_debug_output()` first, kill and recycle the port, fix the root cause, then retry once. If it fails again with the same error, **STOP** and report to the caller: `⛔ BLOCKED: runtime phase failed after sanctioned recovery` — do not infinite loop, and **do not improvise workarounds** (self-launched Godot, `attach_project`, custom test hooks, shell-based runners). Happy-path-only: if the sanctioned path cannot verify, the result is a BLOCKED report, not an invented alternative.

> ⚠️ **Engine-unresponsive signature (read before any run_script retry):** if `get_debug_output()` succeeds while a **trivial** `run_script` probe (`return {"ok": true}`) times out — and this persists across an engine restart — the engine is not servicing RPC. Likely root cause observed in run 10: **host memory pressure** (macOS suspends the engine process; a suspended engine keeps its socket bound and stdio readable but never services calls — restarting cannot fix a starved host). The per-call error "Is the game running?" is misleading: the game IS running. Cap: ONE restart cycle + one TestPlayer-autoload-removal try, 5-minute cumulative timeout budget per phase, then `⛔ BLOCKED: engine unresponsive …` (full procedure and rationale in `../create-entity/reference/mcp-patterns.md`, _Engine/transport unresponsive_). Run 10 (09-07): an agent that ignored this budget spent 4h58m / 5.6M tokens in a timeout ladder producing zero forward progress.

> ⚠️ **Never run pkill yourself** (any variant): the MCP server process (`npx godot-mcp-runtime`) contains "godot" in its command line and broad patterns kill it — permanently removing all engine tools for the session. Even the previously-safe quoted `pkill -f 'godot --path'` is now forbidden: permission rules string-match (not argv-parse), and repeated denials push models toward unquoted forms that killed a live run. Use the blessed script instead: `bash("../create-entity/scripts/stop_engine.sh")`. See the Critical warning in `../create-entity/reference/mcp-patterns.md`.

**Screenshots are now rare** — taken only when a violation occurs, not as primary verification.

> ⚠️ **Background mode throttles idle frames (macOS).** With `background=true`, the OS throttles the hidden-window engine between MCP calls: frame times of **10-12s** were observed (09-04 qwen run 5, benchmarks/results/2026-09-04-rallywall-qwen-shipped.md), meaning the simulated world advances ≤0.133s per idle wall-second. Consequences: (a) a game that "loses in 1.4s of sim time" survives many wall-minutes — never judge pacing from wall-clock observations; (b) a 60s scenario may be only ~1-2s of simulated interaction; (c) huge single-frame deltas on MCP-call resume can trip game logic (instant loss on first frame) — that is a **harness artifact, not necessarily a game bug**; verify suspected boot-loss in a single awaited `run_script` before diagnosing game code. For gameplay-quality judgments (vision/critique), **drive the gameplay inside one `run_script` body** (await physics frames, actuate inputs, sample state) — do not rely on bot behavior across MCP call gaps. **A stateful game may advance to GAME_OVER between your MCP calls while you are thinking** (run 11, benchmarks/results/2026-09-08-rallywall-lumo-max-medium-shipped-run11.md: every one of the critic's screenshots landed on the post-game screen, seeding a false "HUD stuck" claim). If a probe returns unexpected end-state, don't assume a game bug: include a state-reset or scene-reload at the START of your next probe script, or use `get_tree().paused = true` for pure read-only probes of a live session.

> ⚠️ **Synthetic input is invisible to event-driven handlers.** `Input.action_press()` (via `run_script`) and `simulate_input` key/action events do **not** generate InputEvents: handlers using `_unhandled_input(event)` or `Input.is_action_just_pressed()` may never see them (`action_press` registers `just_pressed` for only the exact press frame). If restart/menu handlers appear dead under the harness but work for humans, check which input API the handler uses before declaring the game broken. Robust patterns the harness CAN drive: `Input.is_action_pressed` polling in `_process`, or `_input`/`_input(event)` with `parse_input_event`. A critique-mode REWORK citing "unresponsive controls" must be verified against this list first.

> **Script edits under a running engine require a restart.** Playtest itself never edits game files — but you may have edited a `.gd` file (e.g. fixing a parse error the validation step surfaced) while the engine this skill launched is still running. Godot caches compiled script bytecode in a running process; the live process keeps reporting **stale errors at phantom line numbers** — including parse errors you already fixed (an agent can burn 5+ steps hunting a nonexistent second bug before guessing "cached bytecode"). If you edited a script and the reported error doesn't match the current file contents, **do not debug the file** — `stop_project()`, relaunch, and re-register the autoload before re-validating.

> ⚠️ **Context economy for long verification sessions (probe budget + artifact ledger).** Multi-phase verification (QA gauntlets, multi-violation triage) burns tokens super-linearly: every step re-sends the accumulated diagnostic context (observed 09-04, qwen run: one 180-step gauntlet session consumed 5.95M input — 34% of the entire build). Two rules:
> - **Artifact ledger:** when you finish classifying a violation group or diagnostic finding, append a 2-3 line summary ("artifact ledger") to the report file (or your plan file) — name, root cause, verdict (game bug vs harness artifact), disposition. Treat the ledger as your working memory going forward; do not re-derive classified findings, and cite the ledger instead of re-reading raw outputs.
> - **Probe budget:** if more than **10 probe calls** are spent diagnosing a single violation group without resolution, STOP — reassess the hypothesis class (environment artifact vs game bug) before the next call. Common resolutions at that point: it IS an environment artifact (background throttle, post-reload first-tick noise, startup-inflated p99), or the invariant needs wider bounds/tolerances — both are one-line dispositions, not ten more probes.

> ⚠️ **Empirical first: static analysis is a bounded budget, not a debug strategy.** When triaging a reported bug or unexpected behavior, write and run the **reproduction probe before settling into analysis**. Static reasoning (reading scripts, enumerating races, theorizing root causes) is capped at **~3 reasoning rounds** — if you cannot state the root cause by then, you MUST run a repro probe next. The probe decides; speculation just re-labels guesses. Rationale (run 12, 2026-09-09): a bug-hunt session spent ~150 reasoning paragraphs enumerating hypothetical races around a score-display bug, then ran a repro probe on the next step — which reproduced the bug immediately and invalidated most of the theorizing. A well-built repro probe (drive the real gameplay path in one awaited `run_script`, capture the failing state) is cheaper, faster, and falsifies hypotheses in bulk — every round of pure speculation that survives the probe is a round the probe would have ended on step one. Exception: a 30-second doc/code read to orient the probe (find the state getters, the failure path) is not speculation — reading IS allowed, unfalsifiable theorizing is not.

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
```

**NEVER poll a running scenario across separate tool calls** — no `bash sleep` between `get_test_report()` checks. Sleep-polling was observed burning 2+ hours and 100+ model steps on a single 15s scenario (09-06 qwen run): every wake-up re-sends the whole diagnostic context for a one-line status check, the engine idles (macOS background-throttles idle frames to 10-12s each, so a 15s sim can stretch past every reasonable deadline), and the loop can outlive the session's usefulness. The awaited form has none of these failure modes: the engine keeps ticking at full rate while the call is open, and the client-side 60s transport cap is not a factor for calls with progress heartbeats (godot-mcp-runtime ≥ v3.2.4). A `bash sleep` wait is permission-denied — and improvising a different idle-wait is the same violation in another coat. If `await_test_done()` is missing from the deployed TestPlayer (version mismatch after a `init-project` upgrade), that is a harness defect: report `⛔ BLOCKED: await_test_done() unavailable on deployed TestPlayer — re-install scripts/test_player.gd via init-project`, do not improvise an alternative wait loop.

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

The parent is the bead representing the game (or the milestone epic if one exists); the helper wires `discovered-from` provenance and loop labels automatically. Report-filing and bead-filing are complementary: the report holds evidence, the bead holds the actionable queue entry. Per-task fast-verify/scene-verify FAILs do NOT file beads — the verdict returns to the caller (poppy) inline, who retries within the task's attempt budget.

If no file-write path exists in your session (write denied or tool absent), do NOT improvise writes through engine primitives (ConfigFile/FileAccess indirection) — return the verdict plus full report inline and state explicitly: "report could not be persisted; no write path." The caller will persist it. The orchestrator reads the file only on FAIL or when evidence is needed — a full report inline in the task result accumulates in every upstream session's context.

---

## One-Time Modes: functional, vision, critique

These run **once per game** (after all tasks complete), not per task — not before. Each has its own workflow, report format, and success criteria:

- **functional** — exhaustive mechanic verification: collect per-entity invariants via `glob("tests/scenarios/*.json")` + `read()`, apply the counter sanity gate (every game-economy counter needs a `max_delta_per_sec` rate invariant — a counter without a rate invariant is an unverified counter), then run a 60s chaos scenario with merged invariants. `start_test` returns immediately; the simulation runs autonomously between MCP calls.
- **vision** — creative-alignment check: 90s pursuit-bot observation, 6-8 evenly spaced screenshots (`responseMode: "preview"`) analyzed with the template above, rate each vision element ✅/⚠️/❌.
- **critique** — player-experience evaluation: the executing agent launches the game and drives it with **their own simulated inputs** (no scenario harness, no bots — `Input.is_action_pressed`-style polled controls are the reliably drivable pattern; see gotcha below), playing at a natural consumer pace for roughly 2-3 minutes; screenshots at moments of the agent's choosing; first-person present-tense narration grounded in captures; per the executing agent's role, README.md may be the only context consulted — never sources.

Full workflows, scenario configs, and report templates: [reference/full-modes.md](reference/full-modes.md).

**Rate-limitation gotcha:** start_test invariants are checked for `duration_s` of gameplay — do not confuse run_script probe timeouts (MCP client-side) with the scenario clock. As of godot-mcp-runtime v3.2.4, long in-engine waits in `run_script` bodies are safe (server heartbeats keep the request alive) — see `../create-entity/reference/mcp-patterns.md`.
