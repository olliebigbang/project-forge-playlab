extends SceneTree
## Offline continuation of one already-consumed live acceptance request.
## It never starts a provider process or reads API keys. Only a retained ai_raw.png
## from a pixelizer-stage failure can enter the local 96px fallback.
const PROVIDER := preload("res://scripts/services/fal_general_object_visual_provider.gd")
const FACTORY := preload("res://scripts/combat_feel/weapon_entry_factory.gd")
const LIBRARY := preload("res://scripts/combat_feel/weapon_library_store.gd")
const STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var acceptance_root := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--acceptance-root="):
			acceptance_root = argument.trim_prefix("--acceptance-root=")
	var allowed_root := ProjectSettings.globalize_path("res://.tools/sunny-live-acceptance").replace("\\", "/")
	var absolute_root := (ProjectSettings.globalize_path(acceptance_root) if acceptance_root.begins_with("res://") else acceptance_root).replace("\\", "/")
	if acceptance_root.is_empty() or not absolute_root.begins_with(allowed_root + "/"):
		printerr("RECOVERY_ISOLATED_ACCEPTANCE_ROOT_REQUIRED"); quit(2); return
	var report_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute_root.path_join("report.json")))
	if not report_value is Dictionary or not report_value.get("records", []) is Array or report_value.records.size() != 1:
		printerr("RECOVERY_ONE_RECORD_REQUIRED"); quit(2); return
	var record := (report_value.records as Array)[0] as Dictionary
	var error := str(record.get("error", ""))
	if not error.begins_with("GENERAL_OBJECT_VISUAL_FAL_PIXELIZER_") or int(record.get("visual_requests", 0)) != 1:
		printerr("RECOVERY_PIXELIZER_FAILURE_REQUIRED"); quit(2); return
	var blueprint_value: Variant = record.get("blueprint", {})
	if not blueprint_value is Dictionary:
		printerr("RECOVERY_BLUEPRINT_REQUIRED"); quit(2); return
	var visual_directory := str(record.get("visual_output", ""))
	if visual_directory.is_empty() or not visual_directory.replace("\\", "/").begins_with(absolute_root + "/"):
		printerr("RECOVERY_VISUAL_DIRECTORY_INVALID"); quit(2); return
	var blueprint := WeaponBlueprint.from_dict(blueprint_value)
	var provider := PROVIDER.new()
	provider.cache_root = absolute_root.path_join("recovered-visual-cache")
	provider.output_root = absolute_root.path_join("recovered-visual-requests")
	var visual_result: Dictionary = provider.load_atomic_result(visual_directory, blueprint)
	if str(visual_result.get("status", "")) != "success":
		printerr("RECOVERY_VISUAL_FAILED ", visual_result); quit(1); return
	var finished: Dictionary = FACTORY.finish(blueprint, visual_result)
	if not bool(finished.get("ok", false)):
		printerr("RECOVERY_FINISH_FAILED ", finished); quit(1); return
	var asset := finished.get("asset") as WeaponVisualAsset
	var style_report: Dictionary = STYLE.inspect(asset.source_image if asset != null else null, "sunny_v1")
	if not bool(style_report.get("ok", false)):
		printerr("RECOVERY_STYLE_FAILED ", style_report); quit(1); return
	blueprint.modifiers["art_style_report"] = style_report.duplicate(true)
	finished.visual_evidence["art_style"] = style_report.duplicate(true)
	finished.visual_evidence["generation"] = {"semantic_cache_hit": false, "visual_cache_hit": false, "art_style_id": "sunny_v1", "art_style_version": STYLE.version("sunny_v1"), "visual_requests": 1, "local_pixelizer_recovery": true, "new_network_requests": 0}
	var saved: Dictionary = LIBRARY.new().save_entry(finished)
	if not bool(saved.get("ok", false)):
		printerr("RECOVERY_SAVE_FAILED ", saved); quit(1); return
	var loaded: Dictionary = LIBRARY.new().load_entry(str(saved.get("library_key", "")))
	if not bool(loaded.get("ok", false)) or (loaded.asset as WeaponVisualAsset).source_image.get_data() != asset.source_image.get_data():
		printerr("RECOVERY_RELOAD_FAILED ", loaded); quit(1); return
	var recovery_record := {
		"ok": true,
		"source_acceptance_root": absolute_root,
		"source_error": error,
		"new_network_requests": 0,
		"library_key": saved.library_key,
		"blueprint": blueprint.to_dict(),
		"anchors": asset.anchors_dict(),
		"manifest": visual_result.get("manifest", {}),
		"visual_evidence": finished.visual_evidence,
		"pixels_identical_after_reload": true,
	}
	var file := FileAccess.open(absolute_root.path_join("recovery_record.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(recovery_record, "  ")); file.close()
	print("SUNNY_ACCEPTANCE_RECOVERY_OK key=", saved.library_key, " new_network_requests=0")
	quit(0)
