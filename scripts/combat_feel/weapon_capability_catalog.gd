class_name WeaponCapabilityCatalog
extends RefCounted

const STRATEGY := preload("res://scripts/combat_feel/weapon_strategy_compiler.gd")
const RANGED := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const ROLE_ORDER: Array[String] = ["control", "defense", "area", "reach", "breach", "mobility"]
const LABELS := {"control": "牵引与控制", "defense": "展开与防御", "area": "范围覆盖", "reach": "远距离作用", "breach": "穿透与破甲", "mobility": "轻快出手"}


static func roles_for_entry(entry: Dictionary) -> Array[String]:
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	return roles_for_blueprint(blueprint) if blueprint != null else []


static func roles_for_blueprint(blueprint: WeaponBlueprint) -> Array[String]:
	var runtime := {}
	if str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
		runtime = RANGED.compile(blueprint.affordance, blueprint.affordance_source)
	var profile := STRATEGY.compile(blueprint, WeaponVisualAsset.new(), runtime)
	var roles: Array[String] = []
	for requirement: Array in [["control", 0.52], ["defense", 0.45], ["area", 0.62], ["reach", 0.70], ["penetration", 0.68], ["mobility", 0.64]]:
		if float(profile.get(requirement[0], 0.0)) >= float(requirement[1]):
			roles.append("breach" if requirement[0] == "penetration" else str(requirement[0]))
	return roles


static func summary(entry: Dictionary) -> String:
	var labels: Array[String] = []
	for role: String in roles_for_entry(entry):
		labels.append(str(LABELS[role]))
	return " · ".join(labels) if not labels.is_empty() else "接触打击 · 把握出手距离"
