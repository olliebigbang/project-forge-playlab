class_name ImpactFeedbackProfile
extends Resource

@export var hitstop_seconds := 0.060
@export var enemy_flash_seconds := 0.10
@export var knockback_strength := 120.0
@export var camera_shake_strength := 3.5
@export var particle_scale := 1.0
@export var sound_profile := "forge_impact_medium"
@export var stagger_strength := 0.55
@export var launch_strength := 0.0
@export var recoil_degrees := 7.0
@export var impact_tier := "light"
@export var ring_count := 0
@export var player_pushback_pixels := 0.0
@export var weapon_deflect_degrees := 0.0
@export var player_advance_pixels := 0.0

## Synthesis parameters for an impact.
##
## A struck object rings at several inharmonic frequencies at once, the higher ones dying
## first, and the very first milliseconds are a broadband crack rather than any pitch at
## all. One sine wave and white noise cannot sound like a material, so each voice here is a
## set of modes plus a shaped noise burst.
##
## Which materials actually occupy each resolution matters, and an earlier version of this
## got it wrong by trusting a name: `rebound` was called "ring" and given a bell, but the
## flexible objects in this game are fishing rods and mops. Every metal object is rigid and
## lands on `arrest`. A rod strike is a whip, not a bell.
##
## Returns an empty dictionary for names it does not own, which leaves the caller's own
## table in charge of swings, whiffs and everything that is not an impact.
static func tone_for(sound_profile: String) -> Dictionary:
	match sound_profile:
		"forge_impact_dead":
			# Cast iron into a body. A hard crack as two solids meet, then a low thud the
			# target swallows; nothing is left to ring because nothing was left moving.
			return {
				"duration": 0.130, "attack": 0.0008,
				"modes": [[92.0, 1.00, 38.0], [151.0, 0.52, 52.0], [327.0, 0.26, 120.0]],
				"noise": 0.55, "noise_decay": 150.0, "noise_lowpass": 0.35,
			}
		"forge_impact_soft":
			# Meat, bone and cloth. Soft mass compresses before it transfers, so the attack
			# is slower and almost nothing survives as tone -- what is left is muffled noise.
			return {
				"duration": 0.185, "attack": 0.0055,
				"modes": [[58.0, 0.55, 44.0], [97.0, 0.22, 62.0]],
				"noise": 0.90, "noise_decay": 26.0, "noise_lowpass": 0.06,
			}
		"forge_impact_whip":
			# A flexible rod. The tip is moving fastest and stops last, so the strike is a
			# sharp mid-range thwack with air behind it, and then it is gone.
			return {
				"duration": 0.225, "attack": 0.0006,
				"modes": [[214.0, 0.75, 27.0], [359.0, 0.44, 41.0], [663.0, 0.20, 78.0]],
				"noise": 0.26, "noise_decay": 95.0, "noise_lowpass": 0.55,
			}
	return {}


