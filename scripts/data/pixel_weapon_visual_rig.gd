class_name PixelWeaponVisualRig
extends RefCounted

const SCHEMA := "forge-pixel-weapon-visual-rig-v1"
const MIN_ALPHA := 0.02
const MIN_CONFIDENCE := 0.65
const PART_ROLES: PackedStringArray = [
	"rigid_root",
	"rigid_body",
	"deform_body",
	"tether",
	"terminal",
]
const CURVE_ROLES: PackedStringArray = ["deform_body", "tether"]

var schema := SCHEMA
var source := ""
var automatic := false
var player_confirmation_required := true
var confidence := 0.0
var parts: Array[Dictionary] = []
var bindings: Array[Dictionary] = []
var role_pixel_counts: Dictionary = {}
var source_opaque_pixels := 0
var unassigned_pixels := 0
var canvas_size := Vector2i.ZERO
var _linked_joint_cache: PackedFloat32Array = PackedFloat32Array()
var _linked_joint_measured := false


func linked_joint_ratios() -> PackedFloat32Array:
	# Narrow runs in the actual alpha-bound body identify connectors. No item
	# name or assumed number of rods: an unsegmented silhouette stays rigid.
	if _linked_joint_measured: return _linked_joint_cache
	_linked_joint_measured = true
	var path := source_path_for_role("deform_body")
	var length := 0.0
	for index: int in range(path.size() - 1): length += path[index].distance_to(path[index + 1])
	var bins := maxi(2, roundi(length) + 1)
	var lows: Array[float] = []
	var highs: Array[float] = []
	lows.resize(bins); lows.fill(INF)
	highs.resize(bins); highs.fill(-INF)
	for binding: Dictionary in bindings:
		if str(binding.get("role", "")) != "deform_body": continue
		var index := clampi(roundi(float(binding.get("ratio", 0.0)) * (bins - 1)), 0, bins - 1)
		var offset := float(binding.get("normal_offset", 0.0))
		lows[index] = minf(lows[index], offset)
		highs[index] = maxf(highs[index], offset)
	var widths: Array[float] = []
	var thick := 0.0
	for index: int in range(bins):
		var width := maxf(0.0, highs[index] - lows[index] + 1.0)
		widths.append(width)
		thick = maxf(thick, width)
	if thick < 3.0: return _linked_joint_cache
	var run := -1
	for index: int in range(bins):
		var narrow := widths[index] <= thick * 0.60
		if narrow and run < 0: run = index
		if not narrow and run >= 0:
			var middle := float(run + index - 1) * 0.5
			var ratio := middle / float(bins - 1)
			# Both sides must have substantial rod material, not a tapered tip.
			if run >= 4 and index < bins - 4 and index - run <= bins * 0.18:
				if _linked_joint_cache.is_empty() or ratio - _linked_joint_cache[-1] >= 0.12:
					_linked_joint_cache.append(ratio)
			run = -1
	return _linked_joint_cache


