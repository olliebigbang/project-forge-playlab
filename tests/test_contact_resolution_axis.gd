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
	print("CONTACT_RESOLUTION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


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
