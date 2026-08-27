class_name FirearmVisualIdentityGate
extends RefCounted

const CANVAS_SIZE := Vector2i(96, 96)
const ALPHA_THRESHOLD := 0.10
const MIN_OPAQUE_COLORS := 8
const MAX_OPAQUE_COLORS := 32


static func evaluate(
	image: Image,
	blueprint: WeaponBlueprint,
	contract: Dictionary,
	brief: Dictionary = {}
) -> Dictionary:
	if image == null or image.is_empty():
		return _failure("FIREARM_VISUAL_IMAGE_MISSING")
	if image.get_size() != CANVAS_SIZE:
		return _failure("FIREARM_VISUAL_IMAGE_MUST_BE_96X96")
	if blueprint == null or blueprint.behavior_family != "sustained_ranged":
		return _failure("FIREARM_VISUAL_BLUEPRINT_UNSUPPORTED")
	var declaration := blueprint.affordance
	var identity_card := brief.get("visual_identity_card", {}) as Dictionary
	var layout := str(declaration.get("layout", ""))
	if layout not in ["pistol", "conventional_rifle", "bullpup"]:
		return _failure("FIREARM_VISUAL_LAYOUT_UNSUPPORTED")
	var expected_scaffold_sha := str(contract.get("scaffold_rgba_sha256", ""))
	var actual_rgba_sha := _bytes_sha256(image.get_data())
	if not expected_scaffold_sha.is_empty() and actual_rgba_sha == expected_scaffold_sha:
		return _failure("FIREARM_VISUAL_SCAFFOLD_IS_NOT_FINISHED_ART")
	var alpha := _alpha_metrics(image)
	if not bool(alpha.get("ok", false)):
		return alpha
	var bounds := alpha.get("bounds") as Rect2i
	var aspect := float(bounds.size.x) / float(maxi(1, bounds.size.y))
	var opaque_colors := _opaque_color_count(image)
	var metrics := {
		"schema": "forge-firearm-visual-identity-gate-v1",
		"layout": layout,
		"canvas": [CANVAS_SIZE.x, CANVAS_SIZE.y],
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"aspect_ratio": aspect,
		"opaque_pixels": int(alpha.get("opaque_pixels", 0)),
		"opaque_ratio": float(alpha.get("opaque_ratio", 0.0)),
		"opaque_colors": opaque_colors,
		"rgba_sha256": actual_rgba_sha,
		"required_visible_parts": (brief.get("required_visible_parts", []) as Array).duplicate(),
		"identity_id": str(identity_card.get("identity_id", "")),
		"visual_identity_axes": (
			identity_card.get("visual_axes", {}) as Dictionary
		).duplicate(true),
	}
	if opaque_colors < MIN_OPAQUE_COLORS:
		return _metric_failure("FIREARM_VISUAL_TOO_FEW_AUTHORED_COLORS", metrics)
	if opaque_colors > MAX_OPAQUE_COLORS:
		return _metric_failure("FIREARM_VISUAL_PALETTE_NOT_PIXEL_BOUNDED", metrics)
	if bounds.size.x < 56 or bounds.size.y < 22:
		return _metric_failure("FIREARM_VISUAL_SILHOUETTE_TOO_SMALL", metrics)
	var role_metrics := _role_metrics(image, bounds, layout)
	metrics["role_coverage"] = role_metrics.duplicate(true)
	var contour_metrics := _contour_metrics(image, bounds)
	metrics["contour_roles"] = contour_metrics.duplicate(true)
	var axis_shape_error := _axis_shape_error(declaration, role_metrics, contour_metrics)
	if not axis_shape_error.is_empty():
		return _metric_failure(axis_shape_error, metrics)
	var layout_error := _layout_error(layout, aspect, role_metrics)
	if not layout_error.is_empty():
		return _metric_failure(layout_error, metrics)
	var anchors := _resolve_anchors(image, bounds, layout)
	if not bool(anchors.get("ok", false)):
		return _metric_failure(str(anchors.get("error", "FIREARM_VISUAL_ANCHORS_MISSING")), metrics)
	var grip := anchors.get("GripPrimary") as Vector2
	var feed := anchors.get("FeedCenter") as Vector2
	if layout == "conventional_rifle" and feed.x <= grip.x:
		return _metric_failure("FIREARM_VISUAL_FEED_MUST_BE_AHEAD_OF_GRIP", metrics)
	if layout == "bullpup" and feed.x >= grip.x:
		return _metric_failure("FIREARM_VISUAL_FEED_MUST_BE_BEHIND_GRIP", metrics)
	if layout == "pistol" and feed.distance_to(grip) > 5.0:
		return _metric_failure("FIREARM_VISUAL_PISTOL_FEED_MUST_BE_IN_GRIP", metrics)
	return {
		"ok": true,
		"schema": "forge-firearm-visual-identity-gate-v1",
		"automatic": true,
		"finished_art": true,
		"scaffold_presentable": false,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
		"identity_binding": "exact_identity_card+ai_visual_verifier+ai_axes+visible_role_geometry",
		"metrics": metrics,
		"anchors": {
			"GripPrimary": _pair(grip),
			"GripSecondary": _pair(anchors.get("GripSecondary") as Vector2),
			"Muzzle": _pair(anchors.get("Muzzle") as Vector2),
			"Tip": _pair(anchors.get("Muzzle") as Vector2),
			"RearContact": _pair(anchors.get("RearContact") as Vector2),
			"FeedCenter": _pair(feed),
		},
	}


