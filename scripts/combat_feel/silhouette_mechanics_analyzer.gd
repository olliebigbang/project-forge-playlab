class_name SilhouetteMechanicsAnalyzer
extends RefCounted

const ALPHA_THRESHOLD := 0.10
const RAY_STEP := 0.50
const CHORD_STEP := 0.50
const CONTACT_DEPTH_RATIOS := [0.02, 0.04, 0.06, 0.08, 0.10]
const STABILITY_METRICS: PackedStringArray = [
	"normalized_silhouette_inertia",
	"grip_to_strike_ratio",
	"mass_projection_ratio",
	"contact_span_pixels",
	"contact_span_ratio",
	"normalized_local_curvature",
]


static func analyze(image: Image, grip: Vector2, strike: Vector2) -> Dictionary:
	if image == null or image.is_empty():
		return {}
	var context := _shape_context(image)
	if context.is_empty():
		return {}
	return _analyze_with_context(image, grip, strike, context)


static func _analyze_with_context(image: Image, grip: Vector2, strike: Vector2, context: Dictionary) -> Dictionary:
	var feret := float(context["feret_diameter_pixels"])
	var direction := strike - grip
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var contact_result := _ray_contact(image, grip, direction)
	var contact: Vector2 = contact_result["point"]
	var contact_valid := bool(contact_result["valid"])
	var centroid := Vector2(
		float(context["alpha_x_total"]) / float(context["alpha_total"]),
		float(context["alpha_y_total"]) / float(context["alpha_total"])
	)
	var contact_distance := grip.distance_to(contact)
	var mass_projection_valid := contact_valid and contact_distance > maxf(1.0, feret * 0.05)
	var mass_projection_ratio := (
		(centroid - grip).dot(direction) / contact_distance
		if mass_projection_valid
		else 0.0
	)
	var inertia := _alpha_weighted_inertia(context, grip)
	var contact_profile: Array[Dictionary] = []
	if contact_valid:
		contact_profile = _contact_profile(image, contact, direction, feret)
	var span := _profile_span(contact_profile)
	var curvature := _profile_curvature(contact_profile)
	var bounds: Rect2i = context["alpha_bounds"]
	return {
		"alpha_threshold": ALPHA_THRESHOLD,
		"alpha_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"feret_diameter_pixels": feret,
		"alpha_centroid": [centroid.x, centroid.y],
		"contact_point": [contact.x, contact.y],
		"contact_valid": contact_valid,
		"grip_to_contact_pixels": contact_distance,
		"normalized_silhouette_inertia": inertia,
		"grip_to_strike_ratio": grip.distance_to(strike) / feret,
		"mass_projection_ratio": mass_projection_ratio,
		"mass_projection_ratio_valid": mass_projection_valid,
		"contact_span_pixels": span,
		"contact_span_ratio": span / feret,
		"local_curvature_per_pixel": curvature,
		"normalized_local_curvature": curvature * feret,
		"contact_definition": "outermost Grip->Strike ray intersection",
		"span_definition": "median inward parallel chord",
		"curvature_definition": "median inward-chord circle fit",
	}


static func stability_report(image: Image, grip: Vector2, strike: Vector2, anchor_delta: float = 2.0) -> Dictionary:
	var baseline_context := _shape_context(image)
	if baseline_context.is_empty():
		return {}
	var baseline := _analyze_with_context(image, grip, strike, baseline_context)
	if baseline.is_empty():
		return {}
	var masks := [
		{"name": "eroded_1px", "image": morph_alpha(image, false)},
		{"name": "original", "image": image, "context": baseline_context},
		{"name": "dilated_1px", "image": morph_alpha(image, true)},
	]
	var values := {}
	var invalid_counts := {}
	for metric: String in STABILITY_METRICS:
		values[metric] = []
		invalid_counts[metric] = 0
	var offsets := [-anchor_delta, 0.0, anchor_delta]
	var sample_count := 0
	for mask_data: Dictionary in masks:
		var mask_image: Image = mask_data["image"]
		var context: Dictionary = mask_data.get("context", {})
		if context.is_empty():
			context = _shape_context(mask_image)
		if context.is_empty():
			continue
		for grip_x: float in offsets:
			for grip_y: float in offsets:
				for strike_x: float in offsets:
					for strike_y: float in offsets:
						var result := _analyze_with_context(
							mask_image,
							grip + Vector2(grip_x, grip_y),
							strike + Vector2(strike_x, strike_y),
							context
						)
						if result.is_empty():
							continue
						for metric: String in STABILITY_METRICS:
							if _metric_is_valid(result, metric):
								(values[metric] as Array).append(float(result[metric]))
							else:
								invalid_counts[metric] = int(invalid_counts[metric]) + 1
						sample_count += 1
	var metrics := {}
	for metric: String in STABILITY_METRICS:
		var metric_values: Array = values[metric]
		var base := float(baseline[metric])
		if metric_values.is_empty():
			metrics[metric] = {
				"base": base,
				"min": base,
				"max": base,
				"max_relative_deviation": INF,
				"relative_range": INF,
				"valid_sample_count": 0,
				"invalid_sample_count": int(invalid_counts[metric]),
			}
			continue
		var minimum := INF
		var maximum := -INF
		var maximum_deviation := 0.0
		for value: float in metric_values:
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
			maximum_deviation = maxf(maximum_deviation, absf(value - base) / maxf(absf(base), 0.0001))
		metrics[metric] = {
			"base": base,
			"min": minimum,
			"max": maximum,
			"max_relative_deviation": maximum_deviation,
			"relative_range": (maximum - minimum) / maxf(absf(base), 0.0001),
			"valid_sample_count": metric_values.size(),
			"invalid_sample_count": int(invalid_counts[metric]),
		}
	return {
		"anchor_delta_pixels": anchor_delta,
		"mask_variants": ["eroded_1px", "original", "dilated_1px"],
		"sample_count": sample_count,
		"metrics": metrics,
	}


