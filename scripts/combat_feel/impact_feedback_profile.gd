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
	match profile.tempo:
		"rapid":
			feedback.hitstop_seconds = 0.035
			feedback.knockback_strength = 82.0
			feedback.camera_shake_strength = 1.8
			feedback.sound_profile = "forge_impact_light"
		"committed":
			feedback.hitstop_seconds = 0.064
			feedback.knockback_strength = 152.0
			feedback.camera_shake_strength = 4.8
			feedback.sound_profile = "forge_impact_heavy"
		_:
			feedback.hitstop_seconds = 0.048
			feedback.knockback_strength = 116.0
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
