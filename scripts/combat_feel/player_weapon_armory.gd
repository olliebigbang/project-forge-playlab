class_name PlayerWeaponArmory
extends RefCounted

const FIREARM_CATALOG := preload("res://scripts/combat_feel/firearm_identity_catalog.gd")
const RANGED_AXIS_RESOLVER := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const OPEN_IDENTITY_INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")

const DEFAULT_VISUAL_CACHE_ROOT := "user://playlab/fal_firearm_visual/cache_v1"
const DEFAULT_PROFILE_CACHE_PATHS := [
	"user://playlab/firearm_identity_ai/cache_v3.json",
	"user://playlab/firearm_identity_ai/cache_v2.json",
	"user://playlab/firearm_identity_ai/cache_v1.json",
]

var visual_cache_root := DEFAULT_VISUAL_CACHE_ROOT
var profile_cache_paths := DEFAULT_PROFILE_CACHE_PATHS.duplicate()


func load_entries() -> Array[Dictionary]:
	var profiles := _load_cached_profiles()
	var best_by_identity := {}
	var directory := DirAccess.open(visual_cache_root)
	if directory == null:
		return []
	directory.list_dir_begin()
	var child := directory.get_next()
	while not child.is_empty():
		if directory.current_is_dir() and not child.begins_with("."):
			var entry := _load_visual_entry(visual_cache_root.path_join(child), profiles)
			if not entry.is_empty():
				var normalized := _normalize(str(entry.get("identity", "")))
				var previous := best_by_identity.get(normalized, {}) as Dictionary
				if previous.is_empty() or int(entry.get("cached_unix_time", 0)) > int(previous.get("cached_unix_time", 0)):
					best_by_identity[normalized] = entry
		child = directory.get_next()
	directory.list_dir_end()
	var result: Array[Dictionary] = []
	for raw_entry: Variant in best_by_identity.values():
		if raw_entry is Dictionary:
			result.append(raw_entry as Dictionary)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("cached_unix_time", 0)) > int(b.get("cached_unix_time", 0))
	)
	return result


func _load_visual_entry(directory_path: String, cached_profiles: Dictionary) -> Dictionary:
	var record := _read_dictionary(directory_path.path_join("cache_record.json"))
	var manifest := _read_dictionary(directory_path.path_join("manifest.json"))
	var sprite_path := directory_path.path_join("processed_sprite.png")
	if (
		record.is_empty()
		or manifest.is_empty()
		or not FileAccess.file_exists(sprite_path)
		or str(manifest.get("status", "")) != "success"
		or not bool(manifest.get("finished_art", false))
		or not bool(manifest.get("presentable_to_player", false))
		or not bool(manifest.get("firearm_visual_gate_passed", false))
	):
		return {}
	var expected_hash := str(record.get("processed_sprite_sha256", ""))
	if expected_hash.is_empty() or expected_hash != _sha256_file(sprite_path):
		return {}
	var identity := str(record.get("identity", manifest.get("identity", ""))).strip_edges()
	var canonical_name := str(record.get("canonical_name", manifest.get("canonical_identity", identity))).strip_edges()
	if identity.is_empty():
		identity = canonical_name
	var profile := _profile_for(identity, canonical_name, cached_profiles)
	if profile.is_empty():
		return {}
	var interpreted: Dictionary = OPEN_IDENTITY_INTERPRETER.new().interpret_with_ai_firearm_profile(
		identity,
		PackedByteArray(),
		{},
		profile
	)
	if not bool(interpreted.get("ok", false)):
		return {}
	var blueprint := interpreted.get("blueprint") as WeaponBlueprint
	if blueprint == null:
		return {}
	var runtime: Dictionary = RANGED_AXIS_RESOLVER.compile(
		blueprint.affordance,
		blueprint.affordance_source
	)
	if not bool(runtime.get("ok", false)):
		return {}
	blueprint.modifiers["ranged_runtime_profile"] = runtime.duplicate(true)
	var image := Image.load_from_file(ProjectSettings.globalize_path(sprite_path))
	if image == null or image.is_empty():
		return {}
	var asset: WeaponVisualAsset = ANCHOR_RESOLVER.resolve(image, blueprint)
	if asset == null:
		return {}
	_apply_finished_art_anchors(asset, manifest)
	var modified := int(FileAccess.get_modified_time(directory_path.path_join("manifest.json")))
	return {
		"ok": true,
		"identity": identity,
		"display_name": blueprint.display_name,
		"blueprint": blueprint,
		"asset": asset,
		"ranged_runtime_profile": runtime.duplicate(true),
		"sprite_path": sprite_path,
		"cache_directory": directory_path,
		"cached_unix_time": modified,
		"source_kind": "fal_firearm_cache",
		"legacy_axis_migration": bool(profile.get("legacy_axis_migration", false)),
		"paid_api_call_used_for_selection": false,
	}


