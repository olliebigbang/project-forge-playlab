class_name MechanismPixelScaffold
extends RefCounted

const CANVAS_SIZE := Vector2i(96, 96)
const OUTLINE := Color("151820")
const WOOD_DARK := Color("3a2419")
const WOOD_MID := Color("8b542d")
const WOOD_LIGHT := Color("c17a3d")
const BRASS_DARK := Color("79551f")
const BRASS_MID := Color("c79a3b")
const BRASS_LIGHT := Color("f0cf72")


static func build(affordance: Dictionary) -> Dictionary:
	var validation_error := _validation_error(affordance)
	if not validation_error.is_empty():
		return {"ok": false, "error": validation_error}
	var image := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var mass := str(affordance.get("mass_distribution", "balanced"))
	var handle_points := _handle_points(str(affordance.get("handle_length", "short")))
	var body_start: Vector2 = handle_points[-1]
	var body_finish := _body_finish(str(affordance.get("body_length", "medium")))
	var grip := _grip_anchor(handle_points, body_finish, mass)
	var strike := body_finish
	var tether_origin := body_finish
	var roles: Array[String] = ["rigid_root"]
	var topology := str(affordance.get("flex_topology", "none"))
	var tether := str(affordance.get("tether_topology", "none"))
	var terminal := str(affordance.get("terminal_load", "none"))
	var deployment := str(affordance.get("tether_deployment", "none"))
	var body_widths := _body_widths(mass)

	_draw_handle(image, affordance, handle_points)
	match topology:
		"bending_shaft":
			var body := _curve_between(
				body_start, body_finish,
				[0.0, 0.20, 0.42, 0.64, 0.84, 1.0],
				[0.0, -4.0, -8.0, -8.0, -4.0, 0.0]
			)
			_draw_tapered_path(image, body, body_widths.x, body_widths.y, WOOD_MID, WOOD_LIGHT)
			roles.append("deform_body")
			strike = body[-1]
		"flexible_line":
			var body := _curve_between(
				body_start, body_finish,
				[0.0, 0.18, 0.36, 0.53, 0.70, 0.86, 1.0],
				[0.0, -8.0, -13.0, 8.0, 13.0, 5.0, 0.0]
			)
			_draw_tapered_path(image, body, body_widths.x, maxi(3, body_widths.y - 1), WOOD_MID, BRASS_MID)
			strike = body[-1]
			roles.append("deform_body")
		"linked_segments":
			var centers := _curve_between(
				body_start, body_finish,
				[0.0, 0.20, 0.40, 0.60, 0.80, 1.0],
				[0.0, -2.0, 3.0, -3.0, 2.0, 0.0]
			)
			_draw_linked_path(image, centers, body_widths.x, body_widths.y)
			strike = centers[-1]
			roles.append("deform_body")
		_:
			var body := _rigid_body_points(body_start, body_finish, str(affordance.get("rigidity", "rigid")))
			_draw_tapered_path(image, body, body_widths.x, body_widths.y, WOOD_MID, WOOD_LIGHT)
			strike = body[-1]
			if tether != "none":
				roles.append("rigid_body")

	_draw_tether_deployment_fixture(
		image,
		handle_points[0].lerp(handle_points[-1], 0.45),
		(handle_points[-1] - handle_points[0]).normalized(),
		deployment
	)

	if tether != "none":
		tether_origin = strike
		var tether_points := _tether_points(
			tether_origin,
			str(affordance.get("tether_mode", "none")),
			deployment
		)
		if tether == "linked_segments":
			_draw_linked_path(image, tether_points, 5, 4)
		else:
			_draw_tapered_path(image, tether_points, 3, 2, BRASS_DARK, BRASS_MID)
		strike = tether_points[-1]
		roles.append("tether")

	_draw_secondary_contact(
		image,
		body_start,
		body_finish,
		str(affordance.get("secondary_contact_surface", "none"))
	)

	var contact_direction := (strike - (tether_origin if tether != "none" else body_start)).normalized()
	match str(affordance.get("contact_surface", "whole_body")):
		"point":
			strike = _draw_point_contact(image, strike, contact_direction)
		"edge":
			strike = _draw_edge_contact(image, strike, contact_direction)
		"broad":
			strike = _draw_broad_contact(image, strike, contact_direction)

	if str(affordance.get("tether_mode", "none")) == "hook":
		var hook := PackedVector2Array([
			strike,
			_clamp_point(strike + Vector2(3, 4)),
			_clamp_point(strike + Vector2(-2, 7)),
		])
		_draw_tapered_path(image, hook, 3, 2, BRASS_LIGHT, BRASS_LIGHT)
		strike = hook[-1]

	if terminal != "none":
		var radius := 7 if terminal == "heavy" else 5
		_fill_circle(image, Vector2i(strike.round()), radius + 2, OUTLINE)
		_fill_circle(image, Vector2i(strike.round()), radius, BRASS_MID)
		_fill_circle(
			image,
			Vector2i(strike.round()) + Vector2i(-1, -1),
			maxi(1, floori(float(radius) / 2.0)),
			BRASS_LIGHT
		)
		roles.append("terminal")

	_draw_state_fixture(image, body_start, body_finish, str(affordance.get("state_topology", "fixed")))
	_draw_activation_fixture(image, grip, (body_finish - body_start).normalized(), str(affordance.get("activation_mode", "passive")))
	_draw_output_fixture(image, strike, contact_direction, str(affordance.get("functional_output", "contact_only")))

	_draw_mass_distribution_cue(image, mass, grip, strike)

	return {
		"ok": true,
		"image": image,
		"automatic": true,
		"player_confirmation_required": false,
		"contract": {
			"schema": "forge-mechanism-pixel-scaffold-v1",
			"canvas": [CANVAS_SIZE.x, CANVAS_SIZE.y],
			"axes": _structural_axes(affordance),
			"required_roles": roles,
			"anchors": {
				"GripPrimary": [grip.x, grip.y],
				"StrikePoint": [strike.x, strike.y],
				"TetherOrigin": [tether_origin.x, tether_origin.y],
			},
			"palette": _palette_hex(),
			"structure_locked": true,
			"style_may_change": true,
		},
	}


