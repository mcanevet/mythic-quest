# scripts/test_player.gd
# Game-agnostic test harness autoload — scenario-based playtesting framework.
# Provides start_test(), get_test_report(), and configurable bot behavior.
# Register as autoload via godot-mcp-runtime:add_autoload() at playtest time.

extends Node

# === STATE ===
var _scenario = {}
var _running = false
var _frame_count = 0
var _violations = []
var _violation_counts = {}
var _held_inputs = {}
var _metrics = {
	"start_frame": 0,
	"end_frame": 0,
	"input_count": 0,
	"crash_detected": false,
	"frame_times": [],
	"frame_ms_p99": 0.0,
	"fps_floor_violations": 0,
	"stall_ticks_over_100ms": 0,
	"warmup_resets": 0,
	"worst_frame_ms": 0.0
}
var _rng = RandomNumberGenerator.new()
var _input_actions = []
var _nav_agent = null
var _navigation_goal = null

var _last_time = 0.0
var _warmup_remaining = 3  # settled-ticks required before timing/invariants count
var _rule_prev_values: Dictionary = {}  # rule_name -> {"samples": [{tick, value}]} for windowed delta-rate checks
var _frame_time_buffer_size = 300
var _ticks_per_second = 60

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func start_test(scenario: Dictionary) -> Dictionary:
	_scenario = scenario
	_running = true
	_frame_count = 0
	# Reset warm-up state: a second start_test() in the same process must not
	# inherit the previous test's settle status or last-tick timestamp — the
	# gap between tests (engine idle between MCP calls) would otherwise be
	# sampled as a single multi-second "frame" and trip fps_stable.
	_warmup_remaining = 3
	_last_time = 0.0
	_rule_prev_values.clear()
	_ticks_per_second = Engine.physics_ticks_per_second
	_violations.clear()
	_violation_counts.clear()
	_held_inputs.clear()
	_metrics = {
		"start_frame": Engine.get_physics_frames(),
		"end_frame": 0,
		"input_count": 0,
		"crash_detected": false,
		"frame_times": [],
		"frame_ms_p99": 0.0,
		"fps_floor_violations": 0,
		"stall_ticks_over_100ms": 0,
		"warmup_resets": 0,
		"worst_frame_ms": 0.0
	}
	_rng.seed = scenario.get("bot", {}).get("seed", 42)
	
	_input_actions = InputMap.get_actions()
	_input_actions.erase("ui_accept")
	_input_actions.erase("ui_select")
	_input_actions.erase("ui_cancel")
	_input_actions.erase("ui_focus_next")
	_input_actions.erase("ui_focus_prev")
	_input_actions.erase("ui_left")
	_input_actions.erase("ui_right")
	_input_actions.erase("ui_up")
	_input_actions.erase("ui_down")
	_input_actions.erase("ui_page_up")
	_input_actions.erase("ui_page_down")
	_input_actions.erase("ui_home")
	_input_actions.erase("ui_end")
	
	var bot_cfg = scenario.get("bot", {})
	if bot_cfg.get("type") == "nav_agent":
		_setup_nav_agent(bot_cfg)
	
	print("[TestHarness] Started: bot=%s duration=%ss invariants=%d" % [
		scenario.get("bot", {}).get("type", "chaos"),
		scenario.get("duration_s", 15),
		scenario.get("invariants", []).size()
	])
	return {"status": "started"}

func get_test_report() -> Dictionary:
	if not _metrics.frame_times.is_empty():
		_metrics["frame_ms_p99"] = _compute_p99(_metrics.frame_times)
	# Snapshot: return a duplicate of the violations array and its entries.
	# Callers store the returned report across multiple scenarios (loop
	# start_test/await_test_done); a later start_test() clears the live
	# array, which previously emptied EARLIER reports' violations lists
	# retroactively (observed as "violations: 1, violation_details: []").
	_violations = _violation_counts.values()
	_violations.sort_custom(func(a, b): return a["first_frame"] < b["first_frame"])
	return {
		"status": "running" if _running else "complete",
		"violations": _violations.duplicate(true),
		"metrics": _metrics.duplicate(true),
		"frame_count": _frame_count
	}

func finish_test() -> Dictionary:
	if not _running: return get_test_report()
	_running = false
	_metrics["end_frame"] = Engine.get_physics_frames()
	for action in _input_actions:
		Input.action_release(action)
	_held_inputs.clear()
	if _nav_agent:
		_nav_agent = null
	print("[TestHarness] Finished: %d violation groups, %d inputs" % [_violation_counts.size(), _metrics["input_count"]])
	return get_test_report()

