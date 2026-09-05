extends SceneTree

const ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const PROFILE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const RIG := preload("res://scripts/combat_feel/automatic_pixel_visual_rig_builder.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
var passed := 0
var failed := 0
var report: Dictionary = {"schema": "main-arena-axis-execution-v1", "fixture": true, "live_ai_call": false, "rows": []}

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool, detail: Variant = "") -> void:
	if ok:
		passed += 1
		print("PASS | ", label)
	else:
		failed += 1
		printerr("FAIL | ", label, " | ", detail)

func _base() -> Dictionary:
	var p := PROFILE.new()
	p.contact_surface = "edge"
	p.has_point = true
	p.has_edge = true
	p.has_broad_face = true
	p.evidence_parts = PackedStringArray(["ANONYMOUS CONTROLLED TEST SHAPE; not a live AI interpretation"])
	return p.to_dict()

func _arena(axes: Dictionary) -> GameplayArena:
	var bp := WeaponBlueprint.fixed_blueprint("hammer")
	bp.behavior_family = "heavy_melee"
	bp.affordance = axes.duplicate(true)
	bp.affordance_source = "test_only_anonymous_axes"
	var image := Image.create(128, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(4, 21, 112, 6), Color("94a3b8"))
	image.fill_rect(Rect2i(70, 15, 43, 18), Color("d4d4d8"))
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.texture = ImageTexture.create_from_image(image)
	asset.canvas_size = image.get_size()
	asset.opaque_bounds = image.get_used_rect()
	asset.grip_primary = Vector2(18, 24)
	asset.grip_secondary = Vector2(40, 24)
	asset.tip = Vector2(114, 24)
	asset.muzzle = Vector2(100, 19)
	asset.rear_contact = Vector2(4, 24)
	var arena := ARENA.new() as GameplayArena
	arena.start_stage("training", bp, asset)
	if arena.melee_runtime.profile != null and (str(axes.flex_topology) != "none" or str(axes.tether_topology) != "none"):
		var rig: Dictionary = RIG.build(asset, arena.melee_runtime.affordance)
		if bool(rig.get("ok", false)): asset.visual_rig = rig.get("rig")
	arena.enemies.clear()
	return arena

func _measure(axes: Dictionary) -> Dictionary:
	var arena := _arena(axes)
	if arena.melee_runtime.profile == null:
		var error := {"valid": false, "error": arena.melee_runtime.error}
		arena.free()
		return error
	var observed := {}
	var final_parameters := {}
	for attack: int in range(4):
		var held := attack == 3
		arena._update_melee_attack(true, 0.0, held)
		var elapsed := 0.0
		var angle_sum := 0.0
		var movement_sum := 0.0
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		var contact_count := 0
		var active_steps := 0
		var field_points := 0
		var start_x := arena.player_position.x
		var max_power := 0.0
		while arena.melee_runtime.busy() and elapsed < 3.5:
			arena._update_melee_attack(false, 1.0 / 60.0, held and elapsed < 0.9)
			elapsed += 1.0 / 60.0
			angle_sum += float(arena.melee_frame.get("angle", 0.0))
			movement_sum += float(arena.melee_runtime.movement_ratio())
			max_power = maxf(max_power, arena.melee_runtime.state_power())
			if arena.melee_runtime.active():
				active_steps += 1
				var contacts: PackedVector2Array = arena.melee_frame.get("contacts", PackedVector2Array())
				contact_count = maxi(contact_count, contacts.size())
				for point: Vector2 in contacts:
					max_x = maxf(max_x, point.x - arena.player_position.x)
					min_y = minf(min_y, point.y - arena.player_position.y)
					max_y = maxf(max_y, point.y - arena.player_position.y)
				field_points = maxi(field_points, (arena.melee_frame.get("field", PackedVector2Array()) as PackedVector2Array).size())
				final_parameters[str(attack)] = arena.melee_runtime.evidence()
		observed[str(attack)] = {"seconds": snappedf(elapsed, 0.0001), "active_steps": active_steps, "angle_sum": snappedf(angle_sum, 0.01), "movement_sum": snappedf(movement_sum, 0.01), "root_distance": snappedf(arena.player_position.x - start_x, 0.01), "contact_count": contact_count, "max_x": snappedf(max_x, 0.1) if is_finite(max_x) else 0.0, "min_y": snappedf(min_y, 0.1) if is_finite(min_y) else 0.0, "max_y": snappedf(max_y, 0.1) if is_finite(max_y) else 0.0, "field_points": field_points, "max_power": max_power}
	arena.free()
	return {"valid": true, "observed": observed, "final_parameters": final_parameters}

