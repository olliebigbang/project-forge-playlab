extends SceneTree

const AI_RESOLVER := preload("res://scripts/combat_feel/firearm_identity_ai_resolver.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const FAL_PROVIDER := preload("res://scripts/services/fal_firearm_visual_provider.gd")
const PLAYER_ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")

const AI_FIXTURE := "res://tests/fixtures/firearm_ai_ak47_response.json"
const SPRITE_FIXTURE := "res://tests/fixtures/firearm_visual_v2/m4a1_gpt_image.png"
const TEST_SOURCE := "AI_TEST_FIXTURE_FIREARM_IDENTITY_V3"

var passed := 0
var failed := 0


func _initialize() -> void:
	print("Forge firearm cache-first pipeline tests")
	_run("Dynamic firearm canonical aliases hit semantic cache locally", _test_semantic_alias_cache)
	_run("Validated finished art bypasses Python and remote configuration", _test_finished_art_local_hit)
	_run("Armory reads the current dynamic firearm semantic cache", _test_armory_current_semantic_cache)
	_run("Armory reopens from memory and invalidates changed evidence", _test_armory_memory_cache)
	_run("Forge labels local hits separately from first generation", _test_cache_status_copy)
	print("FIREARM CACHE PIPELINE RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _run(test_name: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result == true:
		passed += 1
		print("PASS | %s" % test_name)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [test_name, str(result)])


func _test_semantic_alias_cache() -> Variant:
	var root := "user://playlab/tests/firearm_pipeline_semantic_%d" % Time.get_ticks_usec()
	var cache_path := root.path_join("cache_v3.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AI_FIXTURE))
	if not parsed is Dictionary:
		return "fixture invalid"
	var payload := (parsed as Dictionary).duplicate(true)
	payload["canonical_name"] = "Kalashnikov Model 1947"
	var accepted: Dictionary = AI_RESOLVER.accept_ai_response(
		"AK-47", payload, TEST_SOURCE, true, cache_path
	)
	var cached: Dictionary = AI_RESOLVER.resolve_identity("Kalashnikov-Model 1947", cache_path)
	_remove_tree(ProjectSettings.globalize_path(root))
	if not bool(accepted.get("ok", false)) or not bool(cached.get("ok", false)):
		return {"accepted": accepted, "cached": cached}
	if not bool(cached.get("cache_hit", false)):
		return "canonical alias did not report a local cache hit"
	if str(cached.get("matched_alias", "")) != "Kalashnikov Model 1947":
		return cached
	return true


func _test_finished_art_local_hit() -> Variant:
	var root := "user://playlab/tests/firearm_pipeline_visual_%d" % Time.get_ticks_usec()
	var interpreted: Dictionary = INTERPRETER.new().interpret("M4A1", PackedByteArray(), {})
	var blueprint := interpreted.get("blueprint") as WeaponBlueprint
	if blueprint == null:
		return interpreted
	var provider = FAL_PROVIDER.new()
	provider.cache_root = root.path_join("cache_v1")
	provider.output_root = root.path_join("requests")
	provider.bridge_script_path = "res://tests/fixtures/bridge_must_not_exist.py"
	var configured: Dictionary = provider.configure_local_first("python-that-must-not-run")
	if not bool(configured.get("ok", false)) or bool(configured.get("remote_generation_ready", true)):
		return configured
	provider.request_visual(blueprint, "", PackedByteArray(), 0.0)
	if provider.request_route() != "remote_generation_unavailable" or provider.process_id != -1:
		return {"first_route": provider.request_route(), "process_id": provider.process_id}
	var current_cache_key: String = provider.active_cache_key
	var cache_key: String = provider._cache_key_for_version(
		provider.active_request_payload,
		"fal-gpt-image-1.5-image2pixel24-anthropic-identity-v3"
	)
	var cache_directory: String = str(provider.cache_root).path_join(cache_key)
	var absolute_directory := ProjectSettings.globalize_path(cache_directory)
	if cache_key.is_empty() or DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return "cache setup failed"
	var sprite_bytes := FileAccess.get_file_as_bytes(SPRITE_FIXTURE)
	_write_bytes(cache_directory.path_join("raw_pixel_art.png"), sprite_bytes)
	_write_bytes(cache_directory.path_join("processed_sprite.png"), sprite_bytes)
	_write_json(cache_directory.path_join("manifest.json"), {
		"schema": FAL_PROVIDER.MANIFEST_SCHEMA,
		"status": "success",
		"identity": "M4A1",
		"canonical_identity": "M4A1",
		"positive_prompt": "exact M4A1 finished side profile pixel sprite",
		"finished_art": true,
		"presentable_to_player": true,
		"firearm_visual_gate_passed": true,
		"ai_visual_identity_verification": {
			"schema": FAL_PROVIDER.VISUAL_VERIFICATION_SCHEMA,
			"ok": true,
			"passed": true,
		},
		"firearm_visual_identity_gate": {"anchors": {}},
	})
	_write_json(cache_directory.path_join("cache_record.json"), {
		"schema": FAL_PROVIDER.CACHE_SCHEMA,
		"key": cache_key,
		"pipeline_version": "fal-gpt-image-1.5-image2pixel24-anthropic-identity-v3",
		"identity": "M4A1",
		"canonical_name": "M4A1",
		"processed_sprite_sha256": _sha256(sprite_bytes),
	})
	var local_hit_started := Time.get_ticks_usec()
	provider.request_visual(blueprint, "", PackedByteArray(), 0.0)
	var route := provider.request_route()
	var result: Dictionary = provider.poll()
	var local_hit_elapsed := Time.get_ticks_usec() - local_hit_started
	var ok: bool = (
		route == "local_immediate_hit"
		and provider.process_id == -1
		and str(result.get("status", "")) == "success"
		and str(result.get("cache_status", "")) == "local_immediate_hit"
		and bool(((result.get("manifest", {}) as Dictionary).get("cache", {}) as Dictionary).get("locally_revalidated", false))
		and not bool(result.get("external_process_started", true))
		and result.get("asset") is WeaponVisualAsset
		and bool((result.get("manifest", {}) as Dictionary).get("finished_art", false))
	)
	# A changed cache record must invalidate the memory-free provider path.
	_remove_tree(ProjectSettings.globalize_path(cache_directory))
	var current_cache_directory: String = str(provider.cache_root).path_join(current_cache_key)
	var current_record: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		current_cache_directory.path_join("cache_record.json")
	))
	var corrupted_record := (current_record as Dictionary).duplicate(true) if current_record is Dictionary else {}
	corrupted_record["processed_sprite_sha256"] = "corrupted"
	_write_json(current_cache_directory.path_join("cache_record.json"), corrupted_record)
	provider.request_visual(blueprint, "", PackedByteArray(), 0.0)
	var corrupt_route := provider.request_route()
	var corrupt_result: Dictionary = provider.poll()
	_remove_tree(ProjectSettings.globalize_path(root))
	if not ok:
		return {"route": route, "result": result}
	if corrupt_route != "remote_generation_unavailable" or str(corrupt_result.get("status", "")) != "failed":
		return {"corrupt_route": corrupt_route, "corrupt_result": corrupt_result}
	print("CACHE_TIMING local_finished_art_hit_usec=%d" % local_hit_elapsed)
	return true


