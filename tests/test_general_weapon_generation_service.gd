extends SceneTree

const SERVICE := preload("res://scripts/services/general_weapon_generation_service.gd")
const DIRECTOR := preload("res://scripts/combat_feel/automatic_armory_director.gd")
const AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const GENERAL_SCAFFOLD := preload("res://scripts/combat_feel/mechanism_visual_scaffold_pipeline.gd")
const FIREARM_SCAFFOLD := preload("res://scripts/combat_feel/firearm_visual_scaffold_pipeline.gd")
const STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")

class SemanticFixture extends RefCounted:
	var response: Dictionary = {}
	var requested := ""
	var cancelled := false
	func configure(_python: String) -> Dictionary:
		return {"ok": true}
	func request_identity(identity: String) -> void:
		requested = identity
	func poll() -> Dictionary:
		return {"status": "success", "response": response, "source": "AI_OFFLINE_CONTRACT_TEST"}
	func cancel_current() -> void:
		cancelled = true

class VisualFixture extends RefCounted:
	var requests := 0
	var cancelled := false
	var failure: Dictionary = {}
	var output: Dictionary = {}
	var style_enabled := false
	func configure(_python: String) -> Dictionary:
		return {"ok": true}
	func request_visual(blueprint: WeaponBlueprint, _identity: String, _sketch: PackedByteArray, _weight: float) -> void:
		requests += 1
		var firearm := str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm"
		var art: Dictionary = FIREARM_SCAFFOLD.fallback(blueprint) if firearm else GENERAL_SCAFFOLD.fallback(blueprint)
		# Explicit test double: this is not evidence that an online image passed.
		output = {"status": "success", "asset": art.get("asset"), "manifest": {"visual_mode": "offline_contract_test", "firearm_visual_identity_gate": {"ok": true, "source": "OFFLINE_TEST_ONLY"}}}
		if style_enabled:
			var asset: WeaponVisualAsset = output.asset
			var normalized := STYLE.normalize(asset.source_image, str(blueprint.modifiers.get("art_style_id", "")))
			asset.source_image = normalized.image
			asset.texture = ImageTexture.create_from_image(asset.source_image)
			output.manifest["art_style"] = STYLE.contract("church_v1")
			output.manifest["cache"] = {"hit": true}
	func poll() -> Dictionary:
		return failure if not failure.is_empty() else output
	func cancel_current() -> void:
		cancelled = true

class CandidateFixture extends RefCounted:
	var requests := 0
	var cancelled := false
	func configure(_python: String) -> Dictionary:
		return {"ok": true}
	func request_candidate(_role: String, _existing: Array[String], _excluded: Array[String]) -> void:
		requests += 1
	func poll() -> Dictionary:
		return {"status": "success", "candidate": {"canonical_name": "offline object %d" % requests, "selection_reason_zh": "离线失败边界测试"}}
	func cancel_current() -> void:
		cancelled = true

class FailingGenerator extends RefCounted:
	var max_visual_requests := 2
	var cancelled := false
	func start(_identity: String, _python: String, _capability: String) -> Dictionary:
		return {"status": "running"}
	func poll() -> Dictionary:
		return {"status": "failed", "failure_reason": "OFFLINE_TEST_REJECTED", "visual_requests": max_visual_requests}
	func cancel_current() -> void:
		cancelled = true

var passed := 0
var failed := 0

func _initialize() -> void:
	OS.set_environment("FORGE_WEAPON_LIBRARY_ROOT", ProjectSettings.globalize_path("res://screenshots/generation_contract_%d" % Time.get_ticks_usec()))
	call_deferred("_run")

func _run() -> void:
	check("ordinary object recognition reaches compiled complete entry", _general_success)
	check("AI firearm classification routes through firearm compiler", _firearm_success)
	check("capability mismatch stops before requesting an image", _capability_reject)
	check("unsupported actors fail without guessing or player mechanism questions", _unsupported)
	check("visual retries have a hard cap and deliver no false success", _visual_budget)
	check("cancel stops both providers", _cancel)
	check("background candidate and image budgets are bounded and rejection persists", _director_budget)
	check("unknown art style stops before any provider", _unknown_style)
	check("unstyled provider cannot masquerade as Church art", _missing_style)
	check("style technical evidence persists with entry and cache provenance", _styled_success)
	print("GENERAL_WEAPON_GENERATION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(label: String, test: Callable) -> void:
	var outcome: Variant = test.call()
	if outcome is bool and outcome:
		passed += 1
		print("PASS | " + label)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [label, str(outcome)])

