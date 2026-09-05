extends SceneTree
## Explicit development asset packaging. Reads legacy cache WITHOUT upgrades;
## writes only new bundled packages. No AI or user's library mutation.
const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const SHELF := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const STORE := preload("res://scripts/combat_feel/weapon_library_store.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var source := ARMORY.new(); source.allow_legacy_cache_updates = false
	var saved := STORE.new(); saved.root_path = SHELF.STARTER_ROOT
	var kinds := {}
	for candidate: Dictionary in source.load_entries():
		if candidate.blueprint.affordance.get("weapon_domain", "") != "handheld_firearm": continue
		var kind: String = "one_hand" if candidate.blueprint.affordance.get("support_mode", "") == "one_hand" else "two_hand"
		if kinds.has(kind): continue
		var prepared := SHELF.prepare(candidate)
		if not prepared.get("ok", false): print("SAMPLE_REJECTED ", candidate.display_name, " ", prepared.get("error", "")); continue
		var result: Dictionary = saved.save_entry(prepared)
		if result.get("ok", false): kinds[kind] = candidate.display_name; print("PACKAGED_SAMPLE ", kind, " ", candidate.display_name, " ", result.library_key)
		if kinds.size() == 2: break
	print("PACKAGED_FIREARMS ", JSON.stringify(kinds)); quit(0 if kinds.size() == 2 else 1)
