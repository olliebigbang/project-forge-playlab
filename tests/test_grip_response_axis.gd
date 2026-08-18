extends SceneTree

## How you hold it is a separate question from what it is made of.
##
## contact_surface answers how the object delivers damage, and rigidity answers what
## happens where it lands. Neither says anything about what happens to the person swinging.
## Braced in two hands you are not moved; held out in one the weapon is knocked aside.
## The game models none of that -- recoil_degrees turns the weapon, and connecting has no
## consequence for the player at all. P16 measured grip_topology as splitting all three
## colliding groups and six of seven colliding pairs, with no outlet anywhere.

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bracing_changes_what_the_hit_does_to_you()
	_test_no_grip_is_simply_the_best_way_to_hold_something()
	print("GRIP_RESPONSE_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


## The behaviour the axis exists for. Everything but the grip is held identical, and the
## first assertion pins the swing itself down so the selection layer cannot explain it.
func _test_bracing_changes_what_the_hit_does_to_you() -> void:
	var one_hand: Variant = _compile(_profile("one_hand_handle"))
	var two_hand: Variant = _compile(_profile("two_hand_handle"))
	if one_hand == null or two_hand == null:
		_check(false, "both profiles compile")
		return
	_check(
		_sequence(one_hand) == _sequence(two_hand),
		"control: identical swing, so the selection layer cannot explain the rest"
	)
	_check(
		not is_equal_approx(
			float(_impact(one_hand).player_pushback_pixels),
			float(_impact(two_hand).player_pushback_pixels)
		),
		"a one-hand grip gives way where a braced two-hand grip does not"
	)


## P08: a real quantity may decide which weapon something is, never whether it is worth
## using. Four grips that rank the same way on every channel would make three of them
## strictly wrong choices, so every grip has to be the best at something. Polarity is
## spelled out here rather than assumed, because two of these channels are costs.
func _test_no_grip_is_simply_the_best_way_to_hold_something() -> void:
	var grips: PackedStringArray = ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"]
	var measured := {}
	for grip: String in grips:
		var compiled: Variant = _compile(_profile(grip))
		if compiled == null:
			_check(false, "all four grips compile")
			return
		var hit: Variant = _impact(compiled)
		measured[grip] = {
			"pushback": -float(hit.player_pushback_pixels),
			"deflect": -float(hit.weapon_deflect_degrees),
			"advance": float(hit.player_advance_pixels),
		}
	var dominant: Array[String] = []
	for grip: String in grips:
		if _best_at_everything(grip, measured):
			dominant.append(grip)
	_check(dominant.is_empty(), "no grip is best on every channel at once%s" % (
		"" if dominant.is_empty() else " (found: %s)" % ", ".join(dominant)))


## Higher is better on every channel here, the two costs having been negated by the caller.
func _best_at_everything(grip: String, measured: Dictionary) -> bool:
	var strictly_better := false
	for channel: String in ["pushback", "deflect", "advance"]:
		for other: String in measured:
			if other == grip:
				continue
			if float(measured[grip][channel]) < float(measured[other][channel]):
				return false
			if float(measured[grip][channel]) > float(measured[other][channel]):
				strictly_better = true
	return strictly_better


func _sequence(motion_profile: Variant) -> String:
	var recipe: Variant = motion_profile.combo_recipe
	return "%s|%s|%s" % [
		recipe.primitive_for(1).motion_family,
		recipe.primitive_for(2).motion_family,
		recipe.primitive_for(3).motion_family,
	]


func _profile(grip: String) -> Resource:
	var profile: Variant = AFFORDANCE.new()
	# A body grip is what you do with something that has no handle, and the schema enforces
	# that, so the fixture cannot hold this one constant.
	profile.handle_length = "none" if grip == "body_grip" else "medium"
	profile.body_length = "medium"
	profile.grip_topology = grip
	profile.contact_surface = "broad"
	profile.secondary_contact_surface = "none"
	profile.rigidity = "rigid"
	profile.mass_distribution = "front"
	profile.has_broad_face = true
	profile.real_length_cm = 60.0
	profile.real_mass_kg = 1.8
	profile.confidence = 1.0
	profile.evidence_parts = PackedStringArray(["synthetic grip fixture"])
	return profile


func _compile(affordance: Resource) -> Variant:
	var loaded: Dictionary = LOADER.new().load_recipe_asset("frying_pan")
	if not bool(loaded.get("ok", false)):
		return null
	var asset: Variant = loaded.get("asset")
	var compiled: Variant = COMPILER.new().compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
	return null if compiled is String else compiled


func _impact(motion_profile: Variant) -> Variant:
	return FEEDBACK.for_attack(motion_profile, "normal", 1, motion_profile.combo_recipe.primitive_for(1))


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