static func palette_image() -> Image:
	var colors := [OUTLINE, WOOD_DARK, WOOD_MID, WOOD_LIGHT, BRASS_DARK, BRASS_MID, BRASS_LIGHT]
	var image := Image.create(colors.size(), 1, false, Image.FORMAT_RGBA8)
	for index: int in range(colors.size()):
		image.set_pixel(index, 0, colors[index])
	return image


static func _handle_points(length: String) -> PackedVector2Array:
	match length:
		"none": return PackedVector2Array([Vector2(10, 86), Vector2(20, 74)])
		"medium": return PackedVector2Array([Vector2(5, 91), Vector2(28, 63)])
		"long": return PackedVector2Array([Vector2(3, 93), Vector2(34, 56)])
		_: return PackedVector2Array([Vector2(7, 88), Vector2(23, 69)])


static func _body_finish(length: String) -> Vector2:
	match length:
		"short": return Vector2(61, 36)
		"long": return Vector2(82, 20)
		_: return Vector2(73, 28)


static func _body_widths(mass_distribution: String) -> Vector2i:
	match mass_distribution:
		"rear": return Vector2i(14, 3)
		"front": return Vector2i(4, 14)
		_: return Vector2i(7, 6)


static func _grip_anchor(
	handle_points: PackedVector2Array,
	body_finish: Vector2,
	mass_distribution: String
) -> Vector2:
	var handle_rear: Vector2 = handle_points[0]
	var handle_front: Vector2 = handle_points[-1]
	match mass_distribution:
		# A rear-weighted object is held closer to the body so the visible mass
		# stays at or behind the hand instead of merely being declared as rear.
		"rear": return handle_front.lerp(body_finish, 0.16)
		# A front-weighted object keeps the hand toward the rear of its handle,
		# leaving the visible body and terminal mass clearly in front of it.
		"front": return handle_rear.lerp(handle_front, 0.18)
		_: return handle_rear.lerp(handle_front, 0.45)


