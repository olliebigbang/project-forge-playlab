class_name PixelWeaponDeformer
extends RefCounted


static func deform(rig: PixelWeaponVisualRig, geometry: Dictionary) -> Dictionary:
	if rig == null:
		return {"pixels": [], "role_bounds": {}, "role_centroids": {}, "errors": ["PIXEL_DEFORMER_RIG_MISSING"]}
	var body_path: PackedVector2Array = geometry.get("body", PackedVector2Array())
	var tether_path: PackedVector2Array = geometry.get("tether", PackedVector2Array())
	var weapon_origin := Vector2(geometry.get("weapon_origin", Vector2.ZERO))
	var source_grip := Vector2(geometry.get("source_grip", Vector2.ZERO))
	var contact := Vector2(geometry.get("contact", _path_end(tether_path, _path_end(body_path, weapon_origin))))
	var weapon_angle := float(geometry.get("weapon_angle", 0.0))
	var facing := -1.0 if float(geometry.get("facing", 1.0)) < 0.0 else 1.0
	var scale := maxf(0.01, float(geometry.get("scale", 1.0)))
	var longitudinal_scale := clampf(float(geometry.get("longitudinal_scale", 1.0)), 0.05, 1.0)
	var pixel_snap := bool(geometry.get("pixel_snap", true))
	var readable_tether := bool(geometry.get("readable_tether", false))
	var readable_links := bool(geometry.get("readable_links", false))
	var include_metadata := bool(geometry.get("include_metadata", true))
	var compact_pixels := bool(geometry.get("compact_pixels", false))
	var body_sampler := _polyline_sampler(body_path)
	var tether_sampler := _polyline_sampler(tether_path)
	var terminal_tangent := _path_end_tangent(tether_path, _path_end_tangent(body_path, Vector2.from_angle(weapon_angle) * facing))
	var output_size := maxf(1.0, ceilf(scale))
	var pixels: Array[Dictionary] = []
	var role_points: Dictionary = {}
	var adjusted_colors: Dictionary = {}
	for binding: Dictionary in rig.bindings:
		var role := str(binding.get("role", ""))
		var world := weapon_origin
		match role:
			"deform_body":
				world = _curve_bound_position_sampled(binding, body_sampler, facing, scale, weapon_origin, weapon_angle, source_grip, longitudinal_scale)
			"tether":
				world = _curve_bound_position_sampled(binding, tether_sampler, facing, scale, weapon_origin, weapon_angle, source_grip, longitudinal_scale)
			"terminal":
				world = _terminal_bound_position(binding, contact, terminal_tangent, facing, scale)
			_:
				world = _rigid_bound_position(binding, weapon_origin, source_grip, weapon_angle, facing, scale, longitudinal_scale)
		if pixel_snap:
			world = Vector2(roundf(world.x), roundf(world.y))
		var color := Color(binding.get("color", Color.WHITE))
		if (readable_tether and role == "tether") or readable_links:
			var color_key := str([color.to_rgba32(), role, readable_tether, readable_links])
			if adjusted_colors.has(color_key): color = adjusted_colors[color_key]
			else:
				if readable_tether and role == "tether": color = _tether_color(color)
				if readable_links: color = _linked_color(color)
				adjusted_colors[color_key] = color
		var pixel := {
			"position": world,
			"color": color,
			"role": role,
			"part_id": str(binding.get("part_id", "")),
			"z_index": int(binding.get("z_index", 0)),
			"size": output_size,
		}
		pixels.append(pixel)
		if include_metadata:
			if not role_points.has(role): role_points[role] = PackedVector2Array()
			var points: PackedVector2Array = role_points[role]
			points.append(world)
			role_points[role] = points
	# Resample the declared tether itself at screen-pixel density when stretched.
	# These are real rendered/contact pixels, not a separate debug guide line.
	if readable_tether and rig.has_role("tether") and tether_path.size() >= 2:
		var line_color := Color(0.60, 0.68, 0.70)
		for binding: Dictionary in rig.bindings:
			if str(binding.get("role", "")) == "tether":
				line_color = _tether_color(Color(binding.get("color", line_color)))
				break
		var samples := clampi(ceili(float(tether_sampler.total)), 1, 1024)
		var points: PackedVector2Array = role_points.get("tether", PackedVector2Array()) if include_metadata else PackedVector2Array()
		for index: int in range(samples + 1):
			var sampled := _sample_polyline_fast(tether_sampler, float(index) / samples)
			var point := Vector2(sampled.x, sampled.y).round()
			pixels.append({"position": point, "color": line_color, "role": "tether", "part_id": "resampled_declared_tether", "z_index": 2, "size": 1.0})
			if include_metadata: points.append(point)
		if include_metadata: role_points["tether"] = points
	if compact_pixels: pixels = _compact_pixels(pixels)
	return {
		"pixels": pixels,
		"role_bounds": _role_bounds(role_points) if include_metadata else {},
		"role_centroids": _role_centroids(role_points) if include_metadata else {},
		"role_points": role_points,
		"body_path": body_path,
		"tether_path": tether_path,
		"contact": contact,
		"errors": [],
	}


