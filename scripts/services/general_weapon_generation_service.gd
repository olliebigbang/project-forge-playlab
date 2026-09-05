class_name GeneralWeaponGenerationService
extends RefCounted

const OBJECT_PROVIDER := preload("res://scripts/services/general_object_ai_provider.gd")
const OBJECT_RESOLVER := preload("res://scripts/combat_feel/general_object_ai_resolver.gd")
const FIREARM_PROVIDER := preload("res://scripts/services/firearm_identity_ai_provider.gd")
const FIREARM_RESOLVER := preload("res://scripts/combat_feel/firearm_identity_ai_resolver.gd")
const OBJECT_VISUAL := preload("res://scripts/services/fal_general_object_visual_provider.gd")
const FIREARM_VISUAL := preload("res://scripts/services/fal_firearm_visual_provider.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const FACTORY := preload("res://scripts/combat_feel/weapon_entry_factory.gd")
const CAPABILITIES := preload("res://scripts/combat_feel/weapon_capability_catalog.gd")
const ART_STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")

var state := "idle"
var identity := ""
var required_capability := ""
var python_executable := "python"
var semantic_provider: RefCounted
var visual_provider: RefCounted
var blueprint: WeaponBlueprint
var visual_requests := 0
var max_visual_requests := 2
var result: Dictionary = {}
var delivered := true
# Dependency injection is for offline contract tests; production always uses the
# same real semantic and visual providers as Forge.
var semantic_provider_factory: Callable
var visual_provider_factory: Callable
var use_semantic_cache := true
var art_style_id := ""
var semantic_cache_hit := false


func start(text: String, python_path: String = "python", capability: String = "") -> Dictionary:
	cancel_current()
	identity = text.strip_edges()
	python_executable = python_path
	required_capability = capability
	visual_requests = 0
	semantic_cache_hit = false
	result.clear()
	delivered = false
	if identity.is_empty():
		return _fail("WEAPON_GENERATION_IDENTITY_EMPTY")
	if not art_style_id.is_empty() and ART_STYLE.contract(art_style_id).is_empty():
		return _fail("WEAPON_GENERATION_ART_STYLE_UNKNOWN")
	if use_semantic_cache:
		var cached := OBJECT_RESOLVER.resolve_identity(identity)
		if bool(cached.get("ok", false)):
			semantic_cache_hit = true
			_accept_profile(cached, false)
			return _snapshot()
	_start_semantic(false)
	return _snapshot()


func poll() -> Dictionary:
	if state in ["success", "failed"]:
		if delivered:
			return {"status": "idle"}
		delivered = true
		return result.duplicate(true)
	if state in ["object_identity", "firearm_identity"]:
		var response: Dictionary = semantic_provider.poll()
		if str(response.get("status", "")) in ["idle", "running"]:
			return _snapshot()
		var firearm := state == "firearm_identity"
		if str(response.get("status", "")) != "success":
			return _fail(str(response.get("failure_reason", "WEAPON_GENERATION_SEMANTIC_FAILED")))
		var accepted: Dictionary
		if firearm:
			accepted = FIREARM_RESOLVER.accept_ai_response(identity, response.get("response", {}), str(response.get("source", "")), use_semantic_cache)
		else:
			accepted = OBJECT_RESOLVER.accept_ai_response(identity, response.get("response", {}), str(response.get("source", "")), use_semantic_cache)
		if not bool(accepted.get("ok", false)):
			if not firearm and str(accepted.get("error", "")) == "AI_GENERAL_OBJECT_FIREARM_ROUTE_REQUIRED":
				_start_semantic(true)
				return _snapshot()
			return _fail(str(accepted.get("error", "WEAPON_GENERATION_IDENTITY_REJECTED")))
		_accept_profile(accepted, firearm)
		return _snapshot()
	if state == "visual":
		var response: Dictionary = visual_provider.poll()
		if str(response.get("status", "")) in ["idle", "running"]:
			return _snapshot()
		var finished: Dictionary = FACTORY.finish(blueprint, response) if str(response.get("status", "")) == "success" else response
		if bool(finished.get("ok", false)) and not art_style_id.is_empty():
			var asset := finished.get("asset") as WeaponVisualAsset
			var report := ART_STYLE.inspect(asset.source_image if asset != null else null, art_style_id)
			var manifest: Dictionary = response.get("manifest", {})
			var declared: Dictionary = manifest.get("art_style", {})
			if not bool(report.get("ok", false)) or declared.get("id") != art_style_id or declared.get("version") != ART_STYLE.version(art_style_id):
				return _fail("WEAPON_GENERATION_ART_STYLE_VALIDATION_FAILED")
			blueprint.modifiers["art_style_report"] = report.duplicate(true)
			finished.visual_evidence["art_style"] = report.duplicate(true)
		if not bool(finished.get("ok", false)):
			if bool(finished.get("retry_required", false)) and visual_requests < max_visual_requests:
				blueprint.modifiers["mechanism_visual_retry_count"] = visual_requests
				blueprint.modifiers["mechanism_visual_retry_prompt"] = str(finished.get("retry_prompt", "Preserve the object identity and all declared structural parts with clean pixel edges."))
				_request_visual()
				return _snapshot()
			return _fail(str(finished.get("failure_reason", finished.get("error", "WEAPON_GENERATION_VISUAL_FAILED"))))
		state = "success"
		var manifest: Dictionary = response.get("manifest", {})
		var evidence := {"semantic_cache_hit": semantic_cache_hit, "visual_cache_hit": bool((manifest.get("cache", {}) as Dictionary).get("hit", false)), "art_style_id": art_style_id, "art_style_version": ART_STYLE.version(art_style_id) if not art_style_id.is_empty() else "", "visual_requests": visual_requests}
		finished.visual_evidence["generation"] = evidence.duplicate(true)
		result = {"ok": true, "status": "success", "entry": finished, "visual_requests": visual_requests, "generation_evidence": evidence, "player_confirmation_required": false}
		return poll()
	return _snapshot()


func _start_semantic(firearm: bool) -> void:
	if firearm and use_semantic_cache:
		var cached := FIREARM_RESOLVER.resolve_identity(identity)
		if bool(cached.get("ok", false)):
			semantic_cache_hit = true
			_accept_profile(cached, true)
			return
	state = "firearm_identity" if firearm else "object_identity"
	semantic_provider = semantic_provider_factory.call(firearm) if semantic_provider_factory.is_valid() else (FIREARM_PROVIDER.new() if firearm else OBJECT_PROVIDER.new())
	var configured: Dictionary = semantic_provider.configure(python_executable)
	if not bool(configured.get("ok", false)):
		_fail(str(configured.get("error", "WEAPON_GENERATION_SEMANTIC_UNAVAILABLE")))
		return
	semantic_provider.request_identity(identity)


func _accept_profile(profile: Dictionary, firearm: bool) -> void:
	var interpreted: Dictionary
	if firearm:
		interpreted = INTERPRETER.new().interpret_with_ai_firearm_profile(identity, PackedByteArray(), {}, profile)
	else:
		interpreted = INTERPRETER.new().interpret_with_ai_object_profile(identity, PackedByteArray(), {}, profile)
	if not bool(interpreted.get("ok", false)) or bool(interpreted.get("player_confirmation_required", true)):
		_fail(str(interpreted.get("error", "WEAPON_GENERATION_INTERPRETATION_FAILED")))
		return
	blueprint = interpreted.get("blueprint") as WeaponBlueprint
	if blueprint == null:
		_fail("WEAPON_GENERATION_BLUEPRINT_MISSING")
		return
	if not art_style_id.is_empty():
		blueprint.modifiers["art_style_id"] = art_style_id
		blueprint.modifiers["art_style_version"] = ART_STYLE.version(art_style_id)
	if not required_capability.is_empty() and required_capability not in CAPABILITIES.roles_for_blueprint(blueprint):
		_fail("WEAPON_GENERATION_CAPABILITY_MISMATCH")
		return
	visual_provider = visual_provider_factory.call(firearm) if visual_provider_factory.is_valid() else (FIREARM_VISUAL.new() if firearm else OBJECT_VISUAL.new())
	var configured: Dictionary = visual_provider.configure(python_executable)
	if not bool(configured.get("ok", false)):
		_fail(str(configured.get("error", "WEAPON_GENERATION_VISUAL_UNAVAILABLE")))
		return
	_request_visual()


func _request_visual() -> void:
	state = "visual"
	visual_requests += 1
	visual_provider.request_visual(blueprint, identity, PackedByteArray(), 0.0)


func cancel_current() -> void:
	for provider: Variant in [semantic_provider, visual_provider]:
		if provider != null and provider.has_method("cancel_current"):
			provider.cancel_current()
	semantic_provider = null
	visual_provider = null
	blueprint = null
	state = "idle"
	delivered = true


func _fail(error: String) -> Dictionary:
	state = "failed"
	result = {"ok": false, "status": "failed", "failure_reason": error, "error": error, "visual_requests": visual_requests, "player_confirmation_required": false}
	return result.duplicate(true)


func _snapshot() -> Dictionary:
	return result.duplicate(true) if state in ["success", "failed"] else {"ok": true, "status": "running" if state != "idle" else "idle", "stage": state, "visual_requests": visual_requests}
