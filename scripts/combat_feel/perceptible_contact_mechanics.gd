class_name PerceptibleContactMechanics
extends RefCounted

const CONTACT_VERBS: PackedStringArray = ["pin", "cleave", "shove", "sweep_control"]


static func verb_for(primitive: Variant) -> String:
	if primitive == null:
		return "none"
	match str(primitive.contact_surface):
		"point": return "pin"
		"edge": return "cleave"
		"broad": return "shove"
		"whole_body": return "sweep_control"
	return "none"


static func outcome_for(primitive: Variant, base_reaction: Dictionary, target_state: String = "") -> Dictionary:
	var verb := verb_for(primitive)
	var knockback: Vector2 = base_reaction.get("knockback", Vector2.ZERO)
	var stagger := float(base_reaction.get("stagger", 0.0))
	var outcome := {
		"verb": verb,
		"status": "",
		"status_seconds": 0.0,
		"knockback": knockback,
		"stagger": stagger,
		"damage_multiplier": 1.0,
		"immobilize": false,
		"interrupts_attack": false,
		"control_lock": false,
	}
	match verb:
		"pin":
			outcome["status"] = "PINNED"
			outcome["status_seconds"] = 0.82
			outcome["knockback"] = knockback * 0.08
			outcome["stagger"] = maxf(stagger, 0.92)
			outcome["immobilize"] = true
			outcome["interrupts_attack"] = target_state in ["tell", "attack", "charge"]
		"cleave":
			outcome["status"] = "CUT"
			outcome["status_seconds"] = 0.34
			outcome["knockback"] = knockback * 0.72
			outcome["stagger"] = stagger * 0.82
			outcome["damage_multiplier"] = 1.18
		"shove":
			outcome["status"] = "SHOVED"
			outcome["status_seconds"] = 0.58
			outcome["knockback"] = knockback * 1.72
			outcome["stagger"] = maxf(stagger, 0.82)
			outcome["interrupts_attack"] = target_state in ["tell", "attack", "charge"]
		"sweep_control":
			outcome["status"] = "CONTROLLED"
			outcome["status_seconds"] = 1.05
			outcome["knockback"] = knockback * 0.62
			outcome["stagger"] = maxf(stagger, 1.12)
			outcome["damage_multiplier"] = 0.84
			outcome["interrupts_attack"] = target_state in ["tell", "attack", "charge"]
			outcome["control_lock"] = true
	return outcome


static func color_for_verb(verb: String, alpha: float = 1.0) -> Color:
	var color := Color("94a3b8")
	match verb:
		"pin": color = Color("22d3ee")
		"cleave": color = Color("fb7185")
		"shove": color = Color("facc15")
		"sweep_control": color = Color("c084fc")
	color.a = clampf(alpha, 0.0, 1.0)
	return color


static func legend_for_verb(verb: String) -> String:
	match verb:
		"pin": return "POINT → PIN · narrow lane, stops one target"
		"cleave": return "EDGE → CLEAVE · cutting arc, higher damage"
		"shove": return "BROAD → SHOVE · displacement and interrupt"
		"sweep_control": return "WHOLE BODY → CONTROL · wide lock-down"
	return "NO CONTACT VERB"
