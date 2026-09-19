# One-Time Playtest Modes: functional, vision, critique

Loaded from `../SKILL.md` — these run once per game (after all tasks complete), not per task.
Referenced back as the full workflows behind the SKILL.md one-time-modes summary.

## Mode: functional

**When:** After all task beads are closed in the ledger
**Purpose:** Verify every mechanic works per spec — exhaustive, evidence-based, systematic

### Preamble: Read the spec

Read **the ledger** (bd list --status closed, completed task beads) and **README.md** (controls, rules, scoring, win conditions, game flow). This is your verification matrix.

### Step 0b: Collect per-entity invariants

`glob("tests/scenarios/*.json")` — each interactive entity created during `create-scene-with-script` has its own invariant config authored with real knowledge of that entity's node paths (see that skill's Step 5c). `read()` each file found and merge their `invariants` arrays into the scenario below, appended after the generic baseline. If no files are found, proceed with the baseline alone — not every project will have interactive entities yet.

**Counter sanity gate (mandatory):** for every game-economy counter you find in the collected `get_test_state()` dictionaries (score, currency, combo, ammo, lives — any monotonically accruing numeric), verify a `max_delta_per_sec` invariant exists for it in the collected set. If one is missing, ADD it to the merged invariants before running, sized to a plausible human ceiling for that game (e.g. a score that legitimately accrues ~1/second gets a ceiling of 5–10/sec). Rationale (see git log / gotchas.md "Observed 09-03"): a per-tick collision-handler bug inflated a score at 60/sec and won the game in one catch — every point-in-time invariant passed because the final value was individually "plausible"; only rate-of-change caught it. A counter with no rate invariant is an unverified counter.

### Step 1: Launch with scenario runner

Launch Godot with `background=true`, then run the full functional test scenario. Start from this baseline and append any invariants collected in Step 0b to the `invariants` array before calling `start_test`:

```gdscript
start_test(scenario={
    "scenario_id": "functional_verification",
    "duration_s": 60,
    "bot": {
        "type": "chaos",
        "seed": 123,
        "input_rate_hz": 15  # Higher rate for stress testing
    },
    "invariants": [
        { "name": "no_crash", "rule": "no_fatal_errors" },
        { "name": "no_physics_blowup", "rule": "nodes_finite" },
        { "name": "fps_stable", "rule": "custom", "path": "_meta.frame_ms_p99", "check": "below", "value": 33.3 },
        { "name": "min_30fps", "rule": "fps_floor", "value": 30 }
        # ...append entries from each tests/scenarios/*.json found in Step 0b here
    ]
})
```

**Rule names matter:** the harness matches `rule` exactly — an unknown name is a silent no-op (verification appears to pass while nothing is checked). See `./../init-project/reference/testing-patterns.md` for the canonical rule list. `no_fatal_errors` is a marker for process-level crash detection verified externally (crash kills the engine before the harness could check) — the other invariants do the in-run work.

### Step 2: Get structured report

```gdscript
# Inside ONE awaited run_script call (tool timeout sized to duration + margin):
var tp = scene_tree.root.get_node_or_null("TestPlayer")
# NOTE: pass positional args. `await f(max_wait_s = 45)` is NOT valid in an
# awaited expression — it compiles as a separate statement's parse error
# ("Assignment is not allowed inside an expression") on Godot 4.x.
var report = await tp.await_test_done(scenario_duration + 30)
# report = {
#   "status": "running" or "complete",
#   "violations": [ { "frame": N, "rule": ..., "detail": ..., "node"?: ... } ],
#   "metrics": { "start_frame": ..., "end_frame": ..., "input_count": ...,
#                "crash_detected": ..., "frame_times": [...],
#                "frame_ms_p99": ..., "fps_floor_violations": ... },
#   "frame_count": N
# }
```

### Step 3: Generate verification table

Run the report renderer (deterministic — the JSON-to-table transform is script territory, not prose):

```
../playtest/scripts/render_report.py <report.json>
```

It emits the standard table (Invariant | Status | Evidence rows for crash, physics stability, FPS p99, engine stalls, FPS floor, input responsiveness, plus one row per violation), an **Overall: PASS/FAIL** line, and the violation count. Exit code 1 when any violation is present. Columns present in `metrics` but not listed here are ignored; missing metrics simply omit their row. The engine-stalls row is **telemetry, not an invariant**: `stall_ticks_over_100ms` / `worst_frame_ms` / `warmup_resets` quantify host-side stalls (background throttle, display sleep, memory pressure — 10-12s frames observed overnight, run 12). A non-zero count renders as ⚠️ INFO with a pointer to the background-throttle gotcha; it never flips the PASS/FAIL verdict, and percentile metrics exclude stalled ticks by design.

