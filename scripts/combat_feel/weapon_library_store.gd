class_name WeaponLibraryStore
extends RefCounted

const SCHEMA := "forge-complete-weapon-library-v1"
const ROOT := "user://playlab/weapon_library/v1"
const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
const AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const RANGED := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const RIG := preload("res://scripts/data/pixel_weapon_visual_rig.gd")
const ANCHORS: Array[String] = ["grip_primary", "grip_secondary", "muzzle", "tip", "tether_origin", "spin_pivot", "rear_contact"]

var root_path := ROOT
var diagnostics: Array[Dictionary] = []
var locked_reward_identities: Array[String] = []


func _init() -> void:
	if OS.has_environment("FORGE_WEAPON_LIBRARY_ROOT"):
		root_path = OS.get_environment("FORGE_WEAPON_LIBRARY_ROOT")


func save_entry(entry: Dictionary, completion_reward: bool = false) -> Dictionary:
	var validation: Dictionary = DIRECTOR.new()._validate_weapon_entry(entry)
	if not bool(validation.get("ok", false)):
		return validation
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	var asset := entry.get("asset") as WeaponVisualAsset
	if not bool(entry.get("accepted_visual", false)) or bool(blueprint.modifiers.get("local_sample_only", false)):
		return _failure("WEAPON_LIBRARY_ACCEPTED_VISUAL_REQUIRED")
	if asset.source_image == null or asset.source_image.is_empty():
		return _failure("WEAPON_LIBRARY_IMAGE_MISSING")
	var asset_data := {
		"canvas_size": asset.canvas_size, "opaque_bounds": asset.opaque_bounds,
		"anchor_confidence": asset.anchor_confidence, "anchor_source": asset.anchor_source,
		"orientation_flipped": asset.orientation_flipped, "orientation_source": asset.orientation_source,
		"visual_rig_source": asset.visual_rig_source, "rig_contract": _rig_contract(asset.visual_rig),
	}
	for name: String in ANCHORS:
		asset_data[name] = asset.get(name)
	var profile: Resource = entry.get("affordance_profile") as Resource
	var payload := {
		"schema": SCHEMA, "blueprint": blueprint.to_dict(), "asset": asset_data,
		"affordance_profile": profile.to_dict() if profile != null else {},
		"ranged_runtime_profile": (entry.get("ranged_runtime_profile", {}) as Dictionary).duplicate(true),
		"identity": str(entry.get("identity", blueprint.player_identity_text)),
		"visual_evidence": (entry.get("visual_evidence", {}) as Dictionary).duplicate(true),
		"completion_reward": completion_reward,
	}
	if not _data_only(payload):
		return _failure("WEAPON_LIBRARY_NON_DATA_PAYLOAD")
	# Typed Variant bytes preserve vectors and integer/float fields exactly. The
	# reader never allows Object deserialization; no script/resource paths execute.
	var data := var_to_bytes(payload)
	var png := asset.source_image.save_png_to_buffer()
	var key := (_hash(data) + _hash(png)).sha256_text()
	var target := root_path.path_join("weapons").path_join(key)
	if DirAccess.dir_exists_absolute(target):
		var existing := load_entry(key)
		return {"ok": true, "library_key": key, "entry": existing} if bool(existing.get("ok", false)) else existing
	var pending := root_path.path_join("weapons").path_join(".pending_%s_%d" % [key, Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(pending) != OK:
		return _failure("WEAPON_LIBRARY_DIRECTORY_FAILED")
	if _write_bytes(pending.path_join("weapon.dat"), data) != OK or _write_bytes(pending.path_join("sprite.png"), png) != OK:
		return _failure("WEAPON_LIBRARY_WRITE_FAILED")
	var manifest := {"schema": SCHEMA, "key": key, "data_sha256": _hash(data), "sprite_sha256": _hash(png), "saved_unix_time": int(Time.get_unix_time_from_system())}
	if _write_bytes(pending.path_join("manifest.json"), JSON.stringify(manifest).to_utf8_buffer()) != OK:
		return _failure("WEAPON_LIBRARY_MANIFEST_FAILED")
	if _publish_path(pending, target) != OK:
		return _failure("WEAPON_LIBRARY_ATOMIC_PUBLISH_FAILED")
	var published := load_entry(key)
	return {"ok": true, "library_key": key, "entry": published} if bool(published.get("ok", false)) else published


func load_entry(key: String) -> Dictionary:
	if key.length() != 64 or not key.is_valid_hex_number(false):
		return _failure("WEAPON_LIBRARY_KEY_INVALID")
	var directory := root_path.path_join("weapons").path_join(key)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json"))) if FileAccess.file_exists(directory.path_join("manifest.json")) else null
	if not manifest is Dictionary or str(manifest.get("schema", "")) != SCHEMA or str(manifest.get("key", "")) != key:
		return _failure("WEAPON_LIBRARY_MANIFEST_INVALID")
	if not FileAccess.file_exists(directory.path_join("weapon.dat")) or not FileAccess.file_exists(directory.path_join("sprite.png")):
		return _failure("WEAPON_LIBRARY_PACKAGE_INCOMPLETE")
	var data := FileAccess.get_file_as_bytes(directory.path_join("weapon.dat"))
	var png := FileAccess.get_file_as_bytes(directory.path_join("sprite.png"))
	if _hash(data) != str(manifest.get("data_sha256", "")) or _hash(png) != str(manifest.get("sprite_sha256", "")):
		return _failure("WEAPON_LIBRARY_CONTENT_HASH_MISMATCH")
	if (_hash(data) + _hash(png)).sha256_text() != key:
		return _failure("WEAPON_LIBRARY_PACKAGE_KEY_MISMATCH")
	var value: Variant = bytes_to_var(data)
	if not value is Dictionary or not _data_only(value) or str(value.get("schema", "")) != SCHEMA:
		return _failure("WEAPON_LIBRARY_PAYLOAD_INVALID")
	var payload := value as Dictionary
	if not payload.get("blueprint") is Dictionary or not payload.get("asset") is Dictionary:
		return _failure("WEAPON_LIBRARY_PAYLOAD_FIELDS_INVALID")
	var blueprint := WeaponBlueprint.from_dict(payload["blueprint"])
	var image := Image.new()
	if image.load_png_from_buffer(png) != OK or image.is_empty():
		return _failure("WEAPON_LIBRARY_IMAGE_INVALID")
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.texture = ImageTexture.create_from_image(image)
	var stored := payload["asset"] as Dictionary
	for name: String in ANCHORS + ["canvas_size", "opaque_bounds", "anchor_confidence", "anchor_source", "orientation_flipped", "orientation_source", "visual_rig_source"]:
		if not stored.has(name):
			return _failure("WEAPON_LIBRARY_ANCHORS_INCOMPLETE")
		asset.set(name, stored[name])
	if asset.canvas_size != image.get_size():
		return _failure("WEAPON_LIBRARY_CANVAS_MISMATCH")
	var rig_contract := stored.get("rig_contract", {}) as Dictionary
	if not rig_contract.is_empty():
		# The saved image and contract are already in the final facing orientation.
		asset.visual_rig = RIG.from_dict(rig_contract, image, false)
		if not asset.visual_rig.validation_errors().is_empty():
			return _failure("WEAPON_LIBRARY_RIG_INVALID")
	var profile: Resource
	if blueprint.behavior_family == "heavy_melee":
		var resolved := AXES.resolve_ai(asset, blueprint.affordance, blueprint.affordance_source)
		if not bool(resolved.get("ok", false)):
			return _failure("WEAPON_LIBRARY_MECHANISM_REVALIDATION_FAILED")
		profile = resolved.get("profile") as Resource
		if profile == null or profile.to_dict() != payload.get("affordance_profile", {}):
			return _failure("WEAPON_LIBRARY_MECHANISM_CHANGED")
	var entry := {
		"ok": true, "library_key": key, "identity": str(payload.get("identity", "")),
		"display_name": blueprint.display_name, "blueprint": blueprint, "asset": asset,
		"affordance_profile": profile, "ranged_runtime_profile": payload.get("ranged_runtime_profile", {}),
		"accepted_visual": true, "visual_evidence": payload.get("visual_evidence", {}),
		"completion_reward": bool(payload.get("completion_reward", false)),
		"source_kind": "complete_weapon_library", "paid_api_call_used_for_selection": false,
		"cached_unix_time": int(manifest.get("saved_unix_time", 0)), "sprite_path": directory.path_join("sprite.png"),
	}
	if str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
		var cached_ranged := entry.ranged_runtime_profile as Dictionary
		if not cached_ranged.has("muzzle_climb_cap_degrees"):
			# Runtime-only migration: the hashed package and player save stay byte-for-
			# byte untouched. Validation sees a freshly compiled complete mechanism
			# card instead of discarding an otherwise valid historical firearm.
			var migrated_ranged := RANGED.compile(blueprint.affordance, blueprint.affordance_source)
			if not bool(migrated_ranged.get("ok", false)): return migrated_ranged
			blueprint.modifiers["ranged_runtime_profile"] = migrated_ranged.duplicate(true)
			entry["ranged_runtime_profile"] = migrated_ranged
	var validation: Dictionary = DIRECTOR.new()._validate_weapon_entry(entry)
	return entry if bool(validation.get("ok", false)) else validation


func load_entries() -> Array[Dictionary]:
	diagnostics.clear()
	locked_reward_identities.clear()
	var entries: Array[Dictionary] = []
	var state := read_session()
	if not DirAccess.dir_exists_absolute(root_path.path_join("weapons")):
		return entries
	for key: String in DirAccess.get_directories_at(root_path.path_join("weapons")):
		if key.begins_with("."):
			continue
		var entry := load_entry(key)
		if not bool(entry.get("ok", false)):
			diagnostics.append({"key": key, "error": entry.get("error", "INVALID")})
			continue
		if bool(entry.get("completion_reward", false)) and key not in state.get("unlocked_reward_keys", []):
			# FAL also writes a legacy firearm cache. Do not let that second
			# entrance expose a reward before the complete package is unlocked.
			locked_reward_identities.append(str(entry.get("identity", "")))
			locked_reward_identities.append(str(entry.get("display_name", "")))
			locked_reward_identities.append(str(entry.blueprint.player_identity_text))
			continue
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("cached_unix_time", 0)) > int(b.get("cached_unix_time", 0)))
	return entries


