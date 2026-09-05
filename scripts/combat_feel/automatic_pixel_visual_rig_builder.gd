class_name AutomaticPixelVisualRigBuilder
extends RefCounted

const PIXEL_VISUAL_RIG := preload("res://scripts/data/pixel_weapon_visual_rig.gd")
const ALPHA_THRESHOLD := 0.10
const TERMINAL_BINDING_SOURCE := "ai_axes_plus_alpha_path_v1_terminal_v2"
const HANDLE_FRACTIONS := {
	"none": 0.0,
	"short": 0.12,
	"medium": 0.21,
	"long": 0.31,
}


static func build(asset: WeaponVisualAsset, affordance_profile: Resource) -> Dictionary:
	if asset == null or asset.source_image == null or asset.source_image.is_empty():
		return _failure("AI_VISUAL_RIG_AUTOBUILD_ASSET_MISSING")
	if affordance_profile == null:
		return _failure("AI_VISUAL_RIG_AUTOBUILD_AFFORDANCE_MISSING")
	var has_body := str(affordance_profile.flex_topology) != "none"
	var has_tether := str(affordance_profile.tether_topology) != "none"
	if not has_body and not has_tether:
		return _failure("AI_VISUAL_RIG_AUTOBUILD_SOFT_AXIS_MISSING")

	var image := asset.source_image
	var original_mask := _alpha_mask(image)
	var path_result := _connected_path(original_mask, image.get_size(), asset.grip_primary, asset.tip)
	if not bool(path_result.get("ok", false)):
		var dilated_once := _dilate_mask(original_mask, image.get_size(), 1)
		path_result = _connected_path(dilated_once, image.get_size(), asset.grip_primary, asset.tip, original_mask)
	if not bool(path_result.get("ok", false)):
		var dilated_twice := _dilate_mask(original_mask, image.get_size(), 2)
		path_result = _connected_path(dilated_twice, image.get_size(), asset.grip_primary, asset.tip, original_mask)
	if not bool(path_result.get("ok", false)):
		return _failure("AI_VISUAL_RIG_AUTOBUILD_PATH_NOT_CONNECTED")

	var raw_path: PackedVector2Array = path_result.get("path", PackedVector2Array())
	if raw_path.size() < 4:
		return _failure("AI_VISUAL_RIG_AUTOBUILD_PATH_TOO_SHORT")
	var handle_fraction := float(HANDLE_FRACTIONS.get(str(affordance_profile.handle_length), 0.12))
	var handle_index := clampi(roundi(float(raw_path.size() - 1) * handle_fraction), 0, raw_path.size() - 3)
	var tether_index := raw_path.size() - 1
	var split_trace := {"method": "none", "confidence": 1.0}
	if has_tether:
		var split := _tether_split(raw_path, original_mask, image.get_size(), handle_index)
		tether_index = clampi(int(split.get("index", roundi(float(raw_path.size() - 1) * 0.58))), handle_index + 2, raw_path.size() - 2)
		split_trace = split

	var body_raw := _path_slice(raw_path, handle_index, tether_index if has_tether else raw_path.size() - 1)
	var tether_raw := _path_slice(raw_path, tether_index, raw_path.size() - 1) if has_tether else PackedVector2Array()
	var body_path := _resample_path(body_raw)
	var tether_path := _resample_path(tether_raw) if has_tether else PackedVector2Array()
	if body_path.size() < 2 or (has_tether and tether_path.size() < 2):
		return _failure("AI_VISUAL_RIG_AUTOBUILD_RESAMPLE_FAILED")

	var root_finish := raw_path[handle_index]
	var root_polygon := _capsule_polygon(
		asset.grip_primary,
		root_finish,
		_root_half_width(original_mask, image.get_size(), asset.grip_primary),
		image.get_size()
	)
	var parts: Array[Dictionary] = [{
		"id": "automatic_root_fixture",
		"role": "rigid_root",
		"pivot": [asset.grip_primary.x, asset.grip_primary.y],
		"source_direction": _array_from_vector(_path_tangent(raw_path, 0)),
		"mask_polygon": _arrays_from_points(root_polygon),
		"priority": 100,
		"z_index": 0,
	}]
	var body_radius := _path_mask_radius(body_raw, original_mask, image.get_size(), 2.5)
	if has_body:
		parts.append({
			"id": "automatic_primary_soft_structure",
			"role": "deform_body",
			"source_path": _arrays_from_points(body_path),
			"mask_radius": body_radius,
			"priority": 20,
			"z_index": 1,
		})
	else:
		parts.append({
			"id": "automatic_primary_rigid_structure",
			"role": "rigid_body",
			"pivot": [asset.grip_primary.x, asset.grip_primary.y],
			"source_direction": _array_from_vector(_path_tangent(raw_path, handle_index)),
			"mask_polygon": _arrays_from_points(_capsule_polygon(
				body_raw[0], body_raw[body_raw.size() - 1], body_radius, image.get_size()
			)),
			"priority": 10,
			"z_index": 1,
		})
	if has_tether:
		parts.append({
			"id": "automatic_attached_soft_structure",
			"role": "tether",
			"source_path": _arrays_from_points(tether_path),
			"mask_radius": _path_mask_radius(tether_raw, original_mask, image.get_size(), 1.5),
			"priority": 30,
			"z_index": 2,
		})
	if str(affordance_profile.terminal_load) != "none":
		var terminal_radius := 8.0 if str(affordance_profile.terminal_load) == "light" else 12.0
		parts.append({
			"id": "automatic_terminal_fixture",
			"role": "terminal",
			"pivot": [asset.tip.x, asset.tip.y],
			"source_direction": _array_from_vector(_path_tangent(raw_path, raw_path.size() - 2)),
			"mask_polygon": _arrays_from_points(_terminal_fixture_polygon(original_mask, image.get_size(), asset.tip, asset.grip_primary, terminal_radius)),
			"priority": 110,
			"z_index": 3,
		})

	var path_confidence := float(path_result.get("confidence", 0.72))
	var split_confidence := float(split_trace.get("confidence", 1.0))
	var confidence := clampf(minf(path_confidence, split_confidence), 0.65, 0.88)
	var contract := {
		"schema": PIXEL_VISUAL_RIG.SCHEMA,
		"source": "ai_axes_plus_alpha_path_v1",
		"automatic": true,
		"player_confirmation_required": false,
		"confidence": confidence,
		"parts": parts,
	}
	var rig: PixelWeaponVisualRig = PIXEL_VISUAL_RIG.from_dict(contract, image)
	var rig_errors := rig.validation_errors()
	if not rig_errors.is_empty():
		var failed := _failure("AI_VISUAL_RIG_AUTOBUILD_INVALID:%s" % ",".join(rig_errors))
		failed["contract"] = contract
		return failed
	var axis_errors := rig.axis_errors(affordance_profile)
	if not axis_errors.is_empty():
		return _failure("AI_VISUAL_RIG_AUTOBUILD_AXIS_MISMATCH:%s" % ",".join(axis_errors))
	return {
		"ok": true,
		"automatic": true,
		"player_confirmation_required": false,
		"source": "ai_axes_plus_alpha_path_v1",
		"confidence": confidence,
		"rig": rig,
		"contract": contract,
		"tether_origin": raw_path[tether_index] if has_tether else asset.tip,
		"trace": {
			"path_method": str(path_result.get("method", "")),
			"path_points": raw_path.size(),
			"handle_fraction": handle_fraction,
			"handle_index": handle_index,
			"tether_split": split_trace,
		},
	}