func _run() -> void:
	var base := _base()
	var soft := base.duplicate(true)
	soft.merge({"rigidity": "flexible", "flex_topology": "bending_shaft", "tether_topology": "flexible_line", "tether_deployment": "fixed_length"}, true)
	var state := base.duplicate(true)
	state.merge({"state_topology": "radial_expand", "activation_mode": "momentary"}, true)
	var explicit_secondary := base.duplicate(true)
	explicit_secondary.has_point = false
	explicit_secondary.has_broad_face = false
	var contexts := {"base": base, "soft": soft, "state": state, "explicit_secondary": explicit_secondary}
	var baseline := {}
	for key: String in contexts: baseline[key] = _measure(contexts[key])
	var mutations := {
		"handle_length": ["base", "long"], "body_length": ["base", "long"],
		"grip_topology": ["base", "two_hand_handle"], "rigidity": ["base", "semi_rigid"],
		"mass_distribution": ["base", "front"], "contact_surface": ["base", "broad"],
		"secondary_contact_surface": ["explicit_secondary", "point"], "flex_topology": ["soft", "flexible_line"],
		"tether_topology": ["soft", "linked_segments"], "terminal_load": ["soft", "heavy"],
		"tether_mode": ["soft", "hook"], "tether_deployment": ["soft", "cast_retract"],
		"state_topology": ["state", "telescoping"], "activation_mode": ["state", "continuous_hold"],
		"functional_output": ["state", "directed_stream"],
	}
	for axis: String in AXES.REQUIRED_AXES:
		var context := str(mutations[axis][0])
		var changed: Dictionary = contexts[context].duplicate(true)
		changed[axis] = mutations[axis][1]
		var result := _measure(changed)
		var original: Dictionary = baseline[context]
		var effects := []
		if bool(result.get("valid", false)) and bool(original.get("valid", false)):
			for stage: String in result.observed:
				for metric: String in result.observed[stage]:
					if result.observed[stage][metric] != original.observed[stage][metric]: effects.append(stage + "." + metric)
		# Tether mode owns the target reaction, not necessarily the geometric path.
		if axis == "tether_mode" and bool(result.get("valid", false)):
			var interaction: Dictionary = preload("res://scripts/combat_feel/weapon_target_interaction_resolver.gd").compile_melee(changed, result.final_parameters["2"].primitive)
			if str(interaction.get("displacement_mode", "")) == "toward_source": effects.append("target.displacement_mode")
		var row := {"axis": axis, "context": context, "from": contexts[context][axis], "to": changed[axis], "effects": effects, "zero_effect": effects.is_empty(), "before": original, "after": result}
		report.rows.append(row)
		_check("single-axis actual execution: " + axis, not effects.is_empty(), result.get("error", effects))
	_test_contact_contract(base)
	_test_soft_contract()
	_test_activation_contract(state)
	_test_directed_output_uses_native_origin(base)
	report["passed"] = passed
	report["failed"] = failed
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/melee-axis-review"))
	var file := FileAccess.open("res://.tools/melee-axis-review/execution-matrix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ARENA_MECHANISM_AXES passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_contact_contract(base: Dictionary) -> void:
	var arena := _arena(base)
	arena._update_melee_attack(true, 0.0)
	var early := arena._melee_frame_contains(arena.player_position + Vector2(60, 0))
	while not arena.melee_runtime.active(): arena._update_melee_attack(false, 1.0 / 120.0)
	var contacts: PackedVector2Array = arena.melee_frame.contacts
	var visible: Array = arena.melee_frame.pixels
	var same_pixels := not contacts.is_empty()
	for point: Vector2 in contacts:
		var found := false
		for pixel: Dictionary in visible:
			if Vector2(pixel.position) == point: found = true; break
		same_pixels = same_pixels and found
	var can_hit := not contacts.is_empty() and arena._melee_frame_contains(contacts[0], 0.1)
	var far_hit := arena._melee_frame_contains(arena.player_position + Vector2(500, 0))
	arena._update_melee_attack(false, 1.5)
	var late := arena._melee_frame_contains(contacts[0]) if not contacts.is_empty() else true
	_check("hits only in active phase, on drawn contact pixels, never remote or recovery", not early and same_pixels and can_hit and not far_hit and not late)
	_check("complete 1-2-3 recipe reaches secondary contact", str(report.rows[6].after.final_parameters["2"].primitive.contact_surface) == "point")
	arena.free()

func _test_soft_contract() -> void:
	var loaded: Dictionary = LOADER.new().load_soft_weapon_asset("fishing_rod_builtin")
	var arena := ARENA.new() as GameplayArena
	arena.start_stage("training", loaded.blueprint, loaded.asset)
	arena.enemies.clear()
	arena._update_melee_attack(true, 0.0, true)
	var maximum := 0.0
	var pixel_hit := false
	for step: int in range(130):
		arena._update_melee_attack(false, 1.0 / 60.0, step < 55)
		if not arena.melee_runtime.active(): continue
		var geometry: Dictionary = arena.melee_frame.get("geometry", {})
		maximum = maxf(maximum, Vector2(geometry.get("contact", arena.player_position)).distance_to(arena.player_position))
		var points: PackedVector2Array = arena.melee_frame.contacts
		if not points.is_empty(): pixel_hit = pixel_hit or arena._melee_frame_contains(points[-1], 0.1)
	_check("real source rig casts beyond body and hits at rendered endpoint", maximum > 140.0 and pixel_hit, maximum)
	arena.free()

func _test_activation_contract(state: Dictionary) -> void:
	var axes := state.duplicate(true)
	axes.activation_mode = "charge_release"
	var arena := _arena(axes)
	arena._update_melee_attack(true, 0.0, true)
	arena._update_melee_attack(false, 1.2, true)
	var waiting := str(arena.melee_runtime.controller.phase) == "startup"
	arena._update_melee_attack(false, 1.0 / 120.0, false)
	_check("charge_release waits for release before active", waiting and arena.melee_runtime.active())
	arena.free()


func _test_directed_output_uses_native_origin(base: Dictionary) -> void:
	var axes := base.duplicate(true)
	axes["activation_mode"] = "continuous_hold"
	axes["functional_output"] = "directed_stream"
	axes["state_topology"] = "fixed"
	var arena := _arena(axes)
	arena._update_melee_attack(true, 0.0, true)
	var observed := Vector2.ZERO
	var expected := Vector2.ZERO
	var found := false
	for step: int in range(180):
		arena._update_melee_attack(false, 1.0 / 60.0, step < 120)
		var field: PackedVector2Array = arena.melee_frame.get("field", PackedVector2Array())
		if field.size() != 4: continue
		observed = (field[0] + field[3]) * 0.5
		expected = arena._soft_source_world(arena.asset.muzzle, Vector2(arena.melee_frame.hand), float(arena.melee_frame.angle))
		found = true
		break
	_check("fixed directed output begins at the validated native Alpha origin", found and observed.distance_to(expected) <= 1.1, {"observed": observed, "expected": expected})
	var field: PackedVector2Array = arena.melee_frame.get("field", PackedVector2Array())
	var target_point := Vector2.ZERO
	if field.size() == 4:
		for point: Vector2 in field: target_point += point
		target_point /= 4.0
		arena._spawn_enemy("target", target_point, 200.0)
	var health_before := float(arena.enemies[0].hp) if not arena.enemies.is_empty() else 0.0
	for step: int in range(32):
		arena._update_melee_attack(false, 1.0 / 120.0, true)
	var health_after := float(arena.enemies[0].hp) if not arena.enemies.is_empty() else health_before
	_check("continuous directed field damages a target inside its rendered polygon", found and health_after < health_before, {"target": target_point, "before": health_before, "after": health_after})
	arena.free()