static func from_dict(data: Dictionary, image: Image, flip_x: bool = false) -> PixelWeaponVisualRig:
	var rig := PixelWeaponVisualRig.new()
	rig._load_contract(data, image.get_size() if image != null else Vector2i.ZERO, flip_x)
	if image != null and not image.is_empty() and rig.validation_errors().is_empty():
		rig._bind_pixels(image)
	return rig


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if schema != SCHEMA:
		errors.append("VISUAL_RIG_SCHEMA_INVALID")
	if canvas_size.x <= 0 or canvas_size.y <= 0:
		errors.append("VISUAL_RIG_CANVAS_INVALID")
	if source.strip_edges().is_empty():
		errors.append("VISUAL_RIG_SOURCE_MISSING")
	if not automatic:
		errors.append("VISUAL_RIG_MUST_BE_AUTOMATIC")
	if player_confirmation_required:
		errors.append("VISUAL_RIG_PLAYER_CONFIRMATION_FORBIDDEN")
	if confidence < MIN_CONFIDENCE or confidence > 1.0:
		errors.append("VISUAL_RIG_CONFIDENCE_INVALID")
	if parts.is_empty():
		errors.append("VISUAL_RIG_PARTS_MISSING")
	var ids: Dictionary = {}
	for part: Dictionary in parts:
		var part_id := str(part.get("id", ""))
		var role := str(part.get("role", ""))
		if part_id.is_empty():
			errors.append("VISUAL_RIG_PART_ID_MISSING")
		elif ids.has(part_id):
			errors.append("VISUAL_RIG_PART_ID_DUPLICATE:%s" % part_id)
		ids[part_id] = true
		if role not in PART_ROLES:
			errors.append("VISUAL_RIG_ROLE_INVALID:%s" % part_id)
		var path: PackedVector2Array = part.get("source_path", PackedVector2Array())
		var polygon: PackedVector2Array = part.get("mask_polygon", PackedVector2Array())
		if role in CURVE_ROLES and path.size() < 2:
			errors.append("VISUAL_RIG_CURVE_PATH_MISSING:%s" % part_id)
		if role in CURVE_ROLES and float(part.get("mask_radius", 0.0)) <= 0.0:
			errors.append("VISUAL_RIG_CURVE_RADIUS_INVALID:%s" % part_id)
		if role not in CURVE_ROLES and polygon.size() < 3:
			errors.append("VISUAL_RIG_MASK_MISSING:%s" % part_id)
		for point: Vector2 in path:
			if not _point_is_in_canvas(point):
				errors.append("VISUAL_RIG_PATH_OUT_OF_BOUNDS:%s" % part_id)
				break
		for point: Vector2 in polygon:
			if not _point_is_in_canvas(point):
				errors.append("VISUAL_RIG_MASK_OUT_OF_BOUNDS:%s" % part_id)
				break
	if not has_role("rigid_root"):
		errors.append("VISUAL_RIG_RIGID_ROOT_MISSING")
	if source_opaque_pixels > 0:
		if bindings.size() != source_opaque_pixels:
			errors.append("VISUAL_RIG_PIXEL_BINDING_INCOMPLETE")
		if unassigned_pixels > 0:
			errors.append("VISUAL_RIG_PIXEL_UNASSIGNED")
		for part: Dictionary in parts:
			if int(role_pixel_counts.get(str(part.get("role", "")), 0)) <= 0:
				errors.append("VISUAL_RIG_ROLE_HAS_NO_PIXELS:%s" % str(part.get("role", "")))
	return errors


func axis_errors(affordance_profile: Resource) -> Array[String]:
	var errors: Array[String] = []
	if affordance_profile == null:
		return ["VISUAL_RIG_AFFORDANCE_MISSING"]
	if str(affordance_profile.flex_topology) != "none" and not has_role("deform_body"):
		errors.append("VISUAL_RIG_DEFORM_BODY_REQUIRED")
	if str(affordance_profile.tether_topology) != "none" and not has_role("tether"):
		errors.append("VISUAL_RIG_TETHER_REQUIRED")
	if str(affordance_profile.terminal_load) != "none" and not has_role("terminal"):
		errors.append("VISUAL_RIG_TERMINAL_REQUIRED")
	if str(affordance_profile.flex_topology) == "none" and has_role("deform_body"):
		errors.append("VISUAL_RIG_DEFORM_BODY_WITHOUT_AXIS")
	if str(affordance_profile.tether_topology) == "none" and has_role("tether"):
		errors.append("VISUAL_RIG_TETHER_WITHOUT_AXIS")
	return errors


func has_role(role: String) -> bool:
	for part: Dictionary in parts:
		if str(part.get("role", "")) == role:
			return true
	return false


func pixel_count(role: String) -> int:
	return int(role_pixel_counts.get(role, 0))


func source_path_for_role(role: String) -> PackedVector2Array:
	for part: Dictionary in parts:
		if str(part.get("role", "")) == role:
			return part.get("source_path", PackedVector2Array())
	return PackedVector2Array()


