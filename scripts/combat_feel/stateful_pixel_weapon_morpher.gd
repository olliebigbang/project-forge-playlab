class_name StatefulPixelWeaponMorpher
extends RefCounted

const ALPHA_THRESHOLD := 0.08
const TOPOLOGIES: PackedStringArray = [
	"fixed", "hinged", "folding", "telescoping", "radial_expand", "rotary",
]


static func deform_local(
	image: Image,
	grip: Vector2,
	strike: Vector2,
	topology: String,
	power_value: float
) -> Dictionary:
	if image == null or image.is_empty():
		return {"pixels": [], "metrics": {}, "errors": ["STATEFUL_PIXEL_IMAGE_MISSING"]}
	if topology not in TOPOLOGIES:
		return {"pixels": [], "metrics": {}, "errors": ["STATEFUL_PIXEL_TOPOLOGY_INVALID"]}
	var axis := (strike - grip).normalized()
	var length := grip.distance_to(strike)
	if axis.length_squared() < 0.5 or length < 6.0:
		axis = Vector2.RIGHT
		length = maxf(12.0, float(image.get_used_rect().size.x))
	var normal := Vector2(-axis.y, axis.x)
	var power := clampf(power_value, 0.0, 1.0)
	var pixels: Array[Dictionary] = []
	var generated_fill_pixels := 0
	var retained_source_pixels := 0
	if topology == "radial_expand" and power > 0.01:
		var radial := _radial_expand(image, grip, axis, normal, length, power)
		pixels = radial.get("pixels", []) as Array[Dictionary]
		generated_fill_pixels = int(radial.get("generated_fill_pixels", 0))
		retained_source_pixels = int(radial.get("retained_source_pixels", 0))
	else:
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var color := image.get_pixel(x, y)
				if color.a < ALPHA_THRESHOLD:
					continue
				var source := Vector2(float(x), float(y))
				var target := _transform_source_pixel(source, grip, axis, normal, length, topology, power)
				pixels.append(_pixel(target - grip, color, false, source))
				retained_source_pixels += 1
	var metrics := _metrics(pixels, axis, normal)
	metrics["topology"] = topology
	metrics["power"] = power
	metrics["generated_fill_pixels"] = generated_fill_pixels
	metrics["retained_source_pixels"] = retained_source_pixels
	metrics["uses_source_palette"] = true
	metrics["closed_sprite_replaced"] = topology != "fixed" and power > 0.01
	return {"pixels": pixels, "metrics": metrics, "errors": []}


static func _transform_source_pixel(
	point: Vector2,
	grip: Vector2,
	axis: Vector2,
	normal: Vector2,
	length: float,
	topology: String,
	power: float
) -> Vector2:
	var relative := point - grip
	var axial := relative.dot(axis)
	var lateral := relative.dot(normal)
	match topology:
		"hinged":
			var pivot_distance := length * 0.52
			if axial > pivot_distance:
				var pivot := grip + axis * pivot_distance
				return pivot + (point - pivot).rotated(0.92 * power)
		"folding":
			var first_distance := length * 0.34
			var second_distance := length * 0.67
			if axial > second_distance:
				var second := grip + axis * second_distance
				return second + (point - second).rotated(-0.82 * power)
			if axial > first_distance:
				var first := grip + axis * first_distance
				return first + (point - first).rotated(0.68 * power)
		"telescoping":
			var root_distance := length * 0.25
			if axial > root_distance:
				var extended := root_distance + (axial - root_distance) * (1.0 + 0.72 * power)
				return grip + axis * extended + normal * lateral
		"rotary":
			var pivot_distance := length * 0.62
			if axial > length * 0.38:
				var pivot := grip + axis * pivot_distance
				return pivot + (point - pivot).rotated(1.72 * power)
	return point


