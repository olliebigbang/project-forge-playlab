extends SceneTree
## Offline UI contracts. Synthetic provider results are labelled fixtures;
## save calls go only to an in-memory test double, never the player's library.
const UI := preload("res://scripts/art_vertical_slice_v1/church_forge.gd")
const RESOLVER := preload("res://scripts/combat_feel/general_object_ai_resolver.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const SCAFFOLD := preload("res://scripts/combat_feel/mechanism_visual_scaffold_pipeline.gd")
const FACTORY := preload("res://scripts/combat_feel/weapon_entry_factory.gd")
const ART_STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")
const LIBRARY := preload("res://scripts/combat_feel/weapon_library_store.gd")

class FakeService extends RefCounted:
	var art_style_id := ""
	var use_semantic_cache := true
	var starts := 0
	var cancels := 0
	var requested := ""
	var reply: Dictionary = {"status": "running", "stage": "object_identity"}
	func start(text: String, _python: String) -> Dictionary:
		starts += 1
		requested = text
		return {"ok": true, "status": "running", "stage": "object_identity"}
	func poll() -> Dictionary: return reply
	func cancel_current() -> void: cancels += 1

class FakeArena extends GameplayArena:
	var starts := 0
	var received_profiles: Array[Dictionary] = []
	func start_stage(_stage: String, bp: WeaponBlueprint, pixels: WeaponVisualAsset, profiles: Array[Dictionary] = []) -> void:
		starts += 1
		blueprint = bp
		asset = pixels
		received_profiles = profiles.duplicate(true)
		enemies = [{"hp": 60.0, "pos": Vector2(700, 470)}, {"hp": 60.0, "pos": Vector2(990, 545)}]
		metrics = {"damage_taken": 0.0}
		active = true
	func _process(_delta: float) -> void: pass

var passed := 0
var failed := 0
var fixture_entry: Dictionary = {}


func _initialize() -> void:
	# Defensive even though no production services/store methods are invoked.
	for name: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]: OS.unset_environment(name)
	call_deferred("_run")


func _check(label: String, value: bool) -> void:
	if value: passed += 1; print("PASS | ", label)
	else: failed += 1; printerr("FAIL | ", label)


func _fixture() -> Dictionary:
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/general_object_ai_fridge_response.json"))
	var accepted: Dictionary = RESOLVER.validate_ai_response("冰箱", payload, "AI_OFFLINE_CHURCH_UI_FIXTURE")
	var interpreted: Dictionary = INTERPRETER.new().interpret_with_ai_object_profile("冰箱", PackedByteArray(), {}, accepted.profile)
	var bp: WeaponBlueprint = interpreted.blueprint
	var art: Dictionary = SCAFFOLD.fallback(bp)
	var normalized: Dictionary = ART_STYLE.normalize(art.asset.source_image, "church_v1")
	art.asset.source_image = normalized.image
	art.asset.texture = ImageTexture.create_from_image(normalized.image)
	bp.modifiers["art_style_id"] = "church_v1"
	bp.modifiers["art_style_version"] = ART_STYLE.VERSION
	bp.modifiers["art_style_report"] = ART_STYLE.inspect(normalized.image, "church_v1")
	var result: Dictionary = FACTORY.finish(bp, {"asset": art.asset, "manifest": {"visual_mode": "offline_contract_fixture_not_online_evidence"}})
	result.visual_evidence["art_style"] = bp.modifiers.art_style_report.duplicate(true)
	return result


func _success() -> Dictionary:
	return {"ok": true, "status": "success", "entry": fixture_entry, "generation_evidence": {"semantic_cache_hit": true, "visual_cache_hit": false, "art_style_id": "church_v1", "art_style_version": "offline_fixture", "visual_requests": 1}}


func _ui(service: FakeService, saves: Dictionary) -> Node2D:
	var ui := UI.new()
	ui.configure_dependencies(func() -> RefCounted: return service, func(_entry: Dictionary) -> Dictionary:
		saves.count += 1
		return saves.get("reply", {"ok": true, "library_key": "in-memory-fixture-only"})
	, func() -> GameplayArena: return FakeArena.new())
	ui.initialize_ui()
	return ui


