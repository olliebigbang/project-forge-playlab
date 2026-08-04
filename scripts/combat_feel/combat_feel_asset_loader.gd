class_name CombatFeelAssetLoader
extends RefCounted

const FIXTURE_PATH := "res://data/combat_feel/heavy_melee_fixtures.json"

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
	var image := Image.new()
	if image.load(sprite_path) != OK or image.is_empty():
		return {"ok": false, "error": "LIVE_SPRITE_INVALID"}
	var blueprint_data := _read_json(blueprint_path)
	var anchors := _read_json(anchors_path)
	if blueprint_data.is_empty() or anchors.is_empty():
		return {"ok": false, "error": "LIVE_HANDOFF_JSON_INVALID"}
	var blueprint := _blueprint_from_semantic_data(blueprint_data)
	if not behavior_supported(blueprint.behavior_family):
		return {"ok": false, "error": "CURRENT_SLICE_ONLY_SUPPORTS_HEAVY_MELEE"}
	var asset := _asset_from_image_and_anchors(image, anchors)
	return {"ok": true, "fixture": false, "fixture_id": "LIVE", "notice": "LIVE LOCAL HANDOFF", "blueprint": blueprint, "asset": asset, "prompt_zh": blueprint.player_identity_text}

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
	var mapped := {
		"id": str(payload.get("id", "live-heavy-melee")),
		"display_name": str(identity.get("display_name_zh", payload.get("display_name", "Live Forge Object"))),
		"source_identity": str(identity.get("canonical_name_zh", payload.get("source_identity", ""))),
		"player_identity_text": str(payload.get("player_identity_text", identity.get("canonical_name_zh", ""))),
		"preserved_visual_features": identity.get("required_identity_parts", payload.get("preserved_visual_features", [])),
		"behavior_family": str(combat.get("behavior_family", payload.get("behavior_family", ""))),
		"delivery": str(combat.get("delivery", payload.get("delivery", "whole_object_strike"))),
		"impact_mode": str(combat.get("impact_mode", payload.get("impact_mode", "whole_body_collision"))),
		"weight_class": str(payload.get("weight_class", "medium")),
		"grip_profile": str(payload.get("grip_profile", "two_hand_rear")),
		"silhouette_mass_distribution": str(identity.get("silhouette_hints", payload.get("silhouette_mass_distribution", "balanced"))),
	}
	return WeaponBlueprint.from_dict(mapped)

func _point(data: Dictionary, keys: Array[String], fallback: Vector2) -> Vector2:
	var source: Dictionary = data.get("corrected_anchors", data)
	for key: String in keys:
		if source.has(key):
			var value: Variant = source[key]
			if value is Array and value.size() >= 2: return Vector2(float(value[0]), float(value[1]))
			if value is Dictionary: return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback

func _read_json(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if not FileAccess.file_exists(absolute): return {}
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
