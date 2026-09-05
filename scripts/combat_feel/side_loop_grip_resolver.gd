class_name SideLoopGripResolver
extends RefCounted

# A conservative Alpha-topology interpretation of an AI-declared handle.
# No noun, sample ID, material or RGB colour is used as mechanics authority.
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]


static func resolve(image: Image, declaration: Dictionary) -> Dictionary:
	if not _supported(declaration):
		return _unresolved("declaration_not_rigid_fixed_broad_handle")
	if image == null or image.is_empty():
		return _unresolved("image_missing")
	var geometry := _geometry(image)
	var bounds: Rect2i = geometry.bounds
	if bounds.size.x < 18 or bounds.size.y < 12 or int(geometry.opaque_count) < 80:
		return _unresolved("silhouette_too_small")
	var centroid: Vector2 = geometry.centroid
	var holes := _enclosed_holes(image)
	var candidates: Array[Dictionary] = []
	var min_hole_area := maxi(9, ceili(float(geometry.opaque_count) * 0.012))
	for hole: Dictionary in holes:
		var area := int(hole.area)
		var hole_bounds: Rect2i = hole.bounds
		var center: Vector2 = hole.centroid
		if area < min_hole_area or float(area) > float(geometry.opaque_count) * 0.18:
			continue
		if hole_bounds.size.x < 3 or hole_bounds.size.y < 4 or float(hole_bounds.size.x) > float(bounds.size.x) * 0.30:
			continue
		if float(hole_bounds.get_area()) > float(bounds.get_area()) * 0.16:
			continue
		if absf(center.x - centroid.x) < float(bounds.size.x) * 0.20 or absf(center.y - centroid.y) > float(bounds.size.y) * 0.35:
			continue
		var side := 1 if center.x > centroid.x else -1
		var candidate := _candidate(image, hole, bounds, centroid, side, "enclosed_alpha_side_loop_with_broad_inner_body")
		if bool(candidate.get("resolved", false)):
			candidates.append(candidate)
	if candidates.size() > 1:
		var competing := _unresolved("competing_side_loop_handles")
		competing.evidence["enclosed_holes"] = holes.size()
		competing.evidence["eligible_side_loops"] = candidates.size()
		return competing
	if candidates.size() == 1:
		var resolved := candidates[0]
		resolved.evidence["enclosed_holes"] = holes.size()
		resolved.evidence["eligible_side_loops"] = 1
		resolved.evidence["eligible_open_side_bays"] = 0
		return resolved
	# Some real handles are C/U-shaped and intentionally open to the outside.
	# Detect a narrow exterior bay between a thin outer bar and a much thicker
	# inner body. This uses Alpha topology only; a straight nozzle has no such bay.
	var open_bays := _open_side_bays(image, bounds, centroid)
	var open_candidates: Array[Dictionary] = []
	var open_rejections: Array[String] = []
	for bay: Dictionary in open_bays:
		var center: Vector2 = bay.centroid
		var side := 1 if center.x > centroid.x else -1
		var candidate := _candidate(image, bay, bounds, centroid, side, "open_alpha_side_bay_with_broad_inner_body")
		if bool(candidate.get("resolved", false)):
			open_candidates.append(candidate)
		else:
			open_rejections.append(str((candidate.get("evidence", {}) as Dictionary).get("reason", "unknown")))
	if open_candidates.size() != 1:
		var failure := _unresolved("competing_side_loop_handles" if candidates.size() > 1 else "no_unambiguous_side_loop")
		failure.evidence["enclosed_holes"] = holes.size()
		failure.evidence["eligible_side_loops"] = 0
		failure.evidence["open_side_bays"] = open_bays.size()
		failure.evidence["open_side_bay_bounds"] = open_bays.map(func(bay: Dictionary) -> Array[int]: var r: Rect2i = bay.bounds; return [r.position.x, r.position.y, r.size.x, r.size.y])
		failure.evidence["eligible_open_side_bays"] = open_candidates.size()
		failure.evidence["open_side_bay_rejections"] = open_rejections
		if open_candidates.size() > 1: failure.evidence["reason"] = "competing_open_side_handles"
		return failure
	var resolved := open_candidates[0]
	resolved.evidence["enclosed_holes"] = holes.size()
	resolved.evidence["eligible_side_loops"] = 0
	resolved.evidence["open_side_bays"] = open_bays.size()
	resolved.evidence["eligible_open_side_bays"] = 1
	return resolved


