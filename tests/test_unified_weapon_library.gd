extends SceneTree

const STORE := preload("res://scripts/combat_feel/weapon_library_store.gd")
const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const RANGED := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
const SCAFFOLD := preload("res://scripts/combat_feel/firearm_visual_scaffold_pipeline.gd")
const DIRECTOR := preload("res://scripts/enemy_attack/automatic_encounter_director.gd")
const CAPABILITIES := preload("res://scripts/combat_feel/weapon_capability_catalog.gd")
const LOOP := preload("res://scenes/automatic_level_loop.tscn")

class LegacyFixtureArmory extends "res://scripts/combat_feel/player_weapon_armory.gd":
	var legacy_fixture: Dictionary = {}
	func _load_legacy_entries() -> Array[Dictionary]:
		return [legacy_fixture] if not legacy_fixture.is_empty() else []

var passed := 0
var failed := 0
var test_root := ""

func _initialize() -> void:
	test_root = "res://screenshots/unified_library_%d" % Time.get_ticks_usec()
	# Never publish synthetic fixtures to the player's real library or call AI.
	OS.set_environment("FORGE_WEAPON_LIBRARY_ROOT", ProjectSettings.globalize_path(test_root))
	OS.unset_environment("ANTHROPIC_API_KEY")
	OS.unset_environment("FORGE_SEMANTIC_MODEL")
	call_deferred("_run")

func _run() -> void:
	check("six structures preserve image, anchors, axes and animation on restart", _roundtrip)
	check("identical entry is idempotent and corrupt package is isolated", _corruption)
	check("incomplete publication never appears in the weapon picker", _incomplete)
	check("damaged newest session falls back to an earlier complete snapshot", _session_recovery)
	check("rewards persist, remain locked on failure and unlock without replacing equipment", _reward_lifecycle)
	check("rejected visual and sample entries do not publish", _reject_incomplete)
	check("capability coverage is name-independent and supports all six roles", _capability_coverage)
	check("general saved weapon appears in picker and finishes three battles", _general_loop)
	print("UNIFIED_WEAPON_LIBRARY_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(label: String, test: Callable) -> void:
	var outcome: Variant = test.call()
	if outcome is bool and outcome:
		passed += 1
		print("PASS | " + label)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [label, str(outcome)])

func store_for(name: String) -> RefCounted:
	var store := STORE.new()
	store.root_path = test_root.path_join(name)
	return store

func fixture(id: String) -> Dictionary:
	var entry: Dictionary
	if id == "firearm":
		var interpreted := INTERPRETER.new().interpret("M4A1", PackedByteArray(), {})
		var blueprint := interpreted.get("blueprint") as WeaponBlueprint
		var art := SCAFFOLD.fallback(blueprint)
		var runtime := RANGED.compile(blueprint.affordance, blueprint.affordance_source)
		blueprint.modifiers["ranged_runtime_profile"] = runtime
		entry = {"blueprint": blueprint, "asset": art.get("asset"), "ranged_runtime_profile": runtime}
	else:
		var asset_id := id if id not in ["radial", "stream"] else "rigid_staff_builtin"
		entry = LOADER.new().load_soft_weapon_asset(asset_id)
		if not bool(entry.get("ok", false)):
			return entry
		var blueprint := entry.get("blueprint") as WeaponBlueprint
		if id in ["radial", "stream"]:
			blueprint.affordance["state_topology"] = "radial_expand" if id == "radial" else "fixed"
			blueprint.affordance["activation_mode"] = "toggle" if id == "radial" else "continuous_hold"
			blueprint.affordance["functional_output"] = "contact_only" if id == "radial" else "directed_stream"
			blueprint.affordance["has_broad_face"] = id == "radial"
			var resolved := AXES.resolve_ai(entry.get("asset"), blueprint.affordance, blueprint.affordance_source)
			entry["affordance_profile"] = resolved.get("profile")
	entry["accepted_visual"] = true
	entry["visual_evidence"] = {"source": "OFFLINE_TEST_ONLY_NOT_GENERATED_ART"}
	entry["identity"] = "offline-test-" + id
	entry["display_name"] = "offline-test-" + id
	return entry

func _roundtrip() -> Variant:
	var store := store_for("roundtrip")
	for id: String in ["firearm", "rigid_staff_builtin", "fishing_rod_builtin", "continuous_lash_builtin", "radial", "stream"]:
		var original := fixture(id)
		var saved: Dictionary = store.save_entry(original)
		if not bool(saved.get("ok", false)):
			return {"id": id, "save": saved}
		var restarted := store_for("roundtrip")
		var restored: Dictionary = restarted.load_entry(str(saved.library_key))
		if not bool(restored.get("ok", false)):
			return restored
		var a := original.asset as WeaponVisualAsset
		var b := restored.asset as WeaponVisualAsset
		if original.blueprint.to_dict() != restored.blueprint.to_dict() or a.anchors_dict() != b.anchors_dict() or a.opaque_bounds != b.opaque_bounds:
			return "blueprint/anchor roundtrip changed: " + id
		if a.source_image.get_data() != b.source_image.get_data():
			return "image changed: " + id
		if a.visual_rig != null and (b.visual_rig == null or a.visual_rig.parts != b.visual_rig.parts or a.visual_rig.bindings != b.visual_rig.bindings):
			return "rig bindings changed: " + id
		if original.get("ranged_runtime_profile", {}) != restored.get("ranged_runtime_profile", {}):
			return "final ranged matrix changed"
	return store.load_entries().size() == 6