func read_session() -> Dictionary:
	if not DirAccess.dir_exists_absolute(root_path.path_join("sessions")):
		return {"equipped_key": "", "pending_reward_key": "", "unlocked_reward_keys": [], "last_run": {}}
	var names := DirAccess.get_files_at(root_path.path_join("sessions"))
	names.sort()
	names.reverse()
	for name: String in names:
		if not name.ends_with(".json"):
			continue
		var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(root_path.path_join("sessions").path_join(name)))
		if not record is Dictionary or str(record.get("schema", "")) != SCHEMA:
			continue
		var data := Marshalls.base64_to_raw(str(record.get("data", "")))
		if _hash(data) != str(record.get("sha256", "")):
			continue
		var state: Variant = bytes_to_var(data)
		if state is Dictionary and _data_only(state):
			return state
	return {"equipped_key": "", "pending_reward_key": "", "unlocked_reward_keys": [], "last_run": {}}


func update_session(changes: Dictionary) -> Dictionary:
	var state := read_session()
	state.merge(changes, true)
	if not _data_only(state):
		return _failure("WEAPON_LIBRARY_SESSION_INVALID")
	var directory := root_path.path_join("sessions")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _failure("WEAPON_LIBRARY_SESSION_DIRECTORY_FAILED")
	var data := var_to_bytes(state)
	var record := {"schema": SCHEMA, "data": Marshalls.raw_to_base64(data), "sha256": _hash(data)}
	var name := "%020d_%020d" % [int(Time.get_unix_time_from_system() * 1000000.0), Time.get_ticks_usec()]
	var temporary := directory.path_join(name + ".pending")
	if _write_bytes(temporary, JSON.stringify(record).to_utf8_buffer()) != OK or _publish_path(temporary, directory.path_join(name + ".json")) != OK:
		return _failure("WEAPON_LIBRARY_SESSION_WRITE_FAILED")
	return {"ok": true, "session": state}