static func _supported(declaration: Dictionary) -> bool:
	return str(declaration.get("grip_topology", "")) == "one_hand_handle" \
		and str(declaration.get("contact_surface", "")) in ["broad", "whole_body"] \
		and str(declaration.get("rigidity", "")) == "rigid" \
		and str(declaration.get("state_topology", "")) == "fixed" \
		and str(declaration.get("flex_topology", "")) == "none" \
		and str(declaration.get("tether_topology", "")) == "none"


static func _candidate(image: Image, hole: Dictionary, bounds: Rect2i, centroid: Vector2, side: int, method: String) -> Dictionary:
	var hole_bounds: Rect2i = hole.bounds
	var center: Vector2 = hole.centroid
	var rows: Dictionary = hole.rows
	var grips: Array[Dictionary] = []
	var low_y := hole_bounds.position.y + floori(float(hole_bounds.size.y) * 0.20)
	var high_y := hole_bounds.end.y - ceili(float(hole_bounds.size.y) * 0.20)
	for y: int in range(low_y, high_y):
		if not rows.has(y): continue
		var row: Vector2i = rows[y]
		var outer_start: int = (row.y + 1) if side > 0 else (row.x - 1)
		var inner_start: int = (row.x - 1) if side > 0 else (row.y + 1)
		var outer_thickness := _opaque_run(image, Vector2i(outer_start, y), side)
		var inner_thickness := _opaque_run(image, Vector2i(inner_start, y), -side)
		if outer_thickness < 1 or outer_thickness > maxi(5, ceili(float(bounds.size.x) * 0.16)):
			continue
		if inner_thickness < maxi(6, ceili(float(bounds.size.x) * 0.15)) or float(inner_thickness) < float(outer_thickness) * 2.4:
			continue
		var grip := Vector2(float(outer_start) + float(side) * float(outer_thickness - 1) * 0.5, float(y))
		grips.append({"grip": grip, "outer_thickness": outer_thickness, "inner_thickness": inner_thickness})
	if grips.size() < maxi(3, ceili(float(hole_bounds.size.y) * 0.30)):
		return _unresolved("loop_not_attached_to_broad_body")
	grips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := absf((a.grip as Vector2).y - center.y)
		var db := absf((b.grip as Vector2).y - center.y)
		return da < db if not is_equal_approx(da, db) else (a.grip as Vector2).y < (b.grip as Vector2).y
	)
	var chosen := grips[0]
	var grip: Vector2 = chosen.grip
	var strike := _broad_body_contact(image, bounds, centroid, side, float(chosen.outer_thickness))
	if not bool(strike.get("ok", false)):
		return _unresolved("broad_contact_unresolved")
	var tip: Vector2 = strike.point
	if float(side) * (grip.x - tip.x) < float(bounds.size.x) * 0.35:
		return _unresolved("loop_and_contact_not_separated")
	var secondary := grip
	for sample: Dictionary in grips:
		var point: Vector2 = sample.grip
		if point.y > grip.y and point.y - grip.y <= 3.0:
			secondary = point
			break
	return {
		"resolved": true, "grip_primary": grip, "grip_secondary": secondary, "strike_point": tip,
		"evidence": {
			"resolved": true, "method": method,
			"coordinate_frame": "source_before_forward_orientation_normalization",
			"hole_area": int(hole.area), "hole_bounds": [hole_bounds.position.x, hole_bounds.position.y, hole_bounds.size.x, hole_bounds.size.y],
			"hole_centroid": [center.x, center.y], "silhouette_centroid": [centroid.x, centroid.y],
			"outer_grip_thickness": chosen.outer_thickness, "inner_body_thickness": chosen.inner_thickness,
			"body_contact_span": strike.span, "body_contact_vertical_span": strike.vertical_span,
			"body_core_vertical_span": strike.core_vertical_span, "minimum_contact_vertical_span": strike.minimum_vertical_span,
			"grip_primary": [grip.x, grip.y], "strike_point": [tip.x, tip.y],
			"alpha_changed": false, "identity_or_color_used": false,
		}
	}


