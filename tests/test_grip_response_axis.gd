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
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")

const EXPECTED_CHECKS := 7

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bracing_changes_what_the_hit_does_to_you()
	_test_no_grip_is_simply_the_best_way_to_hold_something()
	_test_the_hit_reaches_the_player_and_the_weapon()
	_test_connecting_drives_some_grips_forward_and_others_back()
	# A runtime error inside a test aborts that function without reaching a _check, so the
	# counters simply come up short and the suite exits green. Reconciling against a
	# declared total is what turns that silence back into a failure.
	var ran := passed + failed
	if ran != EXPECTED_CHECKS:
		failed += 1
		push_error("FAIL %d checks ran, expected %d -- a test aborted part-way" % [ran, EXPECTED_CHECKS])
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


## The numbers are only a table until something reads them. Before contact the grip has no
## say -- a swing through air is the same swing however you hold it -- and after contact it
## decides how far the weapon is knocked off line and which way the player is moved.
func _test_the_hit_reaches_the_player_and_the_weapon() -> void:
	var one_hand: Variant = _after_contact(_compile(_profile("one_hand_handle")))
	var two_hand: Variant = _after_contact(_compile(_profile("two_hand_handle")))
	var body: Variant = _after_contact(_compile(_profile("body_grip")))
	if one_hand == null or two_hand == null or body == null:
		_check(false, "all three grips compile")
		return
	_check(
		not is_equal_approx(float(one_hand.contact_deflect_radians), float(two_hand.contact_deflect_radians)),
		"a one-hand grip is knocked further off line than a braced one"
	)
	_check(
		float(body.contact_displacement_pixels) > float(two_hand.contact_displacement_pixels),
		"a body grip carries the player through where a braced grip holds position"
	)
	_check(
		_before_contact(_compile(_profile("one_hand_handle"))) == 0.0,
		"a swing that hits nothing moves nobody"
	)


## The sign is the part that makes this a trade rather than a ranking. If connecting only
## ever moved the player forward, the axis would just be "how far you advance", and holding
## something one way would be strictly better than another -- which is what P08 forbids and
## what the first pass at these numbers did. Some grips have to give ground.
##
## A magnitude can be compressed until nobody feels it, which is what happened to every
## continuous axis this line has tried. A direction cannot: you either went forward or you
## did not.
func _test_connecting_drives_some_grips_forward_and_others_back() -> void:
	var forward := false
	var backward := false
	for grip: String in ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"]:
		var controller: Variant = _after_contact(_compile(_profile(grip)))
		if controller == null:
			_check(false, "all four grips compile")
			return
		var moved := float(controller.contact_displacement_pixels)
		if moved > 0.0:
			forward = true
		elif moved < 0.0:
			backward = true
	_check(forward and backward, "connecting carries some grips in and pushes others back")


## Drives a real attack to the middle of its active window and lands a hit.
func _after_contact(motion_profile: Variant) -> Variant:
	if motion_profile == null:
		return null
	var controller: Variant = CONTROLLER.new()
	controller.configure(motion_profile)
	controller.press_attack()
	controller.release_attack()
	var timing: Dictionary = controller.current_timing()
	controller.tick(float(timing.get("startup", 0.1)) * 1.01)
	controller.tick(float(timing.get("active", 0.1)) * 0.4)
	controller.register_hit(1)
	return controller


## The same swing with nothing in its way.
func _before_contact(motion_profile: Variant) -> float:
	var controller: Variant = CONTROLLER.new()
	controller.configure(motion_profile)
	controller.press_attack()
	controller.release_attack()
	var timing: Dictionary = controller.current_timing()
	controller.tick(float(timing.get("startup", 0.1)) * 1.01)
	controller.tick(float(timing.get("active", 0.1)) * 0.8)
	return float(controller.contact_deflect_radians)


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
