# Developer-only real-generation matrix; never loaded by combat runtime.
extends SceneTree

const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const AXIS_RESOLVER := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const AUTOMATIC_VISUAL_RIG := preload("res://scripts/combat_feel/automatic_pixel_visual_rig_builder.gd")
const PIXEL_SCAFFOLD := preload("res://scripts/combat_feel/mechanism_pixel_scaffold.gd")
const VISUAL_BRIEF := preload("res://scripts/combat_feel/mechanism_visual_brief.gd")
const READABILITY_GATE := preload("res://scripts/combat_feel/mechanism_visual_readability_gate.gd")
const VISUAL_PROMPT := preload("res://scripts/services/open_identity_visual_prompt.gd")

const CONTRACT := "forge-mechanism-visual-flux-matrix-v1"
const AI_SOURCE := "ai_mechanism_visual_matrix_v1"
const SHARED_IDENTITY := "由深色木料和黄铜制成的匿名手工工具"
const SHARED_DESCRIPTION := "one original handmade utility object made from dark wood and brass, with no writing or emblem"
const CASES := [
	{
		"case_id": "anonymous_bending_tether",
		"seed": 6261001,
		"axes": {
			"handle_length": "short", "body_length": "long", "grip_topology": "one_hand_handle",
			"rigidity": "flexible", "mass_distribution": "balanced", "contact_surface": "whole_body",
			"secondary_contact_surface": "point", "flex_topology": "bending_shaft",
			"tether_topology": "flexible_line", "terminal_load": "light", "tether_mode": "hook", "tether_deployment": "cast_retract",
		},
		"flags": {"has_point": true, "has_edge": false, "has_broad_face": false, "has_barrel": false, "has_stock": false},
	},
	{
		"case_id": "anonymous_continuous_wrap",
		"seed": 6261002,
		"axes": {
			"handle_length": "short", "body_length": "long", "grip_topology": "one_hand_handle",
			"rigidity": "flexible", "mass_distribution": "balanced", "contact_surface": "whole_body",
			"secondary_contact_surface": "none", "flex_topology": "flexible_line",
			"tether_topology": "none", "terminal_load": "none", "tether_mode": "wrap", "tether_deployment": "none",
		},
		"flags": {"has_point": false, "has_edge": false, "has_broad_face": false, "has_barrel": false, "has_stock": false},
	},
	{
		"case_id": "anonymous_linked_terminal",
		"seed": 6261003,
		"axes": {
			"handle_length": "short", "body_length": "long", "grip_topology": "one_hand_handle",
			"rigidity": "flexible", "mass_distribution": "balanced", "contact_surface": "whole_body",
			"secondary_contact_surface": "point", "flex_topology": "linked_segments",
			"tether_topology": "none", "terminal_load": "light", "tether_mode": "none", "tether_deployment": "none",
		},
		"flags": {"has_point": true, "has_edge": false, "has_broad_face": false, "has_barrel": false, "has_stock": false},
	},
	{
		"case_id": "anonymous_rigid_broad",
		"seed": 6261004,
		"axes": {
			"handle_length": "long", "body_length": "long", "grip_topology": "two_hand_handle",
			"rigidity": "rigid", "mass_distribution": "front", "contact_surface": "broad",
			"secondary_contact_surface": "none", "flex_topology": "none",
			"tether_topology": "none", "terminal_load": "none", "tether_mode": "none", "tether_deployment": "none",
		},
		"flags": {"has_point": false, "has_edge": false, "has_broad_face": true, "has_barrel": false, "has_stock": false},
	},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := _arguments()
	var mode := str(arguments.get("mode", ""))
	var result: Dictionary
	if mode == "prepare":
		result = _prepare_matrix(str(arguments.get("matrix-root", "")))
	elif mode == "evaluate":
		result = _evaluate_result(
			str(arguments.get("request", "")),
			str(arguments.get("result", ""))
		)
	else:
		result = {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_MODE_INVALID"}
	print(JSON.stringify(result))
	quit(0 if bool(result.get("ok", false)) else 2)


func _prepare_matrix(root_value: String) -> Dictionary:
	var matrix_root := _absolute_path(root_value)
	if matrix_root.is_empty():
		return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_ROOT_MISSING"}
	if DirAccess.make_dir_recursive_absolute(matrix_root.path_join("requests")) != OK:
		return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_ROOT_CREATE_FAILED"}
	var palette_path := matrix_root.path_join("palette.png")
	var palette_error := PIXEL_SCAFFOLD.palette_image().save_png(palette_path)
	if palette_error != OK:
		return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_PALETTE_WRITE_FAILED"}
	var records: Array[Dictionary] = []
	for case_value: Variant in CASES:
		var case_data := case_value as Dictionary
		var affordance := _affordance(case_data)
		var validation := AXIS_RESOLVER.validate_ai_declaration(affordance, AI_SOURCE)
		if not bool(validation.get("ok", false)):
			return {
				"ok": false,
				"error": str(validation.get("error", "MECHANISM_VISUAL_MATRIX_AFFORDANCE_INVALID")),
				"case_id": str(case_data.get("case_id", "")),
			}
		var blueprint := _blueprint(case_data, affordance)
		blueprint.visual_structure_brief = VISUAL_BRIEF.compile(affordance, AI_SOURCE)
		blueprint.visual_structure_brief_source = VISUAL_BRIEF.SOURCE
		blueprint.visual_prompt = VISUAL_PROMPT.build(blueprint)
		var case_id := str(case_data["case_id"])
		var request_directory := matrix_root.path_join("requests").path_join(case_id)
		if DirAccess.make_dir_recursive_absolute(request_directory) != OK:
			return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_CASE_DIRECTORY_FAILED", "case_id": case_id}
		var brief_path := request_directory.path_join("visual_structure_brief.json")
		var scaffold_path := request_directory.path_join("structure_scaffold.png")
		var scaffold_contract_path := request_directory.path_join("structure_scaffold.json")
		var request_path := request_directory.path_join("request.json")
		var brief_write := _write_json_atomic(brief_path, blueprint.visual_structure_brief)
		if not brief_write.is_empty():
			return {"ok": false, "error": brief_write, "case_id": case_id}
		var scaffold := PIXEL_SCAFFOLD.build(affordance)
		if not bool(scaffold.get("ok", false)) or not scaffold.get("image") is Image:
			return {
				"ok": false,
				"error": str(scaffold.get("error", "MECHANISM_VISUAL_MATRIX_SCAFFOLD_FAILED")),
				"case_id": case_id,
			}
		if (scaffold.get("image") as Image).save_png(scaffold_path) != OK:
			return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_SCAFFOLD_WRITE_FAILED", "case_id": case_id}
		var scaffold_contract: Dictionary = scaffold.get("contract", {})
		var scaffold_contract_write := _write_json_atomic(scaffold_contract_path, scaffold_contract)
		if not scaffold_contract_write.is_empty():
			return {"ok": false, "error": scaffold_contract_write, "case_id": case_id}
		var request := {
			"contract": CONTRACT,
			"case_id": case_id,
			"seed": int(case_data["seed"]),
			"identity_constant": SHARED_IDENTITY,
			"generation_prompt": blueprint.visual_prompt,
			"provider_prompt": _provider_prompt(blueprint.visual_structure_brief),
			"prompt_policy_version": VISUAL_PROMPT.POLICY_VERSION,
			"blueprint": blueprint.to_dict(),
			"visual_structure_brief": blueprint.visual_structure_brief,
			"structure_scaffold": "structure_scaffold.png",
			"structure_scaffold_contract": scaffold_contract,
			"palette": "../../palette.png",
			"structure_locked": true,
			"style_may_change": true,
			"automatic": true,
			"maximum_redraws": 2,
			"player_confirmation_required": false,
		}
		var request_write := _write_json_atomic(request_path, request)
		if not request_write.is_empty():
			return {"ok": false, "error": request_write, "case_id": case_id}
		records.append({
			"case_id": case_id,
			"seed": int(case_data["seed"]),
			"request": "requests/%s/request.json" % case_id,
			"visual_structure_brief": "requests/%s/visual_structure_brief.json" % case_id,
			"structure_scaffold": "requests/%s/structure_scaffold.png" % case_id,
			"structure_scaffold_contract": "requests/%s/structure_scaffold.json" % case_id,
			"palette": "palette.png",
			"axes": affordance.duplicate(true),
		})
	var contract := {
		"contract": CONTRACT,
		"created_at_utc": Time.get_datetime_string_from_system(true, true),
		"identity_constant": SHARED_IDENTITY,
		"identity_is_constant_across_cases": true,
		"structure_source": "deterministic_mechanism_axes",
		"generator_authority": "style_and_color_only",
		"case_count": records.size(),
		"cases": records,
		"automatic": true,
		"maximum_redraws_per_case": 2,
		"player_confirmation_required": false,
		"playtest_performed": false,
		"feel_tuning_performed": false,
	}
	var contract_path := matrix_root.path_join("matrix_contract.json")
	var contract_write := _write_json_atomic(contract_path, contract)
	if not contract_write.is_empty():
		return {"ok": false, "error": contract_write}
	return {"ok": true, "matrix_contract": contract_path, "case_count": records.size()}


func _evaluate_result(request_value: String, result_value: String) -> Dictionary:
	var request_path := _absolute_path(request_value)
	var result_directory := _absolute_path(result_value)
	var request := _read_json(request_path)
	if request.is_empty() or str(request.get("contract", "")) != CONTRACT:
		return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_REQUEST_INVALID"}
	var manifest := _read_json(result_directory.path_join("manifest.json"))
	if str(manifest.get("status", "")) != "success":
		return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_RESULT_NOT_SUCCESS"}
	var blueprint_data: Variant = request.get("blueprint", {})
	if not blueprint_data is Dictionary:
		return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_BLUEPRINT_INVALID"}
	var blueprint := WeaponBlueprint.from_dict(blueprint_data as Dictionary)
	var image := Image.load_from_file(result_directory.path_join("processed_sprite.png"))
	if image == null or image.is_empty() or image.get_size() != Vector2i(96, 96):
		return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_SPRITE_INVALID"}
	var asset: WeaponVisualAsset = ANCHOR_RESOLVER.resolve(image, blueprint)
	if asset == null:
		return {"ok": false, "error": "MECHANISM_VISUAL_MATRIX_ANCHOR_RESOLUTION_FAILED"}
	var scaffold_anchor_result := _apply_scaffold_anchors(asset, image, request.get("structure_scaffold_contract", {}))
	if not bool(scaffold_anchor_result.get("ok", false)):
		var anchor_gate := _gate_failure(str(scaffold_anchor_result.get("error", "AI_VISUAL_SCAFFOLD_ANCHOR_MISSING")))
		anchor_gate["scaffold_anchors"] = scaffold_anchor_result
		anchor_gate["contract"] = "forge-mechanism-visual-gate-result-v1"
		anchor_gate["case_id"] = str(request.get("case_id", ""))
		anchor_gate["retry_count"] = int(manifest.get("retry_count", 0))
		anchor_gate["identity_constant"] = str(request.get("identity_constant", ""))
		anchor_gate["automatic"] = true
		anchor_gate["player_confirmation_required"] = false
		var failed_gate_path := result_directory.path_join("mechanism_visual_gate.json")
		var failed_gate_write := _write_json_atomic(failed_gate_path, anchor_gate)
		if not failed_gate_write.is_empty():
			return {"ok": false, "error": failed_gate_write}
		return {"ok": true, "gate_path": failed_gate_path, "gate_passed": false}
	var resolution := AXIS_RESOLVER.resolve_ai(asset, blueprint.affordance, blueprint.affordance_source)
	var gate: Dictionary
	var visual_rig_summary: Dictionary = {}
	if not bool(resolution.get("ok", false)) or not resolution.get("profile") is Resource:
		gate = _gate_failure(str(resolution.get("error", "AI_GEOMETRY_CONFLICT")))
		gate["axis_resolution"] = resolution
	else:
		var profile := resolution.get("profile") as Resource
		var uses_soft_visuals := str(profile.flex_topology) != "none" or str(profile.tether_topology) != "none"
		if uses_soft_visuals:
			var built := AUTOMATIC_VISUAL_RIG.build(asset, profile)
			if not bool(built.get("ok", false)):
				gate = _gate_failure(str(built.get("error", "AI_VISUAL_RIG_AUTOBUILD_FAILED")))
				gate["visual_rig_build"] = built
			else:
				asset.visual_rig = built.get("rig") as PixelWeaponVisualRig
				asset.visual_rig_source = str(built.get("source", "ai_axes_plus_alpha_path_v1"))
				asset.tether_origin = Vector2(built.get("tether_origin", asset.tip))
				visual_rig_summary = asset.visual_rig.summary()
				_write_json_atomic(result_directory.path_join("visual_rig.json"), built.get("contract", {}))
		if gate.is_empty():
			gate = READABILITY_GATE.evaluate(asset, profile, blueprint.visual_structure_brief)
		gate["axis_resolution"] = resolution
	gate["contract"] = "forge-mechanism-visual-gate-result-v1"
	gate["case_id"] = str(request.get("case_id", ""))
	gate["retry_count"] = int(manifest.get("retry_count", 0))
	gate["identity_constant"] = str(request.get("identity_constant", ""))
	gate["anchors"] = asset.anchors_dict()
	gate["scaffold_anchors"] = scaffold_anchor_result
	gate["scaffold_alpha_iou"] = _scaffold_alpha_iou(image, request_path, request)
	gate["visual_rig"] = visual_rig_summary
	gate["automatic"] = true
	gate["player_confirmation_required"] = false
	var gate_path := result_directory.path_join("mechanism_visual_gate.json")
	var gate_write := _write_json_atomic(gate_path, gate)
	if not gate_write.is_empty():
		return {"ok": false, "error": gate_write}
	return {"ok": true, "gate_path": gate_path, "gate_passed": bool(gate.get("ok", false))}


func _blueprint(case_data: Dictionary, affordance: Dictionary) -> WeaponBlueprint:
	var blueprint := WeaponBlueprint.new()
	blueprint.id = str(case_data["case_id"])
	blueprint.display_name = "匿名机制样本"
	blueprint.fantasy_summary = "同一匿名物体在不同机制轴下的结构样本。"
	blueprint.source_identity = SHARED_IDENTITY
	blueprint.player_identity_text = SHARED_IDENTITY
	blueprint.identity_confidence = 1.0
	blueprint.preserved_visual_features = ["dark wooden material", "brass fittings", "same original object identity"]
	blueprint.visual_description = SHARED_DESCRIPTION
	blueprint.behavior_family = "heavy_melee"
	blueprint.weapon_form = "anonymous_mechanism_object"
	blueprint.cadence = "slow_strike"
	blueprint.delivery = "whole_object_strike"
	blueprint.impact_mode = "body_contact"
	blueprint.effect_type = "mechanical_contact"
	blueprint.element = "normal"
	blueprint.signature_effect = "impact"
	blueprint.drawback = "recovery"
	blueprint.weight_class = "heavy" if str(affordance.get("mass_distribution", "balanced")) == "front" else "medium"
	blueprint.grip_profile = "two_hand_rear" if str(affordance.get("grip_topology", "")) == "two_hand_handle" else "rear_grip"
	blueprint.palette_hint = "dark_wood_brass"
	blueprint.silhouette_aspect = 3.2
	blueprint.silhouette_curvature = "mechanism_declared"
	blueprint.silhouette_mass_distribution = str(affordance.get("mass_distribution", "balanced"))
	blueprint.silhouette_handle_region = "rear"
	blueprint.affordance = affordance.duplicate(true)
	blueprint.affordance_source = AI_SOURCE
	blueprint.confidence = 0.95
	return blueprint


func _affordance(case_data: Dictionary) -> Dictionary:
	var result := (case_data.get("axes", {}) as Dictionary).duplicate(true)
	for flag: String in AXIS_RESOLVER.REQUIRED_FLAGS:
		result[flag] = bool((case_data.get("flags", {}) as Dictionary).get(flag, false))
	result["confidence"] = 0.95
	result["evidence_parts"] = [
		"anonymous constant identity",
		"mechanism matrix case %s" % str(case_data.get("case_id", "")),
	]
	return result


func _gate_failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"stage": "mechanism_visual_readability",
		"error": error,
		"errors": [error],
		"metrics": {},
		"automatic": true,
		"retry_required": true,
		"player_confirmation_required": false,
		"retry_prompt": "Keep the same identity; separate grip, mass, contacts, flexible body, tether, joints, and terminal in the 96px silhouette.",
	}


func _provider_prompt(brief: Dictionary) -> String:
	var requirements: Array[String] = []
	for value: Variant in brief.get("visual_requirements", []):
		requirements.append(str(value))
	return (
		SHARED_DESCRIPTION
		+ ". Preserve the attached structure exactly. "
		+ " ".join(requirements)
		+ " Surface texture and colors may change, but the handle, paths, joints, terminal, contact face, and empty background must not move, merge, or disappear."
	)


func _apply_scaffold_anchors(asset: WeaponVisualAsset, image: Image, contract_value: Variant) -> Dictionary:
	if not contract_value is Dictionary:
		return {"ok": false, "error": "AI_VISUAL_SCAFFOLD_CONTRACT_MISSING"}
	var contract := contract_value as Dictionary
	var anchors_value: Variant = contract.get("anchors", {})
	if not anchors_value is Dictionary:
		return {"ok": false, "error": "AI_VISUAL_SCAFFOLD_ANCHORS_MISSING"}
	var anchors := anchors_value as Dictionary
	var grip := _nearest_opaque(image, _vector_from_array(anchors.get("GripPrimary", [])), 12)
	var strike := _nearest_opaque(image, _vector_from_array(anchors.get("StrikePoint", [])), 12)
	if not bool(grip.get("ok", false)) or not bool(strike.get("ok", false)):
		return {
			"ok": false,
			"error": "AI_VISUAL_SCAFFOLD_ANCHOR_MISSING",
			"grip": grip,
			"strike": strike,
		}
	asset.grip_primary = _vector_from_array(grip.get("point", []))
	asset.tip = _vector_from_array(strike.get("point", []))
	asset.tether_origin = asset.tip
	if anchors.has("TetherOrigin"):
		var tether := _nearest_opaque(image, _vector_from_array(anchors.get("TetherOrigin", [])), 12)
		if bool(tether.get("ok", false)):
			asset.tether_origin = _vector_from_array(tether.get("point", []))
	asset.anchor_source = "mechanism_scaffold_local_alpha_search"
	asset.anchor_confidence = clampf(1.0 - maxf(float(grip.get("distance", 12.0)), float(strike.get("distance", 12.0))) / 24.0, 0.5, 1.0)
	return {
		"ok": true,
		"search_radius_pixels": 12,
		"grip": grip,
		"strike": strike,
		"maximum_drift_pixels": maxf(float(grip.get("distance", 0.0)), float(strike.get("distance", 0.0))),
	}


func _nearest_opaque(image: Image, desired: Vector2, radius: int) -> Dictionary:
	var nearest := Vector2(-1, -1)
	var nearest_distance := INF
	for y: int in range(maxi(0, roundi(desired.y) - radius), mini(image.get_height() - 1, roundi(desired.y) + radius) + 1):
		for x: int in range(maxi(0, roundi(desired.x) - radius), mini(image.get_width() - 1, roundi(desired.x) + radius) + 1):
			if image.get_pixel(x, y).a <= 0.10:
				continue
			var distance := Vector2(x, y).distance_to(desired)
			if distance < nearest_distance:
				nearest = Vector2(x, y)
				nearest_distance = distance
	return {
		"ok": nearest.x >= 0.0,
		"expected": [desired.x, desired.y],
		"point": [nearest.x, nearest.y],
		"distance": nearest_distance if nearest.x >= 0.0 else -1.0,
	}


func _vector_from_array(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(-1000, -1000)


func _scaffold_alpha_iou(image: Image, request_path: String, request: Dictionary) -> float:
	var scaffold_value := str(request.get("structure_scaffold", ""))
	if scaffold_value.is_empty():
		return 0.0
	var scaffold_path := request_path.get_base_dir().path_join(scaffold_value)
	var scaffold := Image.load_from_file(scaffold_path)
	if scaffold == null or scaffold.is_empty() or scaffold.get_size() != image.get_size():
		return 0.0
	var intersection := 0
	var union := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var generated_opaque := image.get_pixel(x, y).a > 0.10
			var scaffold_opaque := scaffold.get_pixel(x, y).a > 0.10
			if generated_opaque or scaffold_opaque:
				union += 1
			if generated_opaque and scaffold_opaque:
				intersection += 1
	return float(intersection) / maxf(1.0, float(union))


func _arguments() -> Dictionary:
	var result: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		result[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return result


func _absolute_path(value: String) -> String:
	var path := value.strip_edges()
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path.simplify_path() if path.is_absolute_path() else ""


func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _write_json_atomic(path: String, payload: Variant) -> String:
	if path.is_empty():
		return "MECHANISM_VISUAL_MATRIX_WRITE_PATH_EMPTY"
	var temporary := "%s.%d.tmp" % [path, Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "MECHANISM_VISUAL_MATRIX_TEMP_WRITE_FAILED"
	file.store_string(JSON.stringify(payload, "  ") + "\n")
	file.close()
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		DirAccess.remove_absolute(temporary)
		return "MECHANISM_VISUAL_MATRIX_REPLACE_FAILED"
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return "MECHANISM_VISUAL_MATRIX_ATOMIC_RENAME_FAILED"
	return ""