static func _tether_color(color: Color) -> Color:
	var luminance := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	if luminance >= 0.58: return color
	var readable := color.lerp(Color(0.72, 0.80, 0.82, color.a), 0.76)
	readable.a = color.a
	return readable


static func _linked_color(color: Color) -> Color:
	# Thin source rods need a bounded display contrast lift against the arena.
	# Preserve their hue, alpha, pixel positions and original finite palette.
	var luminance := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	if luminance >= 0.42: return color
	return color.lerp(Color(1.0, 1.0, 1.0, color.a), (0.42 - luminance) / (1.0 - luminance))


static func sample_polyline(path: PackedVector2Array, ratio: float) -> Dictionary:
	var sampled := _sample_polyline_fast(_polyline_sampler(path), ratio)
	var tangent := Vector2(sampled.z, sampled.w)
	return {
		"point": Vector2(sampled.x, sampled.y),
		"tangent": tangent,
		"normal": Vector2(-tangent.y, tangent.x),
	}


static func _polyline_sampler(path: PackedVector2Array) -> Dictionary:
	var cumulative := PackedFloat32Array([0.0])
	var total := 0.0
	for index: int in range(path.size() - 1):
		total += path[index].distance_to(path[index + 1])
		cumulative.append(total)
	return {"path": path, "cumulative": cumulative, "total": total}


## Packed point+tangent avoids allocating a Dictionary for every bound pixel.
static func _sample_polyline_fast(sampler: Dictionary, ratio: float) -> Vector4:
	var path: PackedVector2Array = sampler.path
	if path.is_empty(): return Vector4(0.0, 0.0, 1.0, 0.0)
	if path.size() == 1: return Vector4(path[0].x, path[0].y, 1.0, 0.0)
	var cumulative: PackedFloat32Array = sampler.cumulative
	var total := float(sampler.total)
	var target := clampf(ratio, 0.0, 1.0) * total
	for index: int in range(path.size() - 1):
		var start_distance := float(cumulative[index])
		var finish_distance := float(cumulative[index + 1])
		var length := finish_distance - start_distance
		if length <= 0.0001: continue
		if finish_distance >= target or index == path.size() - 2:
			var local_ratio := clampf((target - start_distance) / length, 0.0, 1.0)
			var tangent := (path[index + 1] - path[index]) / length
			var point := path[index].lerp(path[index + 1], local_ratio)
			return Vector4(point.x, point.y, tangent.x, tangent.y)
	var fallback := (path[-1] - path[-2]).normalized()
	return Vector4(path[-1].x, path[-1].y, fallback.x, fallback.y)


static func distance_to_polyline(point: Vector2, path: PackedVector2Array, start_ratio: float = 0.0) -> float:
	var active_path := trim_polyline(path, start_ratio)
	if active_path.is_empty():
		return INF
	if active_path.size() == 1:
		return point.distance_to(active_path[0])
	var nearest := INF
	for index: int in range(active_path.size() - 1):
		var start := active_path[index]
		var finish := active_path[index + 1]
		var span := finish - start
		var length_squared := span.length_squared()
		var ratio := clampf((point - start).dot(span) / length_squared, 0.0, 1.0) if length_squared > 0.0001 else 0.0
		nearest = minf(nearest, point.distance_to(start + span * ratio))
	return nearest


