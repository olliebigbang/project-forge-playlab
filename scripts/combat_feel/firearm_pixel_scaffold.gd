class_name FirearmPixelScaffold
extends RefCounted

const AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const CANVAS_SIZE := Vector2i(96, 96)
const OUTLINE := Color("11151c")


static func build(declaration: Dictionary, source: String = "") -> Dictionary:
	var validation := AXES.validate_ai_declaration(declaration, source)
	if not bool(validation.get("ok", false)):
		return validation
	var image := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var palette := _palette(str(declaration.get("finish_palette", "gunmetal_black")))
	var anchors: Dictionary
	match str(declaration.get("layout", "")):
		"bullpup": anchors = _draw_bullpup(image, declaration, palette)
		"conventional_rifle": anchors = _draw_conventional_rifle(image, declaration, palette)
		"pistol": anchors = _draw_pistol(image, declaration, palette)
		"conventional_shotgun": anchors = _draw_conventional_shotgun(image, declaration, palette)
		"revolver": anchors = _draw_revolver(image, declaration, palette)
		"belt_fed_support": anchors = _draw_belt_fed_support(image, declaration, palette)
		_: return _failure("FIREARM_PIXEL_LAYOUT_UNSUPPORTED")
	var opaque_pixels := _opaque_pixel_count(image)
	if opaque_pixels < 120:
		return _failure("FIREARM_PIXEL_SCAFFOLD_TOO_SPARSE")
	return {
		"ok": true,
		"image": image,
		"automatic": true,
		"player_confirmation_required": false,
		"contract": {
			"schema": "forge-firearm-pixel-scaffold-v1",
			"canvas": [CANVAS_SIZE.x, CANVAS_SIZE.y],
			"axes": (validation.get("axes", {}) as Dictionary).duplicate(true),
			"anchors": anchors.duplicate(true),
			"required_roles": _required_roles(declaration),
			"opaque_pixels": opaque_pixels,
			"scaffold_rgba_sha256": _bytes_sha256(image.get_data()),
			"structure_authority": "ai_ranged_axes",
			"generator_authority": "style_and_color_only",
			"structure_locked": true,
		},
	}


static func _draw_bullpup(image: Image, declaration: Dictionary, palette: Dictionary) -> Dictionary:
	var body := palette["body"] as Color
	var accent := palette["accent"] as Color
	var highlight := palette["highlight"] as Color
	_outlined_rect(image, Rect2i(7, 36, 51, 20), body)
	_outlined_rect(image, Rect2i(5, 40, 10, 18), accent)
	_outlined_rect(image, Rect2i(55, 39, 25, 13), body)
	_segment(image, Vector2(77, 44), Vector2(91, 44), 7, 3, accent)
	_outlined_rect(image, Rect2i(89, 40, 5, 8), highlight)
	_segment(image, Vector2(52, 50), Vector2(48, 73), 13, 8, accent)
	_draw_magazine(image, Vector2(31, 52), "curved", palette["magazine"] as Color, -1.0)
	_segment(image, Vector2(36, 36), Vector2(41, 29), 6, 3, accent)
	_segment(image, Vector2(41, 29), Vector2(65, 29), 6, 3, accent)
	_segment(image, Vector2(65, 29), Vector2(70, 39), 6, 3, accent)
	_outlined_rect(image, Rect2i(58, 45, 7, 5), highlight)
	_draw_trigger_hint(image, Vector2(45, 54), accent)
	return {
		"GripPrimary": [48.0, 64.0],
		"GripSecondary": [66.0, 46.0],
		"Muzzle": [93.0, 44.0],
		"Tip": [93.0, 44.0],
		"RearContact": [6.0, 49.0],
		"FeedCenter": [31.0, 61.0],
	}


