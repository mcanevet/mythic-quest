# project.godot Template

Godot 4.x `project.godot` content to copy verbatim as the project root file.
Replace `<title read from VISION.md line 1>` with the game title from
`VISION.md` line 1 (or `"Untitled Game"` if `VISION.md` does not exist).

**Before writing, discover the installed Godot version** (via the engine MCP
tooling's project-info capability, e.g. `get_project_info`) and use its major
engine version in `config/features` — do NOT copy the `<VERSION>` placeholder
literally. A hardcoded version string that doesn't match the installed engine
causes import/config warnings and can fail headless runs.

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.
;
; Format:
;   [section] ; section goes between []
;   param=value ; assign values to parameters

config_version=5

[application]

config/name="<title read from VISION.md line 1>"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("<VERSION from get_project_info>", "2D")
config/icon="res://icon.svg"

[display]

window/size/viewport_width=960
window/size/viewport_height=540
window/stretch/mode="canvas_items"

[input]

; Input actions are game-specific — do not add defaults here.
; Task 1 will add the correct actions based on VISION.md.

[rendering]

renderer/rendering_method="forward_plus"
```