### Post-report diagnostics: batch your probes

When violations appear and you need follow-up probes (`run_script` state queries, targeted restarts, input tests), **plan them as one batch before touching the engine**, then execute each probe as a single self-contained `run_script` (reset/reload state inside the script body before sampling — see the background-throttle gotcha). Serial one-question-per-call probing is the known cost sink: run 11's functional QA spent 14 `run_script` + engine round-trips across 36 turns for ~21 minutes (run 11 (lumo-max, 09-08)) — equivalent batched probes complete in a fraction of the wall time. Each `run_script` body can gather arbitrary state (query multiple nodes, sample multiple properties, drive input and then sample) and return it as one dictionary; only script-size judgment limits the batch. Probe-budget rules from SKILL.md still apply per violation group.

### Probe-authoring rules (learned the hard way)

- **Probe step 0: reset, then assert not paused.** Every probe begins with `scene_tree.paused = false` (if a lose/win handler pauses the tree) plus `reload_current_scene()` — a paused tree freezes physics while `await physics_frame` still resolves, so a probe run against a paused tree returns all-zero displacement readings that look like a broken game (observed run 13, 2026-09-09 OrbField: a QA probe chain diagnosed "steering broken" for multiple rounds; the tree had been paused by an accidental lose since the previous call). Assert your precondition (`paused == false`, score == 0, ball on floor) in the returned dict so a bad reset is visible, not silent.
- **Hold node PATHS, not node refs, across gameplay events.** A stored node variable dies with `queue_free()` — collecting/pickup handlers commonly free the entity, and reading `.visible` on a freed ref errors mid-probe (run 13: orb-collection verification failed twice on exactly this). Resolve `get_node_or_null(path)` fresh after each event, and guard with `is_instance_valid()` where an event may have freed the node.
- **Batch the whole mechanic suite into ONE awaited script.** The mature pattern (validated run 13): one script that reloads the scene, then sequentially verifies steering → collection → win → restart → lose → restart, reloading/re-centering between segments and sampling state after each input burst inside the same call. Inter-call gaps are where background throttle and idle-state drift corrupt results; inside one awaited call the engine ticks at full rate.
- **Long nested-dict scripts can arrive corrupted.** Multi-line nested dictionaries in inline `run_script` source have arrived at the engine with structural errors (`closing } with no opening`) that the author's copy did not contain (run 13, suspected transport mangling; upstream status: unconfirmed, repro pending). If a script errors at a line that looks syntactically fine in your source, do not debug your logic first — simplify the formatting (flatten nested dicts to single lines, split into multiple statements) and resend before concluding anything about the game.

### Success Criteria
- Full scenario runs for specified duration (no premature exit)
- Invariant checker evaluates all declared properties
- Report generated with structured metrics
- Overall PASS if `violation_count == 0`, FAIL otherwise
- Verdict reported in task result (PASS/FAIL)

Note: Screenshots taken only if violations detected — not as primary verification method.

---

## Mode: vision

**When:** After functional mode passes
**Precondition:** TestPlayer autoload registered (see Common Workflow)
**Purpose:** Evaluate whether the game matches the original creative vision — art direction, pacing, game feel, emotional core

### Step 1: Read VISION.md (vision statement, art style) and README.md (intended player experience)

### Step 2: Launch with extended observation scenario

```gdscript
start_test(scenario={
    "scenario_id": "vision_observation",
    "duration_s": 90,
    "bot": {
        "type": "pursuit"  # use "replay" only when a recorded input session exists (replay requires a prior recording)
        "agent_path": "/root/Game/Player",  # Configure per game
        "target_path": "/root/Game/Enemy",  # Target to pursue
        "deadzone": 10.0  # Movement deadzone
    },
    "invariants": [
        { "name": "no_crash", "rule": "no_fatal_errors" }
    ]
})
```

### Step 3: Observation session (90 seconds)

`start_test` returns immediately and the simulation runs autonomously. **Capture 6-8 screenshots evenly spaced across the run** (~one every 12-15s — place `take_screenshot` calls at different points in the 90-second window; the engine keeps simulating between MCP calls, so each lands on a different phase of gameplay). Use `responseMode: "preview"` to keep token cost down. Judging pacing, art direction, and game feel from 2-3 frames is guesswork — temporal coverage is the point of this mode. Analyze each screenshot with the analysis template (line 10); extra captures without full analysis are acceptable and available for debugging.