func _run() -> void:
	fixture_entry = _fixture()
	_check("Offline synthetic fixture has a complete mechanism contract", bool(fixture_entry.get("ok", false)) and bool(UI.validate_entry(fixture_entry).get("ok", false)))
	fixture_entry.blueprint.modifiers.art_style_id = "old_style"
	_check("Blueprint cannot spoof another style as Church", not UI.validate_entry(fixture_entry).ok)
	fixture_entry.blueprint.modifiers.art_style_id = "church_v1"
	var original_count: int = fixture_entry.visual_evidence.art_style.color_count
	fixture_entry.visual_evidence.art_style.color_count = original_count + 1
	_check("Stale technical report is rejected against actual pixels", not UI.validate_entry(fixture_entry).ok)
	fixture_entry.visual_evidence.art_style.color_count = original_count
	var pixel := Vector2i.ZERO
	var image: Image = fixture_entry.asset.source_image
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0: pixel = Vector2i(x, y)
	var original_color := image.get_pixelv(pixel)
	image.set_pixelv(pixel, Color.WHITE)
	_check("Actual off-palette pixels cannot pass on evidence strings", not UI.validate_entry(fixture_entry).ok)
	image.set_pixelv(pixel, original_color)
	var original_texture: Texture2D = fixture_entry.asset.texture
	var wrong_texture := image.duplicate() as Image
	wrong_texture.set_pixelv(pixel, Color.TRANSPARENT)
	fixture_entry.asset.texture = ImageTexture.create_from_image(wrong_texture)
	_check("Displayed texture must match inspected source pixels", not UI.validate_entry(fixture_entry).ok)
	fixture_entry.asset.texture = original_texture
	var fake := FakeService.new()
	var saves := {"count": 0}
	var ui := _ui(fake, saves)
	_check("Opening Forge does not create service, select sample, or start combat", ui.state == "idle" and ui.service == null and ui.entry.is_empty() and ui.arena.starts == 0 and saves.count == 0)
	var empty: Dictionary = ui.begin_generation("  ")
	_check("Empty input fails before any provider call", not empty.ok and ui.state == "failed" and fake.starts == 0)
	ui.begin_generation("字".repeat(161))
	_check("Oversized input is bounded before provider calls", ui.error_code == "CHURCH_FORGE_IDENTITY_TOO_LONG" and fake.starts == 0)
	ui.begin_generation("  一个没有在样品列表中的东西  ")
	_check("Arbitrary identity goes to service without a name whitelist", fake.requested == "一个没有在样品列表中的东西" and ui.state == "generating")
	_check("Church style and semantic-cache policy reach service", fake.art_style_id == "church_v1" and fake.use_semantic_cache)
	var busy: Dictionary = ui.begin_generation("不应并行请求")
	_check("Repeated generate click cannot overlap paid requests", not busy.ok and fake.starts == 1)
	fake.reply = {"status": "running", "stage": "visual", "visual_requests": 1}
	ui.poll_generation()
	_check("Progress displays actual provider phase", ui.generation_stage == "visual" and ui.visual_requests == 1)
	fake.reply = {"status": "failed", "failure_reason": "OFFLINE_TEST_REJECTED"}
	ui.poll_generation()
	_check("Failure clears entry and never starts combat or saves", ui.state == "failed" and ui.entry.is_empty() and ui.arena.starts == 0 and saves.count == 0)
	_check("Failure cannot be bypassed by enter-battle action", not ui.enter_battle().ok and ui.arena.starts == 0)
	ui.begin_generation("取消的输入")
	var stale_token: int = ui.generation_token
	ui.cancel_generation()
	_check("Cancel stops service and retains the description", ui.state == "cancelled" and fake.cancels == 1 and ui.input_text == "取消的输入")
	_check("Cancelled success is ignored rather than resurrected", not ui.accept_generation_result(stale_token, _success()) and ui.entry.is_empty())
	ui.begin_generation("当前输入")
	_check("Old request cannot overwrite a newer request", not ui.accept_generation_result(stale_token, _success()) and ui.state == "generating")
	ui.accept_generation_result(ui.generation_token, {"ok": true, "status": "success", "entry": {}})
	_check("Success status without real validated pixels is rejected", ui.state == "failed" and ui.entry.is_empty())
	ui.begin_generation("缺少风格证据")
	var no_style: Dictionary = _success()
	no_style["generation_evidence"] = {}
	ui.accept_generation_result(ui.generation_token, no_style)
	_check("Missing Church style evidence does not silently reuse old art", ui.state == "failed" and ui.error_code == "CHURCH_FORGE_STYLE_EVIDENCE_MISSING")
	ui.begin_generation("当前物品描述")
	ui.accept_generation_result(ui.generation_token, _success())
	_check("Valid success exposes the exact asset and no automatic save", ui.state == "success" and ui.entry.asset == fixture_entry.asset and saves.count == 0)
	_check("Semantic and image source are labelled independently", "语义：已验证缓存" in ui.provenance.text and "图像：实时 AI" in ui.provenance.text)
	_check("Unknown provenance is not labelled live AI", "来源未标注" in UI.source_summary({}) and "实时 AI" not in UI.source_summary({}))
	var entered: Dictionary = ui.enter_battle()
	_check("Battle receives the generated blueprint and pixels unchanged", entered.ok and ui.state == "combat" and ui.arena.blueprint == fixture_entry.blueprint and ui.arena.asset == fixture_entry.asset and ui.arena.received_profiles.size() == 2)
	_check("Entering battle does not persist or equip the weapon", saves.count == 0 and not ui.saved)
	ui._on_battle_complete("fixture", {})
	_check("Enemy still alive cannot award victory", ui.state == "combat")
	ui.arena.enemies.clear()
	ui.arena.metrics["damage_taken"] = 100.0
	ui._on_battle_complete("fixture", {})
	ui._process(0.0)
	_check("Lethal frame wins no false victory and closes defeat", ui.state == "defeated" and not ui.arena.active)
	ui.return_to_forge()
	_check("Returning retains generated entry, description and preview", ui.state == "success" and ui.entry.asset == fixture_entry.asset and ui.input_text == "当前物品描述" and ui.forge_page.visible)
	ui.enter_battle()
	ui.arena.enemies.clear()
	ui._on_battle_complete("fixture", {})
	_check("Genuine clear ends battle without implicit saving", ui.state == "victory" and saves.count == 0)
	ui.restart_battle()
	_check("Retry uses the same weapon and a fresh encounter", ui.state == "combat" and ui.arena.starts == 3 and ui.arena.enemies.size() == 2)
	ui.return_to_forge()
	saves["reply"] = {"ok": false, "error": "OFFLINE_SAVE_FAILURE"}
	ui.save_current_entry()
	_check("Save failure keeps usable entry and allows explicit retry", not ui.saved and ui.state == "success" and ui.save_error == "OFFLINE_SAVE_FAILURE" and saves.count == 1)
	saves["reply"] = {"ok": true, "library_key": "in-memory-fixture-only"}
	ui.save_current_entry()
	ui.save_current_entry()
	_check("Only explicit save writes once after success", ui.saved and ui.entry.library_key == "in-memory-fixture-only" and saves.count == 2)
	_check("All major UI controls stay inside the 1280x720 canvas", Rect2(0, 0, 1280, 720).encloses(ui.input_field.get_rect()) and Rect2(0, 0, 1280, 720).encloses(ui.battle_button.get_rect()) and Rect2(0, 0, 1280, 720).encloses(ui.save_button.get_rect()))
	ui.free()
	print("CHURCH_FORGE_TESTS passed=%d failed=%d" % [passed, failed])
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--saved-library="):
			_check_saved_library(argument.trim_prefix("--saved-library="))
			break
	quit(0 if failed == 0 else 1)