## Blocking counterpart to start_test()/get_test_report() polling: waits
## inside one run_script body until the scenario completes, then returns the
## final report. Use this from an awaited run_script (tool `timeout` sized
## to duration_s plus margin) instead of poll-across-MCP-calls sleep loops:
## the engine keeps ticking normally while the call is open (no background
## idle-throttling) and the result arrives in a single tool call.
func await_test_done(max_wait_s: float = 120.0) -> Dictionary:
	var deadline_ms := Time.get_ticks_msec() + int(max_wait_s * 1000.0)
	while _running and Time.get_ticks_msec() < deadline_ms:
		await get_tree().physics_frame
	if _running:
		push_warning("[TestHarness] await_test_done timed out after %ss; returning incomplete report" % max_wait_s)
	return get_test_report()

func _physics_process(delta):
	if not _running: return

	var current_time = Time.get_ticks_msec() / 1000.0
	# Warm-up: the first physics ticks after launch include engine startup
	# (shader compilation, resource streaming) measured as 25,000-40,000ms
	# "frames" — not game performance (startup measured p99 up to ~40s on a
	# healthy run, causing false fps_stable violations). Discard samples until
	# three consecutive sub-100ms ticks say the engine has settled.
	if _warmup_remaining > 0:
		if _last_time > 0:
			var frame_ms = (current_time - _last_time) * 1000.0
			if frame_ms < 100.0:
				_warmup_remaining -= 1
			else:
				# Telemetry (do not discard silently): a >100ms tick here is a
				# stall — host suspension, background throttle, or display
				# sleep (10-12s frames observed overnight, run 12). Counted in
				# warmup_resets/stall_ticks_over_100ms so throttled periods
				# remain VISIBLE in the report even though they pollute
				# frame_ms percentiles and are excluded from them.
				_metrics["warmup_resets"] += 1
				_metrics["stall_ticks_over_100ms"] += 1
				_metrics["worst_frame_ms"] = maxf(_metrics["worst_frame_ms"], frame_ms)
				_warmup_remaining = 3
		_last_time = current_time
		_frame_count += 1
		return
	if _last_time > 0:
		var frame_ms = (current_time - _last_time) * 1000.0
		if frame_ms >= 100.0:
			# Telemetry: stall tick AFTER warm-up (post-startup). Excluded from
			# the percentile buffer (pollutes averages) but counted, not dropped.
			_metrics["stall_ticks_over_100ms"] += 1
			_metrics["worst_frame_ms"] = maxf(_metrics["worst_frame_ms"], frame_ms)
		_metrics.frame_times.append(frame_ms)
		if _metrics.frame_times.size() > _frame_time_buffer_size:
			_metrics.frame_times.pop_front()
	
	_last_time = current_time
	
	_frame_count += 1
	
	var duration_s = _scenario.get("duration_s", 15)
	if _frame_count >= int(duration_s * _ticks_per_second):
		finish_test()
		return
	
	var bot_cfg = _scenario.get("bot", {})
	var bot_type = bot_cfg.get("type", "chaos")
	
	match bot_type:
		"chaos":
			_run_chaos_bot(bot_cfg)
		"pursuit":
			_run_pursuit_bot(bot_cfg)
		"replay":
			_run_replay_bot(bot_cfg)
		"nav_agent":
			_run_nav_agent_bot(bot_cfg)
		_:
			_run_chaos_bot(bot_cfg)
	
	_check_invariants()

func _run_chaos_bot(cfg: Dictionary):
	var rate = cfg.get("input_rate_hz", 10)
	var fire_every = max(1, int(_ticks_per_second / rate))
	if _frame_count % fire_every != 0: return
	
	if _input_actions.is_empty(): return
	
	var action = _input_actions[_rng.randi() % _input_actions.size()]
	_press_action(action)
	call_deferred("release_action", action)

func _press_action(action: String):
	if _held_inputs.has(action):
		return
	_held_inputs[action] = true
	Input.action_press(action)
	_metrics["input_count"] += 1

func release_action(action: String):
	if not _held_inputs.has(action):
		return
	_held_inputs.erase(action)
	Input.action_release(action)