static func _open_side_bays(image: Image, bounds: Rect2i, centroid: Vector2) -> Array[Dictionary]:
	var width := image.get_width()
	var height := image.get_height()
	var exterior := PackedByteArray(); exterior.resize(width * height); exterior.fill(0)
	var queue: Array[Vector2i] = []
	for x: int in range(width):
		for point: Vector2i in [Vector2i(x, 0), Vector2i(x, height - 1)]:
			if not _opaque(image, point) and exterior[point.y * width + point.x] == 0:
				exterior[point.y * width + point.x] = 1; queue.append(point)
	for y: int in range(height):
		for point: Vector2i in [Vector2i(0, y), Vector2i(width - 1, y)]:
			if not _opaque(image, point) and exterior[point.y * width + point.x] == 0:
				exterior[point.y * width + point.x] = 1; queue.append(point)
	var cursor := 0
	while cursor < queue.size():
		var point := queue[cursor]; cursor += 1
		for step: Vector2i in DIRECTIONS:
			var next := point + step
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height: continue
			var index := next.y * width + next.x
			if exterior[index] != 0 or _opaque(image, next): continue
			exterior[index] = 1; queue.append(next)

	var runs: Array[Dictionary] = []
	var maximum_gap := maxi(4, floori(float(bounds.size.x) * 0.18))
	for y: int in range(bounds.position.y + 1, bounds.end.y - 1):
		var x := bounds.position.x + 1
		while x < bounds.end.x - 1:
			if exterior[y * width + x] == 0:
				x += 1; continue
			var start := x
			while x < bounds.end.x - 1 and exterior[y * width + x] != 0: x += 1
			var finish := x - 1
			var run_width := finish - start + 1
			if run_width < 2 or run_width > maximum_gap: continue
			if not _opaque(image, Vector2i(start - 1, y)) or not _opaque(image, Vector2i(finish + 1, y)): continue
			var center_x := (start + finish) * 0.5
			if absf(center_x - centroid.x) < float(bounds.size.x) * 0.20: continue
			runs.append({"y": y, "start": start, "finish": finish, "side": 1 if center_x > centroid.x else -1})

	var groups: Array[Dictionary] = []
	for run: Dictionary in runs:
		var assigned := false
		for group: Dictionary in groups:
			if int(group.side) != int(run.side) or int(run.y) > int(group.last_y) + 1: continue
			if int(run.start) > int(group.maximum_x) + 2 or int(run.finish) < int(group.minimum_x) - 2: continue
			group.last_y = run.y
			group.minimum_x = mini(int(group.minimum_x), int(run.start))
			group.maximum_x = maxi(int(group.maximum_x), int(run.finish))
			group.area = int(group.area) + int(run.finish) - int(run.start) + 1
			var rows: Dictionary = group.rows; rows[run.y] = Vector2i(run.start, run.finish)
			assigned = true; break
		if not assigned:
			groups.append({"side": run.side, "first_y": run.y, "last_y": run.y, "minimum_x": run.start, "maximum_x": run.finish, "area": int(run.finish) - int(run.start) + 1, "rows": {run.y: Vector2i(run.start, run.finish)}})

	var bays: Array[Dictionary] = []
	for group: Dictionary in groups:
		var bay_height := int(group.last_y) - int(group.first_y) + 1
		if bay_height < 4 or int(group.area) < 12: continue
		var bay_bounds := Rect2i(int(group.minimum_x), int(group.first_y), int(group.maximum_x) - int(group.minimum_x) + 1, bay_height)
		bays.append({"area": int(group.area), "centroid": Vector2(bay_bounds.get_center()), "bounds": bay_bounds, "rows": group.rows})
	return bays


