extends "res://tests/church_forge_live_review.gd"
## Offline recompile/render of an explicitly supplied completed live report.
## No generation service is started, no .env, and original artifacts stay intact.
const ANCHORS := preload("res://scripts/systems/anchor_resolver.gd")
const VISUAL := preload("res://scripts/services/fal_general_object_visual_provider.gd")
const FACTORY := preload("res://scripts/combat_feel/weapon_entry_factory.gd")
const STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")
var source_report := ""
var only_index := -1

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source-report="): source_report = arg.trim_prefix("--source-report=")
		if arg.begins_with("--only-index="): only_index = int(arg.trim_prefix("--only-index="))
	if source_report.is_empty() or not FileAccess.file_exists(source_report):
		printerr("OFFLINE_RENDER_SOURCE_REPORT_REQUIRED")
		quit(2)
		return
	for name: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]: OS.unset_environment(name)
	evidence_dir = ProjectSettings.globalize_path("res://.tools/church-ai-forge/review-%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()])
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	OS.set_environment("FORGE_WEAPON_LIBRARY_ROOT", evidence_dir.path_join("isolated-library"))
	call_deferred("_run")

func _run() -> void:
	var input: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_report))
	ui = FORGE.new()
	root.add_child(ui)
	await process_frame
	var success := true
	for index: int in range(input.records.size()):
		if only_index >= 0 and index != only_index: continue
		var previous: Dictionary = input.records[index]
		if previous.state != "success": continue
		var prefix := "%02d" % (index + 1)
		var bp := WeaponBlueprint.from_dict(previous.blueprint)
		var image := Image.load_from_file(str(previous.visual_output).path_join("processed_sprite.png"))
		var asset := ANCHORS.resolve(image, bp)
		VISUAL.new()._apply_mechanism_anchor_intent(asset, bp)
		asset.tether_origin = asset.tip
		var entry := FACTORY.finish(bp, {"asset": asset, "manifest": {"visual_mode": "offline_recompile_of_real_ai_art"}})
		if not bool(entry.get("ok", false)):
			printerr("RECOMPILE_FAILED ", previous.identity, " ", entry)
			success = false
			continue
		var evidence := STYLE.inspect(asset.source_image, "church_v1")
		bp.modifiers["art_style_report"] = evidence
		entry.visual_evidence["art_style"] = evidence
		# Emulate the state reset from begin_generation without starting any API.
		ui._clear_entry()
		ui.state = "generating"
		ui.input_text = previous.identity
		ui.input_field.text = previous.identity
		ui.generation_token += 1
		ui.accept_generation_result(ui.generation_token, {"status": "success", "ok": true, "entry": entry, "generation_evidence": {"art_style_id": "church_v1", "semantic_cache_hit": true, "visual_cache_hit": true, "offline_recompiled_from": source_report}})
		if ui.state != "success":
			printerr("RECOMPILE_UI_REJECTED ", ui.error_code)
			success = false
			continue
		await _capture(prefix + "-preview")
		ui.enter_battle()
		# One out-of-range held attack shows the actual structure without enemy
		# overlap. The following fight restarts normally with untouched AI logic.
		ui.arena.set_touch_attack(true)
		for frame: int in range(100):
			await process_frame
			if frame in [30, 45, 60, 80]: await _capture(prefix + "-structure-%d" % frame)
		ui.restart_battle()
		var record := {"identity": previous.identity, "state": "success", "source": "offline_recompile_same_live_AI_pixels", "source_report": source_report, "anchors": asset.anchors_dict(), "same_generated_asset_in_arena": ui.arena.asset == asset, "battle": await _battle(prefix)}
		ui.return_to_forge()
		var saved: Dictionary = ui.save_current_entry()
		var restored: Dictionary = LIBRARY.new().load_entry(str(saved.get("library_key", ""))) if saved.get("ok", false) else {}
		var roundtrip: bool = bool(restored.get("ok", false)) and restored.asset.source_image.get_data() == asset.source_image.get_data() and restored.asset.grip_primary == asset.grip_primary and restored.asset.tip == asset.tip
		record["isolated_save"] = {"ok": saved.get("ok", false), "key": saved.get("library_key", ""), "restored_pixels_and_anchors": roundtrip}
		success = success and roundtrip and record.battle.runtime_error == "" and int(record.battle.metrics.get("melee_hits", 0)) > 0
		records.append(record)
		await _capture(prefix + "-returned-saved")
		_write_report()
	print("OFFLINE_CHURCH_RENDER_REVIEW entries=%d evidence=%s" % [records.size(), evidence_dir])
	ui.queue_free()
	await process_frame
	quit(0 if success and records.size() == (1 if only_index >= 0 else input.records.size()) else 1)

func _write_report() -> void:
	var file := FileAccess.open(evidence_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"records": records, "source_report": source_report, "library_root": OS.get_environment("FORGE_WEAPON_LIBRARY_ROOT"), "no_user_library_writes": true, "online_calls": 0, "not_manual_desktop": true}, "  "))
	file.close()
