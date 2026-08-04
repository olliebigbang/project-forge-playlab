class_name ImpactFeedbackProfile
extends Resource

@export var hitstop_seconds := 0.060
@export var enemy_flash_seconds := 0.10
@export var knockback_strength := 120.0
@export var camera_shake_strength := 3.5
@export var particle_scale := 1.0
@export var sound_profile := "forge_impact_medium"
@export var stagger_strength := 0.55

static func for_attack(profile: Resource, attack_kind: String, combo_index: int) -> Resource:
	var feedback: Variant = load("res://scripts/combat_feel/impact_feedback_profile.gd").new()
	match profile.tempo:
		"rapid":
			feedback.hitstop_seconds = 0.040
			feedback.knockback_strength = 86.0
			feedback.camera_shake_strength = 2.0
			feedback.sound_profile = "forge_impact_light"
		"committed":
			feedback.hitstop_seconds = 0.080
			feedback.knockback_strength = 148.0
			feedback.camera_shake_strength = 4.6
			feedback.sound_profile = "forge_impact_heavy"
		_:
			feedback.hitstop_seconds = 0.060
			feedback.knockback_strength = 116.0
	if combo_index >= 3 or attack_kind == "charge":
		feedback.hitstop_seconds = minf(0.115, feedback.hitstop_seconds * 1.45)
		feedback.knockback_strength *= 1.62
		feedback.camera_shake_strength *= 1.55
		feedback.particle_scale = 1.65
		feedback.stagger_strength = 1.0
		feedback.sound_profile = "forge_impact_finisher"
	elif attack_kind == "dodge":
		feedback.knockback_strength *= 1.18
		feedback.particle_scale = 1.2
	return feedback
