extends SceneTree

const RESOLVER := preload("res://scripts/combat_feel/side_loop_grip_resolver.gd")
const PROVIDER := preload("res://scripts/services/fal_general_object_visual_provider.gd")
const ANCHOR := preload("res://scripts/systems/anchor_resolver.gd")
var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, condition: bool) -> void:
	if condition: passed += 1; print("PASS | ", label)
	else: failed += 1; printerr("FAIL | ", label)


func _run() -> void:
	var source := _side_loop()
	var bytes := source.get_data()
	var found := RESOLVER.resolve(source, _declaration())
	check("closed lateral hole attached to broad body resolves", bool(found.get("resolved", false)))
	if bool(found.get("resolved", false)):
		var grip: Vector2 = found.grip_primary
		var tip: Vector2 = found.strike_point
		check("primary grip is outer opaque handle bar", grip.x >= 77.0 and source.get_pixelv(Vector2i(grip)).a == 1.0)
		check("contact uses broad body not thin opposing protrusion", tip.x == 25.0 and tip.y > 40.0 and source.get_pixelv(Vector2i(tip)).a == 1.0)
		check("Alpha and source pixels remain untouched", source.get_data() == bytes)
		var mirrored := source.duplicate() as Image
		mirrored.flip_x()
		var reflected := RESOLVER.resolve(mirrored, _declaration())
		check("horizontal reflection preserves chosen roles", bool(reflected.get("resolved", false)) and (reflected.grip_primary as Vector2).is_equal_approx(Vector2(95.0 - grip.x, grip.y)) and (reflected.strike_point as Vector2).is_equal_approx(Vector2(95.0 - tip.x, tip.y)))
		for dy: int in [-3, -2, 2, 3]:
			var shifted := _blank()
			shifted.blit_rect(source, Rect2i(0, 0, 96, 96), Vector2i(0, dy))
			var result := RESOLVER.resolve(shifted, _declaration())
			check("vertical translation preserves grip and contact " + str(dy), bool(result.get("resolved", false)) and (result.grip_primary as Vector2).is_equal_approx(grip + Vector2(0, dy)) and (result.strike_point as Vector2).is_equal_approx(tip + Vector2(0, dy)))
		var noisy := source.duplicate() as Image
		noisy.fill_rect(Rect2i(39, 32, 3, 2), Color.TRANSPARENT)
		var noise_result := RESOLVER.resolve(noisy, _declaration())
		check("six-pixel enclosed noise is not another handle", bool(noise_result.get("resolved", false)) and (noise_result.grip_primary as Vector2).is_equal_approx(grip) and int(noise_result.evidence.eligible_side_loops) == 1)
		var changed_rgb := source.duplicate() as Image
		for y: int in range(96):
			for x: int in range(96):
				if changed_rgb.get_pixel(x, y).a > 0.1: changed_rgb.set_pixel(x, y, Color.MAGENTA)
		var recolored := RESOLVER.resolve(changed_rgb, _declaration())
		check("RGB changes cannot alter mechanism roles", recolored.grip_primary == grip and recolored.strike_point == tip)
		for protrusion_height: int in [3, 18]:
			var nozzle := source.duplicate() as Image
			nozzle.fill_rect(Rect2i(7, 48 - protrusion_height / 2, 18, protrusion_height), Color.WHITE)
			var with_nozzle := RESOLVER.resolve(nozzle, _declaration())
			check("connected side nozzle is not broad contact height=" + str(protrusion_height), bool(with_nozzle.get("resolved", false)) and (with_nozzle.strike_point as Vector2).x == 25.0 and int(with_nozzle.evidence.body_contact_vertical_span) >= int(with_nozzle.evidence.minimum_contact_vertical_span))
	_test_open_side_handle()
	_test_rejections()
	_test_provider_integration(source)
	_test_provider_open_handle_and_function_origin()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--real-sprite="):
			var path := argument.trim_prefix("--real-sprite=")
			var real := Image.load_from_file(path)
			var result := RESOLVER.resolve(real, _declaration())
			check("optional supplied real Alpha resolves without cache writes", bool(result.get("resolved", false)))
			print("REAL_SIDE_LOOP_EVIDENCE ", JSON.stringify(result.get("evidence", {})))
	print("SIDE_LOOP_GRIP_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_rejections() -> void:
	var straight := _blank()
	straight.fill_rect(Rect2i(20, 43, 47, 7), Color.WHITE)
	straight.fill_rect(Rect2i(60, 30, 24, 33), Color.WHITE)
	check("ordinary straight handle is not relabeled a loop", not bool(RESOLVER.resolve(straight, _declaration()).resolved))
	var central := _blank()
	central.fill_rect(Rect2i(20, 20, 56, 56), Color.WHITE)
	central.fill_rect(Rect2i(30, 30, 36, 36), Color.TRANSPARENT)
	check("large central opening is not a lateral grip", not bool(RESOLVER.resolve(central, _declaration()).resolved))
	var two_handles := _blank()
	two_handles.fill_rect(Rect2i(31, 24, 34, 46), Color.WHITE)
	two_handles.fill_rect(Rect2i(14, 35, 20, 26), Color.WHITE)
	two_handles.fill_rect(Rect2i(61, 35, 21, 26), Color.WHITE)
	two_handles.fill_rect(Rect2i(18, 39, 13, 18), Color.TRANSPARENT)
	two_handles.fill_rect(Rect2i(65, 39, 13, 18), Color.TRANSPARENT)
	var ambiguous := RESOLVER.resolve(two_handles, _declaration())
	check("competing side handles are not guessed", not bool(ambiguous.resolved) and ambiguous.evidence.reason == "competing_side_loop_handles")
	var only_noise := straight.duplicate() as Image
	only_noise.fill_rect(Rect2i(70, 43, 2, 3), Color.TRANSPARENT)
	check("tiny isolated hole does not count as handle", not bool(RESOLVER.resolve(only_noise, _declaration()).resolved))
	var disconnected := _side_loop()
	disconnected.fill_rect(Rect2i(60, 24, 2, 46), Color.TRANSPARENT)
	check("detached thin ring does not count as attached handle", not bool(RESOLVER.resolve(disconnected, _declaration()).resolved))
	var open_loop := _side_loop()
	open_loop.fill_rect(Rect2i(77, 46, 5, 1), Color.TRANSPARENT)
	check("open contour does not claim closed-loop evidence", not bool(RESOLVER.resolve(open_loop, _declaration()).resolved))
	for change: Dictionary in [{"rigidity": "flexible"}, {"flex_topology": "segmented_chain"}, {"tether_topology": "line_segment"}, {"state_topology": "folding"}, {"contact_surface": "point"}, {"grip_topology": "body_grip"}]:
		var axes := _declaration()
		axes.merge(change, true)
		var result := RESOLVER.resolve(_side_loop(), axes)
		check("AI declaration gates loop interpretation " + JSON.stringify(change), not bool(result.resolved) and not bool(result.evidence.resolved))
	var missing := _declaration()
	missing.erase("state_topology")
	check("missing fixed-state evidence does not silently resolve", not bool(RESOLVER.resolve(_side_loop(), missing).resolved))


func _test_open_side_handle() -> void:
	var source := _open_side_handle()
	var bytes := source.get_data()
	var found := RESOLVER.resolve(source, _declaration())
	check("open C handle resolves from exterior Alpha bay", bool(found.get("resolved", false)) and str(found.evidence.get("method", "")) == "open_alpha_side_bay_with_broad_inner_body")
	if not bool(found.get("resolved", false)): return
	check("open handle grip uses thin outer bar", (found.grip_primary as Vector2).x >= 76.0)
	check("open handle contact stays on broad opposing body", (found.strike_point as Vector2).x <= 26.0)
	check("open handle analysis leaves source pixels unchanged", source.get_data() == bytes)
	var mirrored := source.duplicate() as Image; mirrored.flip_x()
	var reflected := RESOLVER.resolve(mirrored, _declaration())
	check("open handle reflection preserves grip and contact roles", bool(reflected.get("resolved", false)) and (reflected.grip_primary as Vector2).is_equal_approx(Vector2(95.0 - (found.grip_primary as Vector2).x, (found.grip_primary as Vector2).y)) and (reflected.strike_point as Vector2).is_equal_approx(Vector2(95.0 - (found.strike_point as Vector2).x, (found.strike_point as Vector2).y)))

	var nozzle_only := _blank()
	nozzle_only.fill_rect(Rect2i(25, 25, 42, 45), Color.WHITE)
	nozzle_only.fill_rect(Rect2i(8, 45, 17, 5), Color.WHITE)
	check("straight lateral nozzle cannot masquerade as open handle", not bool(RESOLVER.resolve(nozzle_only, _declaration()).resolved))


func _test_provider_integration(image: Image) -> void:
	var blueprint := WeaponBlueprint.new()
	blueprint.affordance = _declaration()
	var asset: WeaponVisualAsset = ANCHOR.resolve(image, blueprint)
	var before_spin := asset.spin_pivot
	var before_tether := asset.tether_origin
	var provider := PROVIDER.new()
	provider._apply_mechanism_anchor_intent(asset, blueprint)
	check("provider uses structural loop grip before terminal heuristic", asset.anchor_source == "alpha_side_loop+ai_rigid_broad_contact" and bool(blueprint.modifiers.side_loop_grip_evidence.resolved))
	check("full source orientation places broad contact forward", asset.orientation_flipped and asset.grip_primary.x < asset.tip.x)
	var expected := image.duplicate() as Image
	expected.flip_x()
	check("forward normalization reflects entire image rather than moving art parts", asset.source_image.get_data() == expected.get_data())
	check("remaining anchors are reflected in the same coordinate frame", asset.spin_pivot.is_equal_approx(Vector2(95 - before_spin.x, before_spin.y)) and asset.tether_origin.is_equal_approx(Vector2(95 - before_tether.x, before_tether.y)))
	check("grip and strike remain on final opaque pixels", asset.source_image.get_pixelv(Vector2i(asset.grip_primary)).a == 1.0 and asset.source_image.get_pixelv(Vector2i(asset.tip)).a == 1.0)
	var mirrored := image.duplicate() as Image
	mirrored.flip_x()
	var mirrored_blueprint := WeaponBlueprint.new()
	mirrored_blueprint.affordance = _declaration()
	var other: WeaponVisualAsset = ANCHOR.resolve(mirrored, mirrored_blueprint)
	provider._apply_mechanism_anchor_intent(other, mirrored_blueprint)
	check("mirrored source normalizes to identical final grip and contact", other.source_image.get_data() == asset.source_image.get_data() and other.grip_primary == asset.grip_primary and other.tip == asset.tip)


func _test_provider_open_handle_and_function_origin() -> void:
	var image := _open_side_handle()
	# A tall activation-like projection is farther vertically from the hand than
	# the working head. Directed output must still use the forward Alpha terminal.
	image.fill_rect(Rect2i(43, 4, 12, 20), Color.WHITE)
	var blueprint := WeaponBlueprint.new()
	blueprint.affordance = _declaration().merged({"activation_mode": "momentary", "functional_output": "directed_stream"})
	blueprint.modifiers["general_object_mechanism_roles"] = {"grip_part_zh": "开放侧把", "activation_part_zh": "按压部", "effect_origin_part_zh": "直线出口"}
	var asset := ANCHOR.resolve(image, blueprint)
	var provider := PROVIDER.new()
	provider._apply_mechanism_anchor_intent(asset, blueprint)
	check("open handle becomes real grip before endpoint fallback", asset.anchor_source == "alpha_side_loop+ai_rigid_broad_contact" and asset.grip_primary.x < asset.tip.x)
	check("directed native output gets the forward Alpha terminal instead of the tall control", asset.muzzle.x > asset.tip.x and asset.muzzle.y > 35.0 and asset.muzzle.distance_to(asset.grip_primary) > asset.tip.distance_to(asset.grip_primary) and bool(blueprint.modifiers.native_function_origin_evidence.resolved))
	check("native output role evidence names the semantic effect part", str(blueprint.modifiers.native_function_origin_evidence.role) == "直线出口")

	var old_blueprint := WeaponBlueprint.new(); old_blueprint.affordance = _declaration().merged({"activation_mode": "continuous_hold", "functional_output": "directed_stream"})
	old_blueprint.modifiers["general_object_mechanism_roles"] = {"grip_part_zh": "开放侧把", "activation_part_zh": "按压部", "effect_origin_part_zh": "直线出口"}
	var old_asset := ANCHOR.resolve(image, old_blueprint)
	old_asset.anchor_source = "alpha_principal_terminals+ai_contact_surface"
	var blueprint_hash := var_to_bytes(old_blueprint.to_dict()).hex_encode().sha256_text()
	var expected_pixels := image.duplicate() as Image; expected_pixels.flip_x()
	var migrated := provider.refresh_automatic_handle_binding(old_asset, old_blueprint)
	check("old automatic endpoint anchor migrates in memory", migrated and old_asset.grip_primary.x < old_asset.tip.x)
	check("runtime migration preserves the distinct forward native output origin", old_asset.muzzle.x > old_asset.tip.x and old_asset.muzzle.y > 35.0)
	check("runtime migration uses one whole-image reflection, never part edits", old_asset.orientation_flipped and old_asset.source_image.get_data() == expected_pixels.get_data())
	check("runtime handle migration leaves blueprint declaration unchanged", blueprint_hash == var_to_bytes(old_blueprint.to_dict()).hex_encode().sha256_text())


func _declaration() -> Dictionary:
	return {"grip_topology": "one_hand_handle", "contact_surface": "broad", "rigidity": "rigid", "state_topology": "fixed", "flex_topology": "none", "tether_topology": "none"}


func _side_loop() -> Image:
	var image := _blank()
	image.fill_rect(Rect2i(25, 24, 36, 46), Color.WHITE)
	image.fill_rect(Rect2i(59, 35, 23, 26), Color.WHITE)
	image.fill_rect(Rect2i(62, 39, 15, 18), Color.TRANSPARENT)
	image.fill_rect(Rect2i(10, 34, 15, 4), Color.WHITE)
	return image


func _open_side_handle() -> Image:
	var image := _blank()
	image.fill_rect(Rect2i(25, 24, 40, 47), Color.WHITE)
	image.fill_rect(Rect2i(59, 33, 24, 7), Color.WHITE)
	image.fill_rect(Rect2i(77, 37, 6, 23), Color.WHITE)
	image.fill_rect(Rect2i(10, 46, 15, 4), Color.WHITE)
	return image


func _blank() -> Image:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image