Analyze the returned data:
- **Pacing:** Does gameplay tempo match vision? (check interaction lengths from report)
- **Visual feedback:** Are impacts, scores, wins visually clear? (review spot screenshots)
- **Tension curve:** Does difficulty ramp appropriately? (analyze success/failure rates)

**Evidence channels — programmatic text beats pixel reading.** Screenshots lead the verdict only for what is inherently visual (composition, lighting, motion trails). For anything textual or numeric — HUD counters, score displays, end-screen messages — sample the value programmatically (`get_ui_elements`, or a read-only `run_script` returning `label.text` / `get_test_state()` fields) instead of reading it off the image. Small HUD text at camera distance is routinely illegible or misread even in `responseMode: "full"` (observed run 13, 2026-09-09 OrbField: a vision check narrated "'Orbs: 1 / 8'? … I believe (can't fully read)" and had to hedge its verdict). A vision rating grounded in "I think it says" is a downgrade of the whole gate — query the text, cite the query. Also beware idle-frame aliasing: in background mode the engine may idle between calls, so consecutive screenshots can land on the same rest state — a static capture series is NOT evidence of a frozen or unresponsive game (verify with a probe before claiming it).

### Step 4: Stop and evaluate

```
## Vision Achievement Report

**Vision:** [from VISION.md]

**Rating per element** (✅/⚠️/❌):
- Emotional core: [assessment]
- **Art direction:** [assessment based on screenshots]
- **Game feel:** [assessment based on response times]
- **Pacing:** [assessment based on interaction/session length stats]

**Overall: HIGH / MEDIUM / LOW**

**Strengths:** [what delivered, reference specific metrics]
**Gaps:** [what missed, reference specific observations]
**Next:** [improvements with priority]
```

### Success Criteria
- 90-second observation session completes (or game over)
- 6-8 screenshots taken across the session (visual descriptions provided)
- Each vision element rated ✅/⚠️/❌ with reasoning
- Verdict reported in task result (HIGH/MEDIUM/LOW rating)

---

## Mode: critique

**When:** After the functional-QA and vision gates both pass
**Precondition:** none beyond a launchable project — the critic needs no TestPlayer harness (playing it yourself IS the test)
**Purpose:** Consumer evaluation — is it beautiful, is it fun, would a real player care?

### Step 1: Read README.md only (controls, rules, scoring, game flow, art style)

Never read source files, scene files, or the ledger.

### Step 2: Launch the game and play it yourself

No scenario harness, no bot, no invariants — launch the project and drive it
with your own simulated inputs at a natural consumer pace for roughly 2-3
minutes. This is the entire point of the mode: the executing agent's hands
on the controls, not a harness replaying canned inputs.

Reliable input-driving patterns (the synthetic-input gotcha applies — see
SKILL.md Common Workflow):
- `simulate_input` key/action events for `Input.is_action_pressed`-polled
  controls (press + wait ~2 frames + release, in sequence, at your own pace)
- `Input.parse_input_event` probes for menu/restart handlers
- Pause between inputs and take screenshots at moments YOU choose —
  significant or suspicious — grounded in what you actually observe

If controls genuinely don't respond to either input path, that's an
observation for the report — see Part B before calling it a bug.

### Step 3: Play session — two parts

Critique has two distinct jobs, done in order. **Part A plays the game as a consumer; Part B gates failure claims before they reach the verdict.** A critique that skips Part B risks REWORK-ing a working game (observed 09-04, qwen run: three consecutive REWORK verdicts, all harness-path artifacts); a critique that skips Part A loses the consumer lens and reduces to functional testing.

#### Part A: Your own playthrough (chosen-moment screenshots)