static func trim_polyline(path: PackedVector2Array, start_ratio: float) -> PackedVector2Array:
	if path.size() < 2 or start_ratio <= 0.0:
		return path.duplicate()
	if start_ratio >= 1.0:
		return PackedVector2Array([path[path.size() - 1]])
	var sample := sample_polyline(path, start_ratio)
	var result := PackedVector2Array([Vector2(sample.get("point", path[0]))])
	var total := _path_length(path)
	var target := total * start_ratio
	var consumed := 0.0
	for index: int in range(path.size() - 1):
		var length := path[index].distance_to(path[index + 1])
		if consumed + length > target + 0.0001:
			result.append(path[index + 1])
		consumed += length
	return result


static func joined_paths(body: PackedVector2Array, tether: PackedVector2Array) -> PackedVector2Array:
	var joined := body.duplicate()
	for point: Vector2 in tether:
		if joined.is_empty() or joined[joined.size() - 1].distance_to(point) > 0.001:
			joined.append(point)
	return joined


static func path_signature(path: PackedVector2Array) -> Dictionary:
	var turn := 0.0
	var maximum_corner := 0.0
	for index: int in range(1, path.size() - 1):
		var before := (path[index] - path[index - 1]).normalized()
		var after := (path[index + 1] - path[index]).normalized()
		var corner := absf(wrapf(after.angle() - before.angle(), -PI, PI))
		turn += corner
		maximum_corner = maxf(maximum_corner, corner)
	return {
		"point_count": path.size(),
		"length": _path_length(path),
		"turn_radians": turn,
		"maximum_corner_radians": maximum_corner,
		"start": path[0] if not path.is_empty() else Vector2.ZERO,
		"end": path[path.size() - 1] if not path.is_empty() else Vector2.ZERO,
	}


static func rasterize(
	deformation: Dictionary,
	padding: int = 8,
	pixel_scale: int = 3,
	background: Color = Color.TRANSPARENT
) -> Dictionary:
	var pixels: Array = deformation.get("pixels", [])
	if pixels.is_empty():
		return {"image": null, "world_bounds": Rect2(), "origin": Vector2.ZERO}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for pixel: Dictionary in pixels:
		var position := Vector2(pixel.get("position", Vector2.ZERO))
		var half_size := float(pixel.get("size", 1.0)) * 0.5
		minimum.x = minf(minimum.x, position.x - half_size)
		minimum.y = minf(minimum.y, position.y - half_size)
		maximum.x = maxf(maximum.x, position.x + half_size)
		maximum.y = maxf(maximum.y, position.y + half_size)
	var origin := Vector2(floorf(minimum.x) - float(padding), floorf(minimum.y) - float(padding))
	var width := maxi(1, ceili(maximum.x - origin.x) + padding)
	var height := maxi(1, ceili(maximum.y - origin.y) + padding)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(background)
	for pixel: Dictionary in pixels:
		var position := Vector2(pixel.get("position", Vector2.ZERO)) - origin
		var size := maxi(1, ceili(float(pixel.get("size", 1.0))))
		var top_left := Vector2i(roundi(position.x - float(size) * 0.5), roundi(position.y - float(size) * 0.5))
		image.fill_rect(Rect2i(top_left, Vector2i(size, size)), Color(pixel.get("color", Color.WHITE)))
	var scale_factor := maxi(1, pixel_scale)
	if scale_factor > 1:
		image.resize(image.get_width() * scale_factor, image.get_height() * scale_factor, Image.INTERPOLATE_NEAREST)
	return {
		"image": image,
		"world_bounds": Rect2(minimum, maximum - minimum),
		"origin": origin,
		"pixel_scale": scale_factor,
	}


