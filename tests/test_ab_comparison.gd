extends SceneTree

## An A/B switch is only worth having if the two sides differ, and worth trusting only if it
## says how. Three rounds of playtesting compared assets across a relaunch and reported no
## difference, which cannot distinguish "too small to feel" from "identical by mistake".

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const COMPARE := preload("res://scripts/combat_feel/ab_comparison.gd")

const EXPECTED_CHECKS := 3

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_the_same_profile_against_itself_differs_in_nothing()
	_test_a_material_swap_names_the_channels_it_moves()
	var ran := passed + failed
	if ran != EXPECTED_CHECKS:
		failed += 1
		push_error("FAIL %d checks ran, expected %d -- a test aborted part-way" % [ran, EXPECTED_CHECKS])
	print("AB_COMPARISON_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


## The control the playtests kept needing and never had in code. If a comparison is set up
## against itself the switch has to say so, rather than letting a player spend twenty rounds
## failing to feel a difference that was never there.
func _test_the_same_profile_against_itself_differs_in_nothing() -> void:
	var profile: Variant = _compile(_profile("rigid"))
	if profile == null:
		_check(false, "the profile compiles")
		return
	var found: Array = COMPARE.differences(profile, profile)
	_check(found.is_empty(), "a profile compared against itself reports nothing to look for")


## What a real comparison looks like: the impact channels move, the timing does not.
func _test_a_material_swap_names_the_channels_it_moves() -> void:
	var hard: Variant = _compile(_profile("rigid"))
	var soft: Variant = _compile(_profile("semi_rigid"))
	if hard == null or soft == null:
		_check(false, "both profiles compile")
		return
	var found: Array = COMPARE.differences(hard, soft)
	var named := ""
	for row: Dictionary in found:
		named += str(row["channel"]) + " "
	_check("hitstop" in named and "sound" in named, "a material swap names hitstop and sound: %s" % named)
	_check(not ("startup" in named), "and does not claim the timing moved: %s" % named)


func _profile(rigidity: String) -> Resource:
	var profile: Variant = AFFORDANCE.new()
	profile.handle_length = "short"
	profile.body_length = "short"
	profile.grip_topology = "one_hand_handle"
	profile.contact_surface = "broad"
	profile.secondary_contact_surface = "none"
	profile.rigidity = rigidity
	profile.mass_distribution = "front"
	profile.has_broad_face = true
	profile.real_length_cm = 13.0
	profile.real_mass_kg = 0.12
	profile.confidence = 1.0
	profile.evidence_parts = PackedStringArray(["synthetic ab fixture"])
	return profile


func _compile(affordance: Resource) -> Variant:
	var loaded: Dictionary = LOADER.new().load_recipe_asset("frying_pan")
	if not bool(loaded.get("ok", false)):
		return null
	var asset: Variant = loaded.get("asset")
	var compiled: Variant = COMPILER.new().compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
	return null if compiled is String else compiled


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