func _test_armory_current_semantic_cache() -> Variant:
	var paths := PLAYER_ARMORY.DEFAULT_PROFILE_CACHE_PATHS
	if paths.is_empty() or str(paths[0]) != AI_RESOLVER.CACHE_PATH:
		return {"armory_paths": paths, "current_cache": AI_RESOLVER.CACHE_PATH}
	return true


func _test_armory_memory_cache() -> Variant:
	var root := "user://playlab/tests/firearm_pipeline_armory_%d" % Time.get_ticks_usec()
	var cache_directory := root.path_join("cache_v1/m4a1")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory)) != OK:
		return "armory cache setup failed"
	var sprite_bytes := FileAccess.get_file_as_bytes(SPRITE_FIXTURE)
	_write_bytes(cache_directory.path_join("processed_sprite.png"), sprite_bytes)
	_write_json(cache_directory.path_join("cache_record.json"), {
		"schema": FAL_PROVIDER.CACHE_SCHEMA,
		"key": "legacy-armory-m4a1",
		"pipeline_version": "fal-gpt-image-1.5-image2pixel24-anthropic-identity-v3",
		"identity": "M4A1",
		"canonical_name": "M4A1",
		"processed_sprite_sha256": _sha256(sprite_bytes),
	})
	var valid_manifest := {
		"schema": FAL_PROVIDER.MANIFEST_SCHEMA,
		"status": "success",
		"finished_art": true,
		"presentable_to_player": true,
		"firearm_visual_gate_passed": true,
		"ai_visual_identity_verification": {
			"schema": FAL_PROVIDER.VISUAL_VERIFICATION_SCHEMA,
			"ok": true,
			"passed": true,
		},
		"firearm_visual_identity_gate": {"schema": "forge-firearm-visual-identity-gate-v1", "anchors": {}},
	}
	_write_json(cache_directory.path_join("manifest.json"), valid_manifest)
	var armory = PLAYER_ARMORY.new()
	armory.visual_cache_root = root.path_join("cache_v1")
	armory.profile_cache_paths = []
	var first: Array[Dictionary] = armory.load_entries()
	var first_diagnostics: Dictionary = armory.last_load_diagnostics.duplicate(true)
	if first.size() != 1:
		_remove_tree(ProjectSettings.globalize_path(root))
		return {"first": first.size(), "diagnostics": first_diagnostics}
	# Simulate a picker consumer changing ordinary and nested entry data. Resource
	# objects are a documented shared boundary, so this test deliberately mutates
	# only Variant containers that must be isolated from the process cache.
	first[0]["display_name"] = "CALLER_TAMPERED_NAME"
	first[0]["cache_status"] = "caller_tampered_status"
	var first_runtime := first[0].get("ranged_runtime_profile", {}) as Dictionary
	first_runtime["magazine_size"] = -999
	var second: Array[Dictionary] = armory.load_entries()
	var second_diagnostics: Dictionary = armory.last_load_diagnostics.duplicate(true)
	valid_manifest["presentable_to_player"] = false
	_write_json(cache_directory.path_join("manifest.json"), valid_manifest)
	var third: Array[Dictionary] = armory.load_entries()
	var third_diagnostics: Dictionary = armory.last_load_diagnostics.duplicate(true)
	_remove_tree(ProjectSettings.globalize_path(root))
	if str(first_diagnostics.get("source", "")) != "validated_disk_rebuild":
		return first_diagnostics
	if int(first_diagnostics.get("images_decoded", 0)) != 1:
		return first_diagnostics
	if second.size() != 1 or str(second_diagnostics.get("source", "")) != "process_memory_cache":
		return {"second": second.size(), "diagnostics": second_diagnostics}
	var second_runtime := second[0].get("ranged_runtime_profile", {}) as Dictionary
	if (
		str(second[0].get("display_name", "")) != "M4A1"
		or str(second[0].get("cache_status", "")) != "validated_local_finished_art"
		or int(second_runtime.get("magazine_size", 0)) <= 0
	):
		return {"second_entry_after_caller_mutation": second[0]}
	if int(second_diagnostics.get("json_files_read", -1)) != 0 or int(second_diagnostics.get("images_decoded", -1)) != 0:
		return second_diagnostics
	if not third.is_empty() or str(third_diagnostics.get("source", "")) != "validated_disk_rebuild":
		return {"third": third.size(), "diagnostics": third_diagnostics}
	print("ARMORY_TIMING disk_rebuild_usec=%d memory_reopen_usec=%d" % [
		int(first_diagnostics.get("elapsed_usec", -1)),
		int(second_diagnostics.get("elapsed_usec", -1)),
	])
	return true


func _test_cache_status_copy() -> Variant:
	var source := FileAccess.get_file_as_string("res://scripts/open_identity_spike.gd")
	return (
		source.contains("本地成品缓存 · 不调用 AI")
		and source.contains("首次创建这件物品")
		and source.contains("configure_local_first")
	)


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))
	file.close()


func _write_bytes(path: String, value: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(value)
	file.close()


func _sha256(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var child := directory.get_next()
	while not child.is_empty():
		if child != "." and child != "..":
			var child_path := path.path_join(child)
			if directory.current_is_dir():
				_remove_tree(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		child = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