static func _curve_bound_position(
	binding: Dictionary,
	path: PackedVector2Array,
	facing: float,
	scale: float,
	weapon_origin: Vector2,
	weapon_angle: float,
	source_grip: Vector2,
	longitudinal_scale: float = 1.0
) -> Vector2:
	return _curve_bound_position_sampled(binding, _polyline_sampler(path), facing, scale, weapon_origin, weapon_angle, source_grip, longitudinal_scale)


static func _curve_bound_position_sampled(
	binding: Dictionary,
	sampler: Dictionary,
	facing: float,
	scale: float,
	weapon_origin: Vector2,
	weapon_angle: float,
	source_grip: Vector2,
	longitudinal_scale: float = 1.0
) -> Vector2:
	var path: PackedVector2Array = sampler.path
	if path.size() < 2:
		return _rigid_bound_position(binding, weapon_origin, source_grip, weapon_angle, facing, scale, longitudinal_scale)
	var sample := _sample_polyline_fast(sampler, float(binding.get("ratio", 0.0)))
	var normal := Vector2(-sample.w, sample.z)
	var offset := float(binding.get("normal_offset", 0.0)) * facing * scale
	return Vector2(sample.x, sample.y) + normal * offset


static func _compact_pixels(pixels: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var index_by_position: Dictionary = {}
	for pixel: Dictionary in pixels:
		var position := Vector2(pixel.get("position", Vector2.ZERO))
		var key := Vector2i(roundi(position.x), roundi(position.y))
		if index_by_position.has(key): result[int(index_by_position[key])] = pixel
		else:
			index_by_position[key] = result.size()
			result.append(pixel)
	return result


static func _rigid_bound_position(
	binding: Dictionary,
	weapon_origin: Vector2,
	source_grip: Vector2,
	weapon_angle: float,
	facing: float,
	scale: float,
	longitudinal_scale: float = 1.0
) -> Vector2:
	var source := Vector2(binding.get("source_position", source_grip)) - source_grip
	var mirrored := Vector2(source.x * facing, source.y) * scale
	mirrored.x *= longitudinal_scale
	return weapon_origin + mirrored.rotated(weapon_angle)


static func _terminal_bound_position(
	binding: Dictionary,
	contact: Vector2,
	target_tangent: Vector2,
	facing: float,
	scale: float
) -> Vector2:
	var local := Vector2(binding.get("local_offset", Vector2.ZERO))
	var mirrored_local := Vector2(local.x * facing, local.y) * scale
	var source_direction := Vector2(binding.get("source_direction", Vector2.RIGHT))
	source_direction = Vector2(source_direction.x * facing, source_direction.y).normalized()
	var target := target_tangent.normalized() if target_tangent.length_squared() > 0.0001 else Vector2.RIGHT
	var rotation_delta := wrapf(target.angle() - source_direction.angle(), -PI, PI)
	return contact + mirrored_local.rotated(rotation_delta)


static func _path_end(path: PackedVector2Array, fallback: Vector2) -> Vector2:
	return path[path.size() - 1] if not path.is_empty() else fallback


static func _path_end_tangent(path: PackedVector2Array, fallback: Vector2) -> Vector2:
	if path.size() < 2:
		return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector2.RIGHT
	return (path[path.size() - 1] - path[path.size() - 2]).normalized()


static func _path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for index: int in range(path.size() - 1):
		total += path[index].distance_to(path[index + 1])
	return total


static func _role_bounds(role_points: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for role: String in role_points:
		var points: PackedVector2Array = role_points[role]
		if points.is_empty():
			continue
		var minimum := points[0]
		var maximum := points[0]
		for point: Vector2 in points:
			minimum.x = minf(minimum.x, point.x)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x)
			maximum.y = maxf(maximum.y, point.y)
		result[role] = Rect2(minimum, maximum - minimum + Vector2.ONE)
	return result


static func _role_centroids(role_points: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for role: String in role_points:
		var points: PackedVector2Array = role_points[role]
		if points.is_empty():
			continue
		var total := Vector2.ZERO
		for point: Vector2 in points:
			total += point
		result[role] = total / float(points.size())
	return result
