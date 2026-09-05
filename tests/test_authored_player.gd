extends SceneTree
const ARENA := preload("res://scripts/sunny_player_preview/authored_arena.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const MELEE_CLIP := preload("res://scripts/authored_player/melee_clip.gd")
var errors: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: errors.append(message)

func run() -> void:
	var entries: Array[Dictionary] = LIBRARY.new().load_all(false)
	check(entries.size() == 5, "Five unchanged bundled AI weapons")
	var arena := ARENA.new(); root.add_child(arena)
	var report: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var before := var_to_bytes(entry.blueprint.to_dict()).hex_encode().sha256_text()
		arena.start_stage("training", entry.blueprint, entry.asset); arena.set_process(false)
		check(not arena._uses_authored_blade_action(), "Bundled gun, vessel, point tool, and flexible tool never receive blade-only presentation")
		var clips := {}
		for i: int in range(240):
			arena.touch_attack = i < 120
			if i == 0: arena.request_touch_attack()
			arena.touch_vector = Vector2.RIGHT if i >= 140 and i < 175 else Vector2.ZERO
			if i == 150: arena.request_touch_dodge()
			arena._process(1.0 / 60)
			var p: Dictionary = arena._attachment()
			clips[p.frame.key] = true
			check(is_finite(p.hand.x) and is_finite(p.hand.y), "Finite hand")
			if p.fit.support_required:
				var grips := arena._actual_grips(p.origin, p.angle, p.fit.draw_scale)
				check(Vector2(grips.primary).distance_to(p.hand) < 0.01 and Vector2(grips.secondary).distance_to(p.support) < 0.01, "Real support grip, including flexible binding")
			if arena.melee_runtime.profile != null:
				arena._build_melee_frame()
				check(Vector2(arena.melee_frame.hand).distance_to(p.origin) < 0.01, "Visible/contact common root")
			check(not p.frame.parts.has("Weapon"), "No reference weapon in body")
		check(before == var_to_bytes(entry.blueprint.to_dict()).hex_encode().sha256_text(), "Mechanism declaration unchanged")
		check(clips.has("body/Roll"), "Real dodge body animation")
		if arena._uses_firearm_runtime():
			check(not arena.shot_records.is_empty(), "Actual compiled shots")
			check(int(arena.metrics.shots_fired) > 0, "Compiled ammo/shot event")
			arena.authored_moving = false; arena.dodge_timer = 0; arena.reload_timer = 0
			arena.weapon_muzzle_climb_degrees = 0; arena.sustained_muzzle_climb_degrees = 0; arena.weapon_recoil_offset = 0
			arena.shot_age = 0; arena.player_position = Vector2(400, 558)
			for face: float in [1.0, -1.0]:
				arena.facing = face
				var pose := arena._attachment()
				var muzzle_local: Vector2 = (entry.asset.muzzle - entry.asset.grip_primary) * float(pose.fit.draw_scale)
				var muzzle_expected := Vector2(pose.hand) + Vector2(muzzle_local.x * face, muzzle_local.y).rotated(pose.angle)
				check(muzzle_expected.distance_to(arena._muzzle_world()) < 0.01, "Both faces: drawn barrel = actual muzzle")
				check(arena._safe_projectile_origin(muzzle_expected) == muzzle_expected, "No backwards muzzle teleport")
			arena.facing = 1; arena.authored_crouched = false
			var low: Dictionary = arena.enemies[1]
			low.pos = Vector2(700, 558)
			arena.enemies = [low]
			var crouch_needed := arena._should_crouch_for_target()
			arena._fire_bullet()
			print("LOW TARGET ", entry.blueprint.display_name, " crouch=", crouch_needed, " stand=", arena._flat_muzzle_for_pose(0), " crouch_muzzle=", arena._flat_muzzle_for_pose(1), " actual=", arena._muzzle_world(), " target=", low.pos)
			check(arena.authored_crouched == crouch_needed, "Auto crouch based on actual fire pose")
			var hp_before := float(low.hp)
			for _step: int in range(60): arena._update_projectiles(1.0 / 60)
			check(float(low.hp) < hp_before, "Horizontal actual projectile can hit same-lane low alpha")
		print(entry.blueprint.display_name, " clips ", clips.keys(), " fit ", arena._weapon_fit().draw_scale)
		report.append({"weapon": entry.blueprint.display_name, "clips": clips.keys(), "fit": arena._weapon_fit().duplicate(true), "shots": arena.shot_records.size()})
	_test_structural_motion_routes(arena, report)
	var overhead: Dictionary = arena.source_rig.frame("combat/SwordSlash01", 1)
	var neck_pixel := Vector2(42.5, 52.5)
	check(overhead.arm_pixels.LeftArm.has(neck_pixel), "Overhead neck pixel exists in source far-arm layer")
	check(Geometry2D.is_point_in_polygon(neck_pixel, overhead.core_hull), "Body restoration includes the source neck/chest overlap")
	check(arena.source_rig.errors.is_empty(), "Source layer completeness: " + str(arena.source_rig.errors))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/authored-player"))
	var file := FileAccess.open("res://.tools/authored-player/tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "errors": errors, "weapons": report}, "  "))
	print("AUTHORED PLAYER: ", checks, " checks; ", errors.size(), " failures ", errors)
	print("Tests finished: passed=", checks - errors.size(), " failed=", errors.size())
	arena.free(); quit(1 if not errors.is_empty() else 0)

func _test_structural_motion_routes(arena: GameplayArena, report: Array[Dictionary]) -> void:
	# Frozen developer-only assets exercise conditional adapters. They are NOT
	# added to the normal player's shelf or presented as fresh AI generation.
	var loader := LOADER.new()
	var specimens := [loader.load_generalization_asset("longsword_generalization"), loader.load_soft_weapon_asset("fishing_rod_builtin")]
	for specimen: Dictionary in specimens:
		check(specimen.get("ok", false), "Frozen structural route fixture loaded")
		if not specimen.get("ok", false): continue
		var bp: WeaponBlueprint = specimen.blueprint
		if bp.affordance.is_empty():
			# Older archive stores axes in a separate Resource. Copy that evidence
			# for this test only; no invented identity-specific move declaration.
			var profile: Resource = specimen.affordance_profile
			for axis: String in AXES.REQUIRED_AXES + AXES.REQUIRED_FLAGS: bp.affordance[axis] = profile.get(axis)
			bp.affordance.confidence = profile.confidence
			bp.affordance.evidence_parts = Array(profile.evidence_parts)
		var before := var_to_bytes(bp.to_dict()).hex_encode().sha256_text()
		arena.start_stage("training", bp, specimen.asset); arena.set_process(false); arena.enemies.clear()
		check(arena.melee_runtime.profile != null, "Structural route compiled: " + arena.melee_runtime.error)
		if arena.melee_runtime.profile == null: continue
		var clips := {}
		var authored_blade_route: bool = bool(arena._uses_authored_blade_action())
		var blade_alignment_ok := true
		var raw_blade_pose_ok := true
		for step: int in range(180):
			arena._update_melee_attack(step == 0, 1.0 / 60.0, step < 55)
			var p: Dictionary = arena._attachment()
			clips[p.frame.key] = true
			check(is_finite(p.hand.x) and is_finite(p.support.x), "Sword/rod finite authored hands")
			var grips: Dictionary = arena._actual_grips(p.origin, p.angle, p.fit.draw_scale)
			check(Vector2(grips.primary).distance_to(p.hand) < 0.01, "Sword/rod true deformed primary grip")
			if authored_blade_route and bool(p.get("authored_blade", false)) and arena.melee_runtime.busy():
				raw_blade_pose_ok = raw_blade_pose_ok and p.front_frame.parts.RightArm == p.frame.parts.RightArm
				var source_hand: Vector2 = arena.SOURCE_RIG.world(p.frame.primary.hand, p.frame, p.feet, arena.facing, arena.SOURCE_SCALE)
				raw_blade_pose_ok = raw_blade_pose_ok and Vector2(p.hand).distance_to(source_hand) < 0.01
				var reference_vector: Vector2 = arena._reference_weapon_vector(p.frame)
				if reference_vector.length_squared() > 0.01:
					var generated_vector: Vector2 = (specimen.asset.tip - specimen.asset.grip_primary) * float(p.fit.draw_scale)
					generated_vector = Vector2(generated_vector.x * arena.facing, generated_vector.y).rotated(float(p.angle))
					var authored_vector: Vector2 = Vector2(reference_vector.x * arena.facing, reference_vector.y) * 3.0
					blade_alignment_ok = blade_alignment_ok and absf(generated_vector.angle_to(authored_vector)) < 0.02
		var cast_route := str(bp.affordance.get("tether_deployment", "none")) in ["cast_retract", "launch_tension"]
		if cast_route:
			check(not authored_blade_route, "Flexible tether never receives rigid blade presentation")
			check(clips.has("fishing/Charge") and clips.has("fishing/Cast") and clips.has("fishing/Reel"), "Tether axes select charge/cast/reel")
		else:
			check(authored_blade_route, "Rigid passive edge axes select blade presentation")
			check(clips.keys().any(func(k: String) -> bool: return k.begins_with("combat/Sword")), "Rigid edge/point axes select authored melee")
			check(blade_alignment_ok, "Generated blade follows the source sword trajectory")
			check(raw_blade_pose_ok, "Blade keeps untouched source hand and arm layer")
			for combo: int in range(1, 4):
				var native_frame: Dictionary = MELEE_CLIP.sample_blade(arena.source_rig, combo, "normal", "active", 0.5)
				check(native_frame.key == ["", "combat/SwordCombo01", "combat/SwordCombo02", "combat/SwordCombo04"][combo], "Blade combo uses the native authored sequence")
			check(bool(arena.source_rig.frame("combat/SwordCombo01", 3).weapon_smear) and not bool(arena.source_rig.frame("combat/SwordCombo01", 0).weapon_smear), "Only the authored active slash silhouette becomes a trail")
		check(before == var_to_bytes(bp.to_dict()).hex_encode().sha256_text(), "Sword/rod declaration unchanged by animation")
		report.append({"developer_only": true, "weapon": bp.display_name, "clips": clips.keys(), "cast_route": cast_route})
