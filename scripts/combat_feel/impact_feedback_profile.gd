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

static func for_attack(profile: Resource, attack_kind: String, combo_index: int, primitive: Variant = null) -> Resource:
	var feedback: Variant = load("res://scripts/combat_feel/impact_feedback_profile.gd").new()
	# Hitstop belongs to what the object is made of, not to how fast it swings (P12: the
	# new layer needs channels of its own, taken from tempo rather than added beside it).
	feedback.hitstop_seconds = {
		"arrest": 0.064, "follow_through": 0.052, "rebound": 0.034,
	}.get(profile.contact_resolution, 0.048)
	# Named for what the object is made of, not for how heavy it is. Hearing is a finer
	# discriminator of material than swing timing is, which is why this channel moves too.
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
		feedback.sound_profile = "forge_impact_charge"
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
		feedback.sound_profile = "forge_impact_finisher"
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