static func _alpha_metrics(image: Image) -> Dictionary:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	var opaque := 0
	var semitransparent := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var value := image.get_pixel(x, y).a
			if value > ALPHA_THRESHOLD:
				opaque += 1
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
			if value > 0.01 and value < 0.99:
				semitransparent += 1
	if opaque == 0:
		return _failure("FIREARM_VISUAL_ALPHA_MISSING")
	if semitransparent > 0:
		return _failure("FIREARM_VISUAL_ALPHA_MUST_BE_BINARY")
	var ratio := float(opaque) / float(image.get_width() * image.get_height())
	if ratio < 0.035 or ratio > 0.46:
		return _failure("FIREARM_VISUAL_ALPHA_COVERAGE_INVALID")
	return {
		"ok": true,
		"opaque_pixels": opaque,
		"opaque_ratio": ratio,
		"bounds": Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1),
	}


static func _role_metrics(image: Image, bounds: Rect2i, layout: String) -> Dictionary:
	var metrics := {
		"receiver_upper": _region_coverage(image, bounds, Rect2(0.12, 0.02, 0.76, 0.46)),
		"rear_structure": _region_coverage(image, bounds, Rect2(0.00, 0.16, 0.30, 0.56)),
		"front_structure": _region_coverage(image, bounds, Rect2(0.70, 0.12, 0.30, 0.52)),
		"lower_rear": _region_coverage(image, bounds, Rect2(0.02, 0.48, 0.48, 0.52)),
		"lower_middle": _region_coverage(image, bounds, Rect2(0.30, 0.48, 0.32, 0.52)),
		"lower_front": _region_coverage(image, bounds, Rect2(0.54, 0.48, 0.30, 0.52)),
		"stock_lower_mass": _region_coverage(image, bounds, Rect2(0.00, 0.52, 0.30, 0.48)),
	}
	if layout == "bullpup":
		metrics["feed_region"] = _region_coverage(image, bounds, Rect2(0.20, 0.48, 0.24, 0.52))
	elif layout == "conventional_rifle":
		metrics["feed_region"] = _region_coverage(image, bounds, Rect2(0.42, 0.46, 0.34, 0.54))
	else:
		metrics["feed_region"] = float(metrics["lower_rear"])
	return metrics


static func _axis_shape_error(
	declaration: Dictionary,
	_role_metrics: Dictionary,
	contour_metrics: Dictionary
) -> String:
	var upper := str(declaration.get("upper_profile", ""))
	var upper_hole_ratio := float(contour_metrics.get("upper_enclosed_hole_ratio", 0.0))
	if upper == "top_rail" and upper_hole_ratio > 0.008:
		return "FIREARM_VISUAL_TOP_RAIL_HAS_CARRY_HANDLE_LOOP"
	if upper == "carry_handle" and upper_hole_ratio < 0.004:
		return "FIREARM_VISUAL_CARRY_HANDLE_GAP_MISSING"
	return ""


