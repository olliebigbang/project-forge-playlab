extends SceneTree

## Material is a separate question from tempo.
##
## Tempo answers how long the swing takes and how hard it lands, and mass decides tempo
## (P09). Nothing answers what the object is made of: `impact_feedback_profile.gd` matches
## on tempo alone, so a cast iron pan and a chicken leg of the same tempo hit identically.
## P13 measured that `rigidity` splits two of the three colliding groups and four of the
## seven colliding pairs, which is what this axis is for.

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")

const EXPECTED_CHECKS := 14

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_same_tempo_different_rigidity_changes_hitstop()
	_test_same_tempo_different_rigidity_changes_impact_sound()
	_test_no_resolution_dominates_another_on_every_channel()
	_test_mass_does_not_reach_the_resolution()
	_test_material_survives_the_finisher()
	_test_material_leaves_timing_and_damage_alone()
	_test_the_weapon_moves_differently_after_contact()
	_test_a_whiff_traces_the_same_path_for_everything()
	_test_the_three_impacts_sound_like_different_materials()
	_test_neighbouring_resolutions_are_far_enough_apart()
	# A runtime error inside a test aborts that function without reaching a _check, so the
	# counters simply come up short and the suite exits green. Reconciling against a
	# declared total is what turns that silence back into a failure.
	var ran := passed + failed
	if ran != EXPECTED_CHECKS:
		failed += 1
		push_error("FAIL %d checks ran, expected %d -- a test aborted part-way" % [ran, EXPECTED_CHECKS])
	print("CONTACT_RESOLUTION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


## The widest gap in a three-value axis is worth nothing if the two values that actually
## co-occur sit next to each other. Every playable object is arrest or follow_through --
## none is flexible -- so in practice those two are the whole axis, and they were 1.23x
## apart on hitstop while the table looked like 1.88x end to end. That is inside the band
## P13 spent its length condemning.
func _test_neighbouring_resolutions_are_far_enough_apart() -> void:
	var stops: Array[float] = []
	for rigidity: String in ["rigid", "semi_rigid", "flexible"]:
		var compiled: Variant = _compile(_profile(rigidity))
		if compiled == null:
			_check(false, "all three rigidity values compile")
			return
		stops.append(float(_impact(compiled).hitstop_seconds))
	stops.sort()
	var worst := 99.0
	for index: int in range(stops.size() - 1):
		worst = minf(worst, float(stops[index + 1]) / maxf(float(stops[index]), 0.0001))
	_check(worst >= 1.40, "the closest two resolutions are %.2fx apart on hitstop, needs 1.40" % worst)


## The behaviour the axis exists for. Length and mass are held identical so tempo cannot
## be the source of any difference, which the first assertion pins down.
func _test_same_tempo_different_rigidity_changes_hitstop() -> void:
	var hard: Variant = _compile(_profile("rigid"))
	var soft: Variant = _compile(_profile("semi_rigid"))
	if hard == null or soft == null:
		_check(false, "both profiles compile")
		return
	_check(hard.tempo == soft.tempo, "control: identical tempo, so tempo cannot explain the rest")
	var hard_hit: Variant = _impact(hard)
	var soft_hit: Variant = _impact(soft)
	_check(
		not is_equal_approx(float(hard_hit.hitstop_seconds), float(soft_hit.hitstop_seconds)),
		"rigid and semi_rigid land with different hitstop at the same tempo"
	)


## Sound carries material better than timing does, and it was keyed to tempo, so a cast
## iron pan and a chicken leg of the same tempo announced themselves identically.
func _test_same_tempo_different_rigidity_changes_impact_sound() -> void:
	var hard: Variant = _compile(_profile("rigid"))
	var soft: Variant = _compile(_profile("semi_rigid"))
	if hard == null or soft == null:
		_check(false, "both profiles compile")
		return
	_check(
		str(_impact(hard).sound_profile) != str(_impact(soft).sound_profile),
		"rigid and semi_rigid announce themselves with different impact sounds"
	)


## P08: a real quantity may decide which weapon something is, never whether it is worth
## using. Three resolutions that rank the same way on every channel would be a strength
## ladder wearing an enum, and the light end of it would simply be worse. So no resolution
## may be at least as good as another everywhere and better somewhere.
func _test_no_resolution_dominates_another_on_every_channel() -> void:
	var impacts := {}
	for rigidity: String in ["rigid", "semi_rigid", "flexible"]:
		var compiled: Variant = _compile(_profile(rigidity))
		if compiled == null:
			_check(false, "all three rigidity values compile")
			return
		impacts[str(compiled.contact_resolution)] = _impact(compiled)
	_check(impacts.size() == 3, "the three rigidity values reach three distinct resolutions")
	var dominated: Array[String] = []
	for a: String in impacts:
		for b: String in impacts:
			if a == b:
				continue
			if _dominates(impacts[a], impacts[b]):
				dominated.append("%s over %s" % [a, b])
	_check(dominated.is_empty(), "no resolution dominates another on every channel%s" % (
		"" if dominated.is_empty() else " (found: %s)" % ", ".join(dominated)))


## Channels compared as "more of this": hitstop, knockback and how far the weapon kicks
## back. Domination means at least as much of all three and strictly more of one.
func _dominates(a: Variant, b: Variant) -> bool:
	var channels: Array[Array] = [
		[float(a.hitstop_seconds), float(b.hitstop_seconds)],
		[float(a.knockback_strength), float(b.knockback_strength)],
		[float(a.recoil_degrees), float(b.recoil_degrees)],
	]
	var strictly_more := false
	for pair: Array in channels:
		if pair[0] < pair[1]:
			return false
		if pair[0] > pair[1]:
			strictly_more = true
	return strictly_more


## P15 removed the mass threshold this axis was first specified with: it resolved none of
## the collisions rigidity leaves, and no balanced value of it clears P09's noise floor.
## Re-introducing a threshold in `_contact_resolution` is the production change that makes
## this fail, which is how it was verified.
func _test_mass_does_not_reach_the_resolution() -> void:
	var light: Variant = _compile(_profile("rigid"))
	var heavy_affordance: Resource = _profile("rigid")
	heavy_affordance.real_mass_kg = 5.0
	var heavy: Variant = _compile(heavy_affordance)
	if light == null or heavy == null:
		_check(false, "both profiles compile")
		return
	_check(
		str(light.contact_resolution) == str(heavy.contact_resolution),
		"a fortyfold mass difference leaves the resolution alone"
	)


## The third hit and the charge are the loudest hits in the combo and the ones a player
## is most likely to be listening to. Both replaced `sound_profile` outright with a stage
## name, so the material said nothing on exactly the swings that carry.
func _test_material_survives_the_finisher() -> void:
	var hard: Variant = _compile(_profile("rigid"))
	var soft: Variant = _compile(_profile("semi_rigid"))
	if hard == null or soft == null:
		_check(false, "both profiles compile")
		return
	for stage: Array in [["normal", 3], ["charge", 0]]:
		var kind := str(stage[0])
		var index := int(stage[1])
		var a := str(FEEDBACK.for_attack(hard, kind, index, null).sound_profile)
		var b := str(FEEDBACK.for_attack(soft, kind, index, null).sound_profile)
		_check(a != b, "material is still audible on %s" % ("the finisher" if kind == "normal" else "the charge"))


## The channels are owned, not shared. Tempo keeps timing and damage; material keeps the
## impact. Letting rigidity reach `_tempo_for_axes` is the production change that makes
## this fail, which is how it was verified -- and it would quietly hand damage to material,
## which P09 forbids.
func _test_material_leaves_timing_and_damage_alone() -> void:
	var hard: Variant = _compile(_profile("rigid"))
	var soft: Variant = _compile(_profile("flexible"))
	if hard == null or soft == null:
		_check(false, "both profiles compile")
		return
	var same: bool = str(hard.tempo) == str(soft.tempo)
	same = same and is_equal_approx(float(hard.startup_seconds), float(soft.startup_seconds))
	same = same and is_equal_approx(float(hard.active_seconds), float(soft.active_seconds))
	same = same and is_equal_approx(float(hard.recovery_seconds), float(soft.recovery_seconds))
	same = same and is_equal_approx(float(hard.movement_commitment), float(soft.movement_commitment))
	_check(same, "rigidity moves no timing, and so reaches no damage")


## Every channel so far is felt at the instant of contact and then gone. This one is
## visible: what the weapon does after it lands. Arrest stops it dead, rebound throws it
## back, follow-through carries it on through the arc. Nothing in the game reads the hit
## when drawing the swing today, so a hit and a whiff trace the same path.
func _test_the_weapon_moves_differently_after_contact() -> void:
	var progress := {}
	for rigidity: String in ["rigid", "semi_rigid", "flexible"]:
		var compiled: Variant = _compile(_profile(rigidity))
		if compiled == null:
			_check(false, "all three rigidity values compile")
			return
		progress[str(compiled.contact_resolution)] = _swing_progress_after_contact(compiled)
	var values: Array = progress.values()
	_check(
		not is_equal_approx(values[0], values[1]) 			and not is_equal_approx(values[1], values[2]) 			and not is_equal_approx(values[0], values[2]),
		"the three resolutions carry the weapon to three different places after a hit"
	)


## Drives a real attack to the middle of its active window, lands a hit, then advances the
## same amount again and asks where the swing is.
func _swing_progress_after_contact(motion_profile: Variant) -> float:
	var controller: Variant = CONTROLLER.new()
	controller.configure(motion_profile)
	controller.press_attack()
	controller.release_attack()
	var timing: Dictionary = controller.current_timing()
	controller.tick(float(timing.get("startup", 0.1)) * 1.01)
	var active := float(timing.get("active", 0.1))
	controller.tick(active * 0.4)
	controller.register_hit(1)
	controller.tick(active * 0.4)
	return controller.swing_progress()


## The axis acts on contact and nowhere else. A swing through empty air is the same swing
## whatever the object is made of, so this fails if the remap is ever applied
## unconditionally -- which is how it was verified.
func _test_a_whiff_traces_the_same_path_for_everything() -> void:
	var traced := {}
	for rigidity: String in ["rigid", "semi_rigid", "flexible"]:
		var compiled: Variant = _compile(_profile(rigidity))
		if compiled == null:
			_check(false, "all three rigidity values compile")
			return
		traced[rigidity] = _swing_progress_without_contact(compiled)
	_check(
		is_equal_approx(float(traced["rigid"]), float(traced["semi_rigid"]))
			and is_equal_approx(float(traced["rigid"]), float(traced["flexible"])),
		"a swing that hits nothing travels the same path for every material"
	)


func _swing_progress_without_contact(motion_profile: Variant) -> float:
	var controller: Variant = CONTROLLER.new()
	controller.configure(motion_profile)
	controller.press_attack()
	controller.release_attack()
	var timing: Dictionary = controller.current_timing()
	controller.tick(float(timing.get("startup", 0.1)) * 1.01)
	controller.tick(float(timing.get("active", 0.1)) * 0.8)
	return controller.swing_progress()


## Material is heard in how long the impact lasts and how much of it is noise rather than
## tone. Pitch alone reads as the same object at a different size, so three voices that
## separated only there would not be three materials -- both dimensions have to carry.
##
## This deliberately does not say which one lasts longest. An earlier version did, and the
## claim it encoded was wrong: it assumed the flexible bucket held metal because the sound
## was named "ring", when what is actually in there is a fishing rod.
func _test_the_three_impacts_sound_like_different_materials() -> void:
	var voices: Array[Dictionary] = [
		FEEDBACK.tone_for("forge_impact_dead"),
		FEEDBACK.tone_for("forge_impact_soft"),
		FEEDBACK.tone_for("forge_impact_whip"),
	]
	for voice: Dictionary in voices:
		if voice.is_empty():
			_check(false, "all three material voices exist")
			return
	_check(
		_all_apart(voices, "duration", 1.20),
		"no two materials last the same length of time"
	)
	_check(
		_all_apart(voices, "noise", 1.40),
		"no two materials carry the same amount of noise"
	)


## True when every pair on this dimension is separated by at least `ratio`.
func _all_apart(voices: Array[Dictionary], key: String, ratio: float) -> bool:
	for a: int in range(voices.size()):
		for b: int in range(a + 1, voices.size()):
			var low := minf(float(voices[a][key]), float(voices[b][key]))
			var high := maxf(float(voices[a][key]), float(voices[b][key]))
			if low <= 0.0 or high / low < ratio:
				return false
	return true


func _profile(rigidity: String) -> Resource:
	var profile: Variant = AFFORDANCE.new()
	profile.handle_length = "short"
	profile.body_length = "short"
	profile.grip_topology = "one_hand_handle"
	profile.contact_surface = "broad"
	profile.secondary_contact_surface = "none"
	profile.mass_distribution = "front"
	profile.has_broad_face = true
	profile.rigidity = rigidity
	profile.real_length_cm = 13.0
	profile.real_mass_kg = 0.12
	profile.confidence = 1.0
	profile.evidence_parts = PackedStringArray(["synthetic contact resolution fixture"])
	return profile


## Compiles against a real shipped asset's anchors and bounds, so nothing here is mocked.
func _compile(affordance: Resource) -> Variant:
	var loaded: Dictionary = LOADER.new().load_recipe_asset("frying_pan")
	if not bool(loaded.get("ok", false)):
		return null
	var asset: Variant = loaded.get("asset")
	var compiled: Variant = COMPILER.new().compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
	return null if compiled is String else compiled


func _impact(motion_profile: Variant) -> Variant:
	var primitive: Variant = motion_profile.combo_recipe.primitive_for(1)
	return FEEDBACK.for_attack(motion_profile, "normal", 1, primitive)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
