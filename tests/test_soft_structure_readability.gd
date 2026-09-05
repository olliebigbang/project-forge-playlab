extends SceneTree

const RIG := preload("res://scripts/data/pixel_weapon_visual_rig.gd")
const DEFORMER := preload("res://scripts/combat_feel/pixel_weapon_deformer.gd")
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool) -> void:
	if ok: passed += 1; print("PASS | ", label)
	else: failed += 1; printerr("FAIL | ", label)

func _shape(segments: int) -> PixelWeaponVisualRig:
	# Anonymous synthetic alpha bindings: each straight rod is 16 pixels,
	# connectors are 4 pixels. No semantic identity exists in this fixture.
	var rig := RIG.new()
	var length := segments * 20 - 4
	rig.parts = [{"role": "deform_body", "source_path": PackedVector2Array([Vector2.ZERO, Vector2(length - 1, 0)])}]
	for x: int in range(length):
		var half_width := 0 if x % 20 >= 16 else 2
		for y: int in range(-half_width, half_width + 1):
			rig.bindings.append({"role": "deform_body", "ratio": float(x) / (length - 1), "normal_offset": float(y), "source_position": Vector2(x, y), "color": Color(0.2, 0.12, 0.07)})
	return rig

func _run() -> void:
	for count: int in [2, 3, 4]:
		var rig := _shape(count)
		var asset := WeaponVisualAsset.new()
		asset.visual_rig = rig
		asset.grip_primary = Vector2.ZERO
		asset.tip = Vector2(count * 20 - 5, 0)
		asset.opaque_bounds = Rect2i(0, 0, count * 20 - 4, 5)
		var arena := ARENA.new() as GameplayArena
		arena.asset = asset
		arena.blueprint = WeaponBlueprint.fixed_blueprint("hammer")
		var source := rig.source_path_for_role("deform_body")
		var first: PackedVector2Array = arena._linked_body_points(Vector2.ZERO, asset.tip, source, 0.22, 1.0)
		var second: PackedVector2Array = arena._linked_body_points(Vector2.ZERO, asset.tip, source, 0.64, 1.0)
		var invariant := first.size() == count + 1 and second.size() == first.size()
		if invariant:
			for index: int in range(count):
				invariant = invariant and absf(first[index].distance_to(first[index + 1]) - second[index].distance_to(second[index + 1])) < 0.001
		_check("Anonymous %d-segment alpha: joints only, fixed rod lengths" % count, rig.linked_joint_ratios().size() == count - 1 and invariant)
		arena.free()
	_check("Continuous body does not invent named-object joints", _shape(1).linked_joint_ratios().is_empty())
	var fit_asset := WeaponVisualAsset.new()
	fit_asset.opaque_bounds = Rect2i(0, 0, 82, 6)
	var fit_bp := WeaponBlueprint.fixed_blueprint("hammer")
	fit_bp.affordance = {"grip_topology": "body_grip", "body_length": "long"}
	var fit: Dictionary = preload("res://scripts/combat_feel/weapon_player_fit_compiler.gd").compile(fit_bp, fit_asset)
	_check("Body grip does not collapse a long thin structure to palm size", float(fit.rendered_span_pixels) >= 85.0 and float(fit.rendered_span_pixels) <= 90.0)
	var authored := preload("res://scripts/authored_player/arena.gd").new()
	authored.blueprint = fit_bp; authored.asset = fit_asset
	fit_asset.grip_primary = Vector2(18, 3); fit_asset.grip_secondary = Vector2(30, 3)
	_check("Production authored layer preserves long body-grip span", float(authored._weapon_fit().rendered_span_pixels) >= 85.0)
	authored.free()
	var rig := RIG.new()
	rig.parts = [{"role": "tether"}]
	for index: int in range(8):
		rig.bindings.append({"role": "tether", "ratio": float(index) / 7.0, "normal_offset": 0.0, "color": Color(0.01, 0.01, 0.01)})
	var geometry := {"tether": PackedVector2Array([Vector2.ZERO, Vector2(80, -20), Vector2(240, 0)]), "readable_tether": true}
	var frame := DEFORMER.deform(rig, geometry)
	var readable := true
	for pixel: Dictionary in frame.pixels:
		var color: Color = pixel.color
		readable = readable and (color.r + color.g + color.b) / 3.0 > 0.5
	for index: int in range(241):
		var point := Vector2(DEFORMER.sample_polyline(geometry.tether, float(index) / 240.0).point)
		var nearest := INF
		for pixel: Dictionary in frame.pixels: nearest = minf(nearest, point.distance_to(pixel.position))
		readable = readable and nearest < 1.5
	_check("Declared dark tether stays continuous and readable after stretching", readable)
	_test_terminal_fixture()
	print("SOFT_STRUCTURE_READABILITY passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_terminal_fixture() -> void:
	var builder := preload("res://scripts/combat_feel/automatic_pixel_visual_rig_builder.gd")
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(8, 30, 10, 28), Color.BLUE)
	image.fill_rect(Rect2i(17, 32, 68, 1), Color.WHITE)
	image.fill_rect(Rect2i(83, 30, 10, 40), Color.GREEN)
	var asset := WeaponVisualAsset.new(); asset.source_image = image; asset.canvas_size = image.get_size()
	asset.opaque_bounds = image.get_used_rect(); asset.grip_primary = Vector2(12, 50); asset.tip = Vector2(91, 36)
	var profile := preload("res://scripts/combat_feel/object_affordance_profile.gd").new()
	profile.rigidity = "flexible"; profile.flex_topology = "flexible_line"; profile.terminal_load = "light"
	var original := image.get_data()
	var result: Dictionary = builder.build(asset, profile)
	_check("Anonymous cord with tall terminal builds without modifying Alpha", result.get("ok", false) and original == image.get_data())
	if not result.get("ok", false): return
	var terminal_count := 0; var wrongly_stretched := 0
	for binding: Dictionary in result.rig.bindings:
		if binding.color == Color.GREEN:
			terminal_count += 1
			if binding.role != "terminal": wrongly_stretched += 1
	_check("Entire broad terminal fixture stays rigid, not only a fixed square near tip", terminal_count == 400 and wrongly_stretched == 0)