static func _layout_error(layout: String, aspect: float, metrics: Dictionary) -> String:
	if float(metrics.get("receiver_upper", 0.0)) < 0.24:
		return "FIREARM_VISUAL_RECEIVER_NOT_READABLE"
	if float(metrics.get("front_structure", 0.0)) < 0.08:
		return "FIREARM_VISUAL_MUZZLE_REGION_NOT_READABLE"
	match layout:
		"pistol":
			if aspect < 1.25 or aspect > 2.45:
				return "FIREARM_VISUAL_PISTOL_PROPORTIONS_INVALID"
			if float(metrics.get("lower_rear", 0.0)) < 0.20:
				return "FIREARM_VISUAL_PISTOL_GRIP_NOT_READABLE"
			if float(metrics.get("lower_front", 0.0)) > 0.34:
				return "FIREARM_VISUAL_PISTOL_FRONT_TOO_HEAVY"
		"conventional_rifle":
			if aspect < 2.10 or aspect > 4.80:
				return "FIREARM_VISUAL_RIFLE_PROPORTIONS_INVALID"
			if float(metrics.get("rear_structure", 0.0)) < 0.08:
				return "FIREARM_VISUAL_STOCK_NOT_READABLE"
			if float(metrics.get("lower_middle", 0.0)) < 0.08:
				return "FIREARM_VISUAL_PRIMARY_GRIP_NOT_READABLE"
			if float(metrics.get("feed_region", 0.0)) < 0.08:
				return "FIREARM_VISUAL_MAGAZINE_NOT_READABLE"
		"bullpup":
			if aspect < 1.70 or aspect > 4.20:
				return "FIREARM_VISUAL_BULLPUP_PROPORTIONS_INVALID"
			if float(metrics.get("rear_structure", 0.0)) < 0.18:
				return "FIREARM_VISUAL_INTEGRATED_STOCK_NOT_READABLE"
			if float(metrics.get("feed_region", 0.0)) < 0.08:
				return "FIREARM_VISUAL_REAR_MAGAZINE_NOT_READABLE"
	return ""


static func _resolve_anchors(image: Image, bounds: Rect2i, layout: String) -> Dictionary:
	var grip_region: Rect2
	var feed_region: Rect2
	match layout:
		"pistol":
			grip_region = Rect2(0.02, 0.42, 0.52, 0.58)
			feed_region = grip_region
		"bullpup":
			grip_region = Rect2(0.42, 0.42, 0.22, 0.58)
			feed_region = Rect2(0.18, 0.42, 0.25, 0.58)
		_:
			grip_region = Rect2(0.20, 0.42, 0.30, 0.58)
			feed_region = Rect2(0.42, 0.42, 0.34, 0.58)
	var grip := _region_centroid(image, bounds, grip_region)
	var feed := _region_centroid(image, bounds, feed_region)
	var secondary := _region_centroid(image, bounds, Rect2(0.62, 0.20, 0.23, 0.48))
	var receiver_y := float(bounds.position.y) + float(bounds.size.y) * 0.38
	var muzzle := _extreme_opaque(image, bounds, receiver_y, true)
	var rear := _extreme_opaque(image, bounds, receiver_y, false)
	if grip.x < 0.0 or feed.x < 0.0 or muzzle.x < 0.0 or rear.x < 0.0:
		return {"ok": false, "error": "FIREARM_VISUAL_REQUIRED_ANCHOR_ALPHA_MISSING"}
	if secondary.x < 0.0:
		secondary = grip
	return {
		"ok": true,
		"GripPrimary": grip,
		"GripSecondary": secondary,
		"FeedCenter": feed,
		"Muzzle": muzzle,
		"RearContact": rear,
	}


static func _region_coverage(image: Image, bounds: Rect2i, normalized: Rect2) -> float:
	var region := _pixel_region(bounds, normalized)
	var opaque := 0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a > ALPHA_THRESHOLD:
				opaque += 1
	return float(opaque) / float(maxi(1, region.size.x * region.size.y))


static func _region_centroid(image: Image, bounds: Rect2i, normalized: Rect2) -> Vector2:
	var region := _pixel_region(bounds, normalized)
	var total := Vector2.ZERO
	var count := 0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a > ALPHA_THRESHOLD:
				total += Vector2(x, y)
				count += 1
	return total / float(count) if count > 0 else Vector2(-1.0, -1.0)


static func _extreme_opaque(image: Image, bounds: Rect2i, desired_y: float, right: bool) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var best_x := -INF if right else INF
	var half_height := float(bounds.size.y) * 0.32
	for y: int in range(bounds.position.y, bounds.end.y):
		if absf(float(y) - desired_y) > half_height:
			continue
		for x: int in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a <= ALPHA_THRESHOLD:
				continue
			if (right and float(x) > best_x) or (not right and float(x) < best_x):
				best_x = float(x)
				best = Vector2(x, y)
	return best


