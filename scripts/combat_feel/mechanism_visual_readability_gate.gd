class_name MechanismVisualReadabilityGate
extends RefCounted

const VISUAL_BRIEF := preload("res://scripts/combat_feel/mechanism_visual_brief.gd")


static func evaluate(asset: WeaponVisualAsset, affordance_profile: Resource, brief: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var metrics: Dictionary = {}
	if asset == null or asset.source_image == null or asset.source_image.is_empty():
		return _failure(["AI_VISUAL_READABILITY_ASSET_MISSING"], metrics)
	if affordance_profile == null:
		return _failure(["AI_VISUAL_READABILITY_AFFORDANCE_MISSING"], metrics)
	if brief.is_empty():
		brief = VISUAL_BRIEF.compile(affordance_profile.to_dict(), "runtime_affordance_profile")
	var brief_errors := VISUAL_BRIEF.validation_errors(brief)
	if not brief_errors.is_empty():
		return _failure(brief_errors, metrics)

	var canvas_diagonal := maxf(1.0, Vector2(asset.canvas_size).length())
	var silhouette_metrics := asset.silhouette_mechanics()
	metrics["silhouette"] = silhouette_metrics
	var chroma_residue := _chroma_residue_metrics(asset.source_image)
	metrics["chroma_residue"] = chroma_residue
	if int(chroma_residue.get("pixel_count", 0)) >= 8 \
			and float(chroma_residue.get("opaque_ratio", 0.0)) >= 0.025:
		errors.append("AI_VISUAL_READABILITY_CHROMA_RESIDUE")
	var grip_to_strike_span_ratio := asset.grip_primary.distance_to(asset.tip) / canvas_diagonal
	metrics["grip_to_strike_span_ratio"] = grip_to_strike_span_ratio
	var rules: Dictionary = brief.get("gate_rules", {})
	var brief_axes: Dictionary = brief.get("axes", {})
	for axis: String in VISUAL_BRIEF.STRUCTURAL_AXES:
		if brief_axes.has(axis) and str(brief_axes.get(axis, "")) != str(affordance_profile.get(axis)):
			errors.append("AI_VISUAL_READABILITY_BRIEF_AXIS_MISMATCH:%s" % axis)
	if grip_to_strike_span_ratio < float(rules.get("minimum_grip_to_strike_span_ratio", 0.22)):
		errors.append("AI_VISUAL_READABILITY_CONTACT_SPAN_TOO_SMALL")
	if str(affordance_profile.contact_surface) == "broad" \
			and float(silhouette_metrics.get("contact_span_ratio", 0.0)) < 0.17:
		errors.append("AI_VISUAL_READABILITY_BROAD_CONTACT_TOO_NARROW")

	var flex := str(affordance_profile.flex_topology)
	var tether := str(affordance_profile.tether_topology)
	var terminal := str(affordance_profile.terminal_load)
	var uses_soft_structure := flex != "none" or tether != "none"
	if not uses_soft_structure:
		return _result(errors, metrics)
	if asset.visual_rig == null:
		errors.append("AI_VISUAL_READABILITY_RIG_MISSING")
		return _result(errors, metrics)
	var rig: PixelWeaponVisualRig = asset.visual_rig
	for axis_error: String in rig.axis_errors(affordance_profile):
		errors.append("AI_VISUAL_READABILITY_%s" % axis_error)
	for role_value: Variant in brief.get("required_roles", []):
		var role := str(role_value)
		if not rig.has_role(role) or rig.pixel_count(role) <= 0:
			errors.append("AI_VISUAL_READABILITY_ROLE_MISSING:%s" % role)

	var body_path := rig.source_path_for_role("deform_body")
	if flex != "none" and body_path.size() >= 2:
		var body_metrics := _path_metrics(body_path, rig, "deform_body", canvas_diagonal)
		metrics["primary_body"] = body_metrics
		if flex in ["bending_shaft", "flexible_line"]:
			var minimum_curve := float(rules.get("minimum_soft_curvature_ratio", 0.09))
			# Pixel stair-steps can accumulate a large turn angle on a straight bar.
			# Require a visible centerline departure from its end-to-end chord instead.
			if float(body_metrics.get("curvature_ratio", 0.0)) < minimum_curve:
				errors.append("AI_VISUAL_READABILITY_SOFT_BODY_LOOKS_RIGID")
		if flex == "flexible_line" and float(body_metrics.get("slenderness", 0.0)) < 3.6:
			errors.append("AI_VISUAL_READABILITY_FLEXIBLE_LINE_TOO_BLOCKY")
		if flex == "linked_segments":
			var minimum_peaks := int(rules.get("minimum_linked_width_peaks", 3))
			var minimum_color_joints := int(rules.get("minimum_linked_color_transitions", 6))
			if int(body_metrics.get("width_peak_count", 0)) < minimum_peaks \
					and int(body_metrics.get("eroded_2px_component_count", 0)) < 3 \
					and int(body_metrics.get("high_contrast_color_transition_count", 0)) < minimum_color_joints:
				errors.append("AI_VISUAL_READABILITY_LINKS_NOT_VISIBLE")

	var tether_path := rig.source_path_for_role("tether")
	if tether != "none" and tether_path.size() >= 2:
		var tether_metrics := _path_metrics(tether_path, rig, "tether", canvas_diagonal)
		metrics["tether"] = tether_metrics
		if float(tether_metrics.get("span_ratio", 0.0)) < float(rules.get("minimum_tether_span_ratio", 0.16)):
			errors.append("AI_VISUAL_READABILITY_TETHER_TOO_SHORT")
		var connection_distance := _path_end(body_path, asset.grip_primary).distance_to(tether_path[0])
		metrics["body_tether_connection_distance"] = connection_distance
		if connection_distance > 8.0:
			errors.append("AI_VISUAL_READABILITY_TETHER_DISCONNECTED")
		var divergence := _path_divergence_degrees(body_path, tether_path, asset.grip_primary)
		metrics["tether_divergence_degrees"] = divergence
		var minimum_divergence := float(rules.get("minimum_tether_divergence_degrees", 18.0))
		if divergence < minimum_divergence and float(tether_metrics.get("curvature_ratio", 0.0)) < 0.025:
			errors.append("AI_VISUAL_READABILITY_TETHER_NOT_INDEPENDENT")
		if tether == "linked_segments" and int(tether_metrics.get("width_peak_count", 0)) \
				< int(rules.get("minimum_linked_width_peaks", 3)) \
				and int(tether_metrics.get("eroded_2px_component_count", 0)) < 3 \
				and int(tether_metrics.get("high_contrast_color_transition_count", 0)) \
					< int(rules.get("minimum_linked_color_transitions", 6)):
			errors.append("AI_VISUAL_READABILITY_TETHER_LINKS_NOT_VISIBLE")

	if terminal != "none":
		var terminal_metrics := _role_metrics(rig, "terminal")
		metrics["terminal"] = terminal_metrics
		if int(terminal_metrics.get("pixel_count", 0)) < int(rules.get("minimum_terminal_pixels", 4)):
			errors.append("AI_VISUAL_READABILITY_TERMINAL_TOO_SMALL")
		var minimum_extent := 5.0 if terminal == "heavy" else 3.0
		if float(terminal_metrics.get("maximum_extent", 0.0)) < minimum_extent:
			errors.append("AI_VISUAL_READABILITY_TERMINAL_NOT_DISTINCT")
	return _result(errors, metrics)


static func _path_metrics(path: PackedVector2Array, rig: PixelWeaponVisualRig, role: String, canvas_diagonal: float) -> Dictionary:
	var arc_length := 0.0
	var total_turn := 0.0
	for index: int in range(path.size() - 1):
		arc_length += path[index].distance_to(path[index + 1])
		if index > 0:
			var before := (path[index] - path[index - 1]).normalized()
			var after := (path[index + 1] - path[index]).normalized()
			total_turn += absf(rad_to_deg(before.angle_to(after)))
	var chord := path[0].distance_to(path[path.size() - 1])
	var maximum_deviation := 0.0
	for point: Vector2 in path:
		maximum_deviation = maxf(maximum_deviation, _distance_to_segment(point, path[0], path[path.size() - 1]))
	var widths := _width_samples(rig, role, 14)
	var average_width := 0.0
	for width: float in widths:
		average_width += width
	average_width /= maxf(1.0, float(widths.size()))
	var minimum_width: float = widths.min() if not widths.is_empty() else 0.0
	var maximum_width: float = widths.max() if not widths.is_empty() else 0.0
	# Four crossings are required for linked topology, so this lower per-edge
	# threshold can retain two obvious material bands without accepting one ring.
	var high_contrast_transitions := _color_transition_count(rig, role, 14, 0.08)
	return {
		"arc_length": arc_length,
		"chord_length": chord,
		"span_ratio": chord / maxf(1.0, canvas_diagonal),
		"curvature_ratio": maximum_deviation / maxf(1.0, chord),
		"maximum_deviation_pixels": maximum_deviation,
		"arc_excess_ratio": arc_length / maxf(1.0, chord) - 1.0,
		"total_turn_degrees": total_turn,
		"average_half_width": average_width,
		"width_peak_count": _width_peak_count(widths),
		"width_range_ratio": (maximum_width - minimum_width) / maxf(1.0, maximum_width),
		"color_transition_count": high_contrast_transitions,
		"high_contrast_color_transition_count": high_contrast_transitions,
		"eroded_2px_component_count": _eroded_role_component_count(rig, role, 2, 4),
		"slenderness": arc_length / maxf(1.0, average_width * 2.0),
		"width_samples": widths,
	}


static func _width_samples(rig: PixelWeaponVisualRig, role: String, count: int) -> Array[float]:
	var widths: Array[float] = []
	var occupied: Array[bool] = []
	widths.resize(count)
	occupied.resize(count)
	for binding: Dictionary in rig.bindings:
		if str(binding.get("role", "")) != role:
			continue
		var index := clampi(floori(float(binding.get("ratio", 0.0)) * float(count)), 0, count - 1)
		widths[index] = maxf(widths[index], absf(float(binding.get("normal_offset", 0.0))) + 0.5)
		occupied[index] = true
	for index: int in range(count):
		if occupied[index]:
			continue
		var nearest_distance := count + 1
		var nearest_value := 0.0
		for candidate: int in range(count):
			if occupied[candidate] and abs(candidate - index) < nearest_distance:
				nearest_distance = abs(candidate - index)
				nearest_value = widths[candidate]
		widths[index] = nearest_value
	return widths


static func _width_peak_count(widths: Array[float]) -> int:
	var peaks := 0
	for index: int in range(1, widths.size() - 1):
		if widths[index] >= widths[index - 1] + 0.45 and widths[index] >= widths[index + 1] + 0.45:
			peaks += 1
	return peaks


static func _color_transition_count(
	rig: PixelWeaponVisualRig,
	role: String,
	count: int,
	minimum_distance: float
) -> int:
	var sums: Array[Vector3] = []
	var totals: Array[int] = []
	sums.resize(count)
	totals.resize(count)
	for binding: Dictionary in rig.bindings:
		if str(binding.get("role", "")) != role:
			continue
		var index := clampi(floori(float(binding.get("ratio", 0.0)) * float(count)), 0, count - 1)
		var color := Color(binding.get("color", Color.TRANSPARENT))
		sums[index] += Vector3(color.r, color.g, color.b)
		totals[index] += 1
	var averages: Array[Vector3] = []
	averages.resize(count)
	for index: int in range(count):
		if totals[index] > 0:
			averages[index] = sums[index] / float(totals[index])
		elif index > 0:
			averages[index] = averages[index - 1]
	var transitions := 0
	for index: int in range(1, count):
		if averages[index].distance_to(averages[index - 1]) >= minimum_distance:
			transitions += 1
	return transitions


static func _eroded_role_component_count(
	rig: PixelWeaponVisualRig,
	role: String,
	radius: int,
	minimum_component_pixels: int
) -> int:
	var size := rig.canvas_size
	if size.x <= 0 or size.y <= 0:
		return 0
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	for binding: Dictionary in rig.bindings:
		if str(binding.get("role", "")) != role:
			continue
		var point := Vector2i(Vector2(binding.get("source_position", Vector2.ZERO)).round())
		if point.x >= 0 and point.y >= 0 and point.x < size.x and point.y < size.y:
			mask[point.y * size.x + point.x] = 1
	var eroded := PackedByteArray()
	eroded.resize(mask.size())
	for y: int in range(size.y):
		for x: int in range(size.x):
			if mask[y * size.x + x] == 0:
				continue
			var survives := true
			for offset_y: int in range(-radius, radius + 1):
				for offset_x: int in range(-radius, radius + 1):
					if offset_x * offset_x + offset_y * offset_y > radius * radius:
						continue
					var check_x := x + offset_x
					var check_y := y + offset_y
					if check_x < 0 or check_y < 0 or check_x >= size.x or check_y >= size.y \
							or mask[check_y * size.x + check_x] == 0:
						survives = false
						break
				if not survives:
					break
			if survives:
				eroded[y * size.x + x] = 1
	var visited := PackedByteArray()
	visited.resize(mask.size())
	var component_count := 0
	for y: int in range(size.y):
		for x: int in range(size.x):
			var start_index := y * size.x + x
			if eroded[start_index] == 0 or visited[start_index] != 0:
				continue
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			visited[start_index] = 1
			var cursor := 0
			var pixels := 0
			while cursor < queue.size():
				var point := queue[cursor]
				cursor += 1
				pixels += 1
				for offset_y: int in range(-1, 2):
					for offset_x: int in range(-1, 2):
						if offset_x == 0 and offset_y == 0:
							continue
						var neighbor := point + Vector2i(offset_x, offset_y)
						if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.y:
							continue
						var neighbor_index := neighbor.y * size.x + neighbor.x
						if eroded[neighbor_index] == 0 or visited[neighbor_index] != 0:
							continue
						visited[neighbor_index] = 1
						queue.append(neighbor)
			if pixels >= minimum_component_pixels:
				component_count += 1
	return component_count


static func _role_metrics(rig: PixelWeaponVisualRig, role: String) -> Dictionary:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var count := 0
	for binding: Dictionary in rig.bindings:
		if str(binding.get("role", "")) != role:
			continue
		var point := Vector2(binding.get("source_position", Vector2.ZERO))
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
		count += 1
	var extent := maximum - minimum + Vector2.ONE if count > 0 else Vector2.ZERO
	return {
		"pixel_count": count,
		"extent": extent,
		"maximum_extent": maxf(extent.x, extent.y),
	}


static func _chroma_residue_metrics(image: Image) -> Dictionary:
	var opaque_pixels := 0
	var residue_pixels := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.1:
				continue
			opaque_pixels += 1
			if color.r >= 0.72 and color.b >= 0.72 and color.g <= 0.45 \
					and minf(color.r, color.b) - color.g >= 0.35:
				residue_pixels += 1
	return {
		"pixel_count": residue_pixels,
		"opaque_pixel_count": opaque_pixels,
		"opaque_ratio": float(residue_pixels) / maxf(1.0, float(opaque_pixels)),
		"key_family": "high_red_blue_low_green",
	}


static func _path_divergence_degrees(body: PackedVector2Array, tether: PackedVector2Array, grip: Vector2) -> float:
	if tether.size() < 2:
		return 0.0
	var body_tangent := (_path_end(body, grip) - (body[body.size() - 2] if body.size() >= 2 else grip)).normalized()
	var tether_tangent := (tether[1] - tether[0]).normalized()
	return absf(rad_to_deg(body_tangent.angle_to(tether_tangent)))


static func _path_end(path: PackedVector2Array, fallback: Vector2) -> Vector2:
	return path[path.size() - 1] if not path.is_empty() else fallback


static func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var span := finish - start
	if span.length_squared() <= 0.0001:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(span) / span.length_squared(), 0.0, 1.0)
	return point.distance_to(start + span * ratio)


