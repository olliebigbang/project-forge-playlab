extends SceneTree

## A/B the commitment axis against the single constant it replaces.
##
## Both sides come from the same v1.4 sidecar, with `real_mass_kg` zeroed on the OFF side,
## so the only variable is commitment. The right-hand columns are the ones that matter:
## each drives a real attack through the real controller to that fraction of its startup
## and asks whether a dodge still calls the swing off.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##     --script res://tools/combat_feel/verify_commitment_ab.gd

const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")

const OVERRIDE_DIR := "res://artifacts/mass_axis_poc/affordance_v1_4/%s/object_affordance_profile.json"

# Probed at several points rather than one. A single probe hides the axis: at 40% only the
# chicken leg differs from the old constant, which reads as "one object changed" when in
# fact five distinct windows are in play, all of them shorter than the old 0.38.
const PROBE_FRACTIONS: PackedFloat32Array = [0.10, 0.20, 0.30, 0.45, 0.60]


func _initialize() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	var carrier: Dictionary = loader.load_recipe_asset("frying_pan")
	if not bool(carrier.get("ok", false)):
		print("carrier asset failed to load: %s" % carrier.get("error", "?"))
		quit()
		return
	var carrier_asset: Variant = carrier.get("asset")
	var anchors: Dictionary = carrier_asset.anchors_dict()
	var bounds: Rect2i = carrier_asset.opaque_bounds

	print("COMMITMENT AXIS — how far into the startup can the swing still be called off?")
	print("")
	var header := ""
	for fraction: float in PROBE_FRACTIONS:
		header += "%4d%%" % roundi(fraction * 100.0)
	print("   %-20s %7s  %-16s %-10s %7s   %s" % ["object", "kg", "grip", "tempo", "cancel", header.strip_edges()])
	for id: String in ["chicken_leg", "frying_pan", "old_mop", "giant_wooden_spoon", "shotgun_melee", "sledgehammer"]:
		var on_profile: Resource = loader.load_affordance_override(OVERRIDE_DIR % id)
		if on_profile == null:
			print("   %-20s SIDECAR MISSING OR INVALID" % id)
			continue
		var off_profile: Resource = on_profile.duplicate()
		off_profile.real_mass_kg = 0.0
		var off_compiled: Variant = compiler.compile(off_profile, anchors, bounds)
		var on_compiled: Variant = compiler.compile(on_profile, anchors, bounds)
		if off_compiled is String or on_compiled is String:
			print("   %-20s COMPILE FAILED" % id)
			continue
		print("   %-20s %7.2f  %-16s %-10s %7.3f   %s" % [
			id,
			on_profile.real_mass_kg,
			on_profile.grip_topology,
			on_compiled.tempo,
			on_compiled.early_startup_cancel_ratio,
			_abort_pattern(on_compiled),
		])
	print("   %-20s %7s  %-16s %-10s %7.3f   %s" % [
		"(every object, OFF)", "-", "-", "-",
		COMPILER.EARLY_CANCEL_DEFAULT, _abort_pattern(_reference_off(compiler, anchors, bounds, loader)),
	])
	print("")
	print("   OFF is the pre-v1.4 world: one constant, 0.38, for every object ever drawn.")
	print("   Commitment is deliberately not a second reading of tempo -- it is mass plus")
	print("   grip, and grip_topology appears nowhere in _tempo_for_axes, so two objects")
	print("   that swing for the same time can still differ in whether the swing is yours")
	print("   to take back.")
	quit()


## One row of yes/no across PROBE_FRACTIONS, so the shape of the window is visible.
func _abort_pattern(motion_profile: Variant) -> String:
	var row := ""
	for fraction: float in PROBE_FRACTIONS:
		row += "%5s" % ("y" if _can_abort(motion_profile, fraction) else ".")
	return row.strip_edges()


## Drive a real attack to `fraction` of its startup and ask the controller directly.
func _can_abort(motion_profile: Variant, fraction: float) -> bool:
	var controller: Variant = CONTROLLER.new()
	controller.configure(motion_profile)
	controller.press_attack()
	controller.release_attack()
	var startup := float(controller.current_timing().get("startup", 0.1))
	controller.tick(startup * fraction)
	return controller.can_dodge_cancel()


## Any object compiled without a real mass lands on the single old constant.
func _reference_off(compiler: Variant, anchors: Dictionary, bounds: Rect2i, loader: Variant) -> Variant:
	var profile: Resource = loader.load_affordance_override(OVERRIDE_DIR % "old_mop")
	profile.real_mass_kg = 0.0
	return compiler.compile(profile, anchors, bounds)
