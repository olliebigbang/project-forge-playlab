extends RefCounted
## Separate versioned campaign progress. Immutable snapshots make a interrupted
## write recoverable, without deleting or overwriting the old weapon library.
const LIBRARY := preload("res://scripts/combat_feel/weapon_library_store.gd")
const SCHEMA := "church-expedition-save-v1"
var directory := ""

func _init() -> void:
	directory = LIBRARY.new().root_path.path_join("church-expedition-v1")

func read_state() -> Dictionary:
	if not DirAccess.dir_exists_absolute(directory): return _empty()
	var files := Array(DirAccess.get_files_at(directory))
	files.sort(); files.reverse()
	for name: String in files:
		if not name.ends_with(".json"): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(name)))
		if parsed is Dictionary and valid(parsed): return parsed
	return _empty()

func write_state(value: Dictionary) -> Dictionary:
	var snapshot := value.duplicate(true)
	snapshot["schema"] = SCHEMA
	if not valid(snapshot): return {"ok": false, "error": "EXPEDITION_SAVE_INVALID"}
	var parent := directory
	while not parent.is_empty():
		if FileAccess.file_exists(parent): return {"ok": false, "error": "EXPEDITION_SAVE_DIRECTORY_FAILED"}
		var next := parent.get_base_dir()
		if next == parent: break
		parent = next
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return {"ok": false, "error": "EXPEDITION_SAVE_DIRECTORY_FAILED"}
	var name := "%020d-%012d.json" % [int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()]
	var handle := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	if handle == null: return {"ok": false, "error": "EXPEDITION_SAVE_WRITE_FAILED"}
	handle.store_string(JSON.stringify(snapshot)); handle.flush()
	var write_error := handle.get_error(); handle.close()
	if write_error != OK: return {"ok": false, "error": "EXPEDITION_SAVE_WRITE_FAILED"}
	var verified: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(name)))
	if not verified is Dictionary or not valid(verified): return {"ok": false, "error": "EXPEDITION_SAVE_VERIFY_FAILED"}
	return {"ok": true}

static func valid(value: Dictionary) -> bool:
	if value.get("schema", "") != SCHEMA or not value.get("history", null) is Array or not value.get("checkpoint", null) is Dictionary: return false
	if value.history.size() > 10: return false
	if not value.get("selected_key", "") is String: return false
	if value.has("meta_progression") and not _valid_meta_progression(value.meta_progression): return false
	for item: Variant in value.history:
		if not item is Dictionary or not item.get("metrics", null) is Dictionary or not item.get("weapon", null) is String: return false
		if not _valid_metrics(item.metrics): return false
	var point: Dictionary = value.checkpoint
	if point.is_empty(): return true
	for key: String in ["chapter", "seed", "health", "supplies", "weapon_key", "metrics"]:
		if not point.has(key): return false
	if not point.metrics is Dictionary or not _valid_metrics(point.metrics): return false
	if typeof(point.chapter) not in [TYPE_FLOAT, TYPE_INT] or typeof(point.health) not in [TYPE_FLOAT, TYPE_INT] or typeof(point.supplies) not in [TYPE_FLOAT, TYPE_INT] or typeof(point.seed) not in [TYPE_FLOAT, TYPE_INT]: return false
	for number: Variant in [point.chapter, point.supplies, point.seed]:
		if not is_finite(float(number)) or float(number) != floorf(float(number)): return false
	if point.has("run_mode") and str(point.run_mode) not in ["trial", "story"]: return false
	if point.has("story_route") and str(point.story_route) not in ["brook", "grove", "ridge"]: return false
	if point.has("story_carry") and not _valid_story_carry(point.story_carry): return false
	if point.has("run_mode") and str(point.run_mode) == "trial" and int(point.chapter) != 0: return false
	return is_finite(float(point.health)) and float(point.health) > 0 and float(point.health) <= 100 and int(point.chapter) in [0, 1, 2] and int(point.supplies) >= 0 and int(point.supplies) <= 2 and str(point.weapon_key).length() == 64 and str(point.weapon_key).is_valid_hex_number(false)

static func _valid_meta_progression(value: Variant) -> bool:
	# Optional so legacy Church/Sunny snapshots remain readable. The store keeps
	# this contract local instead of depending on a themed campaign script.
	if not value is Dictionary or str(value.get("schema", "")) != "sunny-meta-progression-v1": return false
	for key: String in ["insight", "completed_runs"]:
		var number: Variant = value.get(key, null)
		if typeof(number) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(number)) or float(number) != floorf(float(number)) or int(number) < 0 or int(number) > 9999: return false
	var families: Variant = value.get("mastered_families", null)
	if not families is Array or families.size() > 6: return false
	var allowed := ["ranged_cycle", "flexible_control", "active_output", "point_lever", "edge_contact", "broad_impact"]
	var seen := {}
	for family: Variant in families:
		if not family is String or family not in allowed or seen.has(family): return false
		seen[family] = true
	return true


static func _valid_story_carry(value: Variant) -> bool:
	if not value is Dictionary: return false
	var carry := value as Dictionary
	var materials: Variant = carry.get("forge_materials", 0)
	if typeof(materials) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(materials)) or float(materials) != floorf(float(materials)) or int(materials) < 0 or int(materials) > 99: return false
	var cores: Variant = carry.get("structure_cores", [])
	if not cores is Array or cores.size() > 8: return false
	for core: Variant in cores:
		if not core is String or str(core) not in ["impact", "control", "tempo", "stability"]: return false
	var upgrades: Variant = carry.get("upgrades", [])
	if not upgrades is Array or upgrades.size() > 9: return false
	for upgrade: Variant in upgrades:
		if not upgrade is Dictionary: return false
		var record := upgrade as Dictionary
		if str(record.get("id", "")).is_empty() or not record.get("effects", null) is Dictionary: return false
		for effect: Variant in (record.effects as Dictionary).values():
			if typeof(effect) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(effect)) or absf(float(effect)) > 100.0: return false
	return true

static func _valid_metrics(metrics: Dictionary) -> bool:
	for name: String in ["elapsed_seconds", "damage_taken", "defeated", "dodge_count", "heals_used", "attacks_used", "shots_fired"]:
		var value: Variant = metrics.get(name, 0)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or float(value) < 0: return false
	return true

static func _empty() -> Dictionary:
	return {"schema": SCHEMA, "checkpoint": {}, "history": [], "selected_key": ""}