func _check_saved_library(requested_path: String) -> void:
	var prior_passed := passed
	var prior_failed := failed
	var path := requested_path.replace("\\", "/")
	if not path.is_absolute_path() and not path.begins_with("res://"):
		path = "res://".path_join(path)
	path = ProjectSettings.globalize_path(path).simplify_path()
	if requested_path.strip_edges().is_empty() or not DirAccess.dir_exists_absolute(path.path_join("weapons")):
		_check("Explicit saved-library path contains a weapon package directory", false)
		print("CHURCH_FORGE_SAVED_LIBRARY_TESTS loaded=0 passed=0 failed=1")
		return
	var library := LIBRARY.new()
	# Deliberately override the instance only: no environment changes and no
	# implicit access to the player's default store. load_entries is read-only.
	library.root_path = path
	var restored: Array[Dictionary] = library.load_entries()
	if restored.is_empty(): _check("Explicit saved library contains accepted entries", false)
	if not library.diagnostics.is_empty():
		_check("Explicit saved library has no rejected packages", false)
		print("CHURCH_FORGE_SAVED_LIBRARY_REJECTIONS ", JSON.stringify(library.diagnostics))
	for restored_entry: Dictionary in restored:
		var validation: Dictionary = UI.validate_entry(restored_entry)
		var accepted := false
		var battle_started := false
		var returned := false
		var exact_handoff := false
		var calls := {"save": 0}
		var fake := FakeService.new()
		var ui := UI.new()
		ui.configure_dependencies(func() -> RefCounted: return fake, func(_entry: Dictionary) -> Dictionary:
			calls.save += 1
			return {"ok": false, "error": "READ_ONLY_RESTORE_TEST_FORBIDS_SAVE"}
		)
		ui.initialize_ui() # Actual ChurchArena; no fake combat implementation.
		if bool(validation.get("ok", false)):
			var identity := str(restored_entry.blueprint.player_identity_text)
			ui.begin_generation(identity) # In-memory FakeService only, no provider.
			var modifiers: Dictionary = restored_entry.blueprint.modifiers
			# Replay the saved entry through the success handoff. Historical cache
			# hit flags are not in the library payload, so leave them unknown rather
			# than inventing another live generation or semantic-cache claim.
			ui.accept_generation_result(ui.generation_token, {
				"ok": true, "status": "success", "entry": restored_entry,
				"generation_evidence": {"art_style_id": modifiers.get("art_style_id", ""), "art_style_version": modifiers.get("art_style_version", ""), "source": "explicit_saved_library_read_only_restore"},
			})
			accepted = ui.state == "success"
			var started: Dictionary = ui.enter_battle()
			battle_started = bool(started.get("ok", false)) and ui.state == "combat"
			exact_handoff = ui.arena.asset == restored_entry.asset and ui.arena.blueprint == restored_entry.blueprint
			if battle_started: ui._process(1.0 / 60.0)
			ui.return_to_forge()
			returned = ui.state == "success" and ui.entry.asset == restored_entry.asset and ui.input_text == identity
		var ok: bool = bool(validation.get("ok", false)) and accepted and battle_started and exact_handoff and returned and calls.save == 0 and str(ui.arena.melee_runtime.error).is_empty()
		_check("Saved real entry passes strict pixels/reports and UI battle return: " + str(restored_entry.display_name), ok)
		print("CHURCH_FORGE_SAVED_ENTRY ", JSON.stringify({"identity": restored_entry.display_name, "library_key": restored_entry.library_key, "validation": validation, "ui_success": accepted, "battle_started": battle_started, "exact_asset_handoff": exact_handoff, "returned_with_entry": returned, "save_calls": calls.save, "online_calls": false, "runtime_error": ui.arena.melee_runtime.error, "source": "read_only_saved_entry_not_new_generation"}))
		ui.free()
	print("CHURCH_FORGE_SAVED_LIBRARY_TESTS loaded=%d passed=%d failed=%d" % [restored.size(), passed - prior_passed, failed - prior_failed])