static func _draw_conventional_rifle(image: Image, declaration: Dictionary, palette: Dictionary) -> Dictionary:
	var body := palette["body"] as Color
	var accent := palette["accent"] as Color
	var highlight := palette["highlight"] as Color
	var stock := str(declaration.get("stock_structure", "fixed"))
	if stock == "telescoping":
		_segment(image, Vector2(11, 47), Vector2(29, 47), 6, 2, highlight)
		_outlined_rect(image, Rect2i(6, 38, 8, 21), accent)
	else:
		_segment(image, Vector2(10, 43), Vector2(30, 47), 17, 11, palette["stock"] as Color)
		_segment(image, Vector2(8, 51), Vector2(29, 48), 10, 6, palette["stock"] as Color)
	_outlined_rect(image, Rect2i(27, 35, 35, 18), body)
	_segment(image, Vector2(39, 50), Vector2(36, 73), 13, 8, accent)
	var magazine_shape := str(declaration.get("magazine_shape", "straight"))
	_draw_magazine(image, Vector2(50, 51), magazine_shape, palette["magazine"] as Color, 1.0)
	_outlined_rect(image, Rect2i(59, 38, 22, 13), palette["handguard"] as Color)
	var muzzle_x := 93.0 if str(declaration.get("barrel_length", "medium")) == "long" else 90.0
	_segment(image, Vector2(78, 43), Vector2(muzzle_x, 43), 7, 3, accent)
	_outlined_rect(image, Rect2i(roundi(muzzle_x) - 1, 39, 4, 8), highlight)
	_draw_upper_profile(image, str(declaration.get("upper_profile", "top_rail")), body, highlight)
	_draw_trigger_hint(image, Vector2(43, 54), accent)
	return {
		"GripPrimary": [36.0, 64.0],
		"GripSecondary": [68.0, 46.0],
		"Muzzle": [muzzle_x + 1.0, 43.0],
		"Tip": [muzzle_x + 1.0, 43.0],
		"RearContact": [7.0, 48.0],
		"FeedCenter": [51.0, 61.0],
	}


static func _draw_pistol(image: Image, _declaration: Dictionary, palette: Dictionary) -> Dictionary:
	var body := palette["body"] as Color
	var accent := palette["accent"] as Color
	var highlight := palette["highlight"] as Color
	_outlined_rect(image, Rect2i(24, 34, 55, 14), body)
	_outlined_rect(image, Rect2i(31, 46, 37, 10), accent)
	_segment(image, Vector2(53, 51), Vector2(46, 76), 17, 11, palette["magazine"] as Color)
	_outlined_rect(image, Rect2i(76, 37, 7, 9), highlight)
	for x: int in [30, 35, 40]:
		_fill_rect(image, Rect2i(x, 36, 2, 4), highlight)
	_draw_trigger_hint(image, Vector2(43, 57), accent)
	return {
		"GripPrimary": [48.0, 65.0],
		"GripSecondary": [53.0, 53.0],
		"Muzzle": [82.0, 41.0],
		"Tip": [82.0, 41.0],
		"RearContact": [25.0, 41.0],
		"FeedCenter": [48.0, 65.0],
	}


static func _draw_conventional_shotgun(image: Image, _declaration: Dictionary, palette: Dictionary) -> Dictionary:
	var body := palette["body"] as Color
	var accent := palette["accent"] as Color
	var wood := palette["stock"] as Color
	var highlight := palette["highlight"] as Color
	_segment(image, Vector2(7, 48), Vector2(31, 46), 18, 12, wood)
	_outlined_rect(image, Rect2i(28, 37, 28, 18), body)
	_segment(image, Vector2(39, 52), Vector2(36, 72), 13, 8, accent)
	_segment(image, Vector2(54, 42), Vector2(93, 42), 7, 3, accent)
	_segment(image, Vector2(55, 49), Vector2(88, 49), 6, 2, highlight)
	_outlined_rect(image, Rect2i(58, 46, 22, 10), wood)
	for x: int in range(61, 79, 5):
		_fill_rect(image, Rect2i(x, 48, 2, 6), highlight)
	_outlined_rect(image, Rect2i(90, 38, 4, 8), highlight)
	_draw_trigger_hint(image, Vector2(43, 55), accent)
	return {
		"GripPrimary": [36.0, 64.0],
		"GripSecondary": [69.0, 51.0],
		"Muzzle": [93.0, 42.0],
		"Tip": [93.0, 42.0],
		"RearContact": [7.0, 48.0],
		"FeedCenter": [50.0, 51.0],
	}