static func _connected_path(
	walkable_mask: PackedByteArray,
	size: Vector2i,
	start_value: Vector2,
	finish_value: Vector2,
	original_mask: PackedByteArray = PackedByteArray()
) -> Dictionary:
	var start := _nearest_mask_point(walkable_mask, size, Vector2i(start_value.round()), 12)
	var finish := _nearest_mask_point(walkable_mask, size, Vector2i(finish_value.round()), 12)
	if start.x < 0 or finish.x < 0:
		return {"ok": false}
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	grid.update()
	for y: int in range(size.y):
		for x: int in range(size.x):
			var index := y * size.x + x
			var point := Vector2i(x, y)
			if walkable_mask[index] == 0:
				grid.set_point_solid(point, true)
			elif not original_mask.is_empty() and original_mask[index] == 0:
				grid.set_point_weight_scale(point, 5.0)
	var ids: Array[Vector2i] = grid.get_id_path(start, finish)
	if ids.size() < 2:
		return {"ok": false}
	var path := PackedVector2Array()
	for point: Vector2i in ids:
		path.append(Vector2(point))
	return {
		"ok": true,
		"path": path,
		"method": "alpha_connected_path" if original_mask.is_empty() else "dilated_alpha_connected_path",
		"confidence": 0.84 if original_mask.is_empty() else 0.72,
	}