static func _broad_body_contact(image: Image, bounds: Rect2i, centroid: Vector2, side: int, grip_thickness: float) -> Dictionary:
	var min_width := maxi(8, ceili(maxf(float(bounds.size.x) * 0.30, grip_thickness * 2.5)))
	# A thin lateral nozzle may be horizontally connected to a broad body. A long
	# row alone does not make its endpoint a broad contact. Require comparable
	# vertical substance at the endpoint, measured against the median core column.
	var core_spans: Array[int] = []
	var core_radius := maxi(2, ceili(float(bounds.size.x) * 0.12))
	for x: int in range(maxi(bounds.position.x, floori(centroid.x) - core_radius), mini(bounds.end.x, ceili(centroid.x) + core_radius + 1)):
		var span := _vertical_span(image, Vector2i(x, roundi(centroid.y)))
		if span > 0: core_spans.append(span)
	if core_spans.is_empty(): return {"ok": false}
	core_spans.sort()
	var core_span := core_spans[core_spans.size() / 2]
	var minimum_vertical_span := ceili(maxf(float(core_span) * 0.65, maxf(float(bounds.size.y) * 0.20, grip_thickness * 1.5)))
	var radius := maxi(2, ceili(float(bounds.size.y) * 0.35))
	var options: Array[Dictionary] = []
	for y: int in range(maxi(bounds.position.y, floori(centroid.y) - radius), mini(bounds.end.y, ceili(centroid.y) + radius + 1)):
		var x := bounds.position.x
		while x < bounds.end.x:
			if not _opaque(image, Vector2i(x, y)):
				x += 1
				continue
			var run := _opaque_run(image, Vector2i(x, y), 1)
			if run >= min_width and centroid.x >= float(x - 1) and centroid.x <= float(x + run):
				var point := Vector2(float(x if side > 0 else x + run - 1), float(y))
				var vertical_span := _vertical_span(image, Vector2i(point))
				if vertical_span >= minimum_vertical_span:
					options.append({"ok": true, "point": point, "span": run, "vertical_span": vertical_span, "core_vertical_span": core_span, "minimum_vertical_span": minimum_vertical_span, "distance": absf(float(y) - centroid.y)})
			x += maxi(1, run)
	if options.is_empty(): return {"ok": false}
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance) if not is_equal_approx(float(a.distance), float(b.distance)) else (a.point as Vector2).y < (b.point as Vector2).y)
	return options[0]


static func _geometry(image: Image) -> Dictionary:
	var minimum := image.get_size()
	var maximum := Vector2i(-1, -1)
	var sum := Vector2.ZERO
	var count := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if not _opaque(image, Vector2i(x, y)): continue
			minimum = Vector2i(mini(minimum.x, x), mini(minimum.y, y))
			maximum = Vector2i(maxi(maximum.x, x), maxi(maximum.y, y))
			sum += Vector2(x, y)
			count += 1
	return {"bounds": Rect2i(minimum, maximum - minimum + Vector2i.ONE) if count > 0 else Rect2i(), "centroid": sum / float(maxi(1, count)), "opaque_count": count}


static func _enclosed_holes(image: Image) -> Array[Dictionary]:
	var holes: Array[Dictionary] = []
	var visited := PackedByteArray()
	var width := image.get_width()
	var height := image.get_height()
	visited.resize(width * height)
	for y: int in range(height):
		for x: int in range(width):
			var start := Vector2i(x, y)
			if visited[y * width + x] != 0 or _opaque(image, start): continue
			var queue: Array[Vector2i] = [start]
			visited[y * width + x] = 1
			var index := 0
			var open := false
			var minimum := start
			var maximum := start
			var sum := Vector2.ZERO
			var rows := {}
			while index < queue.size():
				var point := queue[index]
				index += 1
				sum += Vector2(point)
				minimum = Vector2i(mini(minimum.x, point.x), mini(minimum.y, point.y))
				maximum = Vector2i(maxi(maximum.x, point.x), maxi(maximum.y, point.y))
				var row: Vector2i = rows.get(point.y, Vector2i(point.x, point.x))
				rows[point.y] = Vector2i(mini(row.x, point.x), maxi(row.y, point.x))
				if point.x == 0 or point.y == 0 or point.x == width - 1 or point.y == height - 1: open = true
				for step: Vector2i in DIRECTIONS:
					var next := point + step
					if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height: continue
					var offset := next.y * width + next.x
					if visited[offset] != 0 or _opaque(image, next): continue
					visited[offset] = 1
					queue.append(next)
			if not open:
				holes.append({"area": queue.size(), "centroid": sum / float(queue.size()), "bounds": Rect2i(minimum, maximum - minimum + Vector2i.ONE), "rows": rows})
	return holes


static func _opaque_run(image: Image, start: Vector2i, direction: int) -> int:
	var length := 0
	var point := start
	while _opaque(image, point):
		length += 1
		point.x += direction
	return length


static func _vertical_span(image: Image, point: Vector2i) -> int:
	if not _opaque(image, point): return 0
	var up := point.y
	var down := point.y
	while _opaque(image, Vector2i(point.x, up - 1)): up -= 1
	while _opaque(image, Vector2i(point.x, down + 1)): down += 1
	return down - up + 1


static func _opaque(image: Image, point: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < image.get_width() and point.y < image.get_height() and image.get_pixelv(point).a > 0.10


static func _unresolved(reason: String) -> Dictionary:
	return {"resolved": false, "evidence": {"resolved": false, "reason": reason, "identity_or_color_used": false, "alpha_changed": false}}