static func _draw_mass_distribution_cue(
	image: Image,
	mass_distribution: String,
	grip: Vector2,
	strike: Vector2
) -> void:
	if mass_distribution == "balanced" or grip.distance_squared_to(strike) <= 1.0:
		return
	# Keep the front-weight cue behind the contact feature. Otherwise a point
	# or edge would be widened into a false broad face by the mass marker.
	var target_ratio := 0.10 if mass_distribution == "rear" else 0.60
	var target := grip.lerp(strike, target_ratio)
	var center := _nearest_opaque_point(image, target)
	var radius := 11 if mass_distribution == "rear" else 10
	_fill_circle(image, Vector2i(center.round()), radius + 2, OUTLINE)
	_fill_circle(image, Vector2i(center.round()), radius, WOOD_MID if mass_distribution == "rear" else BRASS_MID)
	_fill_circle(
		image,
		Vector2i(center.round()) + Vector2i(-2, -2),
		maxi(3, radius / 2),
		WOOD_LIGHT if mass_distribution == "rear" else BRASS_LIGHT
	)


static func _nearest_opaque_point(image: Image, target: Vector2) -> Vector2:
	var nearest := target
	var nearest_distance := INF
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			var point := Vector2(x, y)
			var distance := point.distance_squared_to(target)
			if distance < nearest_distance:
				nearest = point
				nearest_distance = distance
	return nearest


