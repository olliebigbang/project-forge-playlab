class_name AbComparison
extends RefCounted

## What two compiled profiles actually differ in, at the numbers the player receives.
##
## Three rounds of playtesting compared assets across a relaunch and came back "cannot tell
## them apart", which cannot separate "too small to feel" from "identical by mistake". The
## switch that puts them side by side has to answer the second question itself.

const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")

## Every channel worth comparing, and how far apart two values have to be before it is worth
## a player's attention. Ratios for quantities, any change at all for the categorical ones.
const CHANNELS: Array = [
	["hitstop", "ratio", 1.15],
	["knockback", "ratio", 1.15],
	["camera_shake", "ratio", 1.15],
	["weapon_recoil", "absolute", 3.0],
	["weapon_deflect", "absolute", 4.0],
	["player_move", "absolute", 4.0],
	["sound", "category", 0.0],
	["contact_resolution", "category", 0.0],
	["grip", "category", 0.0],
	["startup", "ratio", 1.10],
	["recovery", "ratio", 1.10],
	["swing_family", "category", 0.0],
]


static func _signature(profile: Variant) -> Dictionary:
	var primitive: Variant = profile.combo_recipe.primitive_for(1)
	var hit: Variant = FEEDBACK.for_attack(profile, "normal", 1, primitive)
	return {
		"hitstop": float(hit.hitstop_seconds),
		"knockback": float(hit.knockback_strength),
		"camera_shake": float(hit.camera_shake_strength),
		"weapon_recoil": float(hit.recoil_degrees),
		"weapon_deflect": float(hit.weapon_deflect_degrees),
		"player_move": float(hit.player_advance_pixels) - float(hit.player_pushback_pixels),
		"sound": str(hit.sound_profile),
		"contact_resolution": str(profile.contact_resolution),
		"grip": str(profile.grip_topology),
		"startup": float(profile.startup_seconds),
		"recovery": float(profile.recovery_seconds),
		"swing_family": str(primitive.motion_family),
	}


## Returns one row per channel that moved far enough to be worth looking for, each carrying
## both values so the readout can show what to watch rather than only that something changed.
static func differences(left: Variant, right: Variant) -> Array:
	var a := _signature(left)
	var b := _signature(right)
	var found: Array = []
	for entry: Array in CHANNELS:
		var channel := str(entry[0])
		var kind := str(entry[1])
		var threshold := float(entry[2])
		var one: Variant = a[channel]
		var two: Variant = b[channel]
		var moved := false
		var amount := ""
		match kind:
			"category":
				moved = str(one) != str(two)
				amount = "%s -> %s" % [one, two]
			"ratio":
				var low := minf(float(one), float(two))
				var high := maxf(float(one), float(two))
				moved = low > 0.0 and high / low >= threshold
				amount = "%.4f -> %.4f  (%.2fx)" % [one, two, high / maxf(low, 0.0001)]
			_:
				moved = absf(float(one) - float(two)) >= threshold
				amount = "%+.1f -> %+.1f" % [one, two]
		if moved:
			found.append({"channel": channel, "detail": amount})
	return found
