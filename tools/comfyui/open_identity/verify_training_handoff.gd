extends SceneTree

const PROVIDER := preload("res://scripts/services/local_comfy_forge_visual_provider.gd")
const ARENA := preload("res://scripts/systems/open_identity_training_arena.gd")
const CASES_PATH := "res://tools/comfyui/open_identity/reports/compiled_cases.json"
const RESULT_PATH := "res://tools/comfyui/open_identity/output/spike2_case_03/seed_52002_policy1"

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CASES_PATH))
	if not parsed is Dictionary:
		_fail("COMPILED_CASES_INVALID")
		return
	var blueprint: WeaponBlueprint
	for value: Variant in (parsed as Dictionary).get("cases", []):
		var test_case := value as Dictionary
		if str(test_case.get("case_id", "")) == "spike2_case_03":
			blueprint = WeaponBlueprint.from_dict(test_case.get("blueprint", {}))
			break
	if blueprint == null:
		_fail("OPEN_IDENTITY_BLUEPRINT_MISSING")
		return
	var provider = PROVIDER.new()
	var result: Dictionary = provider.load_atomic_result(RESULT_PATH, blueprint)
	if str(result.get("status", "")) != "success":
		_fail(str(result.get("failure_reason", "ATOMIC_RESULT_LOAD_FAILED")))
		return
	var asset := result.get("asset") as WeaponVisualAsset
	if asset == null or asset.canvas_size != Vector2i(96, 96):
		_fail("TRAINING_ASSET_INVALID")
		return
	var arena := ARENA.new() as OpenIdentityTrainingArena
	root.add_child(arena)
	arena.start_stage("training", blueprint, asset)
	if arena.stage_name != "training" or arena.blueprint.player_identity_text != blueprint.player_identity_text:
		_fail("TRAINING_IDENTITY_HANDOFF_FAILED")
		return
	print("SPIKE2_TRAINING_HANDOFF=PASS IDENTITY=%s STAGE=%s SIZE=%s" % [
		blueprint.player_identity_text, arena.stage_name, asset.canvas_size
	])
	quit(0)

func _fail(reason: String) -> void:
	printerr("SPIKE2_TRAINING_HANDOFF=FAIL REASON=%s" % reason)
	quit(2)