static func _curve_between(
	start: Vector2,
	finish: Vector2,
	ratios: Array,
	offsets: Array
) -> PackedVector2Array:
	var direction := (finish - start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var result := PackedVector2Array()
	for index: int in range(mini(ratios.size(), offsets.size())):
		result.append(start.lerp(finish, float(ratios[index])) + normal * float(offsets[index]))
	return result


static func _rigid_body_points(start: Vector2, finish: Vector2, rigidity: String) -> PackedVector2Array:
	if rigidity == "semi_rigid":
		return _curve_between(start, finish, [0.0, 0.34, 0.68, 1.0], [0.0, -2.0, -3.0, 0.0])
	if rigidity == "flexible":
		return _curve_between(start, finish, [0.0, 0.28, 0.55, 0.78, 1.0], [0.0, -5.0, 5.0, 4.0, 0.0])
	return PackedVector2Array([start, start.lerp(finish, 0.50), finish])


static func _tether_points(origin: Vector2, mode: String, deployment: String) -> PackedVector2Array:
	# Leave room for point, edge, broad and hook contacts. Clipping those
	# features against the canvas makes unrelated contact morphologies collapse.
	var finish := Vector2(84, 72) if origin.y < 52.0 else Vector2(84, 23)
	var offsets := [0.0, -5.0, -8.0, 5.0, 7.0, 0.0]
	if mode == "wrap":
		offsets = [0.0, -8.0, -12.0, 9.0, 13.0, 0.0]
	elif deployment == "cast_retract":
		offsets = [0.0, 7.0, 12.0, -4.0, -7.0, 0.0]
	elif deployment == "launch_tension":
		offsets = [0.0, -1.0, -2.0, -1.0, 0.0, 0.0]
	return _curve_between(origin, finish, [0.0, 0.18, 0.38, 0.60, 0.82, 1.0], offsets)


static func _draw_tether_deployment_fixture(
	image: Image,
	center: Vector2,
	body_axis: Vector2,
	deployment: String
) -> void:
	match deployment:
		"cast_retract":
			_fill_circle(image, Vector2i(center.round()), 7, OUTLINE)
			_fill_circle(image, Vector2i(center.round()), 5, BRASS_MID)
			_fill_circle(image, Vector2i(center.round()), 2, WOOD_DARK)
			_stroke(image, center - body_axis * 5.0, center + body_axis * 5.0, 2, BRASS_LIGHT)
		"launch_tension":
			_fill_oriented_box(image, center, body_axis, 8.0, 6.0, OUTLINE)
			_fill_oriented_box(image, center, body_axis, 6.0, 3.0, BRASS_MID)
			_stroke(image, center, center + body_axis * 11.0, 3, BRASS_LIGHT)


static func _draw_state_fixture(image: Image, body_start: Vector2, body_finish: Vector2, state: String) -> void:
	var axis := (body_finish - body_start).normalized()
	var normal := Vector2(-axis.y, axis.x)
	match state:
		"hinged":
			var center := body_start.lerp(body_finish, 0.52)
			_fill_circle(image, Vector2i(center.round()), 7, OUTLINE)
			_fill_circle(image, Vector2i(center.round()), 4, BRASS_LIGHT)
			_stroke(image, center, center + normal * 12.0, 5, BRASS_MID)
		"folding":
			for ratio: float in [0.32, 0.58, 0.82]:
				var center := body_start.lerp(body_finish, ratio)
				_fill_circle(image, Vector2i(center.round()), 5, OUTLINE)
				_fill_circle(image, Vector2i(center.round()), 3, BRASS_LIGHT)
		"telescoping":
			for ratio: float in [0.38, 0.62, 0.84]:
				var center := body_start.lerp(body_finish, ratio)
				_fill_oriented_box(image, center, normal, 7.0, 3.0, OUTLINE)
				_fill_oriented_box(image, center, normal, 5.0, 1.0, BRASS_LIGHT)
		"radial_expand":
			var hub := body_start.lerp(body_finish, 0.70)
			_fill_circle(image, Vector2i(hub.round()), 6, OUTLINE)
			_fill_circle(image, Vector2i(hub.round()), 3, BRASS_MID)
			for angle: float in [-1.15, -0.58, 0.58, 1.15]:
				_stroke(image, hub, _clamp_point(hub + axis.rotated(angle) * 15.0), 4, BRASS_LIGHT)
		"rotary":
			var hub := body_start.lerp(body_finish, 0.76)
			_fill_circle(image, Vector2i(hub.round()), 12, OUTLINE)
			_fill_circle(image, Vector2i(hub.round()), 9, BRASS_MID)
			_fill_circle(image, Vector2i(hub.round()), 3, WOOD_DARK)
			for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
				_stroke(image, hub + Vector2.from_angle(angle) * 3.0, hub + Vector2.from_angle(angle) * 9.0, 2, BRASS_LIGHT)


static func _draw_activation_fixture(image: Image, grip: Vector2, axis: Vector2, activation: String) -> void:
	var normal := Vector2(-axis.y, axis.x)
	var center := _clamp_point(grip + normal * 8.0)
	match activation:
		"momentary":
			_fill_circle(image, Vector2i(center.round()), 5, OUTLINE)
			_fill_circle(image, Vector2i(center.round()), 3, BRASS_LIGHT)
		"toggle":
			_fill_circle(image, Vector2i(center.round()), 5, OUTLINE)
			_stroke(image, center, _clamp_point(center + normal * 9.0), 4, BRASS_LIGHT)
		"charge_release":
			for offset: float in [-6.0, 0.0, 6.0]:
				_fill_circle(image, Vector2i(_clamp_point(center + axis * offset).round()), 4, BRASS_MID)
		"continuous_hold":
			_fill_oriented_box(image, center, axis, 8.0, 6.0, OUTLINE)
			_fill_oriented_box(image, center, axis, 6.0, 3.0, BRASS_LIGHT)


static func _draw_output_fixture(image: Image, strike: Vector2, direction: Vector2, output: String) -> void:
	var normal := Vector2(-direction.y, direction.x)
	var center := _clamp_point(strike - direction * 7.0)
	match output:
		"directed_stream":
			_fill_oriented_box(image, center, direction, 8.0, 8.0, OUTLINE)
			_fill_oriented_box(image, center, direction, 6.0, 5.0, BRASS_MID)
		"radial_field":
			_fill_circle(image, Vector2i(center.round()), 12, OUTLINE)
			_fill_circle(image, Vector2i(center.round()), 8, BRASS_DARK)
			for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
				_stroke(image, center + Vector2.from_angle(angle) * 5.0, center + Vector2.from_angle(angle) * 10.0, 3, BRASS_LIGHT)
		"pull_field":
			_stroke(image, center - normal * 10.0, center + normal * 10.0, 6, OUTLINE)
			_stroke(image, center - normal * 7.0, center + normal * 7.0, 3, BRASS_LIGHT)


static func _draw_secondary_contact(
	image: Image,
	body_start: Vector2,
	body_finish: Vector2,
	contact: String
) -> void:
	if contact == "none":
		return
	var direction := (body_finish - body_start).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var root := body_start.lerp(body_finish, 0.68)
	match contact:
		"point":
			_draw_tapered_path(
				image,
				PackedVector2Array([root, _clamp_point(root + normal * 8.0)]),
				4, 1, BRASS_MID, BRASS_LIGHT
			)
		"edge":
			_fill_oriented_box(image, root + normal * 3.0, direction, 8.0, 3.0, OUTLINE)
			_fill_oriented_box(image, root + normal * 3.0, direction, 6.0, 1.0, BRASS_LIGHT)
		"broad":
			_fill_oriented_box(image, root + normal * 4.0, direction, 7.0, 5.0, OUTLINE)
			_fill_oriented_box(image, root + normal * 4.0, direction, 5.0, 3.0, BRASS_MID)
		_:
			_fill_circle(image, Vector2i(root.round()), 5, BRASS_MID)


static func _draw_point_contact(image: Image, start: Vector2, direction: Vector2) -> Vector2:
	var finish := _clamp_point(start + direction * 9.0)
	_draw_tapered_path(
		image,
		PackedVector2Array([start, start.lerp(finish, 0.62), finish]),
		5, 1, BRASS_MID, BRASS_LIGHT
	)
	return finish


static func _draw_edge_contact(image: Image, start: Vector2, direction: Vector2) -> Vector2:
	var normal := Vector2(-direction.y, direction.x)
	var center := _clamp_point(start + direction * 3.0)
	_fill_oriented_box(image, center, normal, 11.0, 4.0, OUTLINE)
	_fill_oriented_box(image, center, normal, 9.0, 2.0, BRASS_LIGHT)
	return _clamp_point(center + direction * 3.0)


static func _draw_broad_contact(image: Image, start: Vector2, direction: Vector2) -> Vector2:
	var normal := Vector2(-direction.y, direction.x)
	_fill_oriented_box(image, start, normal, 17.0, 10.0, OUTLINE)
	_fill_oriented_box(image, start, normal, 14.0, 7.0, BRASS_MID)
	_fill_oriented_box(image, start - direction * 2.0, normal, 10.0, 2.0, BRASS_LIGHT)
	return _clamp_point(start + direction * 6.0)


static func _clamp_point(point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, 1.0, float(CANVAS_SIZE.x - 2)),
		clampf(point.y, 1.0, float(CANVAS_SIZE.y - 2))
	)


