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
var last_load_diagnostics: Dictionary = {}

var _memory_entries: Array[Dictionary] = []
var _memory_dependency_snapshot: Dictionary = {}
var _tracked_entry_files: Array[String] = []
var _memory_cache_ready := false
var _json_files_read := 0
var _sprite_hash_reads := 0
var _images_decoded := 0
var _visual_directories_compiled := 0


func invalidate_cache() -> void:
	_memory_entries.clear()
	_memory_dependency_snapshot.clear()
	_tracked_entry_files.clear()
	_memory_cache_ready = false
	last_load_diagnostics = {"source": "invalidated"}


func load_entries() -> Array[Dictionary]:
	var started_usec := Time.get_ticks_usec()
	if _memory_cache_ready:
		var current_snapshot := _dependency_snapshot(_tracked_entry_files)
		if current_snapshot == _memory_dependency_snapshot:
			last_load_diagnostics = {
				"source": "process_memory_cache",
				"entry_count": _memory_entries.size(),
				"json_files_read": 0,
				"sprite_hash_reads": 0,
				"images_decoded": 0,
				"visual_directories_compiled": 0,
				"elapsed_usec": Time.get_ticks_usec() - started_usec,
			}
			return _copy_entry_array(_memory_entries)
	_json_files_read = 0
	_sprite_hash_reads = 0
	_images_decoded = 0
	_visual_directories_compiled = 0
	_tracked_entry_files.clear()
	var profiles := _load_cached_profiles()
	var best_by_identity := {}
	var directory := DirAccess.open(visual_cache_root)
	if directory == null:
		return []
	directory.list_dir_begin()
	var child := directory.get_next()
	while not child.is_empty():
		if directory.current_is_dir() and not child.begins_with("."):
			var child_path := visual_cache_root.path_join(child)
			_tracked_entry_files.append(child_path.path_join("cache_record.json"))
			_tracked_entry_files.append(child_path.path_join("manifest.json"))
			_tracked_entry_files.append(child_path.path_join("processed_sprite.png"))
			var entry := _load_visual_entry(child_path, profiles)
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
	_memory_entries = _copy_entry_array(result)
	_memory_dependency_snapshot = _dependency_snapshot(_tracked_entry_files)
	_memory_cache_ready = true
	last_load_diagnostics = {
		"source": "validated_disk_rebuild",
		"entry_count": result.size(),
		"json_files_read": _json_files_read,
		"sprite_hash_reads": _sprite_hash_reads,
		"images_decoded": _images_decoded,
		"visual_directories_compiled": _visual_directories_compiled,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
	}
	return result


func _load_visual_entry(directory_path: String, cached_profiles: Dictionary) -> Dictionary:
	_visual_directories_compiled += 1
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
	_images_decoded += 1
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
		"cache_status": "validated_local_finished_art",
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
	_json_files_read += 1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _sha256_file(path: String) -> String:
	_sprite_hash_reads += 1
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


func _copy_entry_array(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in source:
		# Deep-copy Variant containers so callers cannot mutate the process cache
		# through an entry or its nested runtime profile. Godot Resource/Object
		# values (blueprint, asset, texture) intentionally remain shared references;
		# duplicating GPU-backed textures on every picker open would defeat this cache.
		result.append(entry.duplicate(true))
	return result


func _dependency_snapshot(tracked_files: Array[String]) -> Dictionary:
	var child_directories: Array[String] = []
	var directory := DirAccess.open(visual_cache_root)
	if directory != null:
		directory.list_dir_begin()
		var child := directory.get_next()
		while not child.is_empty():
			if directory.current_is_dir() and not child.begins_with("."):
				child_directories.append(child)
			child = directory.get_next()
		directory.list_dir_end()
	child_directories.sort()
	var file_stamps := {}
	var paths: Array[String] = []
	paths.append_array(profile_cache_paths)
	paths.append_array(tracked_files)
	for path: String in paths:
		var absolute_path := ProjectSettings.globalize_path(path)
		file_stamps[path] = {
			"exists": FileAccess.file_exists(absolute_path),
			"modified": int(FileAccess.get_modified_time(absolute_path)) if FileAccess.file_exists(absolute_path) else -1,
			"size": int(FileAccess.get_size(absolute_path)) if FileAccess.file_exists(absolute_path) else -1,
		}
	return {
		"visual_cache_root": visual_cache_root,
		"profile_cache_paths": profile_cache_paths.duplicate(),
		"child_directories": child_directories,
		"file_stamps": file_stamps,
	}