func _corruption() -> Variant:
	var store := store_for("corruption")
	var entry := fixture("fishing_rod_builtin")
	var first: Dictionary = store.save_entry(entry)
	var second: Dictionary = store.save_entry(entry)
	if not first.get("ok", false) or first.get("library_key") != second.get("library_key"):
		return [first, second]
	var other: Dictionary = store.save_entry(fixture("firearm"))
	if not other.get("ok", false):
		return other
	STORE._write_bytes(store.root_path.path_join("weapons").path_join(first.library_key).path_join("weapon.dat"), "corrupt test bytes".to_utf8_buffer())
	var entries: Array = store.load_entries()
	return entries.size() == 1 and entries[0].library_key == other.library_key and store.diagnostics.size() == 1

func _incomplete() -> Variant:
	var store := store_for("pending")
	DirAccess.make_dir_recursive_absolute(store.root_path.path_join("weapons/.pending_test"))
	return store.load_entries().is_empty() and store.diagnostics.is_empty()

func _session_recovery() -> Variant:
	var store := store_for("sessions")
	if not store.update_session({"equipped_key": "first"}).get("ok", false) or not store.update_session({"equipped_key": "second"}).get("ok", false):
		return "session writes failed"
	var names := DirAccess.get_files_at(store.root_path.path_join("sessions"))
	names.sort()
	STORE._write_bytes(store.root_path.path_join("sessions").path_join(names[-1]), "{}".to_utf8_buffer())
	return store_for("sessions").read_session().get("equipped_key") == "first"

func _reward_lifecycle() -> Variant:
	var armory := ARMORY.new()
	armory.library = store_for("reward")
	var old := fixture("firearm")
	if not armory.remember_equipped(old).get("ok", false):
		return "initial equip failed"
	var staged := armory.stage_reward(fixture("fishing_rod_builtin"))
	if not staged.get("ok", false):
		return staged
	var reward: Dictionary = staged.entry
	var restarted := LegacyFixtureArmory.new()
	restarted.library = store_for("reward")
	restarted.legacy_fixture = reward
	if restarted.pending_reward().get("library_key") != reward.library_key or restarted.library.load_entries().size() != 1:
		return "pending reward missing or exposed early"
	if restarted.load_entries().size() != 1:
		return "legacy visual cache bypassed reward lock"
	if restarted.remember_equipped(reward).get("ok", false):
		return "locked reward was equipped"
	restarted.record_run(old, false, {"defeated": 1})
	if restarted.library.load_entries().size() != 1:
		return "failed run unlocked a reward"
	restarted.record_run(old, true, {"defeated": 4})
	if restarted.library.load_entries().size() != 2 or restarted.library.read_session().equipped_key != old.library_key:
		return "completion replaced equipment or failed to unlock"
	if not restarted.remember_equipped(reward).get("ok", false):
		return "unlocked equip failed"
	return restarted.pending_reward().is_empty() and restarted.library.read_session().equipped_key == reward.library_key

func _reject_incomplete() -> Variant:
	var store := store_for("rejected")
	var entry := fixture("firearm")
	entry.accepted_visual = false
	if store.save_entry(entry).get("ok", false):
		return "unaccepted visual saved"
	entry.accepted_visual = true
	entry.blueprint.modifiers["local_sample_only"] = true
	if store.save_entry(entry).get("ok", false):
		return "sample saved"
	return store.load_entries().is_empty() and not STORE._data_only({"object": RefCounted.new()})

func _capability_coverage() -> Variant:
	var covered := {}
	for id: String in ["fishing_rod_builtin", "radial", "stream", "rigid_staff_builtin"]:
		var entry := fixture(id)
		var before := CAPABILITIES.roles_for_entry(entry)
		entry.blueprint.display_name = "anonymous"
		entry.blueprint.player_identity_text = "unrelated words"
		if before != CAPABILITIES.roles_for_entry(entry):
			return "identity changed capabilities"
		for role: String in before:
			covered[role] = true
	var light := fixture("rigid_staff_builtin")
	light.blueprint.affordance["mass_distribution"] = "rear"
	light.blueprint.affordance["contact_surface"] = "point"
	for role: String in CAPABILITIES.roles_for_entry(light):
		covered[role] = true
	return true if covered.size() == 6 else covered

func _general_loop() -> Variant:
	var entry := fixture("fishing_rod_builtin")
	var loop = LOOP.instantiate()
	loop.armory.library = store_for("loop")
	loop.armory.visual_cache_root = test_root.path_join("empty_legacy_cache")
	var saved: Dictionary = loop.armory.save_entry(entry)
	if not saved.get("ok", false):
		loop.free()
		return saved
	root.add_child(loop)
	var cards: int = loop.weapon_list.get_child_count()
	var handoff: Node = root.get_node("MechanismHandoff")
	if not str(handoff.store_entry(saved.entry)).is_empty() or not loop._take_mechanism_handoff():
		loop.free()
		return "complete-entry scene handoff failed"
	loop._begin_run(loop.equipped_entry)
	for index: int in range(3):
		loop._process(2.0)
		loop._on_stage_completed(str(loop.current_encounter.get("stage_name", "")), {"defeated": 1, "elapsed_seconds": 2.0, "attacks_used": 3})
	var state: Dictionary = loop.armory.library.read_session()
	var ok: bool = cards == 1 and loop.state == "completed" and state.last_run.completed and state.last_run.library_key == saved.library_key
	loop.free()
	return ok