static func _radial_expand(
	image: Image,
	grip: Vector2,
	axis: Vector2,
	normal: Vector2,
	length: float,
	power: float
) -> Dictionary:
	var pixels: Array[Dictionary] = []
	var palette := _source_palette(image, grip, axis, length)
	var base := Color(palette.get("base", Color("26384f")))
	var secondary := Color(palette.get("secondary", base.lightened(0.10)))
	var outline := Color(palette.get("outline", base.darkened(0.30)))
	var accent := Color(palette.get("accent", secondary.lightened(0.28)))
	var hub_distance := length * 0.64
	var hub := grip + axis * hub_distance
	var radius := maxf(14.0, length * lerpf(0.38, 0.58, power))
	var spread := lerpf(0.14, 1.22, power)
	var generated_fill_pixels := 0
	var maximum := ceili(radius) + 2
	var ribs: Array[float] = [-1.0, -0.50, 0.0, 0.50, 1.0]
	for axial_offset: int in range(0, maximum + 1):
		for lateral_offset: int in range(-maximum, maximum + 1):
			var radius_value := Vector2(float(axial_offset), float(lateral_offset)).length()
			if radius_value < 3.0 or radius_value > radius:
				continue
			var angle := atan2(float(lateral_offset), float(axial_offset))
			if absf(angle) > spread:
				continue
			var radial_ratio := radius_value / radius
			var angle_ratio := angle / maxf(0.01, spread)
			var edge := radial_ratio >= 0.94 or absf(angle_ratio) >= 0.96
			var rib := false
			for rib_ratio: float in ribs:
				if absf(angle_ratio - rib_ratio) <= maxf(0.025, 0.70 / radius):
					rib = true
					break
			var color := base if (axial_offset + lateral_offset) % 5 != 0 else secondary
			if edge:
				color = outline
			elif rib:
				color = accent
			var target := hub + axis * float(axial_offset) + normal * float(lateral_offset)
			pixels.append(_pixel(target - grip, color, true, target))
			generated_fill_pixels += 1

	# The original folded body is not drawn.  Only the handle/root and a narrow
	# central shaft survive, so the active silhouette is the opened object rather
	# than a closed sprite with guide lines painted on top.
	var retained_source_pixels := 0
	var shaft_half_width := clampf(length * 0.026, 1.25, 2.75)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < ALPHA_THRESHOLD:
				continue
			var point := Vector2(float(x), float(y))
			var relative := point - grip
			var axial := relative.dot(axis)
			var lateral := relative.dot(normal)
			var keep_root := axial <= hub_distance * 0.42
			var keep_shaft := absf(lateral) <= shaft_half_width and axial <= hub_distance + radius * 0.12
			if keep_root or keep_shaft:
				pixels.append(_pixel(point - grip, color, false, point))
				retained_source_pixels += 1

	# A filled hub cap makes the source shaft visibly join the new canopy.
	for offset_y: int in range(-3, 4):
		for offset_x: int in range(-3, 4):
			if Vector2(offset_x, offset_y).length() <= 3.2:
				var target := hub + axis * float(offset_x) + normal * float(offset_y)
				pixels.append(_pixel(target - grip, accent if abs(offset_y) <= 1 else outline, true, target))
				generated_fill_pixels += 1
	return {
		"pixels": pixels,
		"generated_fill_pixels": generated_fill_pixels,
		"retained_source_pixels": retained_source_pixels,
	}


static func _source_palette(image: Image, grip: Vector2, axis: Vector2, length: float) -> Dictionary:
	var counts: Dictionary = {}
	var colors: Dictionary = {}
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < ALPHA_THRESHOLD:
				continue
			var axial := (Vector2(float(x), float(y)) - grip).dot(axis)
			if axial < length * 0.16:
				continue
			var quantized := Color(
				roundf(color.r * 15.0) / 15.0,
				roundf(color.g * 15.0) / 15.0,
				roundf(color.b * 15.0) / 15.0,
				1.0
			)
			var key := quantized.to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
			colors[key] = quantized
	var keys := counts.keys()
	keys.sort_custom(func(left: Variant, right: Variant) -> bool:
		return int(counts.get(left, 0)) > int(counts.get(right, 0))
	)
	var selected: Array[Color] = []
	for key: Variant in keys:
		selected.append(Color(colors[key]))
		if selected.size() >= 6:
			break
	if selected.is_empty():
		selected = [Color("26384f"), Color("405a78"), Color("9fb8cf")]
	var base: Color = selected[0]
	var secondary: Color = selected[min(1, selected.size() - 1)]
	var darkest := base
	var brightest := base
	for color: Color in selected:
		if color.get_luminance() < darkest.get_luminance():
			darkest = color
		if color.get_luminance() > brightest.get_luminance():
			brightest = color
	return {
		"base": base,
		"secondary": secondary,
		"outline": darkest.darkened(0.12),
		"accent": brightest.lightened(0.08),
	}


static func _pixel(position: Vector2, color: Color, generated: bool, source: Vector2) -> Dictionary:
	return {
		"position": Vector2(roundf(position.x), roundf(position.y)),
		"color": color,
		"size": 1.0,
		"generated": generated,
		"source_position": source,
	}


static func _metrics(pixels: Array[Dictionary], axis: Vector2, normal: Vector2) -> Dictionary:
	if pixels.is_empty():
		return {"pixel_count": 0, "axial_span": 0.0, "normal_span": 0.0, "filled_area_ratio": 0.0}
	var unique: Dictionary = {}
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var axial_minimum := INF
	var axial_maximum := -INF
	var normal_minimum := INF
	var normal_maximum := -INF
	for pixel: Dictionary in pixels:
		var position := Vector2(pixel.get("position", Vector2.ZERO))
		unique["%d:%d" % [roundi(position.x), roundi(position.y)]] = true
		minimum.x = minf(minimum.x, position.x)
		minimum.y = minf(minimum.y, position.y)
		maximum.x = maxf(maximum.x, position.x)
		maximum.y = maxf(maximum.y, position.y)
		var axial := position.dot(axis)
		var lateral := position.dot(normal)
		axial_minimum = minf(axial_minimum, axial)
		axial_maximum = maxf(axial_maximum, axial)
		normal_minimum = minf(normal_minimum, lateral)
		normal_maximum = maxf(normal_maximum, lateral)
	var bounds_area := maxf(1.0, (maximum.x - minimum.x + 1.0) * (maximum.y - minimum.y + 1.0))
	return {
		"pixel_count": unique.size(),
		"axial_span": axial_maximum - axial_minimum + 1.0,
		"normal_span": normal_maximum - normal_minimum + 1.0,
		"filled_area_ratio": float(unique.size()) / bounds_area,
	}