You ARE the player — hands on, natural pace, narrating live. Screenshots at
moments you choose (roughly 6-10 over the session; trust your judgment for
what's significant). Use `responseMode: "preview"` to keep token cost down.
Ground your narration in what you actually saw and did; first-person present
tense.

Narrate what you see — pacing, feel, readability, "would I keep playing".
Screenshots here may show symptoms (stuck screens, dead overlays) — record
them as *observations*, not verdicts.

**Observation honesty (mandatory):** every fact you narrate or flag — scores,
rally counts, on-screen text, colors — must come from a screenshot or probe
output you actually inspected in this session. NEVER infer state ("the score
probably incremented", "rally 12 by now") from elapsed time or expected game
behavior and present it as observed. If a fact matters to your critique but
you didn't capture it, say so explicitly ("score display not captured —
couldn't verify") rather than filling the gap. Fabricated observations poison
the REWORK gate downstream: an inferred "bug" can trigger a rebuild of working
code. Signature (run 11, run 11 (lumo-max, 09-08)): background-mode idle advance to GAME_OVER between MCP calls meant every screenshot showed the post-game default — seeding a false "HUD stuck at 0" verdict claim; the functional-QA probe evidence contradicted it, caught only by root cross-check. An honest "HUD unverified — captures all post-game" note would have cost nothing.

**Narration-screenshot correspondence (mandatory):** your narration timeline and your screenshot timeline must correspond one-to-one. Anything you describe as having happened SINCE your last capture must be visible in the NEXT capture, or you retract the description before continuing (observed run 13, 2026-09-09 OrbField: narrated score counts contradicted by the captures themselves — every frame since a first fall showed the frozen Game Over screen, caught only when the counter appeared to go DOWN; several narrated events retracted mid-report). The practical habit: never describe an event you have not yet captured; if you acted since the last capture and haven't re-captured, say "took action, result not yet on screen" instead of narrating an outcome.

#### Part B: Probe gate for failure claims (mandatory)

Before ANY of the following appears in your verdict — "controls unresponsive", "stuck", "bricked", "restart broken", "boot loses instantly", "unplayable" — you MUST verify with a scripted probe:

1. Consult the two gotchas in SKILL.md's Common Workflow (background-mode idle throttling; synthetic input invisible to `_unhandled_input`/edge-detected handlers).
2. Drive the suspect interaction yourself via a `run_script` probe: `Input.parse_input_event` for key/menu handling, programmatic state queries (`get_node` + property reads) for game-state transitions, or programmatic scene reload for restart flows. Sample state *after* the input, inside the same awaited script body.
3. Check the input map actually contains the advertised bindings — a dead binding (keycode 0) is a real bug the action-press path can expose.

If the probe confirms the behavior (game state genuinely doesn't respond), it is a game bug — REWORK with the evidence. If the probe shows the game responding (state changes, scene reloads), the Part-A symptom was a harness artifact — drop the failure claim from the verdict and note the artifact in the report's hand-off section instead.

Failure claims that appear in a verdict without a Part B probe are invalid on review.

At each significant moment, note how you experienced it while playing (first-person, present tense), grounded in what actually happened:

```
**Player reactions:** [reaction keyed to events, present tense]
"That's how the object moves… nice and responsive."
"Missed that one — but it felt fair; the angle was readable."
```

### Step 4: Stop and critique

```
**Key moments:** [up to 3 timestamps grounded in actual events from report, or "nothing notable"]
- T=23s: Perfect deflection against odds (replay_t23.png)
- T=87s: Epic interaction, 15 exchanges (replay_t87.png)

**Frustration risk:** [moments a player would give up on, or "held attention"]
- "The learning curve feels smooth — no frustrating spikes detected"

**Verdict:** [one-sentence takeaway a player would give a friend]
"This one's got juice — I want to keep playing it."

**Probe results:** [for every observed failure symptom: what the Part B probe showed, or "no failure symptoms observed"]
- "GAME OVER restart verified via parse_input_event probe — scene reloaded cleanly; Part A stall was a background-throttle artifact"

**Hand-off:** [bugs/crashes flagged from violation report, or "looked clean"]
```

If game crashes: stop immediately, hand off with abort reason and violation details.

### Success Criteria
- 2-3 minute self-driven play session (or game over/crash) — inputs issued by the critic, not a bot
- 6-10 screenshots at the critic's chosen moments, narration grounded in what they show
- All six critique sections produced (incl. Probe results)
- Every failure claim in the verdict backed by a Part B probe
- **Recommendation** (not verdict) reported in task result: `RECOMMEND_SHIP` or `RECOMMEND_REWORK` + B-hole rating. The ship/rework/vision-revision decision belongs to the orchestrating roles per their own instructions, not to the critic — the critique is one input to that disposition, never the disposition itself.
- **Audio blindness disclosed:** the critic experiences the game via screenshots and state readback and cannot hear. The report must not narrate sound effects or music as lived experience; audio observations (if any) go in a clearly-marked NOTE based only on README promises or code/configuration evidence, never on invented listening.