static func _tether_split(path: PackedVector2Array, mask: PackedByteArray, size: Vector2i, handle_index: int) -> Dictionary:
	var first := maxi(handle_index + 2, roundi(float(path.size() - 1) * 0.32))
	var last := mini(path.size() - 2, roundi(float(path.size() - 1) * 0.84))
	var best_index := clampi(roundi(float(path.size() - 1) * 0.58), first, last)
	var best_score := -INF
	for index: int in range(first, last + 1):
		var before := _window_width(path, mask, size, index - 6, index - 1)
		var after := _window_width(path, mask, size, index + 1, index + 6)
		var drop := before - after
		var thin_reward := maxf(0.0, 2.2 - after) * 0.35
		var score := drop + thin_reward
		if score > best_score:
			best_score = score
			best_index = index
	if best_score >= 0.65:
		return {
			"index": best_index,
			"method": "alpha_thickness_transition",
			"score": best_score,
			"confidence": clampf(0.72 + best_score * 0.08, 0.72, 0.88),
		}
	return {
		"index": best_index,
		"method": "axis_guided_path_fraction",
		"score": best_score,
		"confidence": 0.68,
	}


static func _window_width(path: PackedVector2Array, mask: PackedByteArray, size: Vector2i, first: int, last: int) -> float:
	var total := 0.0
	var count := 0
	for index: int in range(maxi(0, first), mini(path.size() - 1, last) + 1):
		total += _alpha_radius(mask, size, Vector2i(path[index].round()), 8)
		count += 1
	return total / maxf(1.0, float(count))


static func _alpha_mask(image: Image) -> PackedByteArray:
	var size := image.get_size()
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	for y: int in range(size.y):
		for x: int in range(size.x):
			mask[y * size.x + x] = 1 if image.get_pixel(x, y).a >= ALPHA_THRESHOLD else 0
	return mask