func _run_pursuit_bot(cfg: Dictionary):
	var agent_path = cfg.get("agent_path", "")
	var target_path = cfg.get("target_path", "")
	
	if agent_path == "" or target_path == "": 
		_run_chaos_bot(cfg)
		return
	
	var root = get_tree().root if get_tree() else null
	if not root: return
	
	var agent = root.get_node_or_null(NodePath(agent_path))
	var target = root.get_node_or_null(NodePath(target_path))
	if not agent or not target:
		_report_violation("pursuit_bot_config", agent_path, "Agent or target node not found (agent=%s target=%s) — bot issued NO input. Fix agent_path/target_path; do not treat this run as a valid pursuit exercise." % [agent_path, target_path])
		return
	
	var action_map = cfg.get("actions", {})
	var right_action = action_map.get("right", _find_action(["move_right", "right", "ui_right"]))
	var left_action = action_map.get("left", _find_action(["move_left", "left", "ui_left"]))
	var up_action = action_map.get("up", _find_action(["move_up", "up", "ui_up"]))
	var down_action = action_map.get("down", _find_action(["move_down", "down", "ui_down"]))
	if not (right_action or left_action or up_action or down_action):
		_report_violation("pursuit_bot_config", agent_path, "No movement actions found by convention or override — bot issued NO input. Specify the 'actions' override mapping this game's InputMap names.")
		return
	
	var dx = target.position.x - agent.position.x
	var dy = target.position.y - agent.position.y
	var deadzone = cfg.get("deadzone", 10.0)
	
	if right_action and dx > deadzone:
		_press_action(right_action)
	elif right_action:
		release_action(right_action)
	if left_action and dx < -deadzone:
		_press_action(left_action)
	elif left_action:
		release_action(left_action)
	if down_action and dy > deadzone:
		_press_action(down_action)
	elif down_action:
		release_action(down_action)
	if up_action and dy < -deadzone:
		_press_action(up_action)
	elif up_action:
		release_action(up_action)

func _run_replay_bot(cfg: Dictionary):
	var inputs = cfg.get("inputs", [])
	if inputs.is_empty():
		_run_chaos_bot(cfg)
		return
	
	for entry in inputs:
		if entry.get("frame", -1) == _frame_count:
			var action = entry.get("action", "")
			var pressed = entry.get("pressed", true)
			if action != "":
				if pressed:
					_press_action(action)
				else:
					release_action(action)

func _run_nav_agent_bot(cfg: Dictionary):
	if not _nav_agent:
		_setup_nav_agent(cfg)
		if not _nav_agent:
			_report_violation("nav_agent_bot_config", "agent", "No NavigationAgent2D/3D found on/under agent_path — nav_agent bot cannot run. Configure a navigation-capable agent or use a different bot type.")
			return
	
	var target_pos = _navigation_goal.global_position if _navigation_goal else null
	if not target_pos:
		_report_violation("nav_agent_bot_config", "target", "Navigation goal not found (target_path unset and no default group) — nav_agent bot has no destination. Configure target_path.")
		return
	
	_nav_agent.target_position = target_pos
	
	var next_path_pos = _nav_agent.get_next_path_position()
	var agent = _nav_agent.get_parent()
	
	var action_map = cfg.get("actions", {})
	var right_action = action_map.get("right", _find_action(["move_right", "right", "ui_right"]))
	var left_action = action_map.get("left", _find_action(["move_left", "left", "ui_left"]))
	var up_action = action_map.get("up", _find_action(["move_up", "up", "ui_up"]))
	var down_action = action_map.get("down", _find_action(["move_down", "down", "ui_down"]))
	if not (right_action or left_action or up_action or down_action):
		_report_violation("nav_agent_bot_config", str(_navigation_goal.get_path() if _navigation_goal else "unset"), "No movement actions found by convention or override — bot issued NO input. Specify the 'actions' override mapping this game's InputMap names.")
		return
	
	var dx = next_path_pos.x - agent.position.x
	var dy = next_path_pos.y - agent.position.y
	var deadzone = cfg.get("deadzone", 10.0)
	
	if right_action and dx > deadzone:
		_press_action(right_action)
	elif right_action:
		release_action(right_action)
	if left_action and dx < -deadzone:
		_press_action(left_action)
	elif left_action:
		release_action(left_action)
	if down_action and dy > deadzone:
		_press_action(down_action)
	elif down_action:
		release_action(down_action)
	if up_action and dy < -deadzone:
		_press_action(up_action)
	elif up_action:
		release_action(up_action)