static func morph_alpha(image: Image, dilate: bool) -> Image:
	var result := Image.new()
	result.copy_from(image)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var selected := 0.0 if dilate else 1.0
			for offset_y: int in range(-1, 2):
				for offset_x: int in range(-1, 2):
					var check_x := x + offset_x
					var check_y := y + offset_y
					var alpha := 0.0
					if check_x >= 0 and check_y >= 0 and check_x < image.get_width() and check_y < image.get_height():
						alpha = image.get_pixel(check_x, check_y).a
					selected = maxf(selected, alpha) if dilate else minf(selected, alpha)
			var color := image.get_pixel(x, y)
			color.a = selected
			result.set_pixel(x, y, color)
	return result


static func _shape_context(image: Image) -> Dictionary:
	var opaque_points: Array[Vector2] = []
	var alpha_total := 0.0
	var alpha_x_total := 0.0
	var alpha_y_total := 0.0
	var alpha_squared_radius_total := 0.0
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			if alpha > 0.0:
				alpha_total += alpha
				alpha_x_total += alpha * float(x)
				alpha_y_total += alpha * float(y)
				alpha_squared_radius_total += alpha * float(x * x + y * y)
			if alpha <= ALPHA_THRESHOLD:
				continue
			opaque_points.append(Vector2(x, y))
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if opaque_points.size() < 3 or alpha_total <= 0.0001:
		return {}
	var hull := _convex_hull(opaque_points)
	var feret := _feret_diameter(hull)
	if feret <= 0.0001:
		return {}
	return {
		"alpha_bounds": Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1),
		"feret_diameter_pixels": feret,
		"alpha_total": alpha_total,
		"alpha_x_total": alpha_x_total,
		"alpha_y_total": alpha_y_total,
		"alpha_squared_radius_total": alpha_squared_radius_total,
	}


static func _convex_hull(points: Array[Vector2]) -> Array[Vector2]:
	var sorted := points.duplicate()
	sorted.sort_custom(func(left: Vector2, right: Vector2) -> bool:
		return left.y < right.y if is_equal_approx(left.x, right.x) else left.x < right.x
	)
	var lower: Array[Vector2] = []
	for point: Vector2 in sorted:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], point) <= 0.0:
			lower.pop_back()
		lower.append(point)
	var upper: Array[Vector2] = []
	for index: int in range(sorted.size() - 1, -1, -1):
		var point: Vector2 = sorted[index]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], point) <= 0.0:
			upper.pop_back()
		upper.append(point)
	lower.pop_back()
	upper.pop_back()
	lower.append_array(upper)
	return lower


static func _cross(origin: Vector2, first: Vector2, second: Vector2) -> float:
	return (first - origin).cross(second - origin)


static func _feret_diameter(hull: Array[Vector2]) -> float:
	var diameter := 0.0
	for first_index: int in range(hull.size()):
		for second_index: int in range(first_index + 1, hull.size()):
			diameter = maxf(diameter, hull[first_index].distance_to(hull[second_index]))
	return diameter


static func _alpha_weighted_inertia(context: Dictionary, grip: Vector2) -> float:
	var alpha_total := float(context["alpha_total"])
	var feret := float(context["feret_diameter_pixels"])
	var weighted_distance := (
		float(context["alpha_squared_radius_total"])
		- 2.0 * grip.x * float(context["alpha_x_total"])
		- 2.0 * grip.y * float(context["alpha_y_total"])
		+ alpha_total * grip.length_squared()
	)
	return maxf(0.0, weighted_distance) / maxf(alpha_total * feret * feret, 0.0001)


