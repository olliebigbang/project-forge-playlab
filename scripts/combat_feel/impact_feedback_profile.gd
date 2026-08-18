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

## Synthesis parameters for an impact, so the material reaches the speaker and not just the
## profile. Material is heard in two things above all: how long the impact rings, and how
## much of it is noise rather than tone. Pitch is the weakest of the three -- on its own it
## reads as the same object at a different size -- so it carries the least here.
##
## Returns an empty dictionary for names it does not own, which leaves the caller's own
## table in charge of swings, whiffs and everything that is not an impact.
static func tone_for(sound_profile: String) -> Dictionary:
	match sound_profile:
		"forge_impact_dead":
			# Cast iron into a body: all of it arrives at once and none of it survives.
			return {"frequency": 74.0, "duration": 0.085, "decay": 9.0, "noise": 0.22, "partial": 0.0}
		"forge_impact_ring":
			# Struck metal that was not stopped, so it keeps sounding after the hit is over.
			return {"frequency": 392.0, "duration": 0.340, "decay": 2.2, "noise": 0.04, "partial": 0.53}
		"forge_impact_soft":
			# Meat and cloth have almost no tone to give; what is left is the noise of it.
			return {"frequency": 58.0, "duration": 0.160, "decay": 5.5, "noise": 0.62, "partial": 0.0}
	return {}


static func for_attack(profile: Resource, attack_kind: String, combo_index: int, primitive: Variant = null) -> Resource:
	var feedback: Variant = load("res://scripts/combat_feel/impact_feedback_profile.gd").new()
	# Hitstop belongs to what the object is made of, not to how fast it swings (P12: the
	# new layer needs channels of its own, taken from tempo rather than added beside it).
	feedback.hitstop_seconds = {
		"arrest": 0.064, "follow_through": 0.052, "rebound": 0.034,
	}.get(profile.contact_resolution, 0.048)
	# Named for what the object is made of, not for how heavy it is. Hearing is a finer
	# discriminator of material than swing timing is, which is why this channel moves too.
	# The combo stage does not overwrite this: it already has `impact_tier` to itself, so
	# the two stay separate fields rather than multiplying into nine blended names.
	feedback.sound_profile = {
		"arrest": "forge_impact_dead",
		"follow_through": "forge_impact_soft",
		"rebound": "forge_impact_ring",
	}.get(profile.contact_resolution, "forge_impact_medium")
	# Each resolution wins a different channel, because P08 forbids an axis on which one
	# value is simply worse. Arrest stops the target dead and owns hitstop. Follow-through
	# does not stop it, it shoves it, and owns knockback. Rebound throws the weapon back
	# instead of the target and owns recoil, which is what buys its short recovery.
	feedback.knockback_strength = {
		"arrest": 96.0, "follow_through": 152.0, "rebound": 82.0,
	}.get(profile.contact_resolution, 116.0)
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
