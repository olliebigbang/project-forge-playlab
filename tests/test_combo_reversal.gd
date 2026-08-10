extends SceneTree

## The second hit is supposed to come back.
##
## The legacy path calls this combo shape `forward_reverse_finisher`, and
## `_synthesize_primitive` has a branch that swaps hit_2's angles for the two swinging
## families. What that branch produced was not a reversal: for `bash` it turned
## [-0.62, +0.30] into [+0.30, +0.62], which carries on in the same direction for 18
## degrees where the opening swing covered 53. Measured across the six shipped objects,
## every arc in every combo rotated the same way -- nothing in the game ever swung back.

const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")

const SHOTGUN_SIDECAR := "res://artifacts/mass_axis_poc/affordance_v1_4/shotgun_melee/object_affordance_profile.json"

# Below this an arc is a twitch rather than a swing. The opening bash covers 0.92 rad and
# the broken reversal covered 0.32; anything in that lower region reads as an input
# stutter, which is why `_hit_coverage` had to floor arc length at 8 degrees to keep the
# hitbox from vanishing.
const SWING_ARC_MINIMUM := 0.50

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_second_hit_reverses_the_swing()
	print("COMBO_REVERSAL_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_second_hit_reverses_the_swing() -> void:
	var recipe: Variant = _compile_shotgun_recipe()
	if recipe == null:
		_check(false, "shotgun recipe compiles")
		return
	var hit_2: Variant = recipe.hit_2
	if not (hit_2.motion_family in ["bash", "sweep"]):
		# The reversal branch only covers the swinging families, so if selection stops
		# landing here the test is silently passing on nothing.
		_check(false, "hit_2 selects a swinging family (got %s)" % hit_2.motion_family)
		return
	var arc: float = float(hit_2.end_angle) - float(hit_2.start_angle)
	_check(arc < 0.0,
		"hit_2 rotates back the other way (arc %+.0f degrees)" % rad_to_deg(arc))
	_check(absf(arc) >= SWING_ARC_MINIMUM,
		"hit_2 is a swing rather than a twitch (arc %.0f degrees)" % absf(rad_to_deg(arc)))


func _compile_shotgun_recipe() -> Variant:
	var loader: Variant = LOADER.new()
	var carrier: Dictionary = loader.load_recipe_asset("frying_pan")
	if not bool(carrier.get("ok", false)):
		return null
	var affordance: Resource = loader.load_affordance_override(SHOTGUN_SIDECAR)
	if affordance == null:
		return null
	var asset: Variant = carrier.get("asset")
	var compiled: Variant = COMPILER.new().compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
	return null if compiled is String else compiled.combo_recipe


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)