static func _failure(errors: Array[String], metrics: Dictionary) -> Dictionary:
	return _result(errors, metrics)


static func _result(errors: Array[String], metrics: Dictionary) -> Dictionary:
	var readable := errors.is_empty()
	return {
		"ok": readable,
		"stage": "mechanism_visual_readability",
		"error": "" if readable else errors[0],
		"errors": errors,
		"metrics": metrics,
		"automatic": true,
		"retry_required": not readable,
		"player_confirmation_required": false,
		"retry_prompt": _retry_prompt(errors) if not readable else "",
	}


static func _retry_prompt(errors: Array[String]) -> String:
	if errors.has("AI_VISUAL_READABILITY_CHROMA_RESIDUE"):
		return "Keep identity. Leave a visible gap in any loop so magenta background stays outside the object mask."
	if errors.has("AI_VISUAL_READABILITY_BROAD_CONTACT_TOO_NARROW"):
		return "Keep identity. Make the striking end a clearly wider flat blunt mass, at least twice the shaft width at 96px."
	if errors.has("AI_VISUAL_READABILITY_LINKS_NOT_VISIBLE") \
			or errors.has("AI_VISUAL_READABILITY_TETHER_LINKS_NOT_VISIBLE"):
		return "Keep identity. Draw 3-5 chunky sections; cut two narrow hinge necks into the outer silhouette. Never one smooth bar."
	if errors.has("AI_VISUAL_READABILITY_SOFT_BODY_LOOKS_RIGID"):
		return "Keep identity. Draw one deep S-curve; offset its midpoint and turn its tip back. Never draw a straight bar."
	if errors.has("AI_VISUAL_READABILITY_TETHER_NOT_INDEPENDENT"):
		return "Keep identity. Make the second thin tether visibly branch, bend, and depart from the main body's direction."
	return "Keep identity. Separate grip, contact, flexible body, tether, joints, and terminal as chunky 96px regions."