func _profile_for(identity: String, canonical_name: String, cached_profiles: Dictionary) -> Dictionary:
	for candidate: String in [identity, canonical_name]:
		var catalog := FIREARM_CATALOG.resolve_identity(candidate)
		if bool(catalog.get("ok", false)):
			return catalog
	for candidate: String in [identity, canonical_name]:
		var normalized := _normalize(candidate)
		if cached_profiles.has(normalized):
			return (cached_profiles[normalized] as Dictionary).duplicate(true)
	return {}


func _load_cached_profiles() -> Dictionary:
	var profiles := {}
	var timestamps := {}
	for cache_path: String in profile_cache_paths:
		var cache := _read_dictionary(cache_path)
		if not str(cache.get("schema", "")).begins_with("forge-firearm-identity-ai-cache-v"):
			continue
		for raw_entry: Variant in cache.get("entries", []):
			if not raw_entry is Dictionary:
				continue
			var entry := raw_entry as Dictionary
			if not entry.get("profile", {}) is Dictionary:
				continue
			var profile := _upgrade_legacy_profile(
				(entry.get("profile", {}) as Dictionary).duplicate(true)
			)
			var declaration := profile.get("declaration", {}) as Dictionary
			var source := str(declaration.get("source", profile.get("catalog_source", "")))
			if not bool(RANGED_AXIS_RESOLVER.validate_ai_declaration(declaration, source).get("ok", false)):
				continue
			var timestamp := int(entry.get("cached_unix_time", 0))
			var aliases: Array[String] = [
				str(entry.get("normalized_identity", "")),
				str(entry.get("player_identity_text", "")),
				str(profile.get("canonical_name_zh", "")),
			]
			for raw_alias: Variant in profile.get("aliases", []):
				aliases.append(str(raw_alias))
			for alias: String in aliases:
				var normalized := _normalize(alias)
				if normalized.is_empty():
					continue
				if not timestamps.has(normalized) or timestamp >= int(timestamps[normalized]):
					profiles[normalized] = profile.duplicate(true)
					timestamps[normalized] = timestamp
	return profiles


func _upgrade_legacy_profile(profile: Dictionary) -> Dictionary:
	if not profile.get("declaration", {}) is Dictionary:
		return profile
	var declaration := (profile.get("declaration", {}) as Dictionary).duplicate(true)
	var migrated := false
	if not declaration.has("recoil_recovery"):
		declaration["recoil_recovery"] = {
			"light": "quick", "medium": "balanced", "strong": "slow",
		}.get(str(declaration.get("recoil", "medium")), "balanced")
		migrated = true
	if not declaration.has("muzzle_climb"):
		declaration["muzzle_climb"] = {
			"light": "low", "medium": "medium", "strong": "high",
		}.get(str(declaration.get("recoil", "medium")), "medium")
		migrated = true
	if not declaration.has("impact_force"):
		declaration["impact_force"] = str(declaration.get("recoil", "medium"))
		migrated = true
	if not declaration.has("penetration"):
		declaration["penetration"] = {
			"short": "light", "medium": "medium", "long": "strong",
		}.get(str(declaration.get("effective_range", "medium")), "medium")
		migrated = true
	if migrated:
		declaration["source"] = "AI_LEGACY_FIREARM_AXIS_MIGRATION_V1"
		profile["declaration"] = declaration
		profile["legacy_axis_migration"] = true
	return profile


func _apply_finished_art_anchors(asset: WeaponVisualAsset, manifest: Dictionary) -> void:
	var gate := manifest.get("firearm_visual_identity_gate", {}) as Dictionary
	var anchors := gate.get("anchors", {}) as Dictionary
	if anchors.is_empty():
		return
	asset.grip_primary = _vector_from_pair(anchors.get("GripPrimary", []), asset.grip_primary)
	asset.grip_secondary = _vector_from_pair(anchors.get("GripSecondary", []), asset.grip_secondary)
	asset.muzzle = _vector_from_pair(anchors.get("Muzzle", []), asset.muzzle)
	asset.tip = _vector_from_pair(anchors.get("Tip", anchors.get("Muzzle", [])), asset.tip)
	asset.tether_origin = asset.muzzle
	asset.rear_contact = _vector_from_pair(anchors.get("RearContact", []), asset.rear_contact)
	asset.anchor_confidence = 0.92
	asset.anchor_source = "cached_firearm_finished_art_gate_v1"


func _vector_from_pair(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _sha256_file(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _normalize(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	for separator: String in [" ", "-", "_", "·", ".", "/", "\\", "（", "）", "(", ")"]:
		normalized = normalized.replace(separator, "")
	return normalized