static func _draw_handle(image: Image, affordance: Dictionary, handle: PackedVector2Array) -> void:
	var grip_topology := str(affordance.get("grip_topology", "one_hand_handle"))
	var width := 11 if grip_topology == "two_hand_handle" else (13 if grip_topology == "body_grip" else 9)
	_draw_tapered_path(image, handle, width, width, WOOD_DARK, WOOD_MID)
	var band_ratios := [0.38, 0.72] if grip_topology == "two_hand_handle" else [0.48]
	for ratio: float in band_ratios:
		var center := handle[0].lerp(handle[-1], ratio)
		var tangent := (handle[-1] - handle[0]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		_stroke(image, center - normal * 3.0, center + normal * 3.0, width + 2, OUTLINE)
		_stroke(image, center - normal * 3.0, center + normal * 3.0, maxi(3, width - 2), BRASS_MID)
	if grip_topology == "clamp_grip":
		var tangent := (handle[-1] - handle[0]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		_fill_circle(image, Vector2i((handle[-1] + normal * 6.0).round()), 4, OUTLINE)
		_fill_circle(image, Vector2i((handle[-1] - normal * 6.0).round()), 4, OUTLINE)
		_fill_circle(image, Vector2i((handle[-1] + normal * 6.0).round()), 2, BRASS_LIGHT)
		_fill_circle(image, Vector2i((handle[-1] - normal * 6.0).round()), 2, BRASS_LIGHT)


static func _draw_tapered_path(
	image: Image,
	points: PackedVector2Array,
	start_width: int,
	end_width: int,
	start_color: Color,
	end_color: Color
) -> void:
	if points.size() < 2:
		return
	for index: int in range(points.size() - 1):
		var ratio := float(index) / maxf(1.0, float(points.size() - 2))
		var width := roundi(lerpf(float(start_width), float(end_width), ratio))
		_stroke(image, points[index], points[index + 1], width + 4, OUTLINE)
	for index: int in range(points.size() - 1):
		var ratio := float(index) / maxf(1.0, float(points.size() - 2))
		var width := roundi(lerpf(float(start_width), float(end_width), ratio))
		_stroke(image, points[index], points[index + 1], width, start_color.lerp(end_color, ratio))


static func _draw_linked_path(
	image: Image,
	centers: PackedVector2Array,
	start_width: int,
	end_width: int
) -> void:
	for index: int in range(centers.size() - 1):
		_stroke(image, centers[index], centers[index + 1], 5, OUTLINE)
		_stroke(image, centers[index], centers[index + 1], 2, BRASS_DARK)
	for index: int in range(centers.size()):
		var ratio := float(index) / maxf(1.0, float(centers.size() - 1))
		var radius := maxi(4, roundi(lerpf(float(start_width), float(end_width), ratio)))
		_fill_circle(image, Vector2i(centers[index].round()), radius + 2, OUTLINE)
		_fill_circle(image, Vector2i(centers[index].round()), radius, BRASS_MID if index % 2 == 0 else WOOD_LIGHT)
		_fill_circle(image, Vector2i(centers[index].round()) + Vector2i(-1, -1), maxi(2, radius / 2), BRASS_LIGHT)


static func _stroke(image: Image, start: Vector2, finish: Vector2, width: int, color: Color) -> void:
	var delta := finish - start
	var steps := maxi(1, ceili(maxf(absf(delta.x), absf(delta.y))))
	var radius := maxi(0, width / 2)
	for step: int in range(steps + 1):
		var center := Vector2i(start.lerp(finish, float(step) / float(steps)).round())
		_fill_circle(image, center, radius, color)


static func _fill_circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if Vector2i(x, y).distance_squared_to(center) <= radius * radius:
				image.set_pixel(x, y, color)


static func _fill_oriented_box(
	image: Image,
	center: Vector2,
	axis: Vector2,
	half_length: float,
	half_width: float,
	color: Color
) -> void:
	var along := axis.normalized()
	var normal := Vector2(-along.y, along.x)
	var radius := ceili(half_length + half_width + 2.0)
	for y: int in range(maxi(0, floori(center.y) - radius), mini(image.get_height(), ceili(center.y) + radius + 1)):
		for x: int in range(maxi(0, floori(center.x) - radius), mini(image.get_width(), ceili(center.x) + radius + 1)):
			var relative := Vector2(x, y) - center
			if absf(relative.dot(along)) <= half_length and absf(relative.dot(normal)) <= half_width:
				image.set_pixel(x, y, color)


static func _structural_axes(affordance: Dictionary) -> Dictionary:
	var result := {}
	for axis: String in [
		"handle_length", "body_length", "grip_topology", "rigidity", "mass_distribution",
		"contact_surface", "secondary_contact_surface", "flex_topology", "tether_topology",
		"terminal_load", "tether_mode", "tether_deployment",
		"state_topology", "activation_mode", "functional_output",
	]:
		result[axis] = str(affordance.get(axis, ""))
	return result


static func _palette_hex() -> Array[String]:
	return [
		OUTLINE.to_html(false), WOOD_DARK.to_html(false), WOOD_MID.to_html(false),
		WOOD_LIGHT.to_html(false), BRASS_DARK.to_html(false), BRASS_MID.to_html(false),
		BRASS_LIGHT.to_html(false),
	]


static func _validation_error(affordance: Dictionary) -> String:
	for axis: String in [
		"handle_length", "body_length", "grip_topology", "rigidity", "mass_distribution",
		"contact_surface", "secondary_contact_surface", "flex_topology", "tether_topology",
		"terminal_load", "tether_mode", "tether_deployment",
		"state_topology", "activation_mode", "functional_output",
	]:
		if not affordance.has(axis) or str(affordance.get(axis, "")).is_empty():
			return "MECHANISM_PIXEL_SCAFFOLD_AXIS_MISSING:%s" % axis
	return ""
