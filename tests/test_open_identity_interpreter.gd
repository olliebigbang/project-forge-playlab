extends SceneTree

const INTERPRETER_SCRIPT := preload("res://scripts/services/open_identity_interpreter.gd")

const REQUIRED_CASES: Array[Dictionary] = [
	{"text": "会飞出去撞敌人再返回的木桌", "family": "returning_thrown"},
	{"text": "会连续发射螺丝的木椅", "family": "sustained_ranged"},
	{"text": "喷射高温蒸汽的旧茶壶", "family": "sustained_ranged"},
	{"text": "会吸血的巨大鸡腿", "family": "heavy_melee"},
	{"text": "能放出电流的机械雨伞", "family": "sustained_ranged"}
]

var passed := 0
var failed := 0

func _initialize() -> void:
	print("Forge Open Identity Interpretation Spike 2 tests")
	_run("Five required identities remain verbatim", _test_required_identities)
	_run("Three distinct identities share sustained behavior", _test_same_family_visual_diversity)
	_run("Object nouns never select behavior", _test_object_nouns_do_not_select_behavior)
	_run("Sketch-only input asks exact identity question", _test_sketch_only_clarification)
	_run("Structured sketch clarification continues without default", _test_structured_sketch_clarification)
	_run("Unclear behavior asks once and rejects an unclear answer", _test_behavior_clarification_once)
	_run("Conflicting behavior clues ask once instead of using priority", _test_behavior_conflict_clarification)
	_run("Fastener wording compiles to the generic fastener effect", _test_fastener_effect)
	_run("Text plus sketch preserves both evidence sources", _test_text_and_sketch_evidence)
	_run("Behavior delta cannot replace identity", _test_delta_preserves_identity)
	print("OPEN IDENTITY RESULT: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _run(test_name: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result == true:
		passed += 1
		print("PASS | %s" % test_name)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [test_name, str(result)])

func _test_required_identities() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	for test_case: Dictionary in REQUIRED_CASES:
		var original := str(test_case["text"])
		var result: Dictionary = interpreter.interpret(original, PackedByteArray(), {})
		if not bool(result.get("ok", false)) or bool(result.get("needs_clarification", true)):
			return "did not compile: %s" % original
		if bool(result.get("ai_interpretation_used", true)):
			return "falsely claimed AI interpretation: %s" % original
		if bool(result.get("identity_semantics_understood", true)):
			return "falsely claimed semantic understanding: %s" % original
		if not bool(result.get("identity_passthrough", false)):
			return "passthrough boundary missing: %s" % original
		var blueprint := result.get("blueprint") as WeaponBlueprint
		if blueprint == null:
			return "blueprint missing: %s" % original
		if blueprint.player_identity_text != original or blueprint.source_identity != original:
			return "identity text changed: %s" % original
		if blueprint.visual_description != original or blueprint.display_name != original:
			return "visual identity changed: %s" % original
		if blueprint.identity_confidence != 1.0:
			return "player-authoritative identity confidence changed: %s" % original
		if blueprint.behavior_family != str(test_case["family"]):
			return "wrong family for %s: %s" % [original, blueprint.behavior_family]
		if blueprint.weapon_form != "open_identity_object":
			return "behavior replaced weapon form: %s" % blueprint.weapon_form
		if not blueprint.visual_prompt.contains(original):
			return "generation prompt omitted verbatim identity: %s" % original
		for fixed_form: String in ["heavy_gatling", "mechanical_umbrella", "chainsaw_greatsword"]:
			if fixed_form in [blueprint.weapon_form, blueprint.id, blueprint.visual_description, blueprint.visual_prompt]:
				return "fixed visual replacement leaked: %s" % fixed_form
	return true

func _test_same_family_visual_diversity() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	var sustained_identities: Dictionary = {}
	for test_case: Dictionary in REQUIRED_CASES:
		var result: Dictionary = interpreter.interpret(str(test_case["text"]), PackedByteArray(), {})
		var blueprint := result.get("blueprint") as WeaponBlueprint
		if blueprint != null and blueprint.behavior_family == "sustained_ranged":
			sustained_identities[blueprint.player_identity_text] = true
	if sustained_identities.size() != 3:
		return "expected chair, teapot, and mechanical umbrella in one family; got %s" % str(sustained_identities.keys())
	return true

func _test_object_nouns_do_not_select_behavior() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	for noun_only: String in ["木桌", "木椅", "旧茶壶", "巨大鸡腿", "机械雨伞"]:
		var result: Dictionary = interpreter.interpret(noun_only, PackedByteArray(), {})
		if not bool(result.get("needs_clarification", false)):
			return "object noun selected a behavior: %s" % noun_only
		if str(result.get("clarification_kind", "")) != "behavior":
			return "wrong clarification kind for %s" % noun_only
	return true

func _test_sketch_only_clarification() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	var sketch := PackedByteArray([137, 80, 78, 71])
	var result: Dictionary = interpreter.interpret("", sketch, {"stroke_count": 3})
	if not bool(result.get("ok", false)) or not bool(result.get("needs_clarification", false)):
		return "sketch-only input did not clarify"
	if str(result.get("clarification_kind", "")) != "identity":
		return "sketch-only clarification was not identity"
	return str(result.get("question", "")) == "你画的是什么？" if str(result.get("question", "")) != "" else "identity question missing"

