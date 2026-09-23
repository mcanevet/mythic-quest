extends SceneTree
func _init() -> void:
	# Thresholds are calibration defaults (wt17 invisible-game incident);
	# overridable via env vars for deliberately near-monochrome games.
	var sat_thresh: float = float(OS.get_environment("VISUAL_GATE_SAT").to_float() if OS.get_environment("VISUAL_GATE_SAT") != "" else 0.25)
	var chrom_thresh: float = float(OS.get_environment("VISUAL_GATE_CHROMATIC").to_float() if OS.get_environment("VISUAL_GATE_CHROMATIC") != "" else 0.01)
	var dom_thresh: float = float(OS.get_environment("VISUAL_GATE_DOMINANT").to_float() if OS.get_environment("VISUAL_GATE_DOMINANT") != "" else 0.98)
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("VISUAL_FAIL_BLANK no-screenshot-argument")
		quit(1)
		return
	var img := Image.load_from_file(args[0])
	if img == null:
		print("VISUAL_FAIL_BLANK cannot-load-image")
		quit(1)
		return
	var w := img.get_width()
	var h := img.get_height()
	if w < 8 or h < 8:
		print("VISUAL_FAIL_BLANK image-too-small")
		quit(1)
		return
	var counts := {}
	var chromatic := 0
	var total := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var c := img.get_pixel(x, y)
			total += 1
			var s: float = maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			var L: float = c.get_luminance()
			if s > sat_thresh and L > 0.08:
				chromatic += 1
			var key := "%03d_%03d_%03d" % [c.r8, c.g8, c.b8]
			counts[key] = counts.get(key, 0) + 1
	var max_count := 0
	for k in counts:
		max_count = max(max_count, counts[k])
	var chromatic_ratio := float(chromatic) / total
	var dominant_share := float(max_count) / total
	if chromatic_ratio >= chrom_thresh and dominant_share < dom_thresh:
		print("VISUAL_PASS chromatic=%.4f dominant=%.4f distinct=%d" % [chromatic_ratio, dominant_share, counts.size()])
		quit(0)
	else:
		print("VISUAL_FAIL_BLANK chromatic=%.4f dominant=%.4f distinct=%d" % [chromatic_ratio, dominant_share, counts.size()])
		quit(1)