static func _dilate_mask(mask: PackedByteArray, size: Vector2i, radius: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(mask.size())
	for y: int in range(size.y):
		for x: int in range(size.x):
			if mask[y * size.x + x] == 0:
				continue
			for offset_y: int in range(-radius, radius + 1):
				for offset_x: int in range(-radius, radius + 1):
					var check_x := x + offset_x
					var check_y := y + offset_y
					if check_x >= 0 and check_y >= 0 and check_x < size.x and check_y < size.y:
						result[check_y * size.x + check_x] = 1
	return result


static func _nearest_mask_point(mask: PackedByteArray, size: Vector2i, desired: Vector2i, radius: int) -> Vector2i:
	var nearest := Vector2i(-1, -1)
	var nearest_distance := INF
	for y: int in range(maxi(0, desired.y - radius), mini(size.y - 1, desired.y + radius) + 1):
		for x: int in range(maxi(0, desired.x - radius), mini(size.x - 1, desired.x + radius) + 1):
			if mask[y * size.x + x] == 0:
				continue
			var distance := Vector2i(x, y).distance_squared_to(desired)
			if distance < nearest_distance:
				nearest = Vector2i(x, y)
				nearest_distance = distance
	return nearest


static func _alpha_radius(mask: PackedByteArray, size: Vector2i, center: Vector2i, maximum: int) -> float:
	if center.x < 0 or center.y < 0 or center.x >= size.x or center.y >= size.y:
		return 0.0
	if mask[center.y * size.x + center.x] == 0:
		return 0.0
	var nearest := float(maximum)
	for offset_y: int in range(-maximum, maximum + 1):
		for offset_x: int in range(-maximum, maximum + 1):
			var check_x := center.x + offset_x
			var check_y := center.y + offset_y
			if check_x < 0 or check_y < 0 or check_x >= size.x or check_y >= size.y \
					or mask[check_y * size.x + check_x] == 0:
				nearest = minf(nearest, Vector2(offset_x, offset_y).length())
	return nearest


static func _path_mask_radius(path: PackedVector2Array, mask: PackedByteArray, size: Vector2i, padding: float) -> float:
	if path.is_empty():
		return padding
	var total := 0.0
	var count := 0
	var stride := maxi(1, int(path.size() / 16))
	for index: int in range(0, path.size(), stride):
		total += _alpha_radius(mask, size, Vector2i(path[index].round()), 10)
		count += 1
	return clampf(total / maxf(1.0, float(count)) + padding, 2.0, 12.0)


static func _root_half_width(mask: PackedByteArray, size: Vector2i, grip: Vector2) -> float:
	return clampf(_alpha_radius(mask, size, Vector2i(grip.round()), 12) + 6.0, 7.0, 14.0)


static func _capsule_polygon(start: Vector2, finish: Vector2, half_width: float, size: Vector2i) -> PackedVector2Array:
	var tangent := (finish - start).normalized()
	if tangent.length_squared() < 0.0001:
		tangent = Vector2.RIGHT
	var normal := Vector2(-tangent.y, tangent.x) * half_width
	var extension := tangent * 4.0
	return _clamped_polygon(PackedVector2Array([
		start - extension - normal,
		finish + extension - normal,
		finish + extension + normal,
		start - extension + normal,
	]), size)


static func _square_polygon(center: Vector2, radius: float, size: Vector2i) -> PackedVector2Array:
	return _clamped_polygon(PackedVector2Array([
		center + Vector2(-radius, -radius),
		center + Vector2(radius, -radius),
		center + Vector2(radius, radius),
		center + Vector2(-radius, radius),
	]), size)


static func _terminal_fixture_polygon(mask: PackedByteArray, size: Vector2i, tip: Vector2, grip: Vector2, fallback_radius: float) -> PackedVector2Array:
	# Segment only the binding mask, never change the source Alpha. Eroding a
	# one-pixel neck isolates a broad terminal fixture from its flexible path.
	# A fixed square around the strike anchor could cut a tall fixture in half,
	# assigning its remaining rigid pixels to the stretching cord.
	var core := PackedByteArray(); core.resize(mask.size()); core.fill(0)
	for y: int in range(1, size.y - 1):
		for x: int in range(1, size.x - 1):
			var i := y * size.x + x
			if mask[i] and mask[i - 1] and mask[i + 1] and mask[i - size.x] and mask[i + size.x]: core[i] = 1
	var seed_point := _nearest_mask_point(core, size, Vector2i(tip.round()), 8)
	if seed_point.x < 0: return _square_polygon(tip, fallback_radius, size)
	var pending: Array[Vector2i] = [seed_point]
	var seen := {}; seen[seed_point] = true
	var bounds := Rect2(Vector2(seed_point), Vector2.ONE)
	var cursor := 0
	while cursor < pending.size():
		var point := pending[cursor]; cursor += 1
		bounds = bounds.expand(Vector2(point)); bounds = bounds.expand(Vector2(point + Vector2i.ONE))
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var candidate := point + offset
			if candidate.x < 0 or candidate.y < 0 or candidate.x >= size.x or candidate.y >= size.y or seen.has(candidate): continue
			if core[candidate.y * size.x + candidate.x] == 0: continue
			seen[candidate] = true; pending.append(candidate)
	var padded := bounds.grow(1.1)
	# Do not capture the entire body or held fixture when no separate neck exists.
	if pending.size() < 3 or padded.has_point(grip) or maxf(padded.size.x, padded.size.y) > maxf(size.x, size.y) * 0.55:
		return _square_polygon(tip, fallback_radius, size)
	return _clamped_polygon(PackedVector2Array([padded.position, Vector2(padded.end.x, padded.position.y), padded.end, Vector2(padded.position.x, padded.end.y)]), size)


static func refresh_automatic_terminal_binding(asset: WeaponVisualAsset) -> bool:
	# Runtime-only upgrade of our own older automatic masks. Preserve custom
	# rigs, source pixels, all anchors/paths and the immutable saved package.
	if asset == null or asset.source_image == null or asset.visual_rig == null: return false
	var old := asset.visual_rig
	if old.source != "ai_axes_plus_alpha_path_v1" or not old.has_role("terminal"): return false
	var parts: Array[Dictionary] = []
	for raw: Dictionary in old.parts:
		var part := raw.duplicate(true)
		if part.role == "terminal":
			part.mask_polygon = _terminal_fixture_polygon(_alpha_mask(asset.source_image), asset.source_image.get_size(), Vector2(part.pivot), asset.grip_primary, 8.0)
		for key: String in ["source_path", "mask_polygon"]: part[key] = _arrays_from_points(part[key])
		for key: String in ["pivot", "source_direction"]: part[key] = _array_from_vector(part[key])
		parts.append(part)
	var fresh := PIXEL_VISUAL_RIG.from_dict({"schema": old.schema, "source": TERMINAL_BINDING_SOURCE, "automatic": old.automatic, "player_confirmation_required": old.player_confirmation_required, "confidence": old.confidence, "parts": parts}, asset.source_image)
	if not fresh.validation_errors().is_empty(): return false
	asset.visual_rig = fresh; asset.visual_rig_source = TERMINAL_BINDING_SOURCE
	return true


static func _clamped_polygon(points: PackedVector2Array, size: Vector2i) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(Vector2(
			clampf(point.x, 0.0, float(size.x - 1)),
			clampf(point.y, 0.0, float(size.y - 1))
		))
	return result


static func _path_slice(path: PackedVector2Array, first: int, last: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index: int in range(clampi(first, 0, path.size() - 1), clampi(last, 0, path.size() - 1) + 1):
		result.append(path[index])
	return result


static func _resample_path(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() <= 2:
		return path.duplicate()
	var cumulative: Array[float] = [0.0]
	var total := 0.0
	for index: int in range(path.size() - 1):
		total += path[index].distance_to(path[index + 1])
		cumulative.append(total)
	var sample_count := clampi(ceili(total / 7.0) + 1, 4, 16)
	var result := PackedVector2Array()
	for sample_index: int in range(sample_count):
		var target := total * float(sample_index) / float(sample_count - 1)
		for index: int in range(cumulative.size() - 1):
			if cumulative[index + 1] + 0.0001 < target:
				continue
			var span := maxf(0.0001, cumulative[index + 1] - cumulative[index])
			var ratio := clampf((target - cumulative[index]) / span, 0.0, 1.0)
			result.append(path[index].lerp(path[index + 1], ratio))
			break
	return result


static func _path_tangent(path: PackedVector2Array, index: int) -> Vector2:
	if path.size() < 2:
		return Vector2.RIGHT
	var start := clampi(index, 0, path.size() - 2)
	return (path[start + 1] - path[start]).normalized()


static func _arrays_from_points(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point: Vector2 in points:
		result.append([point.x, point.y])
	return result


static func _array_from_vector(value: Vector2) -> Array:
	return [value.x, value.y]


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"automatic": true,
		"player_confirmation_required": false,
	}