func payload(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary

func inert(identity: String, classification: String) -> Dictionary:
	var declaration := {}
	for axis: String in AXES.REQUIRED_AXES:
		declaration[axis] = "not_applicable"
	for flag: String in AXES.REQUIRED_FLAGS:
		declaration[flag] = false
	return {"schema": "forge-general-object-ai-response-v1", "requested_identity": identity, "classification": classification, "canonical_name": identity, "confidence": 0.97, "identity_evidence": ["separate runtime required"], "visual_description_en": "", "required_identity_parts_zh": [], "confusable_exclusions_en": [], "mechanism_roles": {"grip_part_zh": "", "activation_part_zh": "", "effect_origin_part_zh": ""}, "behavior_family": "not_applicable", "scale_treatment": "not_applicable", "declaration": declaration}

func fixture_service(semantic: SemanticFixture, visual: VisualFixture) -> RefCounted:
	var service := SERVICE.new()
	service.use_semantic_cache = false
	service.semantic_provider_factory = func(_firearm: bool) -> RefCounted: return semantic
	service.visual_provider_factory = func(_firearm: bool) -> RefCounted: return visual
	return service

func finish(service: RefCounted) -> Dictionary:
	for index: int in range(12):
		var result: Dictionary = service.poll()
		if result.get("status") in ["success", "failed"]:
			return result
	return {"error": "did not terminate"}

func _general_success() -> Variant:
	var semantic := SemanticFixture.new()
	semantic.response = payload("res://tests/fixtures/general_object_ai_fridge_response.json")
	var visual := VisualFixture.new()
	var service := fixture_service(semantic, visual)
	service.start("冰箱")
	var result := finish(service)
	return true if result.get("ok", false) and result.entry.get("affordance_profile") != null and visual.requests == 1 else result

func _firearm_success() -> Variant:
	var general := SemanticFixture.new()
	general.response = inert("AK-47", "firearm_route_required")
	var firearm := SemanticFixture.new()
	firearm.response = payload("res://tests/fixtures/firearm_ai_ak47_response.json")
	var visual := VisualFixture.new()
	var service := fixture_service(general, visual)
	service.semantic_provider_factory = func(is_firearm: bool) -> RefCounted: return firearm if is_firearm else general
	service.start("AK-47")
	var result := finish(service)
	return true if result.get("ok", false) and result.entry.ranged_runtime_profile.get("ok", false) and firearm.requested == "AK-47" else result

func _capability_reject() -> Variant:
	var semantic := SemanticFixture.new()
	semantic.response = payload("res://tests/fixtures/general_object_ai_fridge_response.json")
	var visual := VisualFixture.new()
	var service := fixture_service(semantic, visual)
	service.start("冰箱", "unused", "breach")
	var result := finish(service)
	return result.get("error") == "WEAPON_GENERATION_CAPABILITY_MISMATCH" and visual.requests == 0

func _unsupported() -> Variant:
	var semantic := SemanticFixture.new()
	semantic.response = inert("坦克", "powered_vehicle_actor_required")
	var visual := VisualFixture.new()
	var service := fixture_service(semantic, visual)
	service.start("坦克")
	var result := finish(service)
	return true if result.get("error") == "AI_GENERAL_OBJECT_POWERED_VEHICLE_ACTOR_REQUIRED" and not result.get("player_confirmation_required", true) and visual.requests == 0 else result

func _visual_budget() -> Variant:
	var semantic := SemanticFixture.new()
	semantic.response = payload("res://tests/fixtures/general_object_ai_fridge_response.json")
	var visual := VisualFixture.new()
	visual.failure = {"status": "failed", "failure_reason": "TEST_BAD_ART", "retry_required": true}
	var service := fixture_service(semantic, visual)
	service.start("冰箱")
	var result := finish(service)
	return result.get("status") == "failed" and visual.requests == 2 and result.visual_requests == 2

func _cancel() -> Variant:
	var semantic := SemanticFixture.new()
	semantic.response = payload("res://tests/fixtures/general_object_ai_fridge_response.json")
	var visual := VisualFixture.new()
	var service := fixture_service(semantic, visual)
	service.start("冰箱")
	service.poll()
	service.cancel_current()
	return semantic.cancelled and visual.cancelled and service.poll().get("status") == "idle"

func _director_budget() -> Variant:
	var director := DIRECTOR.new()
	var candidate := CandidateFixture.new()
	director.candidate_provider_factory = func() -> RefCounted: return candidate
	director.generation_service_factory = func() -> RefCounted: return FailingGenerator.new()
	director.start([])
	var result := finish(director)
	var rejected: Array[String] = DIRECTOR.new()._recent_rejected_identities()
	return true if result.get("status") == "failed" and result.total_visual_requests == 3 and candidate.requests == 2 and rejected.size() == 2 else result

func _unknown_style() -> Variant:
	var service := SERVICE.new()
	service.art_style_id = "unknown"
	return service.start("anything").get("error") == "WEAPON_GENERATION_ART_STYLE_UNKNOWN" and service.semantic_provider == null and service.visual_requests == 0

func _missing_style() -> Variant:
	var semantic := SemanticFixture.new()
	semantic.response = payload("res://tests/fixtures/general_object_ai_fridge_response.json")
	var service := fixture_service(semantic, VisualFixture.new())
	service.art_style_id = "church_v1"
	service.start("冰箱")
	return finish(service).get("error") == "WEAPON_GENERATION_ART_STYLE_VALIDATION_FAILED"

func _styled_success() -> Variant:
	var semantic := SemanticFixture.new()
	semantic.response = payload("res://tests/fixtures/general_object_ai_fridge_response.json")
	var visual := VisualFixture.new()
	visual.style_enabled = true
	var service := fixture_service(semantic, visual)
	service.art_style_id = "church_v1"
	service.start("冰箱")
	var result := finish(service)
	return true if result.get("ok", false) and result.entry.visual_evidence.art_style.ok and result.entry.blueprint.modifiers.art_style_report.id == "church_v1" and result.generation_evidence.visual_cache_hit and not result.generation_evidence.semantic_cache_hit else result
