extends SceneTree

const GENERAL := preload("res://scripts/services/fal_general_object_visual_provider.gd")
const FIREARM := preload("res://scripts/services/fal_firearm_visual_provider.gd")
const STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")
var passed := 0
var failed := 0
var evidence_root := ""


func _initialize() -> void:
	evidence_root = ProjectSettings.globalize_path("res://.tools/church-style-provider-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(evidence_root)
	call_deferred("_run")


func check(label: String, condition: bool) -> void:
	if condition: passed += 1; print("PASS | ", label)
	else: failed += 1; printerr("FAIL | ", label)


func _run() -> void:
	for is_firearm: bool in [false, true]:
		var provider: RefCounted = FIREARM.new() if is_firearm else GENERAL.new()
		var label := "firearm" if is_firearm else "object"
		check(label + " production output defaults retained", provider.output_root == provider.OUTPUT_ROOT and provider.cache_root == provider.CACHE_ROOT)
		provider.output_root = evidence_root.path_join(label + "-requests")
		provider.cache_root = evidence_root.path_join(label + "-cache")
		check(label + " QA roots can be isolated without changing provider", provider.output_root.begins_with(evidence_root) and provider.cache_root.begins_with(evidence_root))
		var blueprint := WeaponBlueprint.new()
		blueprint.player_identity_text = "offline arbitrary structure"
		blueprint.display_name = blueprint.player_identity_text
		blueprint.behavior_family = "sustained_ranged" if is_firearm else "heavy_melee"
		blueprint.affordance = {"weapon_domain": "handheld_firearm"} if is_firearm else {}
		blueprint.modifiers["general_object_profile_id"] = "object_offline_fixture"
		var legacy: Dictionary = provider._build_request_payload(blueprint, {})
		check(label + " legacy request omits style", not legacy.has("art_style"))
		blueprint.modifiers["art_style_id"] = STYLE.ID
		var styled: Dictionary = provider._build_request_payload(blueprint, {})
		check(label + " style carries exact version and prompt", styled.art_style == STYLE.contract(STYLE.ID))
		check(label + " style isolates cache from legacy", provider._cache_key(styled) != provider._cache_key(legacy))
		var retry := styled.duplicate(true)
		retry.seed = 5; retry.retry_index = 2; retry.retry_prompt = "redraw test"
		check(label + " retry nonce does not fragment style cache", provider._cache_key(styled) == provider._cache_key(retry))
		provider.active_request_payload = retry.duplicate(true)
		check(label + " redraw cannot reuse rejected cached pixels", not provider._can_reuse_visual_cache())
		provider.active_request_payload = styled.duplicate(true)
		check(label + " first request still uses matching cache", provider._can_reuse_visual_cache())
		retry.art_style.version = "other-version"
		check(label + " changed style version invalidates cache", provider._cache_key(styled) != provider._cache_key(retry))
		blueprint.modifiers["art_style_id"] = "unknown-style"
		provider.request_visual(blueprint, "", PackedByteArray(), 0.0)
		var rejection: Dictionary = provider.poll()
		check(label + " unknown style fails before spawning bridge", provider.process_id == -1 and "ART_STYLE_UNSUPPORTED" in str(rejection.get("error", "")))
		provider.active_request_payload = styled.duplicate(true)
		provider.active_output_directory = evidence_root.path_join(label)
		DirAccess.make_dir_recursive_absolute(provider.active_output_directory)
		var image := _fixture_image()
		var before_alpha := _alpha_bytes(image)
		var normalized := {"image": image}
		var manifest := {"art_style": STYLE.contract(STYLE.ID)}
		var applied: Dictionary = provider._apply_art_style(normalized, manifest, false)
		var final_image := normalized.image as Image
		check(label + " final image meets fixed Church palette", bool(applied.get("ok", false)) and bool(STYLE.inspect(final_image, STYLE.ID).get("ok", false)))
		check(label + " styling preserves real Alpha for anchor compilation", _alpha_bytes(final_image) == before_alpha)
		var disk_image := Image.load_from_file(str(provider.active_output_directory).path_join("processed_sprite.png"))
		check(label + " final pixels on disk match downstream image", disk_image != null and disk_image.get_data() == final_image.get_data())
		check(label + " report records normalization evidence", bool((manifest.get("art_style_report", {}) as Dictionary).get("ok", false)))
		var cache_image := final_image.duplicate() as Image
		var cached := {"image": cache_image}
		var cache_check: Dictionary = provider._apply_art_style(cached, manifest, true)
		check(label + " accepted cache restores without repeated pixel drift", bool(cache_check.get("ok", false)) and (cached.image as Image).get_data() == cache_image.get_data())
		var missing_report := manifest.duplicate(true)
		missing_report.erase("art_style_report")
		check(label + " style cache requires recorded evidence", not bool(provider._apply_art_style(cached, missing_report, true).get("ok", false)))
		var wrong_report := manifest.duplicate(true)
		wrong_report.art_style_report.version = "not-current"
		check(label + " style cache rejects stale normalization report", not bool(provider._apply_art_style(cached, wrong_report, true).get("ok", false)))
		check(label + " noncanonical cache cannot silently restyle", not bool(provider._apply_art_style({"image": _fixture_image()}, manifest, true).get("ok", false)))
		var wrong_manifest := manifest.duplicate(true)
		wrong_manifest.art_style.version = "old-version"
		check(label + " mismatched manifest fails before anchors", not bool(provider._apply_art_style(normalized, wrong_manifest, false).get("ok", false)))
		check(label + " invalid image fails style gate", not bool(provider._apply_art_style({"image": Image.create(16, 16, false, Image.FORMAT_RGBA8)}, manifest, false).get("ok", false)))
		_test_cache_evidence(provider, manifest, is_firearm, label)
		provider.active_request_payload = legacy
		var untouched := _fixture_image()
		var untouched_bytes := untouched.get_data()
		check(label + " default path does not recolor existing weapons", bool(provider._apply_art_style({"image": untouched}, {}, false).get("ok", false)) and untouched.get_data() == untouched_bytes)
	print("CHURCH_STYLE_PROVIDER_TESTS passed=%d failed=%d evidence=%s" % [passed, failed, evidence_root])
	quit(0 if failed == 0 else 1)


func _test_cache_evidence(provider: RefCounted, style_manifest: Dictionary, firearm: bool, label: String) -> void:
	var directory := str(provider.active_output_directory)
	var sprite := FileAccess.get_file_as_bytes(directory.path_join("processed_sprite.png"))
	var manifest := style_manifest.duplicate(true)
	manifest.merge({"schema": provider.MANIFEST_SCHEMA, "status": "success", "finished_art": true, "presentable_to_player": true, "firearm_visual_gate_passed": true})
	if firearm:
		manifest["ai_visual_identity_verification"] = {"schema": FIREARM.VISUAL_VERIFICATION_SCHEMA, "ok": true, "passed": true}
		var anchors := {}
		for anchor: String in ["GripPrimary", "GripSecondary", "Muzzle", "FeedCenter", "ActionCycle", "ActionReload"]: anchors[anchor] = [12, 48]
		manifest["firearm_visual_identity_gate"] = {"schema": FIREARM.CACHE_POLICY.GATE_SCHEMA, "ok": true, "action_anchor_contract": true, "anchors": anchors}
	var record := {"schema": provider.CACHE_SCHEMA, "key": "offline-style-test", "pipeline_version": FIREARM.VISUAL_PIPELINE_VERSION if firearm else GENERAL.PIPELINE_VERSION, "processed_sprite_sha256": provider._bytes_sha256(sprite), "art_style": STYLE.contract(STYLE.ID)}
	provider._write_json_atomic(directory.path_join("manifest.json"), manifest)
	provider._write_json_atomic(directory.path_join("cache_record.json"), record)
	check(label + " cache accepts matching hashed styled evidence", provider._cache_entry_valid(directory, "offline-style-test"))
	record.art_style.version = "outdated"
	provider._write_json_atomic(directory.path_join("cache_record.json"), record)
	check(label + " cache rejects mismatched record contract", not provider._cache_entry_valid(directory, "offline-style-test"))
	if firearm:
		check("firearm cannot migrate legacy pixels into Church style", not provider._try_migrate_legacy_cache(directory, "offline-style-test"))


func _fixture_image() -> Image:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(12, 42, 64, 12), Color(0.21, 0.52, 0.36, 1.0))
	image.fill_rect(Rect2i(14, 44, 10, 8), Color(0.95, 0.31, 0.11, 1.0))
	return image


func _alpha_bytes(image: Image) -> PackedByteArray:
	var result := PackedByteArray()
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			result.append(roundi(image.get_pixel(x, y).a * 255.0))
	return result