static func _metric_is_valid(result: Dictionary, metric: String) -> bool:
	if metric == "mass_projection_ratio":
		return bool(result.get("mass_projection_ratio_valid", false))
	if metric in ["contact_span_pixels", "contact_span_ratio", "normalized_local_curvature"]:
		return bool(result.get("contact_valid", false))
	return true


static func _ray_contact(image: Image, origin: Vector2, direction: Vector2) -> Dictionary:
	var interval := _ray_image_interval(image, origin, direction)
	if interval.y < interval.x:
		return {"valid": false, "point": origin}
	var last_opaque_distance := -1.0
	var distance := interval.x
	while distance <= interval.y:
		if _alpha_at(image, origin + direction * distance) > ALPHA_THRESHOLD:
			last_opaque_distance = distance
		distance += RAY_STEP
	if last_opaque_distance < 0.0:
		return {"valid": false, "point": origin}
	var inside := last_opaque_distance
	var outside := minf(last_opaque_distance + RAY_STEP, interval.y + RAY_STEP)
	for _index: int in range(8):
		var midpoint := (inside + outside) * 0.5
		if _alpha_at(image, origin + direction * midpoint) > ALPHA_THRESHOLD:
			inside = midpoint
		else:
			outside = midpoint
	return {"valid": true, "point": origin + direction * inside}


static func _ray_image_interval(image: Image, origin: Vector2, direction: Vector2) -> Vector2:
	var minimum := 0.0
	var maximum := INF
	var axes := [
		[origin.x, direction.x, float(image.get_width() - 1)],
		[origin.y, direction.y, float(image.get_height() - 1)],
	]
	for axis: Array in axes:
		var axis_origin := float(axis[0])
		var axis_direction := float(axis[1])
		var axis_maximum := float(axis[2])
		if absf(axis_direction) <= 0.000001:
			if axis_origin < 0.0 or axis_origin > axis_maximum:
				return Vector2(1.0, 0.0)
			continue
		var first := (0.0 - axis_origin) / axis_direction
		var second := (axis_maximum - axis_origin) / axis_direction
		minimum = maxf(minimum, minf(first, second))
		maximum = minf(maximum, maxf(first, second))
		if maximum < minimum:
			return Vector2(1.0, 0.0)
	return Vector2(minimum, maximum)


static func _alpha_at(image: Image, point: Vector2) -> float:
	if point.x < 0.0 or point.y < 0.0 or point.x > image.get_width() - 1 or point.y > image.get_height() - 1:
		return 0.0
	var x0 := floori(point.x)
	var y0 := floori(point.y)
	var x1 := mini(x0 + 1, image.get_width() - 1)
	var y1 := mini(y0 + 1, image.get_height() - 1)
	var tx := point.x - float(x0)
	var ty := point.y - float(y0)
	var top := lerpf(image.get_pixel(x0, y0).a, image.get_pixel(x1, y0).a, tx)
	var bottom := lerpf(image.get_pixel(x0, y1).a, image.get_pixel(x1, y1).a, tx)
	return lerpf(top, bottom, ty)


static func _contact_profile(image: Image, contact: Vector2, direction: Vector2, feret: float) -> Array[Dictionary]:
	var profile: Array[Dictionary] = []
	var normal := Vector2(-direction.y, direction.x)
	for ratio: float in CONTACT_DEPTH_RATIOS:
		var depth := feret * ratio
		var center := contact - direction * depth
		var width := _chord_width(image, center, normal, feret)
		if width > 0.0:
			profile.append({"depth": depth, "width": width})
	return profile


static func _profile_span(profile: Array[Dictionary]) -> float:
	var widths: Array[float] = []
	for sample: Dictionary in profile:
		widths.append(float(sample["width"]))
	return _median(widths)


static func _profile_curvature(profile: Array[Dictionary]) -> float:
	var curvatures: Array[float] = []
	for sample: Dictionary in profile:
		var depth := float(sample["depth"])
		var half_width := float(sample["width"]) * 0.5
		var radius := (half_width * half_width + depth * depth) / maxf(2.0 * depth, 0.0001)
		if radius > 0.0001:
			curvatures.append(1.0 / radius)
	return _median(curvatures)


static func _chord_width(image: Image, center: Vector2, normal: Vector2, feret: float) -> float:
	var minimum := INF
	var maximum := -INF
	var forward := _ray_image_interval(image, center, normal)
	var backward := _ray_image_interval(image, center, -normal)
	var start := maxf(-feret, -backward.y)
	var finish := minf(feret, forward.y)
	var distance := start
	while distance <= finish:
		if _alpha_at(image, center + normal * distance) > ALPHA_THRESHOLD:
			minimum = minf(minimum, distance)
			maximum = maxf(maximum, distance)
		distance += CHORD_STEP
	return maximum - minimum if maximum >= minimum else 0.0


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := floori(float(sorted.size()) / 2.0)
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) * 0.5