func _setup_nav_agent(cfg: Dictionary):
	var actor_path = cfg.get("actor", "")
	var goal_path = cfg.get("goal", "")
	
	if actor_path == "":
		_nav_agent = null
		return
	
	var root = get_tree().root if get_tree() else null
	if not root:
		_nav_agent = null
		return
	
	var actor = root.get_node_or_null(NodePath(actor_path))
	if not actor:
		_nav_agent = null
		return
	
	_nav_agent = actor.get_node_or_null("NavigationAgent2D")
	if not _nav_agent:
		_nav_agent = actor.get_node_or_null("NavigationAgent3D")
	
	if not _nav_agent:
		if actor is NavigationAgent2D or actor is NavigationAgent3D:
			_nav_agent = actor
	
	if not _nav_agent:
		printerr("[TestHarness] nav_agent bot: No NavigationAgent2D/3D found on actor '%s'" % actor_path)
		_nav_agent = null
		return
	
	if goal_path != "":
		_navigation_goal = root.get_node_or_null(NodePath(goal_path))
		if not _navigation_goal:
			var groups = get_tree().get_nodes_in_group(goal_path)
			if not groups.is_empty():
				_navigation_goal = groups[0]
			else:
				printerr("[TestHarness] nav_agent bot: Goal '%s' not found" % goal_path)
				_navigation_goal = null
	else:
		_navigation_goal = null

func _find_action(candidates: Array) -> String:
	for c in candidates:
		if _input_actions.has(c):
			return c
	return ""

func _compute_p99(arr: Array) -> float:
	if arr.is_empty(): return 0.0
	var sorted_arr = arr.duplicate()
	sorted_arr.sort()
	var idx = int(sorted_arr.size() * 0.99)
	idx = min(idx, sorted_arr.size() - 1)
	return sorted_arr[idx]

func _report_violation(rule_name: String, node_path: String, detail: String):
	var key = "%s|%s" % [rule_name, node_path]
	if _violation_counts.has(key):
		var entry = _violation_counts[key]
		entry["count"] += 1
		entry["last_frame"] = _frame_count
		entry["detail"] = detail
	else:
		_violation_counts[key] = {
			"frame": _frame_count,
			"rule": rule_name,
			"node": node_path,
			"first_frame": _frame_count,
			"last_frame": _frame_count,
			"count": 1,
			"detail": detail,
		}

func _check_invariants():
	var invariants = _scenario.get("invariants", [])
	for rule in invariants:
		var rule_name = rule.get("name", "unknown")
		var rule_check = rule.get("rule", "")
		
		match rule_check:
			"no_fatal_errors":
				pass
			"nodes_finite":
				_check_finite_positions(rule_name)
			"nodes_in_bounds":
				_check_bounds(rule_name, rule)
			"no_null_refs":
				_check_null_refs(rule_name)
			"frame_time_p99_below":
				_check_frame_time_p99(rule_name, rule)
			"fps_floor":
				_check_fps_floor(rule_name, rule)
			"no_nan_or_inf":
				_check_no_nan_inf(rule_name)
			"custom":
				_check_custom_invariant(rule_name, rule)
				_track_custom_delta(rule_name, rule)

func _check_finite_positions(rule_name: String):
	var root = get_tree().root if get_tree() else null
	if not root: return
	_check_node_recursive(root, rule_name)

func _check_node_recursive(node: Node, rule_name: String):
	if node is Node2D:
		var pos = node.position
		if is_nan(pos.x) or is_nan(pos.y) or is_inf(pos.x) or is_inf(pos.y):
			_report_violation(rule_name, str(node.get_path()), "Non-finite position: (%f, %f)" % [pos.x, pos.y])
	elif node is Node3D:
		var pos3d = node.position
		if is_nan(pos3d.x) or is_nan(pos3d.y) or is_nan(pos3d.z) or is_inf(pos3d.x) or is_inf(pos3d.y) or is_inf(pos3d.z):
			_report_violation(rule_name, str(node.get_path()), "Non-finite position: (%f, %f, %f)" % [pos3d.x, pos3d.y, pos3d.z])
	for child in node.get_children():
		_check_node_recursive(child, rule_name)

