# Driving the live engine (canonical reference)

Everything a specialist needs to actuate and observe a RUNNING Godot project
under the MCP bridge, in one place. Read this before your first
`run_script` probe, `simulate_input`, or engine-state check — the facts
below were each re-derived independently (at 10-60 min cost per session) by
QA, vision, and acceptance specialists who didn't have this document.

**Rule of channels:**

| Need | Channel | Never use |
|---|---|---|
| Verify a gameplay mechanic/timing/invariant | TestPlayer scenario (`start_test` + one awaited report) | manual `create_timer` probing between calls |
| Read game state (score, phase, positions) | `run_script` returning `{key: value}` summaries | screenshots |
| Drive input into a running game | `simulate_input` (key events) or scenario input map | `Input.action_press` for polled axes |
| Judge aesthetics/layout | screenshot + `read` | state probes |

## The facts

1. **TestPlayer scenarios are the evidence channel of record** for anything
   timing-dependent (serve delays, rally survival, win/loss pacing). Manual
   probing — `create_timer` callbacks, `await`s split across separate
   `run_script` calls — is unreliable: macOS background throttles the
   hidden window, frame advance between calls is unpredictable, and each
   probe round-trip costs a full model turn. If the question is "does X
   happen after Y seconds of gameplay", it is a scenario with an
   invariant, not a probe.

2. **Input: `simulate_input` key events reach `_input` handlers.**
   `Input.action_press()` does NOT reliably drive `get_axis`/`get_action_pressed`
   polling in background mode, and it registers `just_pressed` for only the
   exact press frame. Event-driven handlers (`_unhandled_input`) need
   actual events — see the synthetic-input gotcha in `gotchas.md` for the
   full compatibility matrix.

3. **Auto-serving games auto-serve.** Rally/serve-loop games commonly
   launch the serve ~1s after (re)start with no key required. Before
   concluding "the serve never fires" or "input is dead", wait one second
   of sim time inside an awaited script and re-read state — do not build
   a key-press ladder to coax the serve.

4. **Do not teleport entities to drive gameplay.** Moving the paddle (or
   any player-controlled body) directly via `position =` while physics is
   live corrupts the state under test — observed as "ball parked
   off-screen forever" that was the *probe's own interference*, not a game
   bug. If you must arrange a state, do it inside a scenario setup, paused,
   or after a scene reload at the START of the probe script.

5. **State resets belong at probe start.** A stateful game advances while
   you think between calls; a probe that returns an unexpected end-state
   should first be retried with a scene-reload/reset as the probe's first
   lines before anyone diagnoses game code.

6. **Read state via node text and getters, not pixels.** Scores, prompts,
   and panel visibility are deterministic via `get_node(...).text` /
   `run_script` state returns. Screenshot digit misreads ("2" vs "6") are
   expected — never reconcile a state discrepancy with more screenshots.

## Framing for expectations

A question of the form "does the engine behave like X?" (timing, rates,
scheduling) was likely already answered by a sibling specialist paying full
price. Check this document and `gotchas.md` before the first hypothesis —
the three most expensive sessions of a recent run spent 40+ reasoning
paragraphs each re-deriving facts 1-5 above.
