class_name CombatFeelAssetLoader
extends RefCounted

const FIXTURE_PATH := "res://data/combat_feel/heavy_melee_fixtures.json"
const LIVE_INDEX_PATH := "res://data/combat_feel/live_assets/revision_a/index.json"
const RECIPE_INDEX_PATH := "res://data/combat_feel/live_assets/recipe_slice_1b/index.json"
const MOTION_GRAMMAR_INDEX_PATH := "res://data/combat_feel/live_assets/motion_grammar_slice_1a/index.json"
const GENERALIZATION_INDEX_PATH := "res://data/combat_feel/live_assets/motion_grammar_generalization_v1/index.json"
const AFFORDANCE_PROFILE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const ANCHOR_CALIBRATION := preload("res://scripts/data/semantic_anchor_calibration.gd")


func recipe_asset_ids() -> Array[String]:
	var ids: Array[String] = []
	var index := _read_json(RECIPE_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		ids.append(str(entry.get("id", "")))
	return ids


func motion_grammar_asset_ids() -> Array[String]:
	var ids: Array[String] = []
	var index := _read_json(MOTION_GRAMMAR_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		ids.append(str(entry.get("id", "")))
	return ids


func generalization_asset_ids() -> Array[String]:
	var ids: Array[String] = []
	var index := _read_json(GENERALIZATION_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		ids.append(str(entry.get("id", "")))
	return ids


func load_generalization_asset(asset_id: String) -> Dictionary:
	var index := _read_json(GENERALIZATION_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		if str(entry.get("id", "")) != asset_id:
			continue
		if not bool(entry.get("developer_only", false)) or bool(entry.get("normal_player_flow", true)):
			return {"ok": false, "error": "GENERALIZATION_DEVELOPER_BOUNDARY_INVALID:%s" % asset_id}
		var integrity_error := _verify_named_evidence_hashes(entry)
		if not integrity_error.is_empty():
			return {"ok": false, "error": integrity_error.replace("MOTION_GRAMMAR_", "GENERALIZATION_")}
		var qualification_error := _verify_generalization_qualification(entry)
		if not qualification_error.is_empty():
			return {"ok": false, "error": qualification_error}
		var loaded := load_live(
			str(entry.get("sprite", "")),
			str(entry.get("blueprint", "")),
			str(entry.get("anchors", ""))
		)
		if not bool(loaded.get("ok", false)):
			return loaded
		var affordance_profile: Resource = _affordance_profile_from_dict(
			_read_json(str(entry.get("affordance_profile", "")))
		)
		if affordance_profile == null:
			return {"ok": false, "error": "GENERALIZATION_AFFORDANCE_INVALID:%s" % asset_id}
		loaded["asset_id"] = asset_id
		loaded["source_kind"] = str(entry.get("source_kind", ""))
		loaded["developer_only"] = true
		loaded["normal_player_flow"] = false
		loaded["notice"] = str(index.get("notice", "MOTION GRAMMAR GENERALIZATION BLIND"))
		loaded["affordance_profile"] = affordance_profile
		return loaded
	return {"ok": false, "error": "GENERALIZATION_ASSET_NOT_FOUND:%s" % asset_id}


func load_motion_grammar_asset(asset_id: String) -> Dictionary:
	var index := _read_json(MOTION_GRAMMAR_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		if str(entry.get("id", "")) != asset_id:
			continue
		var integrity_error := _verify_named_evidence_hashes(entry)
		if not integrity_error.is_empty():
			return {"ok": false, "error": integrity_error}
		var affordance_data := _read_json(str(entry.get("affordance_profile", "")))
		var affordance_profile: Resource = _affordance_profile_from_dict(affordance_data)
		if affordance_profile == null:
			return {"ok": false, "error": "MOTION_GRAMMAR_AFFORDANCE_INVALID:%s" % asset_id}
		var recipe_source_id := str(entry.get("source_recipe_asset_id", ""))
		if not recipe_source_id.is_empty():
			var retained := load_recipe_asset(recipe_source_id)
			if not bool(retained.get("ok", false)):
				return retained
			retained["asset_id"] = asset_id
			retained["affordance_profile"] = affordance_profile
			retained["notice"] = str(index.get("notice", "MOTION GRAMMAR SLICE 1A"))
			return retained
		return _load_developer_motion_grammar_asset(entry, affordance_profile, index)
	return {"ok": false, "error": "MOTION_GRAMMAR_ASSET_NOT_FOUND:%s" % asset_id}


func _load_developer_motion_grammar_asset(entry: Dictionary, affordance_profile: Resource, index: Dictionary) -> Dictionary:
	var asset_id := str(entry.get("id", ""))
	if not bool(entry.get("developer_only", false)) or bool(entry.get("normal_player_flow", true)):
		return {"ok": false, "error": "MOTION_GRAMMAR_DEVELOPER_BOUNDARY_INVALID:%s" % asset_id}
	var manifest := _read_json(str(entry.get("manifest", "")))
	if str(manifest.get("status", "")) != "completed" \
		or not bool(manifest.get("identity_confirmed", false)) \
		or not bool(manifest.get("anchor_confirmed", false)) \
		or not bool(manifest.get("entered_training", false)):
		return {"ok": false, "error": "MOTION_GRAMMAR_SOURCE_NOT_PLAYER_CONFIRMED:%s" % asset_id}
	var override := _read_json(str(entry.get("override", "")))
	if not bool(override.get("developer_only", false)) or bool(override.get("normal_player_flow", true)):
		return {"ok": false, "error": "MOTION_GRAMMAR_OVERRIDE_BOUNDARY_INVALID:%s" % asset_id}
	var melee_intent: Dictionary = override.get("melee_intent_override", {})
	if str(melee_intent.get("behavior_family", "")) != "heavy_melee":
		return {"ok": false, "error": "MOTION_GRAMMAR_MELEE_OVERRIDE_INVALID:%s" % asset_id}
	var source_hash_error := _verify_override_source_hashes(override)
	if not source_hash_error.is_empty():
		return {"ok": false, "error": source_hash_error}
	var image := _load_png(str(entry.get("sprite", "")))
	if image == null or image.is_empty() or image.get_size() != Vector2i(96, 96) or not _has_useful_alpha(image):
		return {"ok": false, "error": "MOTION_GRAMMAR_SPRITE_INVALID:%s" % asset_id}
	var blueprint_data := _read_json(str(entry.get("blueprint", "")))
	var blueprint := _blueprint_from_semantic_data(blueprint_data)
	var original_behavior := blueprint.behavior_family
	if original_behavior != "sustained_ranged":
		return {"ok": false, "error": "MOTION_GRAMMAR_SOURCE_BEHAVIOR_CHANGED:%s" % asset_id}
	var anchor_override: Dictionary = override.get("anchor_override", {})
	var asset := _asset_from_image_and_anchors(image, anchor_override)
	if asset == null or asset.rear_contact == asset.grip_primary:
		return {"ok": false, "error": "MOTION_GRAMMAR_REAR_CONTACT_INVALID:%s" % asset_id}
	blueprint.behavior_family = "heavy_melee"
	blueprint.delivery = "whole_object_strike"
	blueprint.impact_mode = "whole_body_collision"
	blueprint.grip_profile = str(anchor_override.get("grip_profile", blueprint.grip_profile))
	blueprint.silhouette_aspect = float(maxi(asset.opaque_bounds.size.x, asset.opaque_bounds.size.y)) / maxf(1.0, float(mini(asset.opaque_bounds.size.x, asset.opaque_bounds.size.y)))
	return {
		"ok": true,
		"fixture": false,
		"developer_only": true,
		"normal_player_flow": false,
		"asset_id": asset_id,
		"source_round_id": str(entry.get("source_round_id", "")),
		"source_behavior_family": original_behavior,
		"notice": str(index.get("notice", "MOTION GRAMMAR SLICE 1A")),
		"blueprint": blueprint,
		"asset": asset,
		"affordance_profile": affordance_profile,
		"prompt_zh": blueprint.player_identity_text,
	}


func load_recipe_asset(asset_id: String) -> Dictionary:
	var index := _read_json(RECIPE_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		if str(entry.get("id", "")) != asset_id:
			continue
		var integrity_error := _verify_recipe_entry_hashes(entry)
		if not integrity_error.is_empty():
			return {"ok": false, "error": integrity_error}
		var manifest := _read_json(str(entry.get("manifest", "")))
		if str(manifest.get("status", "")) != "completed" \
			or not bool(manifest.get("identity_confirmed", false)) \
			or not bool(manifest.get("anchor_confirmed", false)) \
			or not bool(manifest.get("entered_training", false)):
			return {"ok": false, "error": "RECIPE_ASSET_NOT_PLAYER_CONFIRMED:%s" % asset_id}
		var loaded := load_live(
			str(entry.get("sprite", "")),
			str(entry.get("blueprint", "")),
			str(entry.get("anchors", ""))
		)
		if not bool(loaded.get("ok", false)):
			return loaded
		var affordance_data := _read_json(str(entry.get("affordance_profile", "")))
		var affordance_profile: Resource = _affordance_profile_from_dict(affordance_data)
		if affordance_profile == null:
			return {"ok": false, "error": "RECIPE_AFFORDANCE_PROFILE_INVALID:%s" % asset_id}
		loaded["asset_id"] = asset_id
		loaded["source_kind"] = str(entry.get("source_kind", "frozen_open_playtest"))
		loaded["source_round_id"] = str(entry.get("source_round_id", ""))
		loaded["notice"] = str(index.get("notice", "FROZEN PLAYER-CONFIRMED OPEN PLAYTEST RESULT"))
		loaded["affordance_profile"] = affordance_profile
		return loaded
	return {"ok": false, "error": "RECIPE_ASSET_NOT_FOUND:%s" % asset_id}

func load_default_live() -> Dictionary:
	var index := _read_json(LIVE_INDEX_PATH)
	var asset_id := str(index.get("default_asset_id", ""))
	if asset_id.is_empty():
		return {"ok": false, "error": "LIVE_DEFAULT_ASSET_NOT_CONFIGURED"}
	return load_frozen_live(asset_id)

func frozen_live_ids() -> Array[String]:
	var ids: Array[String] = []
	var index := _read_json(LIVE_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		ids.append(str(entry.get("id", "")))
	return ids

func load_frozen_live(asset_id: String) -> Dictionary:
	var index := _read_json(LIVE_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		if str(entry.get("id", "")) != asset_id:
			continue
		var integrity_error := _verify_entry_hashes(entry)
		if not integrity_error.is_empty():
			return {"ok": false, "error": integrity_error}
		var loaded := load_live(
			str(entry.get("sprite", "")),
			str(entry.get("blueprint", "")),
			str(entry.get("anchors", ""))
		)
		if not bool(loaded.get("ok", false)):
			return loaded
		loaded["asset_id"] = asset_id
		loaded["fixture_id"] = asset_id
		loaded["source_kind"] = str(entry.get("source_kind", "frozen_live"))
		loaded["source_run_id"] = str(entry.get("source_run_id", ""))
		loaded["notice"] = str(index.get("notice", "FROZEN REAL LIVE FORGE RESULT"))
		var affordance_profile := _affordance_profile_from_dict(_read_json(str(entry.get("affordance_profile", ""))))
		if affordance_profile == null:
			return {"ok": false, "error": "LIVE_AFFORDANCE_PROFILE_INVALID:%s" % asset_id}
		loaded["affordance_profile"] = affordance_profile
		return loaded
	return {"ok": false, "error": "FROZEN_LIVE_ASSET_NOT_FOUND:%s" % asset_id}

func load_open_playtest_round(round_directory: String, require_affordance_grammar: bool = false) -> Dictionary:
	if round_directory.is_empty():
		return {"ok": false, "error": "OPEN_PLAYTEST_ROUND_PATH_REQUIRED"}
	var loaded := load_live(
		round_directory.path_join("processed_sprite.png"),
		round_directory.path_join("semantic_blueprint.json"),
		round_directory.path_join("anchors.json")
	)
	if not bool(loaded.get("ok", false)):
		return loaded
	var affordance_path := round_directory.path_join("object_affordance_profile.json")
	if not FileAccess.file_exists(affordance_path):
		return {"ok": false, "error": "AFFORDANCE_NOT_READY"} if require_affordance_grammar else loaded
	var affordance_profile := _affordance_profile_from_dict(_read_json(affordance_path))
	if affordance_profile == null:
		return {"ok": false, "error": "AFFORDANCE_CONTRACT_INVALID"}
	loaded["affordance_profile"] = affordance_profile
	return loaded

func load_fixture(fixture_id: String) -> Dictionary:
	var data := _read_json(FIXTURE_PATH)
	for value: Variant in data.get("fixtures", []):
		var fixture: Dictionary = value
		if str(fixture.get("id", "")) == fixture_id:
			var blueprint: WeaponBlueprint = WeaponBlueprint.from_dict(fixture.get("blueprint", {}))
			if blueprint.behavior_family != "heavy_melee":
				return {"ok": false, "error": "NON_HEAVY_MELEE_FIXTURE_REJECTED"}
			return {
				"ok": true, "fixture": true, "fixture_id": fixture_id,
				"notice": str(data.get("notice", "DEVELOPER FIXTURE")),
				"blueprint": blueprint, "asset": _render_fixture(fixture),
				"prompt_zh": str(fixture.get("prompt_zh", "")),
			}
	return {"ok": false, "error": "FIXTURE_NOT_FOUND:%s" % fixture_id}

func load_live(sprite_path: String, blueprint_path: String, anchors_path: String) -> Dictionary:
	if sprite_path.is_empty() or blueprint_path.is_empty() or anchors_path.is_empty():
		return {"ok": false, "error": "LIVE_HANDOFF_PATHS_REQUIRED"}
	var image := _load_png(sprite_path)
	if image == null or image.is_empty():
		return {"ok": false, "error": "LIVE_SPRITE_INVALID"}
	if image.get_size() != Vector2i(96, 96):
		return {"ok": false, "error": "LIVE_SPRITE_MUST_BE_96X96"}
	if not _has_useful_alpha(image):
		return {"ok": false, "error": "LIVE_SPRITE_ALPHA_INVALID"}
	var blueprint_data := _read_json(blueprint_path)
	var anchors := _read_json(anchors_path)
	if blueprint_data.is_empty() or anchors.is_empty():
		return {"ok": false, "error": "LIVE_HANDOFF_JSON_INVALID"}
	var blueprint := _blueprint_from_semantic_data(blueprint_data)
	if not behavior_supported(blueprint.behavior_family):
		return {"ok": false, "error": "CURRENT_SLICE_ONLY_SUPPORTS_HEAVY_MELEE"}
	var asset := _asset_from_image_and_anchors(image, anchors)
	blueprint.grip_profile = str(anchors.get("grip_profile", blueprint.grip_profile))
	blueprint.silhouette_aspect = float(maxi(asset.opaque_bounds.size.x, asset.opaque_bounds.size.y)) / maxf(1.0, float(mini(asset.opaque_bounds.size.x, asset.opaque_bounds.size.y)))
	return {"ok": true, "fixture": false, "fixture_id": "LIVE", "asset_id": "LIVE", "notice": "LIVE OPEN PLAYTEST HANDOFF", "blueprint": blueprint, "asset": asset, "prompt_zh": blueprint.player_identity_text}

static func behavior_supported(family: String) -> bool:
	return family == "heavy_melee"

func _render_fixture(fixture: Dictionary) -> WeaponVisualAsset:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for value: Variant in fixture.get("shapes", []):
		var shape: Dictionary = value
		var color: Color = Color(str(shape.get("color", "ffffff")))
		if str(shape.get("type", "")) == "rect":
			var rect: Array = shape.get("rect", [0, 0, 1, 1])
			image.fill_rect(Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])), color)
		elif str(shape.get("type", "")) == "circle":
			var center_data: Array = shape.get("center", [48, 48])
			var center := Vector2i(int(center_data[0]), int(center_data[1]))
			var radius: int = int(shape.get("radius", 1))
			for y: int in range(center.y - radius, center.y + radius + 1):
				for x: int in range(center.x - radius, center.x + radius + 1):
					if x >= 0 and y >= 0 and x < 96 and y < 96 and Vector2i(x, y).distance_squared_to(center) <= radius * radius:
						image.set_pixel(x, y, color)
	var anchor_data: Dictionary = fixture.get("anchors", {})
	return _asset_from_image_and_anchors(image, anchor_data)

func _asset_from_image_and_anchors(image: Image, anchors: Dictionary) -> WeaponVisualAsset:
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.texture = ImageTexture.create_from_image(image)
	asset.canvas_size = image.get_size()
	asset.opaque_bounds = image.get_used_rect()
	asset.grip_primary = _point(anchors, ["GripPrimary", "grip_primary"], Vector2(18, 48))
	asset.grip_secondary = _point(anchors, ["GripSecondary", "grip_secondary"], asset.grip_primary)
	asset.tip = _point(anchors, ["StrikePoint", "Tip", "strike_point", "tip"], Vector2(asset.opaque_bounds.end.x, asset.opaque_bounds.get_center().y))
	asset.muzzle = _point(anchors, ["EffectOrigin", "Muzzle", "effect_origin", "muzzle"], asset.tip)
	asset.spin_pivot = _point(anchors, ["SpinPivot", "spin_pivot"], Vector2(asset.opaque_bounds.get_center()))
	asset.anchor_confidence = 1.0
	asset.anchor_source = "developer_fixture" if anchors.has("strike_point") else "live_player_confirmed"
	asset.rear_contact = asset.grip_primary
	return _normalize_asset_orientation(asset, anchors)


func _normalize_asset_orientation(asset: WeaponVisualAsset, anchors: Dictionary) -> WeaponVisualAsset:
	var required_values: Array = anchors.get("required_anchor_types", [])
	if asset == null or not required_values.has("GripPrimary"):
		return asset
	var action_type := "EffectOrigin" if required_values.has("EffectOrigin") else "StrikePoint"
	if not required_values.has(action_type):
		return asset
	var calibration: Variant = ANCHOR_CALIBRATION.new()
	calibration.asset = asset
	calibration.behavior_family = str(anchors.get("behavior_family", ""))
	calibration.grip_profile = str(anchors.get("grip_profile", ""))
	for value: Variant in required_values:
		calibration.required_anchor_types.append(str(value))
	calibration.auto_anchors = _points_from_json(anchors.get("auto_anchors", {}))
	calibration.corrected_anchors = _points_from_json(anchors.get("corrected_anchors", {}))
	calibration.auto_confidence = (anchors.get("auto_confidence", {}) as Dictionary).duplicate(true)
	calibration.confidence = (anchors.get("confidence", {}) as Dictionary).duplicate(true)
	var normalized: WeaponVisualAsset = calibration.build_asset_copy()
	if normalized == null:
		return asset
	normalized.anchor_source = asset.anchor_source
	normalized.anchor_confidence = asset.anchor_confidence
	if normalized.tip != normalized.grip_primary:
		normalized.muzzle = normalized.tip
	var source: Dictionary = anchors.get("corrected_anchors", anchors)
	if source.has("RearContact") or source.has("rear_contact"):
		var rear_raw := _point(anchors, ["RearContact", "rear_contact"], asset.grip_primary)
		normalized.rear_contact = _transform_point_x(rear_raw, normalized.orientation_flipped, normalized.canvas_size.x)
	else:
		normalized.rear_contact = normalized.grip_primary
	return normalized


func _points_from_json(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for key: Variant in (value as Dictionary).keys():
		var point_value: Variant = (value as Dictionary)[key]
		if point_value is Array and point_value.size() >= 2:
			result[str(key)] = Vector2(float(point_value[0]), float(point_value[1]))
		elif point_value is Dictionary:
			result[str(key)] = Vector2(float(point_value.get("x", 0.0)), float(point_value.get("y", 0.0)))
	return result


func _transform_point_x(point: Vector2, flip_x: bool, width: int) -> Vector2:
	return Vector2(float(width - 1) - point.x, point.y) if flip_x else point

func _blueprint_from_semantic_data(data: Dictionary) -> WeaponBlueprint:
	var payload := data
	for key: String in ["compiled", "blueprint", "forge_semantic_blueprint", "result"]:
		if payload.has(key) and payload[key] is Dictionary: payload = payload[key]
	var identity: Dictionary = payload.get("identity", {})
	var combat: Dictionary = payload.get("combat", {})
	var cadence_hint := str(combat.get("cadence_hint", payload.get("cadence", "")))
	var drawback := str(combat.get("drawback", payload.get("drawback", "recovery")))
	var mapped := {
		"id": str(payload.get("id", "live-heavy-melee")),
		"display_name": str(identity.get("display_name_zh", payload.get("display_name", "Live Forge Object"))),
		"source_identity": str(identity.get("canonical_name_zh", identity.get("name_zh", payload.get("source_identity", "")))),
		"player_identity_text": str(payload.get("player_identity_text", identity.get("canonical_name_zh", identity.get("name_zh", "")))),
		"identity_confidence": float(payload.get("confidence", 0.0)),
		"preserved_visual_features": identity.get("required_identity_parts", payload.get("preserved_visual_features", [])),
		"visual_description": str(payload.get("visual_description", payload.get("visual", {}).get("prompt_en", ""))),
		"behavior_family": str(combat.get("behavior_family", payload.get("behavior_family", ""))),
		"delivery": str(combat.get("delivery", payload.get("delivery", "whole_object_strike"))),
		"impact_mode": str(combat.get("impact_mode", payload.get("impact_mode", "whole_body_collision"))),
		"cadence": cadence_hint,
		"drawback": drawback,
		"effect_type": str(combat.get("effect_type", payload.get("effect_type", "normal"))),
		"weight_class": _semantic_weight_class(cadence_hint, drawback, payload),
		"grip_profile": str(payload.get("grip_profile", "two_hand_rear")),
		"silhouette_mass_distribution": str(payload.get("silhouette_mass_distribution", "balanced")),
		"confidence": float(payload.get("confidence", 1.0)),
	}
	return WeaponBlueprint.from_dict(mapped)

func _semantic_weight_class(cadence_hint: String, drawback: String, payload: Dictionary) -> String:
	var explicit := str(payload.get("weight_class", ""))
	if explicit in WeaponBlueprint.WEIGHT_CLASSES:
		return explicit
	if cadence_hint == "slow_heavy" or drawback in ["slow_movement", "slow_startup"]:
		return "heavy"
	return "medium"

func _verify_entry_hashes(entry: Dictionary) -> String:
	var expected: Dictionary = entry.get("sha256", {})
	var paths := {
		"processed_sprite.png": str(entry.get("sprite", "")),
		"semantic_blueprint.json": str(entry.get("blueprint", "")),
		"anchors.json": str(entry.get("anchors", "")),
		"object_affordance_profile.json": str(entry.get("affordance_profile", "")),
		"result_manifest.json": str(entry.get("manifest", "")),
	}
	for filename: String in paths:
		if not expected.has(filename):
			return "LIVE_EVIDENCE_HASH_MISSING:%s" % filename
		var path: String = paths[filename]
		if not FileAccess.file_exists(path):
			return "LIVE_EVIDENCE_FILE_MISSING:%s" % filename
		if _sha256_file(path) != str(expected[filename]).to_lower():
			return "LIVE_EVIDENCE_HASH_MISMATCH:%s" % filename
	return ""

func _verify_recipe_entry_hashes(entry: Dictionary) -> String:
	var expected: Dictionary = entry.get("sha256", {})
	var paths := {
		"processed_sprite.png": str(entry.get("sprite", "")),
		"semantic_blueprint.json": str(entry.get("blueprint", "")),
		"anchors.json": str(entry.get("anchors", "")),
		"object_affordance_profile.json": str(entry.get("affordance_profile", "")),
		"open_playtest_round.json": str(entry.get("manifest", "")),
	}
	for filename: String in paths:
		if not expected.has(filename):
			return "RECIPE_EVIDENCE_HASH_MISSING:%s" % filename
		var path: String = paths[filename]
		if not FileAccess.file_exists(path):
			return "RECIPE_EVIDENCE_FILE_MISSING:%s" % filename
		if _sha256_file(path) != str(expected[filename]).to_lower():
			return "RECIPE_EVIDENCE_HASH_MISMATCH:%s" % filename
	return ""


func _verify_named_evidence_hashes(entry: Dictionary) -> String:
	var paths: Dictionary = entry.get("evidence_files", {})
	var expected: Dictionary = entry.get("sha256", {})
	if paths.is_empty() or expected.is_empty():
		return "MOTION_GRAMMAR_EVIDENCE_HASHES_MISSING"
	for filename: Variant in paths.keys():
		var key := str(filename)
		if not expected.has(key):
			return "MOTION_GRAMMAR_EVIDENCE_HASH_MISSING:%s" % key
		var path := str(paths[key])
		if not FileAccess.file_exists(path):
			return "MOTION_GRAMMAR_EVIDENCE_FILE_MISSING:%s" % key
		if _sha256_file(path) != str(expected[key]).to_lower():
			return "MOTION_GRAMMAR_EVIDENCE_HASH_MISMATCH:%s" % key
	return ""


func _verify_override_source_hashes(override: Dictionary) -> String:
	var source_files: Dictionary = override.get("source_files", {})
	var expected: Dictionary = override.get("source_sha256", {})
	var bindings := {
		"processed_sprite.png": str(source_files.get("processed_sprite", "")),
		"semantic_blueprint.json": str(source_files.get("semantic_blueprint", "")),
		"anchors.json": str(source_files.get("anchors", "")),
	}
	for filename: String in bindings:
		var path: String = bindings[filename]
		if path.is_empty() or not expected.has(filename):
			return "MOTION_GRAMMAR_OVERRIDE_HASH_MISSING:%s" % filename
		if not FileAccess.file_exists(path):
			return "MOTION_GRAMMAR_OVERRIDE_FILE_MISSING:%s" % filename
		if _sha256_file(path) != str(expected[filename]).to_lower():
			return "MOTION_GRAMMAR_OVERRIDE_HASH_MISMATCH:%s" % filename
	return ""


func _verify_generalization_qualification(entry: Dictionary) -> String:
	var mode := str(entry.get("qualification_mode", ""))
	var manifest := _read_json(str(entry.get("manifest", "")))
	match mode:
		"player_confirmed_open_playtest":
			var identity_review := _read_json(str(entry.get("identity_review", "")))
			if str(manifest.get("status", "")) != "completed" \
				or not bool(manifest.get("identity_confirmed", false)) \
				or not bool(manifest.get("anchor_confirmed", false)) \
				or not bool(manifest.get("entered_training", false)) \
				or not bool(identity_review.get("identity_confirmed", false)):
				return "GENERALIZATION_SOURCE_NOT_PLAYER_CONFIRMED"
		"developer_identity_binding":
			if str(manifest.get("status", "")) != "eligible_for_developer_blind_test" \
				or not bool(manifest.get("developer_only", false)) \
				or bool(manifest.get("normal_player_flow", true)) \
				or int(manifest.get("model_calls_performed_for_binding", -1)) != 0 \
				or bool(manifest.get("case_specific_recipe", true)):
				return "GENERALIZATION_BINDING_BOUNDARY_INVALID"
		_:
			return "GENERALIZATION_QUALIFICATION_MODE_INVALID"
	return ""

func _affordance_profile_from_dict(data: Dictionary) -> Resource:
	var required_fields := [
		"handle_length", "body_length", "grip_topology", "mass_distribution",
		"contact_surface", "secondary_contact_surface", "rigidity", "has_point",
		"has_edge", "has_broad_face", "has_barrel", "has_stock", "confidence",
		"evidence_parts",
	]
	for field: String in required_fields:
		if not data.has(field):
			return null
	var handle_length := str(data.get("handle_length", ""))
	var body_length := str(data.get("body_length", ""))
	var grip_topology := str(data.get("grip_topology", ""))
	var mass_distribution := str(data.get("mass_distribution", ""))
	var contact_surface := str(data.get("contact_surface", ""))
	var secondary_contact_surface := str(data.get("secondary_contact_surface", ""))
	var rigidity := str(data.get("rigidity", ""))
	var confidence := float(data.get("confidence", -1.0))
	var evidence_value: Variant = data.get("evidence_parts", [])
	if handle_length not in ["none", "short", "medium", "long"] \
		or body_length not in ["short", "medium", "long"] \
		or grip_topology not in ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"] \
		or mass_distribution not in ["rear", "balanced", "front"] \
		or contact_surface not in ["point", "edge", "broad", "whole_body"] \
		or secondary_contact_surface not in ["none", "point", "edge", "broad", "whole_body"] \
		or rigidity not in ["rigid", "semi_rigid", "flexible"] \
		or confidence < 0.65 or confidence > 1.0 \
		or not evidence_value is Array or (evidence_value as Array).is_empty():
		return null
	var profile: Variant = AFFORDANCE_PROFILE.new()
	profile.handle_length = handle_length
	profile.body_length = body_length
	profile.grip_topology = grip_topology
	profile.mass_distribution = mass_distribution
	profile.contact_surface = contact_surface
	profile.secondary_contact_surface = secondary_contact_surface
	profile.rigidity = rigidity
	profile.has_point = bool(data.get("has_point"))
	profile.has_edge = bool(data.get("has_edge"))
	profile.has_broad_face = bool(data.get("has_broad_face"))
	profile.has_barrel = bool(data.get("has_barrel"))
	profile.has_stock = bool(data.get("has_stock"))
	profile.confidence = confidence
	profile.evidence_parts = PackedStringArray(evidence_value)
	# Optional so pre-v1.3 profiles keep loading unchanged; absent stays 0.0.
	profile.real_length_cm = float(data.get("real_length_cm", 0.0))
	# Same for mass and pre-v1.4 profiles.
	profile.real_mass_kg = float(data.get("real_mass_kg", 0.0))
	return null if not profile.validation_errors().is_empty() else profile

## Developer-only: read an affordance profile from an arbitrary path, outside the index
## and its hash checks. Exists so a contract change can be A/B playtested against the
## frozen assets without editing them -- those are SHA-256 pinned and must not move.
## No normal load path calls this; the caller is expected to mark the run as unverified.
func load_affordance_override(path: String) -> Resource:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	return _affordance_profile_from_dict(_read_json(path))


func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(mini(65536, file.get_length() - file.get_position())))
	file.close()
	return context.finish().hex_encode()

func _has_useful_alpha(image: Image) -> bool:
	var transparent := 0
	var opaque := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			if alpha <= 0.02: transparent += 1
			elif alpha >= 0.25: opaque += 1
	return transparent > 0 and opaque >= 32

func _point(data: Dictionary, keys: Array[String], fallback: Vector2) -> Vector2:
	var source: Dictionary = data.get("corrected_anchors", data)
	for key: String in keys:
		if source.has(key):
			var value: Variant = source[key]
			if value is Array and value.size() >= 2: return Vector2(float(value[0]), float(value[1]))
			if value is Dictionary: return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path): return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty(): return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK: return null
	return image