func _check_bounds(rule_name: String, rule: Dictionary):
	var min_x = rule.get("min_x", -10000)
	var max_x = rule.get("max_x", 10000)
	var min_y = rule.get("min_y", -10000)
	var max_y = rule.get("max_y", 10000)
	var min_z = rule.get("min_z", null)
	var max_z = rule.get("max_z", null)
	var targets = rule.get("targets", [])
	var root = get_tree().root if get_tree() else null
	if not root: return
	if targets.is_empty():
		# Default: gameplay nodes only. Container/structural nodes (scene roots
		# at origin, backgrounds, UI anchored to the viewport) legitimately sit
		# at (0,0) — flagging them makes every run report false positives
		# (structural nodes flooding reports and masking real signal).
		# Gameplay = physics bodies + positioned visuals — the nodes that can
		# actually leave the play area.
		_walk_bounds_gameplay(root, rule_name, min_x, max_x, min_y, max_y, min_z, max_z)
	else:
		# Explicit targets: node paths or "group:<name>" — opt-in exact checking
		for target in targets:
			if typeof(target) == TYPE_STRING and target.begins_with("group:"):
				for n in get_tree().get_nodes_in_group(target.substr(6)):
					_check_bounds_node(n, rule_name, min_x, max_x, min_y, max_y, min_z, max_z)
			elif typeof(target) == TYPE_STRING:
				var n = root.get_node_or_null(NodePath(String(target)))
				if n:
					_check_bounds_node(n, rule_name, min_x, max_x, min_y, max_y, min_z, max_z)

func _is_gameplay_bounds_node(node: Node) -> bool:
	return node is PhysicsBody2D or node is PhysicsBody3D \
		or node is Sprite2D or node is Sprite3D \
		or node is TextureRect or node is ColorRect

func _check_bounds_node(node: Node, rule_name: String, min_x, max_x, min_y, max_y, min_z, max_z):
	if node is Node2D:
		var pos = node.position
		if pos.x < min_x or pos.x > max_x or pos.y < min_y or pos.y > max_y:
			_report_violation(rule_name, str(node.get_path()), "Out of bounds (2D): (%f, %f)" % [pos.x, pos.y])
	elif node is Node3D:
		var pos3d = node.position
		var in_bounds = pos3d.x >= min_x and pos3d.x <= max_x and pos3d.y >= min_y and pos3d.y <= max_y
		if min_z != null:
			in_bounds = in_bounds and pos3d.z >= min_z
		if max_z != null:
			in_bounds = in_bounds and pos3d.z <= max_z
		if not in_bounds:
			var detail = "Out of bounds (3D): (%f, %f, %f)" % [pos3d.x, pos3d.y, pos3d.z]
			_report_violation(rule_name, str(node.get_path()), detail)

func _walk_bounds_gameplay(node: Node, rule_name: String, min_x, max_x, min_y, max_y, min_z, max_z):
	if _is_gameplay_bounds_node(node):
		_check_bounds_node(node, rule_name, min_x, max_x, min_y, max_y, min_z, max_z)
	for child in node.get_children():
		_walk_bounds_gameplay(child, rule_name, min_x, max_x, min_y, max_y, min_z, max_z)

func _check_null_refs(rule_name: String):
	var root = get_tree().root if get_tree() else null
	if not root:
		_report_violation(rule_name, "", "Scene tree root is null")

func _check_frame_time_p99(rule_name: String, rule: Dictionary):
	var threshold_ms = rule.get("value", 33.3)
	var current_p99 = _compute_p99(_metrics.frame_times)
	if current_p99 > threshold_ms:
		_report_violation(rule_name, "", "Frame time p99 = %.2fms (threshold: %.2fms)" % [current_p99, threshold_ms])

func _check_fps_floor(rule_name: String, rule: Dictionary):
	var min_fps = rule.get("value", 30)
	var threshold_ms = 1000.0 / min_fps
	
	var recent_times = _metrics.frame_times.slice(max(0, _metrics.frame_times.size() - 60))
	if not recent_times.is_empty():
		var avg_frame_ms = 0.0
		for t in recent_times:
			avg_frame_ms += t
		avg_frame_ms /= recent_times.size()
		
		if avg_frame_ms > threshold_ms:
			_metrics.fps_floor_violations += 1
			if _metrics.fps_floor_violations > 10:
				_report_violation(rule_name, "", "Avg frame time = %.2fms (min fps: %d)" % [avg_frame_ms, min_fps])

func _check_no_nan_inf(rule_name: String):
	_check_finite_positions(rule_name)

