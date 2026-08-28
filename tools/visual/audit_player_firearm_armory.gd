extends SceneTree

const PLAYER_ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")


func _initialize() -> void:
	var armory = PLAYER_ARMORY.new()
	var entries: Array[Dictionary] = armory.load_entries()
	var summary: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var blueprint := entry.get("blueprint") as WeaponBlueprint
		var runtime := entry.get("ranged_runtime_profile", {}) as Dictionary
		summary.append({
			"identity": str(entry.get("identity", "")),
			"display_name": str(entry.get("display_name", "")),
			"family": str(blueprint.affordance.get("firearm_family", "")) if blueprint != null else "",
			"layout": str(blueprint.affordance.get("layout", "")) if blueprint != null else "",
			"automatic_fire": bool(runtime.get("automatic_fire", false)),
			"cycle_action_code": int(runtime.get("cycle_action_code", -1)),
			"reload_feed_code": int(runtime.get("reload_feed_code", -1)),
			"pellet_count": int(runtime.get("pellet_count", 1)),
			"magazine_size": int(runtime.get("magazine_size", 0)),
			"finished_art": entry.get("asset") is WeaponVisualAsset,
		})
	print("PLAYER_FIREARM_ARMORY_AUDIT=%s" % JSON.stringify({
		"entry_count": entries.size(),
		"entries": summary,
		"diagnostics": armory.last_load_diagnostics,
	}))
	quit(0)
