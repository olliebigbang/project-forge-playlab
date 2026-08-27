class_name PerceptibleExperimentAssetLoader
extends RefCounted

const INDEX_PATH := "res://data/combat_feel/perceptible_mechanism_experiment_assets.json"
const BASE_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const VALID_SURFACES := ["point", "edge", "broad", "whole_body"]


func load_surface(surface: String) -> Dictionary:
	var descriptor := sample_for_surface(surface)
	if not bool(descriptor.get("ok", false)):
		return descriptor
	return load_asset(str(descriptor.get("asset_id", "")))


func sample_for_surface(surface: String) -> Dictionary:
	if surface not in VALID_SURFACES:
		return {"ok": false, "error": "PERCEPTIBLE_EXPERIMENT_SURFACE_INVALID:%s" % surface}
	var index := _validated_index()
	if not bool(index.get("ok", false)):
		return index
	var match_count := 0
	var result := {}
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		if str(entry.get("representative_surface", "")) != surface:
			continue
		match_count += 1
		result = {
			"ok": true,
			"surface": surface,
			"asset_id": str(entry.get("id", "")),
			"sample_label": str(entry.get("sample_label", "SAMPLE")),
		}
	if match_count != 1:
		return {"ok": false, "error": "PERCEPTIBLE_EXPERIMENT_SURFACE_SAMPLE_COUNT:%s:%d" % [surface, match_count]}
	return result


func load_asset(asset_id: String) -> Dictionary:
	var index := _validated_index()
	if not bool(index.get("ok", false)):
		return index
	for value: Variant in index.get("assets", []):
		var entry: Dictionary = value
		if str(entry.get("id", "")) != asset_id:
			continue
		var loaded := BASE_LOADER.new().load_live(
			str(entry.get("sprite", "")),
			str(entry.get("blueprint", "")),
			str(entry.get("anchors", ""))
		)
		if not bool(loaded.get("ok", false)):
			return loaded
		var profile := _profile_from_dict(entry.get("affordance", {}) as Dictionary)
		if profile == null:
			return {"ok": false, "error": "PERCEPTIBLE_EXPERIMENT_AFFORDANCE_INVALID:%s" % asset_id}
		var representative_surface := str(entry.get("representative_surface", ""))
		if representative_surface not in VALID_SURFACES or profile.contact_surface != representative_surface:
			return {"ok": false, "error": "PERCEPTIBLE_EXPERIMENT_SURFACE_MISMATCH:%s" % asset_id}
		loaded["asset_id"] = asset_id
		loaded["representative_surface"] = representative_surface
		loaded["sample_label"] = str(entry.get("sample_label", "SAMPLE"))
		loaded["affordance_profile"] = profile
		loaded["developer_only"] = true
		loaded["normal_player_flow"] = false
		loaded["frozen_evidence_claim"] = false
		loaded["notice"] = str(index.get("notice", "DEVELOPER EXPERIMENT"))
		return loaded
	return {"ok": false, "error": "PERCEPTIBLE_EXPERIMENT_ASSET_NOT_FOUND:%s" % asset_id}


func _validated_index() -> Dictionary:
	var index := _read_json(INDEX_PATH)
	if not bool(index.get("developer_experiment_only", false)) \
			or bool(index.get("normal_player_flow", true)) \
			or bool(index.get("frozen_evidence_claim", true)):
		return {"ok": false, "error": "PERCEPTIBLE_EXPERIMENT_BOUNDARY_INVALID"}
	index["ok"] = true
	return index


func _profile_from_dict(data: Dictionary) -> Resource:
	var profile: Resource = AFFORDANCE.new()
	for key: String in profile.to_dict():
		if key == "evidence_parts":
			profile.evidence_parts = PackedStringArray(data.get(key, []))
		elif data.has(key):
			profile.set(key, data[key])
	return null if not profile.validation_errors().is_empty() else profile


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
