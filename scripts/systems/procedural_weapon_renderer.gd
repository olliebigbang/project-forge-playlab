class_name ProceduralWeaponRenderer
extends RefCounted

const SIZE := 96

static func build_image(blueprint: WeaponBlueprint, geometry: Dictionary = {}) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	match blueprint.behavior_family:
		"returning_thrown": _draw_umbrella(image, blueprint, geometry)
		"heavy_melee": _draw_greatsword(image, blueprint, geometry)
		_: _draw_gatling(image, blueprint, geometry)
	_add_outline(image)
	return image

static func _draw_gatling(image: Image, blueprint: WeaponBlueprint, geometry: Dictionary) -> void:
	var steel := Color("27364a")
	var light := Color("7388a3")
	var dark := Color("111827")
	var blue := Color("36d8ff")
	var aspect_scale: float = clampf(float(geometry.get("aspect_ratio", blueprint.silhouette_aspect)) / 2.8, 0.82, 1.14)
	var barrel_length := roundi(42.0 * aspect_scale)
	_fill_rect(image, Rect2i(23, 38, 29, 24), steel)
	_fill_rect(image, Rect2i(28, 42, 18, 16), Color("41536b"))
	_fill_rect(image, Rect2i(18, 52, 12, 15), dark)
	_fill_rect(image, Rect2i(20, 55, 8, 15), light)
	_fill_rect(image, Rect2i(34, 58, 7, 15), dark)
	_fill_rect(image, Rect2i(36, 60, 5, 13), light)
	for index: int in range(4):
		var y := 38 + index * 6
		_fill_rect(image, Rect2i(48, y, barrel_length, 3), dark)
		_fill_rect(image, Rect2i(50, y, barrel_length - 2, 1), light)
	_fill_rect(image, Rect2i(45, 35, 9, 30), Color("526780"))
	_fill_rect(image, Rect2i(50, 41, 5, 18), blue)
	_fill_rect(image, Rect2i(53, 45, 3, 10), Color.WHITE)
	var muzzle_x := mini(93, 48 + barrel_length)
	_fill_rect(image, Rect2i(muzzle_x, 41, 3, 20), Color("8af0ff"))
	_fill_rect(image, Rect2i(14, 41, 10, 16), Color("1b2637"))
	_fill_rect(image, Rect2i(12, 45, 5, 8), light)

static func _draw_umbrella(image: Image, _blueprint: WeaponBlueprint, geometry: Dictionary) -> void:
	var metal := Color("29405c")
	var cyan := Color("3ce6ee")
	var violet := Color("7b61ff")
	var dark := Color("101827")
	var center := Vector2i(49, 39)
	var radius_x: int = roundi(30.0 * clampf(float(geometry.get("aspect_ratio", 1.45)) / 1.45, 0.82, 1.18))
	for y: int in range(17, 48):
		for x: int in range(12, 86):
			var nx := float(x - center.x) / float(radius_x)
			var ny := float(y - center.y) / 23.0
			var edge := nx * nx + ny * ny
			if edge <= 1.0 and y <= center.y + int(absf(nx) * 8.0):
				var stripe := (x / 6) % 2
				image.set_pixel(x, y, cyan if stripe == 0 else violet)
	for spoke: int in range(-3, 4):
		_draw_line(image, center, Vector2i(center.x + spoke * 10, 22 + abs(spoke) * 3), metal, 2)
	_fill_rect(image, Rect2i(46, 38, 6, 38), metal)
	_fill_rect(image, Rect2i(43, 72, 9, 7), dark)
	_fill_rect(image, Rect2i(50, 77, 10, 4), metal)
	_fill_rect(image, Rect2i(47, 35, 4, 8), Color.WHITE)
	for offset: Vector2i in [Vector2i(-33, 0), Vector2i(33, 0), Vector2i(0, -24)]:
		_fill_rect(image, Rect2i(center + offset - Vector2i(1, 1), Vector2i(3, 3)), Color("b8ffff"))

static func _draw_greatsword(image: Image, blueprint: WeaponBlueprint, geometry: Dictionary) -> void:
	var bone := Color("d8d2bd")
	var steel := Color("596273")
	var crimson := Color("b31f3a")
	var glow := Color("ff5470")
	var dark := Color("24151b")
	var aspect_scale: float = clampf(float(geometry.get("aspect_ratio", blueprint.silhouette_aspect)) / 3.2, 0.78, 1.12)
	var blade_end := roundi(86.0 * aspect_scale)
	_fill_rect(image, Rect2i(13, 52, 22, 8), dark)
	_fill_rect(image, Rect2i(17, 55, 7, 17), crimson)
	_fill_rect(image, Rect2i(27, 43, 10, 24), steel)
	for x: int in range(34, mini(91, blade_end)):
		var top := 35 + int(float(x - 34) * 0.09)
		var bottom := 63 - int(float(x - 34) * 0.03)
		for y: int in range(top, bottom):
			image.set_pixel(x, y, bone if (x + y) % 5 else steel)
		if x % 6 == 0:
			_fill_rect(image, Rect2i(x, top - 4, 4, 5), crimson)
			_fill_rect(image, Rect2i(x + 1, top - 3, 2, 2), glow)
	for x: int in range(39, mini(88, blade_end), 7):
		_fill_rect(image, Rect2i(x, 50, 4, 4), Color("61202b"))
	_fill_rect(image, Rect2i(mini(88, blade_end), 42, 5, 16), steel)

static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(0, 0, SIZE, SIZE))
	for y: int in range(clipped.position.y, clipped.end.y):
		for x: int in range(clipped.position.x, clipped.end.x):
			image.set_pixel(x, y, color)

static func _draw_line(image: Image, from: Vector2i, to: Vector2i, color: Color, width: int = 1) -> void:
	var points: int = maxi(abs(to.x - from.x), abs(to.y - from.y))
	for index: int in range(points + 1):
		var t := float(index) / float(maxi(1, points))
		var point := Vector2i(roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t)))
		_fill_rect(image, Rect2i(point - Vector2i(width / 2, width / 2), Vector2i(width, width)), color)

static func _add_outline(image: Image) -> void:
	var copy := image.duplicate()
	for y: int in range(1, SIZE - 1):
		for x: int in range(1, SIZE - 1):
			if copy.get_pixel(x, y).a > 0.1:
				continue
			var neighbor := false
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if copy.get_pixelv(Vector2i(x, y) + offset).a > 0.1:
					neighbor = true
					break
			if neighbor:
				image.set_pixel(x, y, Color("09111f"))