static func _draw_revolver(image: Image, _declaration: Dictionary, palette: Dictionary) -> Dictionary:
	var body := palette["body"] as Color
	var accent := palette["accent"] as Color
	var highlight := palette["highlight"] as Color
	_outlined_rect(image, Rect2i(25, 36, 30, 17), body)
	_fill_circle(image, Vector2i(52, 47), 12, OUTLINE)
	_fill_circle(image, Vector2i(52, 47), 9, accent)
	for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		_fill_circle(image, Vector2i((Vector2(52, 47) + Vector2.from_angle(angle) * 5.0).round()), 2, highlight)
	_segment(image, Vector2(58, 42), Vector2(84, 42), 9, 5, body)
	_outlined_rect(image, Rect2i(82, 38, 5, 8), highlight)
	_segment(image, Vector2(40, 52), Vector2(33, 75), 18, 12, palette["stock"] as Color)
	_draw_trigger_hint(image, Vector2(43, 55), accent)
	return {
		"GripPrimary": [35.0, 65.0],
		"GripSecondary": [47.0, 51.0],
		"Muzzle": [86.0, 42.0],
		"Tip": [86.0, 42.0],
		"RearContact": [25.0, 44.0],
		"FeedCenter": [52.0, 47.0],
	}


static func _draw_belt_fed_support(image: Image, _declaration: Dictionary, palette: Dictionary) -> Dictionary:
	var body := palette["body"] as Color
	var accent := palette["accent"] as Color
	var highlight := palette["highlight"] as Color
	_segment(image, Vector2(6, 47), Vector2(28, 46), 18, 12, palette["stock"] as Color)
	_outlined_rect(image, Rect2i(26, 33, 40, 21), body)
	_segment(image, Vector2(39, 51), Vector2(36, 73), 13, 8, accent)
	_outlined_rect(image, Rect2i(48, 53, 24, 20), palette["magazine"] as Color)
	for x: int in range(47, 69, 5):
		_fill_circle(image, Vector2i(x, 53), 2, Color("c79748"))
	_outlined_rect(image, Rect2i(63, 37, 20, 13), palette["handguard"] as Color)
	_segment(image, Vector2(79, 41), Vector2(94, 41), 7, 3, accent)
	_segment(image, Vector2(70, 52), Vector2(62, 78), 5, 2, highlight)
	_segment(image, Vector2(72, 52), Vector2(82, 78), 5, 2, highlight)
	_segment(image, Vector2(28, 30), Vector2(65, 30), 5, 2, highlight)
	_draw_trigger_hint(image, Vector2(43, 55), accent)
	return {
		"GripPrimary": [36.0, 64.0],
		"GripSecondary": [72.0, 45.0],
		"Muzzle": [94.0, 41.0],
		"Tip": [94.0, 41.0],
		"RearContact": [6.0, 47.0],
		"FeedCenter": [58.0, 62.0],
	}


static func _draw_magazine(image: Image, root: Vector2, shape: String, color: Color, direction: float) -> void:
	if shape == "straight":
		_segment(image, root, root + Vector2(2.0 * direction, 19.0), 12, 7, color)
	elif shape == "curved":
		var middle := root + Vector2(1.0 * direction, 11.0)
		var finish := root + Vector2(7.0 * direction, 21.0)
		_segment(image, root, middle, 12, 7, color)
		_segment(image, middle, finish, 11, 6, color)


static func _draw_upper_profile(image: Image, profile: String, body: Color, highlight: Color) -> void:
	match profile:
		"carry_handle":
			_segment(image, Vector2(31, 33), Vector2(35, 26), 6, 3, body)
			_segment(image, Vector2(35, 26), Vector2(55, 26), 6, 3, body)
			_segment(image, Vector2(55, 26), Vector2(60, 34), 6, 3, body)
			_segment(image, Vector2(37, 30), Vector2(54, 30), 3, 2, Color.TRANSPARENT)
			_fill_rect(image, Rect2i(43, 22, 5, 5), highlight)
		"top_rail":
			_segment(image, Vector2(30, 32), Vector2(59, 32), 5, 2, highlight)
			for x: int in range(32, 59, 6):
				_fill_rect(image, Rect2i(x, 29, 2, 4), OUTLINE)
		"raised_gas_tube":
			_segment(image, Vector2(36, 32), Vector2(76, 35), 6, 3, body)
			_outlined_rect(image, Rect2i(31, 29, 7, 7), highlight)


