extends SceneTree

## Commitment is a separate question from tempo.
##
## Tempo answers "how long does the swing take". Commitment answers "once you have
## started it, can you still change your mind". Before this axis every object in the game
## answered the second question identically: `early_startup_cancel_ratio` is 0.38 for
## everything the player can draw, and nothing in the compiler ever assigned it.

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_light_one_hand_can_abort_where_heavy_two_hand_cannot()
	_test_same_tempo_can_still_differ_in_commitment()
	_test_profile_without_real_mass_keeps_the_old_window()
	print("COMMITMENT_AXIS_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


## The behaviour the axis exists for: a chicken leg is a swing you can call off, a
## sledgehammer is a swing you are committed to. Asked through the real controller at the
## same point in startup, so this fails if the ratio stops reaching `can_dodge_cancel`.
func _test_light_one_hand_can_abort_where_heavy_two_hand_cannot() -> void:
	var light: Variant = _compile(_profile("light"))
	var heavy: Variant = _compile(_profile("heavy"))
	if light == null or heavy == null:
		_check(false, "both profiles compile")
		return
	var light_aborts := _can_abort_at(light, 0.40)
	var heavy_aborts := _can_abort_at(heavy, 0.40)
	_check(light_aborts, "0.12kg one-hand object can still dodge-cancel 40% into startup")
	_check(not heavy_aborts, "5.0kg two-hand object is committed 40% into startup")


## The property that makes commitment an axis instead of a second reading of tempo.
##
## Two objects identical in length and mass, differing only in how they are held, must
## compile to the same tempo and to different cancel windows. Delete the grip term from
## `_commitment` and this is the test that goes red.
func _test_same_tempo_can_still_differ_in_commitment() -> void:
	var one_hand: Variant = _compile(_grip_profile("one_hand_handle"))
	var two_hand: Variant = _compile(_grip_profile("two_hand_handle"))
	if one_hand == null or two_hand == null:
		_check(false, "both grip profiles compile")
		return
	_check(one_hand.tempo == two_hand.tempo,
		"same length and mass compile to the same tempo (%s)" % one_hand.tempo)
	_check(_can_abort_at(one_hand, 0.30) and not _can_abort_at(two_hand, 0.30),
		"at equal tempo the one-hand grip can still abort and the two-hand grip cannot")


## Every asset frozen under data/ predates v1.4 and carries no mass, so all four must keep
## the window they shipped with. Nothing else in the suite covers the cancel path at all --
## a grep for `can_dodge_cancel` across tests/ finds only this file -- so without this the
## guard could be deleted and every existing assertion would still pass.
func _test_profile_without_real_mass_keeps_the_old_window() -> void:
	var legacy: Resource = _grip_profile("two_hand_handle")
	legacy.real_mass_kg = 0.0
	var compiled: Variant = _compile(legacy)
	if compiled == null:
		_check(false, "pre-v1.4 profile compiles")
		return
	# Brackets the ratio into (0.30, 0.40], which is the 0.38 every object had before.
	_check(_can_abort_at(compiled, 0.30) and not _can_abort_at(compiled, 0.40),
		"a profile carrying no real mass keeps the pre-v1.4 cancel window")


## Identical but for grip_topology, which appears nowhere in `_tempo_for_axes`.
func _grip_profile(grip: String) -> Resource:
	var profile: Variant = AFFORDANCE.new()
	profile.handle_length = "medium"
	profile.body_length = "medium"
	profile.grip_topology = grip
	profile.contact_surface = "broad"
	profile.secondary_contact_surface = "none"
	profile.rigidity = "rigid"
	profile.mass_distribution = "front"
	profile.has_broad_face = true
	profile.confidence = 1.0
	profile.evidence_parts = PackedStringArray(["synthetic grip fixture"])
	profile.real_length_cm = 80.0
	profile.real_mass_kg = 1.2
	return profile


func _profile(kind: String) -> Resource:
	var profile: Variant = AFFORDANCE.new()
	profile.contact_surface = "broad"
	profile.secondary_contact_surface = "none"
	profile.rigidity = "rigid"
	profile.mass_distribution = "front"
	profile.has_broad_face = true
	profile.confidence = 1.0
	profile.evidence_parts = PackedStringArray(["synthetic commitment fixture"])
	match kind:
		"light":
			profile.handle_length = "short"
			profile.body_length = "short"
			profile.grip_topology = "one_hand_handle"
			profile.real_length_cm = 13.0
			profile.real_mass_kg = 0.12
		_:
			profile.handle_length = "long"
			profile.body_length = "medium"
			profile.grip_topology = "two_hand_handle"
			profile.real_length_cm = 90.0
			profile.real_mass_kg = 5.0
	return profile


## Compiles against a real shipped asset's anchors and bounds, so nothing here is mocked.
func _compile(affordance: Resource) -> Variant:
	var loaded: Dictionary = LOADER.new().load_recipe_asset("frying_pan")
	if not bool(loaded.get("ok", false)):
		return null
	var asset: Variant = loaded.get("asset")
	var compiled: Variant = COMPILER.new().compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
	return null if compiled is String else compiled


## Drive a real attack to `fraction` of its startup and ask whether a dodge still cancels.
func _can_abort_at(motion_profile: Variant, fraction: float) -> bool:
	var controller: Variant = CONTROLLER.new()
	controller.configure(motion_profile)
	controller.press_attack()
	controller.release_attack()
	var startup := float(controller.current_timing().get("startup", 0.1))
	controller.tick(startup * fraction)
	return controller.can_dodge_cancel()


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