func summary() -> Dictionary:
	return {
		"schema": schema,
		"source": source,
		"automatic": automatic,
		"player_confirmation_required": player_confirmation_required,
		"confidence": confidence,
		"part_count": parts.size(),
		"source_opaque_pixels": source_opaque_pixels,
		"bound_pixels": bindings.size(),
		"unassigned_pixels": unassigned_pixels,
		"role_pixel_counts": role_pixel_counts.duplicate(true),
	}


func _load_contract(data: Dictionary, image_size: Vector2i, flip_x: bool) -> void:
	schema = str(data.get("schema", ""))
	source = str(data.get("source", ""))
	automatic = bool(data.get("automatic", false))
	player_confirmation_required = bool(data.get("player_confirmation_required", true))
	confidence = float(data.get("confidence", 0.0))
	canvas_size = image_size
	parts.clear()
	for value: Variant in data.get("parts", []):
		if not value is Dictionary:
			continue
		var raw: Dictionary = value
		var part := {
			"id": str(raw.get("id", "")),
			"role": str(raw.get("role", "")),
			"z_index": int(raw.get("z_index", 0)),
			"priority": int(raw.get("priority", 0)),
			"mask_radius": float(raw.get("mask_radius", 0.0)),
			"source_path": _points(raw.get("source_path", []), flip_x),
			"mask_polygon": _points(raw.get("mask_polygon", raw.get("polygon", [])), flip_x),
			"pivot": _point(raw.get("pivot", [0.0, 0.0]), flip_x),
			"source_direction": _direction(raw.get("source_direction", [1.0, 0.0]), flip_x),
		}
		parts.append(part)


func _bind_pixels(image: Image) -> void:
	_linked_joint_measured = false
	_linked_joint_cache.clear()
	bindings.clear()
	role_pixel_counts.clear()
	source_opaque_pixels = 0
	unassigned_pixels = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a <= MIN_ALPHA:
				continue
			source_opaque_pixels += 1
			var point := Vector2(float(x), float(y))
			var assignment := _assign_part(point)
			if assignment.is_empty():
				unassigned_pixels += 1
				continue
			var binding := _make_binding(point, color, assignment)
			bindings.append(binding)
			var role := str(binding.get("role", ""))
			role_pixel_counts[role] = int(role_pixel_counts.get(role, 0)) + 1
	bindings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var az := int(a.get("z_index", 0))
		var bz := int(b.get("z_index", 0))
		if az != bz:
			return az < bz
		var ap: Vector2 = a.get("source_position", Vector2.ZERO)
		var bp: Vector2 = b.get("source_position", Vector2.ZERO)
		return ap.y < bp.y or (is_equal_approx(ap.y, bp.y) and ap.x < bp.x)
	)


func _assign_part(point: Vector2) -> Dictionary:
	var explicit: Dictionary = {}
	var explicit_priority := -2147483648
	for part: Dictionary in parts:
		var polygon: PackedVector2Array = part.get("mask_polygon", PackedVector2Array())
		if polygon.size() < 3 or not Geometry2D.is_point_in_polygon(point, polygon):
			continue
		var priority := int(part.get("priority", 0))
		if explicit.is_empty() or priority > explicit_priority:
			explicit = part
			explicit_priority = priority
	if not explicit.is_empty():
		return explicit

	var nearest: Dictionary = {}
	var nearest_score := INF
	for part: Dictionary in parts:
		var role := str(part.get("role", ""))
		if role not in CURVE_ROLES:
			continue
		var projection := project_to_polyline(point, part.get("source_path", PackedVector2Array()))
		var radius := maxf(0.01, float(part.get("mask_radius", 0.0)))
		var score := float(projection.get("distance", INF)) / radius - float(part.get("priority", 0)) * 0.001
		if float(projection.get("distance", INF)) <= radius and score < nearest_score:
			nearest = part
			nearest_score = score
	if not nearest.is_empty():
		return nearest

	# Preserve every visible source pixel. If the AI mask leaves a one-pixel gap,
	# attach that pixel to the geometrically nearest declared part instead of
	# dropping identity detail or asking the player to repair the rig.
	for part: Dictionary in parts:
		var role := str(part.get("role", ""))
		var distance := INF
		if role in CURVE_ROLES:
			distance = float(project_to_polyline(point, part.get("source_path", PackedVector2Array())).get("distance", INF))
		else:
			distance = point.distance_to(Vector2(part.get("pivot", Vector2.ZERO)))
		if distance < nearest_score:
			nearest = part
			nearest_score = distance
	return nearest


