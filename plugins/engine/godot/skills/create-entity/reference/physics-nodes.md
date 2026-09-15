# Physics Node Patterns

## Choosing the Right Node Type

Choose based on **what the entity DOES**, not game genre:

```
Entity Role                        → Recommended Node Type
──────────────────────────────────────────────────────────
Moves by player input              → CharacterBody2D  (jump, move, respond to input)
Moves by physics forces            → RigidBody2D      (bounce, fall, collide naturally)
Detects overlaps (no physics)      → Area2D           (trigger zones, pickups, hazards)
Immovable geometry                 → StaticBody2D     (walls, floors, platforms)
Animated decoration                → Sprite2D / AnimatedSprite2D (no physics)
Text/info display                  → Label / RichTextLabel
Interactive UI                     → Button / Control hierarchy
```

**Decision guide:**
- Player-controlled entities → **CharacterBody2D** (predictable, responsive)
- Physics-driven entities (bouncing, chain reactions) → **RigidBody2D** (natural, less controllable)
- Entities that BOTH respond to input AND physics → **CharacterBody2D** with manual force simulation

## Collision Shape Setup

**Primary path — MCP tools with inline Resource construction** (typed-dict values in `add_node`/`set_node_properties`; writes are validated and persist as `[sub_resource]` blocks; upstream status in SKILL.md Step 5a):

```
add_node(
  node_type="CollisionShape2D", node_name="ColShape", parent_node_path="Entity1",
  properties={ "shape": { "type": "RectangleShape2D", "size": { "x": 20, "y": 100 } } }
)
```

Or after the fact: `set_node_properties` with `property: "shape"`, `value: {type: "RectangleShape2D", size: {x: 20, y: 100}}`.

**Reference — what the persisted scene looks like** (the tools produce this automatically; direct-edit is denied — ⛔ BLOCKED if the tools cannot express it):

```ini
[gd_scene format=3]

[sub_resource type="RectangleShape2D" id="shape_1"]
size = Vector2(20, 100)

[node name="Entity1" type="Area2D" parent="."]
collision_layer = 1
collision_mask = 2

[node name="CollisionShape2D" type="CollisionShape2D" parent="Entity1"]
shape = SubResource("shape_1")
```

**Alternative (runtime only, not persisted):**
```gdscript
var col_shape = get_node("/root/Entity1/CollisionShape2D")
var shape = RectangleShape2D.new()
shape.size = Vector2(20, 100)
col_shape.shape = shape
```

**RigidBody2D critical config** (if used):
- `contact_monitor = true` is REQUIRED for collision signals to fire (defaults to false!)
- `max_contacts_reported` must be > 0 (e.g., 1-10)
- Use `linear_velocity` for movement, NOT `velocity` (velocity is CharacterBody2D API)

**Gotchas:**
- StaticBody2D is for immovable geometry — if entity moves, do NOT use StaticBody2D
- CharacterBody2D uses `move_and_slide()` for movement
- RigidBody2D uses `apply_force()`/`apply_impulse()` for physics

## Common Validation Errors

If validator fails on "missing shape property":
1. Check `[sub_resource]` blocks exist after `[gd_scene format=3]`
2. Verify `shape = SubResource("shape_X")` references correct ID
3. Run validator: `<skill-path>/scripts/validate.sh scenes/main.tscn`
