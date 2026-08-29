class_name EnemyVisualAssetLibrary
extends RefCounted

const DEFAULT_PATH := "res://data/enemy_attack/enemy_visual_assets_v1.json"
const SCHEMA := "forge-enemy-visual-assets-v1"

var background_texture: Texture2D
var entries: Dictionary = {}
var error := ""


func load_validated(path: String = DEFAULT_PATH) -> Dictionary:
	entries.clear()
	background_texture = null
	error = ""
	if not FileAccess.file_exists(path):
		return _failure("ENEMY_VISUAL_MANIFEST_MISSING")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _failure("ENEMY_VISUAL_MANIFEST_INVALID_JSON")
	var source := parsed as Dictionary
	if str(source.get("schema", "")) != SCHEMA:
		return _failure("ENEMY_VISUAL_MANIFEST_SCHEMA_INVALID")
	var background_path := str(source.get("background_path", ""))
	background_texture = _load_texture(background_path)
	if background_texture == null:
		return _failure("ENEMY_VISUAL_BACKGROUND_MISSING")
	var raw_entries := source.get("enemies", {}) as Dictionary
	if raw_entries.is_empty():
		return _failure("ENEMY_VISUAL_ENTRIES_MISSING")
	for raw_id: Variant in raw_entries.keys():
		var blueprint_id := str(raw_id).strip_edges()
		var declaration := raw_entries.get(raw_id, {}) as Dictionary
		var texture := _load_texture(str(declaration.get("sprite_path", "")))
		var draw_size := _vector_from_array(declaration.get("draw_size", []))
		var anchor := _vector_from_array(declaration.get("anchor", []))
		if blueprint_id.is_empty() or texture == null or draw_size.x <= 0.0 or draw_size.y <= 0.0:
			return _failure("ENEMY_VISUAL_ENTRY_INVALID:%s" % blueprint_id)
		if anchor.x < 0.0 or anchor.y < 0.0 or anchor.x > draw_size.x or anchor.y > draw_size.y:
			return _failure("ENEMY_VISUAL_ANCHOR_INVALID:%s" % blueprint_id)
		entries[blueprint_id] = {
			"texture": texture,
			"sprite_path": str(declaration.get("sprite_path", "")),
			"draw_size": draw_size,
			"anchor": anchor,
			"health_bar_y": float(declaration.get("health_bar_y", -68.0)),
		}
	return {
		"ok": true,
		"schema": SCHEMA,
		"enemy_count": entries.size(),
		"background_path": background_path,
	}


func visual_for(blueprint_id: String) -> Dictionary:
	return (entries.get(blueprint_id, {}) as Dictionary).duplicate(true)


func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _vector_from_array(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))


func _failure(code: String) -> Dictionary:
	error = code
	return {"ok": false, "error": code, "schema": SCHEMA}