static func _contour_metrics(image: Image, bounds: Rect2i) -> Dictionary:
	var width := bounds.size.x
	var height := bounds.size.y
	var visited := PackedByteArray()
	visited.resize(width * height)
	var queue: Array[Vector2i] = []
	for local_x: int in range(width):
		for local_y: int in [0, height - 1]:
			var index := local_y * width + local_x
			if visited[index] == 0 and image.get_pixel(
				bounds.position.x + local_x,
				bounds.position.y + local_y
			).a <= ALPHA_THRESHOLD:
				visited[index] = 1
				queue.append(Vector2i(local_x, local_y))
	for local_y: int in range(height):
		for local_x: int in [0, width - 1]:
			var index := local_y * width + local_x
			if visited[index] == 0 and image.get_pixel(
				bounds.position.x + local_x,
				bounds.position.y + local_y
			).a <= ALPHA_THRESHOLD:
				visited[index] = 1
				queue.append(Vector2i(local_x, local_y))
	var cursor := 0
	var neighbors: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	while cursor < queue.size():
		var point := queue[cursor]
		cursor += 1
		for offset: Vector2i in neighbors:
			var next := point + offset
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			var next_index := next.y * width + next.x
			if visited[next_index] != 0:
				continue
			if image.get_pixel(bounds.position.x + next.x, bounds.position.y + next.y).a > ALPHA_THRESHOLD:
				continue
			visited[next_index] = 1
			queue.append(next)
	var largest_upper_hole := 0
	var largest_upper_centroid := Vector2.ZERO
	for local_y: int in range(height):
		for local_x: int in range(width):
			var start_index := local_y * width + local_x
			if visited[start_index] != 0:
				continue
			if image.get_pixel(bounds.position.x + local_x, bounds.position.y + local_y).a > ALPHA_THRESHOLD:
				continue
			var hole_queue: Array[Vector2i] = [Vector2i(local_x, local_y)]
			visited[start_index] = 1
			var hole_cursor := 0
			var area := 0
			var total := Vector2.ZERO
			while hole_cursor < hole_queue.size():
				var point := hole_queue[hole_cursor]
				hole_cursor += 1
				area += 1
				total += Vector2(point)
				for offset: Vector2i in neighbors:
					var next := point + offset
					if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
						continue
					var next_index := next.y * width + next.x
					if visited[next_index] != 0:
						continue
					if image.get_pixel(bounds.position.x + next.x, bounds.position.y + next.y).a > ALPHA_THRESHOLD:
						continue
					visited[next_index] = 1
					hole_queue.append(next)
			var centroid := total / float(maxi(1, area))
			var normalized_centroid := Vector2(
				centroid.x / float(maxi(1, width)),
				centroid.y / float(maxi(1, height))
			)
			if normalized_centroid.y < 0.42 and area > largest_upper_hole:
				largest_upper_hole = area
				largest_upper_centroid = normalized_centroid
	return {
		"upper_enclosed_hole_pixels": largest_upper_hole,
		"upper_enclosed_hole_ratio": float(largest_upper_hole) / float(maxi(1, width * height)),
		"upper_enclosed_hole_centroid": _pair(largest_upper_centroid),
	}


static func _pixel_region(bounds: Rect2i, normalized: Rect2) -> Rect2i:
	var x0 := bounds.position.x + floori(float(bounds.size.x) * normalized.position.x)
	var y0 := bounds.position.y + floori(float(bounds.size.y) * normalized.position.y)
	var x1 := bounds.position.x + ceili(float(bounds.size.x) * normalized.end.x)
	var y1 := bounds.position.y + ceili(float(bounds.size.y) * normalized.end.y)
	return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0))


static func _opaque_color_count(image: Image) -> int:
	var colors := {}
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a > ALPHA_THRESHOLD:
				colors[pixel.to_html(false)] = true
	return colors.size()


static func _pair(value: Vector2) -> Array[float]:
	return [value.x, value.y]


static func _bytes_sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _metric_failure(error: String, metrics: Dictionary) -> Dictionary:
	var result := _failure(error)
	result["metrics"] = metrics
	return result


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"retry_required": true,
		"retry_prompt": _retry_prompt(error),
		"player_confirmation_required": false,
	}


static func _retry_prompt(error: String) -> String:
	match error:
		"FIREARM_VISUAL_TOP_RAIL_HAS_CARRY_HANDLE_LOOP":
			return "Remove the carry-handle arch completely; keep a low straight flat top rail and preserve the exact named firearm identity."
		"FIREARM_VISUAL_CARRY_HANDLE_GAP_MISSING":
			return "Add the declared raised carry handle with one clean transparent gap beneath it while preserving the exact identity."
		"FIREARM_VISUAL_MAGAZINE_NOT_READABLE":
			return "Make the separate magazine large and unmistakable at its declared position relative to the primary grip."
	return "Keep the exact firearm identity; redraw a finished, readable side-view pixel sprite with separate stock, receiver, grip, magazine and muzzle structures."
