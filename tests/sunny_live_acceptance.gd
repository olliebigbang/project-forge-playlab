extends SceneTree
## Explicit paid QA only. Not discovered by offline tests. Never substitutes a fixture.
const SESSION := preload("res://scripts/sunny_expedition/session.gd")
const SERVICE := preload("res://scripts/services/general_weapon_generation_service.gd")
const LIBRARY := preload("res://scripts/combat_feel/weapon_library_store.gd")
const DEFAULT_MANIFEST := "res://data/sunny_live_acceptance_samples_v1.json"
var directory := ""
var current_case := ""
var semantic_outputs: Array[String] = []
var records: Array[Dictionary] = []
var ui: Node
var dry_run := false

func _initialize() -> void:
	dry_run = "--dry-run" in OS.get_cmdline_user_args()
	directory = OS.get_environment("FORGE_ACCEPTANCE_ROOT")
	if directory.is_empty() or OS.get_environment("FORGE_WEAPON_LIBRARY_ROOT") != directory.path_join("isolated-library"):
		printerr("ACCEPTANCE_ISOLATED_ROOT_REQUIRED"); quit(2); return
	if not dry_run and "--allow-live-ai-review" not in OS.get_cmdline_user_args():
		printerr("ACCEPTANCE_EXPLICIT_LIVE_FLAG_REQUIRED"); quit(2); return
	if FileAccess.file_exists(directory.path_join("budget.json")):
		printerr("ACCEPTANCE_RUN_ALREADY_STARTED_NO_AUTOMATIC_PAID_REPLAY"); quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("run")

func run() -> void:
	var manifest_path := OS.get_environment("FORGE_ACCEPTANCE_MANIFEST")
	if manifest_path.is_empty(): manifest_path = DEFAULT_MANIFEST
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var selected := OS.get_environment("FORGE_ACCEPTANCE_SAMPLE_IDS")
	if not selected.is_empty():
		manifest.samples = manifest.samples.filter(func(sample: Dictionary) -> bool: return str(sample.id) in selected.split(","))
	write_json("samples.json", manifest)
	ui = SESSION.new(); ui.include_user_library = false; ui.use_semantic_cache = false
	ui.service_factory = make_service
	root.add_child(ui); await process_frame
	ui.open_forge()
	await capture("empty-forge")
	if dry_run:
		print("ACCEPTANCE_DRY_RUN_OK samples=", manifest.samples.size(), " online_calls=0")
		ui.free(); quit(0); return
	write_json("budget.json", {"reserved_first_pass_visual_requests": manifest.samples.size(), "per_sample_maximum": 1, "separately_authorized_reserve_limit": int(manifest.get("reserve_visual_requests", 0)) if selected.is_empty() else 0, "started_cases": []})
	for sample: Dictionary in manifest.samples:
		current_case = str(sample.id)
		semantic_outputs.clear()
		DirAccess.make_dir_recursive_absolute(directory.path_join(current_case))
		# Persist consumption before any network request; rerunning this directory refuses.
		var budget: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("budget.json")))
		budget.started_cases.append(current_case); write_json("budget.json", budget)
		var start := Time.get_ticks_msec()
		print("ACCEPTANCE_BEGIN ", current_case, " ", sample.identity)
		ui.begin_generation(sample.identity)
		var stage := ""
		while ui.state == "generating" and Time.get_ticks_msec() - start < 410000:
			if stage != ui.generation_stage:
				stage = ui.generation_stage; print("ACCEPTANCE_STAGE ", current_case, " ", stage)
			await create_timer(0.10).timeout
		var record := sample.duplicate(true)
		record["seconds"] = snappedf((Time.get_ticks_msec() - start) / 1000.0, 0.1)
		record["state"] = ui.state; record["error"] = ui.error_code
		record["generation_evidence"] = ui.generation_evidence.duplicate(true)
		if ui.service != null:
			record["visual_requests"] = ui.service.visual_requests
			record["semantic_outputs"] = semantic_outputs.duplicate()
			if ui.service.blueprint != null: record["blueprint"] = ui.service.blueprint.to_dict()
			if ui.service.visual_provider != null: record["visual_output"] = ui.service.visual_provider.active_output_directory
		if ui.state == "generating":
			ui.cancel_generation(); record.state = "failed"; record.error = "ACCEPTANCE_DEADLINE"
		await capture(current_case + "/generation-" + str(record.state))
		if record.state == "success":
			var asset: WeaponVisualAsset = ui.entry.asset
			asset.source_image.save_png(directory.path_join(current_case + "/sprite.png"))
			record["anchors"] = asset.anchors_dict()
			record["visual_evidence"] = ui.entry.visual_evidence.duplicate(true)
			var saved: Dictionary = ui.save_current_entry()
			var loaded: Dictionary = LIBRARY.new().load_entry(str(saved.get("library_key", ""))) if saved.get("ok", false) else {}
			record["save"] = {"ok": saved.get("ok", false), "error": saved.get("error", ""), "library_key": saved.get("library_key", ""), "restored": loaded.get("ok", false), "pixels_identical": loaded.get("ok", false) and loaded.asset.source_image.get_data() == asset.source_image.get_data(), "sunny_valid": loaded.get("ok", false) and ui.validate_entry(loaded, "sunny_v1").get("ok", false)}
		records.append(record); write_json(current_case + "/record.json", record)
		write_json("report.json", {"records": records, "source": "live AI, no semantic cache, fresh isolated visual caches", "manual_desktop": false, "campaign_test": "separate offline replay of these exact saved outputs", "personal_library_untouched": true})
		print("ACCEPTANCE_RESULT ", current_case, " ", record.state, " ", record.error, " seconds=", record.seconds)
		# Account failures are not a reason to spend the remaining quota.
		if "AUTH" in str(record.error) or "KEY_MISSING" in str(record.error) or "BALANCE" in str(record.error): break
	ui.free(); await process_frame
	print("ACCEPTANCE_EVIDENCE ", directory)
	var pipeline_and_save_passed: bool = records.size() == manifest.samples.size() and records.all(func(record: Dictionary) -> bool:
		var saved: Dictionary = record.get("save", {})
		return record.state == "success" and saved.get("ok", false) and saved.get("restored", false) and saved.get("pixels_identical", false) and saved.get("sunny_valid", false))
	# This is a technical pipeline result, never a semantic/art/playability vote.
	print("ACCEPTANCE_PIPELINE_AND_SAVE_PASSED ", pipeline_and_save_passed)
	quit(0 if pipeline_and_save_passed else 1)

func make_service() -> RefCounted:
	var service := SERVICE.new(); service.max_visual_requests = 1
	service.semantic_provider_factory = func(firearm: bool) -> RefCounted:
		var provider: RefCounted = SERVICE.FIREARM_PROVIDER.new() if firearm else SERVICE.OBJECT_PROVIDER.new()
		provider.output_root = directory.path_join(current_case + ("/semantic-firearm" if firearm else "/semantic-object"))
		semantic_outputs.append(provider.output_root)
		return provider
	service.visual_provider_factory = func(firearm: bool) -> RefCounted:
		var provider: RefCounted = SERVICE.FIREARM_VISUAL.new() if firearm else SERVICE.OBJECT_VISUAL.new()
		provider.cache_root = directory.path_join(current_case + "/fresh-visual-cache")
		provider.output_root = directory.path_join(current_case + "/visual-requests")
		return provider
	return service

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))

func write_json(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  ")); file.close()
