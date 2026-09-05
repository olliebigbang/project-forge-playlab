extends SceneTree

const STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	var source := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	source.fill(Color.TRANSPARENT)
	for y: int in range(20, 65):
		for x: int in range(10, 82):
			source.set_pixel(x, y, Color(float(x) / 96.0, float(y) / 96.0, 0.25, 1.0))
	# One-pixel strand and a deliberately separated part are both real Alpha.
	for x: int in range(15, 85): source.set_pixel(x, 78, Color.RED)
	source.set_pixel(90, 90, Color.GREEN)
	var before := source.get_data()
	var result := STYLE.normalize(source, "church_v1")
	check("known style succeeds", result.get("ok", false))
	check("source not mutated", source.get_data() == before)
	var image: Image = result.image
	var same_alpha := true
	for y: int in range(96):
		for x: int in range(96): same_alpha = same_alpha and image.get_pixel(x, y).a == source.get_pixel(x, y).a
	check("exact Alpha including thin strands and separate parts preserved", same_alpha)
	check("fixed palette and 24-color budget", result.report.color_count <= 24 and STYLE.inspect(image, "church_v1").ok)
	check("second normalization is byte-identical", STYLE.normalize(image, "church_v1").image.get_data() == image.get_data())
	check("does not pretend technical gate is aesthetic approval", result.report.aesthetic_review == "not_automated")
	check("unknown style rejected", not STYLE.normalize(source, "arbitrary").ok)
	check("legacy style stays untouched", STYLE.normalize(source, "").image == source)
	var invalid := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	invalid.fill(Color.TRANSPARENT)
	check("empty silhouette rejected", not STYLE.normalize(invalid, "church_v1").ok)
	invalid.set_pixel(40, 40, Color(1, 0, 0, 0.5))
	check("soft Alpha not silently changed", not STYLE.normalize(invalid, "church_v1").ok)
	check("wrong canvas rejected", not STYLE.normalize(Image.create(32, 32, false, Image.FORMAT_RGBA8), "church_v1").ok)
	check("no reference-image conditioning claim", result.report.conditioning.contains("not_image_reference"))
	var bp := WeaponBlueprint.new()
	bp.affordance = {"grip_topology": "body_grip", "body_length": "medium", "flex_topology": "linked_segments"}
	var asset := WeaponVisualAsset.new()
	asset.opaque_bounds = Rect2i(7, 30, 82, 35)
	var fit_compiler := preload("res://scripts/combat_feel/weapon_player_fit_compiler.gd")
	var original_fit := fit_compiler.compile(bp, asset)
	bp.modifiers["art_style_id"] = STYLE.ID
	var new_fit := fit_compiler.compile(bp, asset)
	check("styled hanging links keep length fit, legacy compact fit unchanged", original_fit.rendered_span_pixels == 54.0 and new_fit.rendered_span_pixels == 68.0)
	var arena := preload("res://scripts/systems/gameplay_arena.gd").new()
	arena.blueprint = bp
	var options: Dictionary = arena._soft_pixel_render_options()
	check("chain outlines and holes not bleached or filled with solid strand", not options.readable_tether and not options.readable_links)
	bp.affordance["flex_topology"] = "continuous"
	check("continuous tethers retain continuity treatment", arena._soft_pixel_render_options().readable_tether)
	arena.free()
	print("CHURCH_PIXEL_STYLE_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(label: String, value: bool) -> void:
	if value:
		passed += 1
		print("PASS | " + label)
	else:
		failed += 1
		printerr("FAIL | " + label)