static func _rig_contract(rig: PixelWeaponVisualRig) -> Dictionary:
	if rig == null:
		return {}
	var parts: Array[Dictionary] = []
	for raw: Dictionary in rig.parts:
		var part := raw.duplicate(true)
		for key: String in ["source_path", "mask_polygon"]:
			var pairs: Array = []
			for point: Vector2 in part.get(key, PackedVector2Array()):
				pairs.append([point.x, point.y])
			part[key] = pairs
		for key: String in ["pivot", "source_direction"]:
			var point: Vector2 = part.get(key, Vector2.ZERO)
			part[key] = [point.x, point.y]
		parts.append(part)
	return {"schema": rig.schema, "source": rig.source, "automatic": rig.automatic, "player_confirmation_required": rig.player_confirmation_required, "confidence": rig.confidence, "parts": parts}


static func _data_only(value: Variant) -> bool:
	if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if not _data_only(key) or not _data_only(value[key]):
				return false
	elif value is Array:
		for item: Variant in value:
			if not _data_only(item):
				return false
	return true


static func _hash(data: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	return hashing.finish().hex_encode()


static func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	return error


static func _publish_path(source: String, target: String) -> Error:
	# Windows scanners may briefly hold a newly closed file. Keep the atomic
	# rename requirement; retry briefly without copying over an existing save.
	var error := ERR_CANT_CREATE
	for attempt: int in range(4):
		error = DirAccess.rename_absolute(source, target)
		if error == OK:
			return OK
		if attempt < 3:
			OS.delay_msec(15)
	return error


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "player_confirmation_required": false}
