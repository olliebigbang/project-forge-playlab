class_name CombatRules
extends RefCounted

static func base_damage(family: String) -> float:
	match family:
		"returning_thrown": return 24.0
		"heavy_melee": return 40.0
		_: return 9.0

static func damage_against(family: String, enemy_type: String, from_front: bool, modifiers: Dictionary = {}) -> float:
	var damage := base_damage(family) * float(modifiers.get("damage_multiplier", 1.0))
	if enemy_type == "guard" and from_front:
		damage *= 0.45
	if enemy_type == "guard" and family == "heavy_melee":
		damage *= 1.25
	return maxf(1.0, damage)

static func can_damage(family: String, enemy_type: String) -> bool:
	return family in WeaponBlueprint.BEHAVIOR_FAMILIES and enemy_type in ["swarmling", "rusher", "guard", "target"]

