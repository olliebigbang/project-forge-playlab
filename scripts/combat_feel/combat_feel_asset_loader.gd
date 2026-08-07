class_name CombatFeelAssetLoader
extends RefCounted

const FIXTURE_PATH := "res://data/combat_feel/heavy_melee_fixtures.json"
const LIVE_INDEX_PATH := "res://data/combat_feel/live_assets/revision_a/index.json"
const RECIPE_INDEX_PATH := "res://data/combat_feel/live_assets/recipe_slice_1b/index.json"
const AFFORDANCE_PROFILE := preload("res://scripts/combat_feel/object_affordance_profile.gd")


func recipe_asset_ids() -> Array[String]:
	var ids: Array[String] = []
	var index := _read_json(RECIPE_INDEX_PATH)
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		ids.append(str(entry.get("id", "")))
	return ids


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
		return loaded
	return {"ok": false, "error": "FROZEN_LIVE_ASSET_NOT_FOUND:%s" % asset_id}

func load_open_playtest_round(round_directory: String) -> Dictionary:
	if round_directory.is_empty():
		return {"ok": false, "error": "OPEN_PLAYTEST_ROUND_PATH_REQUIRED"}
	return load_live(
		round_directory.path_join("processed_sprite.png"),
		round_directory.path_join("semantic_blueprint.json"),
		round_directory.path_join("anchors.json")
	)

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
	return asset

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

func _affordance_profile_from_dict(data: Dictionary) -> Resource:
	var handle_length := str(data.get("handle_length", ""))
	var body_length := str(data.get("body_length", ""))
	var mass_distribution := str(data.get("mass_distribution", ""))
	var contact_surface := str(data.get("contact_surface", ""))
	var rigidity := str(data.get("rigidity", ""))
	if handle_length not in ["short", "medium", "long"] \
		or body_length not in ["short", "medium", "long"] \
		or mass_distribution not in ["rear", "balanced", "front"] \
		or contact_surface not in ["point", "edge", "broad", "whole_body"] \
		or rigidity not in ["rigid", "semi_rigid", "flexible"]:
		return null
	var profile: Variant = AFFORDANCE_PROFILE.new()
	profile.handle_length = handle_length
	profile.body_length = body_length
	profile.mass_distribution = mass_distribution
	profile.contact_surface = contact_surface
	profile.rigidity = rigidity
	return profile

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
