# Signal Wiring Verification Procedure

**Upstream retirement:** This procedure will be replaced by `verify_node_connections` tool (upstream bead 8nk). Until then, use this manual verification.

## Connection Method Selection

Choose the weakest coupling that works:
- **Static connections** (known at design time) → `godot-mcp-runtime:connect_signal()` (persists in `.tscn`)
- **Conditional/runtime connections** → Code-based in `_ready()` (`signal.connect(method.bind(...))`)

## Handler Requirements

Callback methods must:
1. Accept the same parameter list as the signal (signature mismatch = silent no-op or runtime error)
2. Follow `_on_<node>_<signal>` naming (e.g., `_on_ball_body_entered`) for debuggability
3. Exist on the receiving node before the connection fires

## Mandatory Verification (4-Point Check)

After wiring signals, verify all four:

1. **Connection present**: `godot-mcp-runtime:get_node_signals(nodePath)` shows the connection (target, method)
2. **Handler executes**: Fire manually at runtime (`run_script` or input) → confirm the handler runs and produces the expected effect
3. **No errors**: Inspect `godot-mcp-runtime:get_debug_output()` for `SCRIPT ERROR`, "method not found", "signal not connected" backtraces
4. **Fix & re-verify**: If missing/mismatched → re-wire or fix the signature, then repeat all 4 steps

## Common Failure Patterns

- **Orphaned handlers**: `_on_X_connected` method exists but the signal was never connected
- **Missing handlers**: Signal connected but the method doesn't exist (runtime error on emit)
- **Signature mismatch**: Method accepts wrong parameters (silent no-op or crash)
- **Timing errors**: Handler created after the signal fires (race condition)

## Example

```gdscript
# In the consumer node's script:
func _ready():
    $Ball.body_entered.connect(_on_ball_body_entered)

func _on_ball_body_entered(body):
    # Handle the event
    pass
```

Verification:
1. `get_node_signals($Ball)` → shows `body_entered` connected to `_on_ball_body_entered`
2. Trigger ball-body collision → observe handler execution
3. `get_debug_output()` → no errors
4. If any step fails → fix and re-verify