static func _draw_trigger_hint(image: Image, center: Vector2, color: Color) -> void:
	_segment(image, center + Vector2(-5, -1), center + Vector2(-5, 7), 5, 2, color)
	_segment(image, center + Vector2(-5, 7), center + Vector2(3, 7), 5, 2, color)


static func _required_roles(declaration: Dictionary) -> Array[String]:
	var roles: Array[String] = ["receiver", "primary_grip", "muzzle", "feed"]
	match str(declaration.get("layout", "")):
		"conventional_shotgun": roles.append_array(["stock", "pump_fore_end", "tube_magazine"])
		"revolver": roles.append_array(["cylinder", "hammer", "revolver_grip"])
		"belt_fed_support": roles.append_array(["stock", "feed_cover", "ammunition_belt", "belt_box", "support_grip"])
		_: pass
	if str(declaration.get("support_mode", "")) in ["two_hand_shouldered", "two_hand_free"] and "support_grip" not in roles:
		roles.append_array(["stock", "support_grip"])
	elif str(declaration.get("layout", "")) == "pistol":
		roles.append("slide")
	roles.append(str(declaration.get("upper_profile", "upper_profile")))
	return roles


static func _palette(name: String) -> Dictionary:
	match name:
		"olive_black":
			return {"body": Color("46523d"), "accent": Color("252b27"), "highlight": Color("9aa58c"), "stock": Color("3d4938"), "handguard": Color("58644b"), "magazine": Color("272e29")}
		"wood_steel":
			return {"body": Color("424950"), "accent": Color("20252a"), "highlight": Color("9da6ad"), "stock": Color("87542f"), "handguard": Color("9b6034"), "magazine": Color("24292e")}
		"dark_polymer":
			return {"body": Color("3d4650"), "accent": Color("242b32"), "highlight": Color("9ba7b2"), "stock": Color("303840"), "handguard": Color("303840"), "magazine": Color("252c33")}
		_:
			return {"body": Color("38414a"), "accent": Color("1f252b"), "highlight": Color("9aa5af"), "stock": Color("30373e"), "handguard": Color("343d45"), "magazine": Color("20262c")}


static func _outlined_rect(image: Image, rect: Rect2i, color: Color) -> void:
	_fill_rect(image, Rect2i(rect.position - Vector2i(2, 2), rect.size + Vector2i(4, 4)), OUTLINE)
	_fill_rect(image, rect, color)


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(maxi(0, rect.position.y), mini(image.get_height(), rect.end.y)):
		for x: int in range(maxi(0, rect.position.x), mini(image.get_width(), rect.end.x)):
			image.set_pixel(x, y, color)


static func _segment(image: Image, from: Vector2, to: Vector2, outline_width: int, inner_width: int, color: Color) -> void:
	_stroke(image, from, to, outline_width, OUTLINE)
	_stroke(image, from, to, inner_width, color)


static func _stroke(image: Image, from: Vector2, to: Vector2, width: int, color: Color) -> void:
	var steps := maxi(1, ceili(from.distance_to(to) * 1.5))
	var radius := maxi(1, floori(float(width) / 2.0))
	for index: int in range(steps + 1):
		_fill_circle(image, Vector2i(from.lerp(to, float(index) / float(steps)).round()), radius, color)


static func _fill_circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y: int in range(maxi(0, center.y - radius), mini(image.get_height(), center.y + radius + 1)):
		for x: int in range(maxi(0, center.x - radius), mini(image.get_width(), center.x + radius + 1)):
			if Vector2i(x, y).distance_squared_to(center) <= radius * radius:
				image.set_pixel(x, y, color)


static func _opaque_pixel_count(image: Image) -> int:
	var count := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.1:
				count += 1
	return count


static func _bytes_sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"retry_required": true,
		"player_confirmation_required": false,
	}
