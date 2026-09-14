---
name: init-project
description: Scaffold a Godot project with project.godot, icon.svg, and .gitignore. Use when starting a new Godot game project.
---

## What I do

Creates the minimal Godot project structure:
- `project.godot` — Godot project configuration (4.x format)
- `icon.svg` — Default project icon
- `.gitignore` — Standard Godot ignore patterns

## Execution

### Step 1: Create project.godot

Write `project.godot` with:
```ini
; Godot 4.x project configuration
config_version=5

[application]
config/name="[Game Name]"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.2", "Forward Plus")

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080

[input]
; Input actions defined as features are implemented

[rendering]
renderer/rendering_method=forward_plus
```

### Step 2: Create icon.svg

Write a placeholder SVG icon (or copy from a template).

### Step 3: Create .gitignore

```
# Godot 4+
.godot/
.export/
*.import

# Editor
.project.godot.editor/
.vscode/

# OS junk
.DS_Store
Thumbs.db
```

## Validation

Run `validate.sh` (if present) or manually verify:
- ✅ `project.godot` exists with config_version=5
- ✅ `icon.svg` exists
- ✅ `.gitignore` exists with standard patterns