## The samples themselves, so that anything wanting to hear a tone -- the game, or a tool
## exporting them for review -- gets the same one.
static func synthesise(kind: String, mix_rate: int) -> PackedByteArray:
	var material: Dictionary = tone_for(kind)
	if material.is_empty():
		return _synthesise_legacy(kind, mix_rate)
	var duration := float(material["duration"])
	var attack := float(material["attack"])
	var modes: Array = material["modes"]
	var noise_amp := float(material["noise"])
	var noise_decay := float(material["noise_decay"])
	var lowpass := float(material["noise_lowpass"])
	var sample_count := int(float(mix_rate) * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var filtered := 0.0
	for index: int in range(sample_count):
		var seconds := float(index) / float(mix_rate)
		var value := 0.0
		for mode: Array in modes:
			value += sin(TAU * float(mode[0]) * seconds) * float(mode[1]) * exp(-float(mode[2]) * seconds)
		# One pole of lowpass turns hiss into the muffled thump a soft object actually makes.
		filtered += lowpass * (randf_range(-1.0, 1.0) - filtered)
		value += filtered * noise_amp * exp(-noise_decay * seconds)
		# Without a rise the first sample is a step, which is its own click.
		var rise := 1.0 if seconds >= attack else seconds / attack
		data.encode_s16(index * 2, roundi(clampf(value * rise * 0.62, -1.0, 1.0) * 32767.0))
	return data


static func _synthesise_legacy(kind: String, mix_rate: int) -> PackedByteArray:
	var frequency: float = float({"swing_light": 245.0, "swing_heavy": 150.0, "whiff": 360.0, "hit": 118.0, "heavy_hit": 64.0, "dodge": 310.0, "hurt": 92.0}.get(kind, 140.0))
	var duration: float = float({"swing_light": 0.045, "swing_heavy": 0.072, "whiff": 0.065, "hit": 0.085, "heavy_hit": 0.16, "dodge": 0.055, "hurt": 0.10}.get(kind, 0.07))
	var sample_count := int(float(mix_rate) * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index: int in range(sample_count):
		var progress := float(index) / float(sample_count)
		var envelope := 1.0 - progress
		var phase := TAU * frequency * float(index) / float(mix_rate)
		var wave := sin(phase)
		if kind == "heavy_hit":
			wave = sin(phase) * 0.70 + sin(phase * 0.51) * 0.45
		elif kind == "whiff":
			wave = sin(phase * (1.0 + progress * 1.6)) * 0.55
		var noise_amount := 0.18 if kind in ["hit", "heavy_hit"] else (0.08 if kind == "whiff" else 0.0)
		var noise := randf_range(-noise_amount, noise_amount)
		var gain := 0.55 if kind == "heavy_hit" else 0.38
		data.encode_s16(index * 2, roundi(clampf((wave + noise) * envelope * gain, -1.0, 1.0) * 32767.0))
	return data


static func for_attack(profile: Resource, attack_kind: String, combo_index: int, primitive: Variant = null) -> Resource:
	var feedback: Variant = load("res://scripts/combat_feel/impact_feedback_profile.gd").new()
	# Hitstop belongs to what the object is made of, not to how fast it swings (P12: the
	# new layer needs channels of its own, taken from tempo rather than added beside it).
	# Spaced so that any two neighbours are far enough apart to be felt, not just the two
	# ends. Every playable object is arrest or follow_through and none is flexible, so those
	# neighbours are the whole axis in practice; at 1.23x they were inside the band P13
	# spent its length condemning, and a player could not tell them apart.
	feedback.hitstop_seconds = {
		"arrest": 0.075, "follow_through": 0.046, "rebound": 0.030,
	}.get(profile.contact_resolution, 0.048)
	# Named for what the object is made of, not for how heavy it is. Hearing is a finer
	# discriminator of material than swing timing is, which is why this channel moves too.
	# The combo stage does not overwrite this: it already has `impact_tier` to itself, so
	# the two stay separate fields rather than multiplying into nine blended names.
	feedback.sound_profile = {
		"arrest": "forge_impact_dead",
		"follow_through": "forge_impact_soft",
		"rebound": "forge_impact_whip",
	}.get(profile.contact_resolution, "forge_impact_medium")
	# Each resolution wins a different channel, because P08 forbids an axis on which one
	# value is simply worse. Arrest stops the target dead and owns hitstop. Follow-through
	# does not stop it, it shoves it, and owns knockback. Rebound throws the weapon back
	# instead of the target and owns recoil, which is what buys its short recovery.
	feedback.knockback_strength = {
		"arrest": 96.0, "follow_through": 152.0, "rebound": 82.0,
	}.get(profile.contact_resolution, 116.0)
	# What connecting does to the person swinging, which nothing modelled before. Each grip
	# wins one of these outright, because P08 forbids a scale on which three of four ways to
	# hold something are simply wrong. Two hands hold the ground and keep the weapon on
	# line, and pay for it by being planted. A body grip takes the worst of the shove and
	# has nothing that can be knocked aside, so it drives straight through -- a body check.
	# A clamp is the easiest to knock off line, which is the price of holding something that
	# was never meant to be swung.
	# The runtime applies advance minus pushback, so these are chosen for what that
	# difference comes to rather than for how they read apart. The first pass had one hand
	# at six and five, which is a shove of one pixel; a player ran it against two hands and
	# could not tell. What matters is the net, and it now spans 28 pixels with grips going
	# both ways.
	feedback.player_pushback_pixels = {
		"two_hand_handle": 0.0, "one_hand_handle": 11.0, "body_grip": 4.0, "clamp_grip": 13.0,
	}.get(profile.grip_topology, 4.0)
	feedback.weapon_deflect_degrees = {
		"two_hand_handle": 2.0, "one_hand_handle": 22.0, "body_grip": 6.0, "clamp_grip": 34.0,
	}.get(profile.grip_topology, 8.0)
	feedback.player_advance_pixels = {
		"two_hand_handle": 0.0, "one_hand_handle": 2.0, "body_grip": 20.0, "clamp_grip": 1.0,
	}.get(profile.grip_topology, 4.0)
	feedback.recoil_degrees = {
		"arrest": 2.0, "follow_through": 0.0, "rebound": 16.0,
	}.get(profile.contact_resolution, 7.0)
	match profile.tempo:
		"rapid":
			feedback.camera_shake_strength = 1.8
		"committed":
			feedback.camera_shake_strength = 4.8
	feedback.knockback_strength *= float(profile.control_strength)
	feedback.camera_shake_strength *= float(profile.impact_sharpness)
	if attack_kind == "charge":
		feedback.hitstop_seconds = maxf(0.135, feedback.hitstop_seconds * 2.05)
		feedback.knockback_strength *= 1.95
		feedback.camera_shake_strength *= 2.10
		feedback.particle_scale = 2.35
		feedback.stagger_strength = 1.25
		feedback.launch_strength = 88.0
		feedback.recoil_degrees = 17.0
		feedback.impact_tier = "charge"
		feedback.ring_count = 2
	elif combo_index >= 3:
		feedback.hitstop_seconds = maxf(0.112, feedback.hitstop_seconds * 1.85)
		feedback.knockback_strength *= 1.78
		feedback.camera_shake_strength *= 1.90
		feedback.particle_scale = 2.0
		feedback.stagger_strength = 1.10
		feedback.launch_strength = 42.0
		feedback.recoil_degrees = 14.0
		feedback.impact_tier = "finisher"
		feedback.ring_count = 2
	elif combo_index == 2:
		feedback.hitstop_seconds *= 1.28
		feedback.knockback_strength *= 1.18
		feedback.camera_shake_strength *= 1.22
		feedback.particle_scale = 1.28
		feedback.stagger_strength = 0.72
		feedback.recoil_degrees = 9.5
		feedback.impact_tier = "medium"
		feedback.ring_count = 1
	elif attack_kind == "dodge":
		feedback.knockback_strength *= 1.18
		feedback.particle_scale = 1.2
		feedback.impact_tier = "medium"
	else:
		feedback.particle_scale = 0.92
		feedback.stagger_strength = 0.48
		feedback.impact_tier = "light"
	if primitive != null:
		feedback.knockback_strength *= float(primitive.knockback_multiplier)
		feedback.stagger_strength *= float(primitive.stagger_multiplier)
		feedback.hitstop_seconds *= float(primitive.hitstop_multiplier)
		feedback.camera_shake_strength *= float(primitive.camera_kick_multiplier)
	return feedback