func _make_binding(point: Vector2, color: Color, part: Dictionary) -> Dictionary:
	var role := str(part.get("role", ""))
	var binding := {
		"part_id": str(part.get("id", "")),
		"role": role,
		"z_index": int(part.get("z_index", 0)),
		"source_position": point,
		"color": color,
		"pivot": Vector2(part.get("pivot", Vector2.ZERO)),
		"source_direction": Vector2(part.get("source_direction", Vector2.RIGHT)).normalized(),
		"ratio": 0.0,
		"normal_offset": 0.0,
		"local_offset": point - Vector2(part.get("pivot", Vector2.ZERO)),
	}
	if role in CURVE_ROLES:
		var projection := project_to_polyline(point, part.get("source_path", PackedVector2Array()))
		binding["ratio"] = float(projection.get("ratio", 0.0))
		binding["normal_offset"] = float(projection.get("signed_offset", 0.0))
		binding["source_direction"] = Vector2(projection.get("tangent", Vector2.RIGHT))
	return binding


static func project_to_polyline(point: Vector2, path: PackedVector2Array) -> Dictionary:
	if path.size() < 2:
		return {
			"point": path[0] if path.size() == 1 else Vector2.ZERO,
			"ratio": 0.0,
			"distance": INF,
			"signed_offset": 0.0,
			"tangent": Vector2.RIGHT,
		}
	var total_length := 0.0
	var segment_lengths: Array[float] = []
	for index: int in range(path.size() - 1):
		var length := path[index].distance_to(path[index + 1])
		segment_lengths.append(length)
		total_length += length
	var best_distance := INF
	var best_point := path[0]
	var best_ratio := 0.0
	var best_offset := 0.0
	var best_tangent := Vector2.RIGHT
	var distance_before := 0.0
	for index: int in range(path.size() - 1):
		var start := path[index]
		var finish := path[index + 1]
		var span := finish - start
		var length: float = segment_lengths[index]
		if length <= 0.0001:
			continue
		var tangent := span / length
		var along := clampf((point - start).dot(tangent), 0.0, length)
		var projected := start + tangent * along
		var delta := point - projected
		var distance := delta.length()
		if distance < best_distance:
			best_distance = distance
			best_point = projected
			best_ratio = (distance_before + along) / maxf(0.0001, total_length)
			best_offset = delta.dot(Vector2(-tangent.y, tangent.x))
			best_tangent = tangent
		distance_before += length
	return {
		"point": best_point,
		"ratio": clampf(best_ratio, 0.0, 1.0),
		"distance": best_distance,
		"signed_offset": best_offset,
		"tangent": best_tangent,
	}


static func _points(value: Variant, flip_x: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not value is Array:
		return result
	for point_value: Variant in value:
		result.append(_point(point_value, flip_x))
	return result


static func _point(value: Variant, flip_x: bool) -> Vector2:
	var point := Vector2.ZERO
	if value is Array and value.size() >= 2:
		point = Vector2(float(value[0]), float(value[1]))
	elif value is Dictionary:
		point = Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	if flip_x:
		point.x = 95.0 - point.x
	return point


static func _direction(value: Variant, flip_x: bool) -> Vector2:
	var direction := _point(value, false)
	if flip_x:
		direction.x = -direction.x
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT


func _point_is_in_canvas(point: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x < float(canvas_size.x) and point.y < float(canvas_size.y)
