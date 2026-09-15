# Worked Examples

> Three canonical entity types. Read the one matching your entity before creating scenes.
> See also [physics-nodes.md](physics-nodes.md) for the full decision tree.

## Example 1: Player-controlled entity (CharacterBody2D with collision)

Input: "Create a controllable player entity, moved by W/S keys"

Output:
- `scenes/player.tscn` — CharacterBody2D root, CollisionShape2D (RectangleShape2D 20x100), Sprite2D
- `scripts/player.gd` — `extends CharacterBody2D`, `_physics_process` reads `move_up`/`move_down` actions via `Input.get_axis`, sets `velocity`, calls `move_and_slide()`

> **Do not type a player as Area2D** — Area2D is for trigger zones/pickups/hazards, not movement (see SKILL.md Step 1b and [physics-nodes.md](physics-nodes.md)). A player controlled by input is always CharacterBody2D.

## Example 2: Trigger zone / pickup (Area2D)

Input: "Create a pickup that the player collects on overlap"

Output:
- `scenes/pickup.tscn` — Area2D root, CollisionShape2D (CircleShape2D r=10), Sprite2D
- `scripts/pickup.gd` — `extends Area2D`, `body_entered` signal → `_on_body_entered` handler; no `_physics_process`

## Example 3: Physics object (RigidBody2D)

Input: "Create an object that bounces off walls and collides with entities"

Output:
- `scenes/projectile.tscn` — RigidBody2D root, CollisionShape2D (CircleShape2D r=10), Sprite2D
- `scripts/projectile.gd` — `extends RigidBody2D`, `contact_monitor=true`, `max_contacts_reported=10`, signal `body_entered` → `_on_body_entered`