func _check_custom_invariant(rule_name: String, rule: Dictionary):
	var path = rule.get("path", "")
	var value = rule.get("value", null)
	
	var current_val = null
	if path.begins_with("_meta."):
		var field = path.substr(6)
		if field == "frame_ms_p99":
			current_val = _compute_p99(_metrics.frame_times)
		else:
			current_val = _metrics.get(field, null)
		if current_val == null:
			_report_violation(rule_name, path, "Meta field '%s' not found" % field)
			return
	elif path.begins_with("/"):
		current_val = _resolve_test_value(path)
		if current_val == null:
			_report_violation(rule_name, path, "Test path '%s' not found or not exposed" % path)
			return
	else:
		_report_violation(rule_name, path, "Unsupported invariant path '%s' (use _meta.<field> or /root/<node>:<state_key>)" % path)
		return
	
	var check = rule.get("check", "below")
	if check != "equals" and typeof(current_val) not in [TYPE_INT, TYPE_FLOAT]:
		_report_violation(rule_name, path, "Value at '%s' is not numeric (%s) — 'below'/'above' need numbers; use 'equals'" % [path, typeof(current_val)])
		return
	if check != "equals" and typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		_report_violation(rule_name, path, "Threshold '%s' is not numeric (%s) — 'below'/'above' need a numeric 'value'; use 'equals'" % [str(value), typeof(value)])
		return
	
	match check:
		"below":
			if current_val > value:
				_report_violation(rule_name, path, "%s = %s (threshold: %s)" % [path, current_val, value])
		"above":
			if current_val < value:
				_report_violation(rule_name, path, "%s = %s (threshold: %s)" % [path, current_val, value])
		"equals":
			if current_val != value:
				_report_violation(rule_name, path, "%s = %s (expected: %s)" % [path, current_val, value])

## Rate-of-change tracking for custom invariants. Fires only when the scenario
## declares max_delta_per_sec; catches "value exploded" bugs that point-in-time
## checks miss (e.g. a hit handler re-firing every physics tick, awarding +1
## sixty times a second). Per-consecutive-tick deltas CANNOT express this: a
## single legitimate +1 award also measures 1 delta in 1 tick (60/sec). So the
## check is WINDOWED: the rate is the change accumulated over roughly the last
## second of samples (one full physics second), not between adjacent ticks.
## A discrete +1 event is a window rate of ~1/sec — legal under any ceiling
## >= 1. A re-firing handler climbs the whole window — 60/sec — and violates.
## Size max_delta_per_sec as "plausible sustained human pace, in units/sec".
func _track_custom_delta(rule_name: String, rule: Dictionary):
	var max_dps = rule.get("max_delta_per_sec", null)
	if max_dps == null:
		return
	var current = _read_invariant_raw(rule)
	if current == null or not (current is int or current is float):
		return
	if not _rule_prev_values.has(rule_name):
		_rule_prev_values[rule_name] = {"samples": []}
	var samples: Array = _rule_prev_values[rule_name]["samples"]
	samples.append({"tick": _frame_count, "value": current})
	# Keep samples covering the last ~1s of physics ticks.
	var window_ticks = max(1, int(_ticks_per_second))
	while samples.size() > 1 and _frame_count - int(samples[0]["tick"]) > window_ticks:
		samples.pop_front()
	var oldest = samples[0]
	var dt_ticks = _frame_count - int(oldest["tick"])
	# Evaluate only once the window holds a full physics second: shorter spans
	# measure true rates with warm-up skew (a first-second burst of 5 reads as
	# 5 * 60/59 = 5.08 and can trip a 5.0 ceiling spuriously).
	if dt_ticks >= window_ticks:
		var rate = abs(float(current) - float(oldest["value"])) / (float(dt_ticks) / _ticks_per_second)
		if rate > float(max_dps):
			var detail = "Delta rate %.1f/sec exceeds max_delta_per_sec %s (value %s -> %s over %d ticks)" % [rate, str(max_dps), str(oldest["value"]), str(current), dt_ticks]
			_report_violation(rule_name, rule.get("path", ""), detail)

func _read_invariant_raw(rule: Dictionary):
	var path = rule.get("path", "")
	if path.begins_with("_meta."):
		return _metrics.get(path.substr(6), null)
	elif path.begins_with("/"):
		return _resolve_test_value(path)
	return null

func _resolve_test_value(path: String):
	var node_path = path
	var prop = ""
	var idx = path.rfind(":")
	if idx != -1:
		node_path = path.substr(0, idx)
		prop = path.substr(idx + 1)
	var root = get_tree().root if get_tree() else null
	if not root: return null
	var node = root.get_node_or_null(NodePath(node_path))
	if not node: return null
	if prop != "":
		if node.has_method("get_test_state"):
			var state = node.get_test_state()
			if state is Dictionary and state.has(prop):
				return state.get(prop)
		return node.get(prop)
	return null