func _test_structured_sketch_clarification() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	var sketch := PackedByteArray([1, 2, 3])
	var clarification := "IDENTITY::一块无法画清的抽象物件::BEHAVIOR::returning_thrown"
	var result: Dictionary = interpreter.interpret("", sketch, {"aspect_ratio": 1.3}, null, "", clarification)
	if not bool(result.get("ok", false)) or bool(result.get("needs_clarification", true)):
		return "structured clarification did not continue"
	var blueprint := result.get("blueprint") as WeaponBlueprint
	if blueprint == null:
		return "blueprint missing"
	if blueprint.player_identity_text != "一块无法画清的抽象物件":
		return "clarified identity not preserved"
	if blueprint.behavior_family != "returning_thrown":
		return "explicit behavior not honored"
	return blueprint.weapon_form == "open_identity_object"

func _test_behavior_clarification_once() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	var first: Dictionary = interpreter.interpret("一只旧水壶", PackedByteArray(), {})
	if not bool(first.get("needs_clarification", false)) or str(first.get("clarification_kind", "")) != "behavior":
		return "first gameplay clarification missing"
	var second: Dictionary = interpreter.interpret("一只旧水壶", PackedByteArray(), {}, null, "", "说不清")
	if bool(second.get("needs_clarification", true)):
		return "unclear gameplay answer asked a second time"
	if bool(second.get("ok", true)) or str(second.get("error", "")) != "BEHAVIOR_CLARIFICATION_UNRECOGNIZED":
		return "unclear answer did not fail explicitly"
	var accepted: Dictionary = interpreter.interpret("一只旧水壶", PackedByteArray(), {}, null, "", "BEHAVIOR::sustained_ranged")
	if not bool(accepted.get("ok", false)):
		return "explicit family answer rejected"
	var blueprint := accepted.get("blueprint") as WeaponBlueprint
	return blueprint != null and blueprint.player_identity_text == "一只旧水壶" and blueprint.behavior_family == "sustained_ranged"

func _test_behavior_conflict_clarification() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	var identity := "会连续发射后再飞出去返回的普通物件"
	var first: Dictionary = interpreter.interpret(identity, PackedByteArray(), {})
	if not bool(first.get("needs_clarification", false)):
		return "conflicting action clues were silently prioritized"
	if str(first.get("clarification_kind", "")) != "behavior" or str(first.get("reason", "")) != "behavior_action_conflict":
		return "conflict did not use the behavior clarification boundary"
	var candidates: Array = first.get("behavior_candidates", [])
	if candidates.size() != 2 or not candidates.has("sustained_ranged") or not candidates.has("returning_thrown"):
		return "conflict candidates were not recorded"
	var unclear: Dictionary = interpreter.interpret(identity, PackedByteArray(), {}, null, "", "仍然都要")
	if bool(unclear.get("needs_clarification", true)) or str(unclear.get("error", "")) != "BEHAVIOR_CLARIFICATION_UNRECOGNIZED":
		return "unclear conflict answer asked more than once"
	var resolved: Dictionary = interpreter.interpret(identity, PackedByteArray(), {}, null, "", "BEHAVIOR::returning_thrown")
	var blueprint := resolved.get("blueprint") as WeaponBlueprint
	return blueprint != null and blueprint.behavior_family == "returning_thrown" and blueprint.player_identity_text == identity

func _test_fastener_effect() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	var result: Dictionary = interpreter.interpret("会连续发射螺丝的普通物件", PackedByteArray(), {})
	var blueprint := result.get("blueprint") as WeaponBlueprint
	if blueprint == null or blueprint.effect_type != "forge_fastener" or blueprint.delivery != "continuous_emission":
		return "fastener behavior fields were not compiled"
	if not blueprint.visual_prompt.contains("delivery action continuous emission"):
		return "generic delivery contract was omitted from visual prompt"
	return blueprint.visual_prompt.contains("effect forge fastener") and blueprint.visual_prompt.contains(blueprint.player_identity_text)

func _test_text_and_sketch_evidence() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	var original := "会连续放出光点的手绘物件"
	var result: Dictionary = interpreter.interpret(original, PackedByteArray([4, 5, 6]), {
		"stroke_count": 4, "aspect_ratio": 2.75, "dominant_axis": "horizontal"
	})
	var blueprint := result.get("blueprint") as WeaponBlueprint
	if blueprint == null or blueprint.player_identity_text != original:
		return "text identity not preserved"
	if not blueprint.preserved_visual_features.has("rough_player_sketch_present"):
		return "sketch presence omitted"
	if not blueprint.preserved_visual_features.has("sketch_dominant_axis=horizontal"):
		return "sketch axis omitted"
	return is_equal_approx(blueprint.silhouette_aspect, 2.75) and blueprint.visual_prompt.contains("sketch_aspect_ratio=2.750")

func _test_delta_preserves_identity() -> Variant:
	var interpreter: WeaponInterpreter = INTERPRETER_SCRIPT.new()
	var original := "会连续发射碎屑的纸盒"
	var initial: Dictionary = interpreter.interpret(original, PackedByteArray(), {})
	var blueprint := initial.get("blueprint") as WeaponBlueprint
	var changed: Dictionary = interpreter.apply_delta(blueprint, "改成飞出去再返回")
	var changed_blueprint := changed.get("blueprint") as WeaponBlueprint
	if changed_blueprint == null:
		return "delta blueprint missing"
	if changed_blueprint.behavior_family != "returning_thrown":
		return "behavior delta not applied"
	return changed_blueprint.player_identity_text == original and changed_blueprint.source_identity == original and changed_blueprint.visual_description == original and changed_blueprint.visual_prompt.contains(original)
