extends SceneTree

## A/B the real-mass axis against the categorical one it replaces.
##
## Both sides come from the same v1.4 sidecar, with `real_mass_kg` zeroed on the OFF side.
## That isolates the change: real_length_cm and every categorical field stay identical, so
## any difference below is mass and nothing else.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##     --script res://tools/combat_feel/verify_mass_ab.gd

const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")

const OVERRIDE_DIR := "res://artifacts/mass_axis_poc/affordance_v1_4/%s/object_affordance_profile.json"

# Mirrors the base table in combat_feel_slice_0.gd `_current_damage`. Reproduced rather
# than imported because the point of printing it here is to show that mass reaches damage
# only by selecting a tempo, never as a multiplier -- decision P08's red line.
const DAMAGE_FOR_TEMPO := {"rapid": 22.0, "balanced": 27.0, "committed": 34.0}


func _initialize() -> void:
	var loader: Variant = LOADER.new()
	var compiler: Variant = COMPILER.new()
	# Demo objects are not shipped assets, so they borrow frying_pan's anchors and bounds.
	# Only mass-derived columns are meaningful for them; reach is not reported.
	var carrier: Dictionary = loader.load_recipe_asset("frying_pan")
	if not bool(carrier.get("ok", false)):
		print("carrier asset failed to load: %s" % carrier.get("error", "?"))
		quit()
		return
	var carrier_asset: Variant = carrier.get("asset")

	var targets := ["chicken_leg", "sledgehammer", "frying_pan", "giant_wooden_spoon", "old_mop", "shotgun_melee"]

	print("1. THE AXIS  (what the compiler knows about how heavy the object is)")
	print("   %-20s %8s   %-18s   %-18s" % ["object", "kg", "mass_axis OFF->ON", "weight_class OFF->ON"])
	var rows: Array = []
	for id: String in targets:
		var on_profile: Resource = loader.load_affordance_override(OVERRIDE_DIR % id)
		if on_profile == null:
			print("   %-20s SIDECAR MISSING OR INVALID" % id)
			continue
		var off_profile: Resource = on_profile.duplicate()
		off_profile.real_mass_kg = 0.0
		var anchors: Dictionary = carrier_asset.anchors_dict()
		var bounds: Rect2i = carrier_asset.opaque_bounds
		var off_compiled: Variant = compiler.compile(off_profile, anchors, bounds)
		var on_compiled: Variant = compiler.compile(on_profile, anchors, bounds)
		if off_compiled is String or on_compiled is String:
			print("   %-20s COMPILE FAILED" % id)
			continue
		# _mass_axis is private; recover it from the knockback multiplier it feeds,
		# knockback = 0.88 + 0.18 * mass_axis at stage hit_1 (finisher 1.0).
		var off_axis := (float(off_compiled.combo_recipe.hit_1.knockback_multiplier) - 0.88) / 0.18
		var on_axis := (float(on_compiled.combo_recipe.hit_1.knockback_multiplier) - 0.88) / 0.18
		print("   %-20s %8.2f   %5.3f -> %5.3f      %-8s -> %-8s" % [
			id, on_profile.real_mass_kg, off_axis, on_axis,
			off_compiled.weight_class, on_compiled.weight_class,
		])
		rows.append({"id": id, "off": off_compiled, "on": on_compiled, "kg": on_profile.real_mass_kg})

	print("")
	print("2. WHAT IT BUYS  (tempo is a trade, not a ranking: light keeps DPS and mobility)")
	print("   %-20s %-22s %-15s %-15s %-15s" % ["object", "tempo OFF -> ON", "swing s", "move kept", "DPS"])
	for row: Dictionary in rows:
		var off: Variant = row["off"]
		var on: Variant = row["on"]
		print("   %-20s %-10s -> %-10s %5.2f -> %5.2f   %5.2f -> %5.2f   %5.1f -> %5.1f" % [
			row["id"], off.tempo, on.tempo,
			_swing_seconds(off), _swing_seconds(on),
			off.movement_commitment, on.movement_commitment,
			_dps(off), _dps(on),
		])

	print("")
	print("3. RED LINE  (P08: a real quantity may never multiply damage)")
	for row: Dictionary in rows:
		var on: Variant = row["on"]
		var damage: float = float(DAMAGE_FOR_TEMPO[on.tempo])
		# If mass multiplied damage, this ratio would track kilograms. It must instead
		# take exactly one of three values however far apart the masses are.
		print("   %-20s %6.2f kg -> tempo %-10s -> base damage %5.1f" % [
			row["id"], row["kg"], on.tempo, damage,
		])
	var distinct := {}
	for row: Dictionary in rows:
		distinct[float(DAMAGE_FOR_TEMPO[row["on"].tempo])] = true
	var heaviest: float = 0.0
	var lightest: float = INF
	for row: Dictionary in rows:
		heaviest = maxf(heaviest, float(row["kg"]))
		lightest = minf(lightest, float(row["kg"]))
	print("   mass spans %.1fx across these objects; damage takes %d of 3 possible values." % [
		heaviest / lightest, distinct.size(),
	])
	quit()


func _swing_seconds(profile: Variant) -> float:
	return float(profile.startup_seconds) + float(profile.active_seconds) + float(profile.recovery_seconds)


func _dps(profile: Variant) -> float:
	return float(DAMAGE_FOR_TEMPO[profile.tempo]) / _swing_seconds(profile)
