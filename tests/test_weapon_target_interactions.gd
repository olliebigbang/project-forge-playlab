extends SceneTree

const INTERACTION := preload("res://scripts/combat_feel/weapon_target_interaction_resolver.gd")
const PRIMITIVE := preload("res://scripts/combat_feel/motion_primitive.gd")
const ENEMY := preload("res://scripts/combat_feel/combat_feel_enemy.gd")
const ARENA := preload("res://scripts/systems/gameplay_arena.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	_run("Seven target-reaction axes have complete independent finite differences", _test_finite_difference_audit)
	_run("Point, edge, broad and whole-body contacts produce distinct target decisions", _test_contact_surface_reactions)
	_run("Flexible wrap entangles while a fishing hook pulls without inventing a rigid shove", _test_soft_weapon_reactions)
	_run("Ranged impact, penetration and cadence own stagger, breach and suppression", _test_ranged_reactions)
	_run("Target mass and armor resist the same weapon without changing weapon identity", _test_target_resistance)
	_run("Dictionary target runtime stores armor break, displacement and control timers", _test_arena_runtime_application)
	_run("Node target runtime exposes the same automatic interaction state", _test_enemy_runtime_application)
	_run("Runtime integrations consume the shared resolver for melee and projectiles", _test_runtime_integration_sources)
	_run("Resolver contains no weapon-model or enemy-identity branch", _test_identity_free_resolver)
	_run("Every interaction is automatic and never asks the player how it should work", _test_no_player_mechanism_input)
	print("WEAPON_TARGET_INTERACTION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _run(label: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	if result is bool and bool(result):
		passed += 1
		print("PASS | %s" % label)
	else:
		failed += 1
		printerr("FAIL | %s | %s" % [label, str(result)])


func _test_finite_difference_audit() -> Variant:
	var audit: Dictionary = INTERACTION.finite_difference_audit()
	if not bool(audit.get("ok", false)) or not bool(audit.get("passed", false)):
		return audit
	if (audit.get("axis_cases", {}) as Dictionary).size() != INTERACTION.EFFECT_AXES.size():
		return "not every effect axis was varied"
	if (audit.get("baseline_final_parameters", {}) as Dictionary).size() != INTERACTION.AUDITED_PARAMETERS.size():
		return "final clamp matrix is incomplete"
	for issue: String in [
		"zero_effect_axes", "duplicate_direction_groups", "covered_effects",
		"uncovered_parameters", "owner_mismatches",
	]:
		if not (audit.get(issue, []) as Array).is_empty():
			return "%s: %s" % [issue, str(audit.get(issue))]
	return true


func _test_contact_surface_reactions() -> Variant:
	var expected := {
		"point": "pin",
		"edge": "cleave",
		"broad": "shove",
		"whole_body": "stagger",
	}
	var actual := {}
	for surface: String in expected:
		var primitive := _primitive(surface, "thrust" if surface == "point" else "sweep")
		var profile: Dictionary = INTERACTION.compile_melee({}, primitive)
		var outcome: Dictionary = INTERACTION.resolve(
			profile,
			{"mass_class": "medium", "armor_integrity": 0.0, "state": "tell"},
			10.0,
			{"knockback": Vector2(100, 0), "stagger": 0.2}
		)
		actual[surface] = str(outcome.get("primary_reaction", ""))
	if actual != expected:
		return actual
	return true


func _test_soft_weapon_reactions() -> Variant:
	var wrap := _primitive("whole_body", "spin")
	wrap.flex_topology = "flexible_line"
	wrap.tether_mode = "wrap"
	wrap.tether_strength = 120.0
	var wrap_profile: Dictionary = INTERACTION.compile_melee({}, wrap)
	var wrap_outcome: Dictionary = INTERACTION.resolve(
		wrap_profile,
		{"mass_class": "medium", "armor_integrity": 0.0, "state": "attack"},
		8.0,
		{"knockback": Vector2(100, 0), "stagger": 0.2}
	)
	if str(wrap_outcome.get("primary_reaction", "")) != "entangle" or not bool(wrap_outcome.get("immobilize", false)):
		return "wrap did not entangle: %s" % str(wrap_outcome)

	var hook := _primitive("point", "sweep")
	hook.flex_topology = "flexible_line"
	hook.tether_mode = "hook"
	hook.tether_strength = 130.0
	var hook_profile: Dictionary = INTERACTION.compile_melee({}, hook)
	var hook_outcome: Dictionary = INTERACTION.resolve(
		hook_profile,
		{"mass_class": "medium", "armor_integrity": 0.0, "state": "approach"},
		8.0,
		{"knockback": Vector2(-100, 0), "stagger": 0.2}
	)
	if str(hook_outcome.get("primary_reaction", "")) != "hook_pull":
		return "hook did not pull: %s" % str(hook_outcome)
	if str(hook_outcome.get("displacement_mode", "")) != "toward_source" or bool(hook_outcome.get("immobilize", true)):
		return "hook collapsed into a wrap hold"
	return true


func _test_ranged_reactions() -> Variant:
	var light: Dictionary = INTERACTION.compile_ranged({
		"impact_force": "light", "penetration": "light", "cadence": "deliberate",
	})
	var strong: Dictionary = INTERACTION.compile_ranged({
		"impact_force": "strong", "penetration": "strong", "cadence": "rapid",
	})
	if float(strong.get("displacement_scale", 0.0)) <= float(light.get("displacement_scale", 0.0)):
		return "impact did not own displacement"
	if float(strong.get("stagger_seconds", 0.0)) <= float(light.get("stagger_seconds", 0.0)):
		return "impact did not own stagger"
	if float(strong.get("armor_damage_ratio", 0.0)) <= float(light.get("armor_damage_ratio", 0.0)):
		return "penetration did not own breach"
	if float(strong.get("suppression_seconds", 0.0)) <= float(light.get("suppression_seconds", 0.0)):
		return "cadence did not own suppression"
	return true


func _test_target_resistance() -> Variant:
	var profile: Dictionary = INTERACTION.compile_ranged({
		"impact_force": "strong", "penetration": "strong", "cadence": "balanced",
	})
	var light_target: Dictionary = INTERACTION.resolve(
		profile, {"mass_class": "light", "armor_integrity": 0.0, "state": "approach"},
		10.0, {"knockback": Vector2(20, 0), "stagger": 0.1}
	)
	var heavy_target: Dictionary = INTERACTION.resolve(
		profile, {"mass_class": "heavy", "armor_integrity": 0.0, "state": "approach"},
		10.0, {"knockback": Vector2(20, 0), "stagger": 0.1}
	)
	if Vector2(light_target.get("knockback", Vector2.ZERO)).length() <= Vector2(heavy_target.get("knockback", Vector2.ZERO)).length():
		return "mass resistance did not reduce displacement"
	var armored: Dictionary = INTERACTION.resolve(
		profile, {"mass_class": "heavy", "armor_integrity": 0.40, "state": "attack"},
		8.0, {"knockback": Vector2(20, 0), "stagger": 0.1}
	)
	if not bool(armored.get("armor_break", false)) or float(armored.get("armor_damage", 0.0)) < 0.40:
		return "strong breach did not break depleted armor"
	return true


func _test_arena_runtime_application() -> Variant:
	var arena: Node2D = ARENA.new()
	arena._spawn_enemy("guard", Vector2(800, 350), 120.0)
	var guard: Dictionary = arena.enemies[0]
	guard["armor_integrity"] = 0.40
	var profile: Dictionary = INTERACTION.compile_ranged({
		"impact_force": "strong", "penetration": "strong", "cadence": "rapid",
	})
	var outcome: Dictionary = INTERACTION.resolve(
		profile,
		{"mass_class": "heavy", "armor_integrity": 0.40, "state": "attack"},
		8.0,
		{"knockback": Vector2(22, 0), "stagger": 0.1}
	)
	var before: Vector2 = guard["pos"]
	arena._apply_target_interaction(guard, outcome)
	var ok: bool = float(guard.get("armor_integrity", 1.0)) == 0.0
	ok = ok and str(guard.get("interaction_status", "")) == "ARMOR BROKEN"
	ok = ok and float(guard.get("suppression_seconds", 0.0)) > 0.0
	ok = ok and Vector2(guard.get("pos", before)) != before
	arena.free()
	return true if ok else guard


func _test_enemy_runtime_application() -> Variant:
	var enemy: Node2D = ENEMY.new()
	enemy.setup(ENEMY.RAM, 1, Vector2.ZERO)
	enemy.armor_integrity = 0.40
	enemy.force_state("charge")
	var profile: Dictionary = INTERACTION.compile_ranged({
		"impact_force": "strong", "penetration": "strong", "cadence": "rapid",
	})
	var outcome: Dictionary = INTERACTION.resolve(
		profile,
		enemy.target_interaction_context(),
		8.0,
		{"knockback": Vector2(80, 0), "stagger": 0.1}
	)
	enemy.apply_hit(float(outcome["health_damage"]), Vector2(outcome["knockback"]), float(outcome["stagger"]), 7.0, outcome)
	var ok: bool = enemy.armor_integrity == 0.0 and enemy.state == "recovery"
	ok = ok and enemy.mechanism_status == "ARMOR BROKEN" and not enemy.last_target_interaction.is_empty()
	enemy.free()
	return true if ok else "node target did not store automatic reaction"


func _test_runtime_integration_sources() -> Variant:
	var slice_source := FileAccess.get_file_as_string("res://scripts/combat_feel/combat_feel_slice_0.gd")
	var arena_source := FileAccess.get_file_as_string("res://scripts/systems/gameplay_arena.gd")
	var open_arena_source := FileAccess.get_file_as_string("res://scripts/systems/open_identity_training_arena.gd")
	var ok := slice_source.contains("TARGET_INTERACTION.compile_melee")
	ok = ok and arena_source.contains("TARGET_INTERACTION.compile_ranged")
	ok = ok and arena_source.contains("_resolve_projectile_hit(projectile, enemy)")
	ok = ok and open_arena_source.contains("_resolve_projectile_hit(projectile, enemy)")
	return true if ok else "one runtime bypasses the shared target interaction resolver"


func _test_identity_free_resolver() -> Variant:
	var source := FileAccess.get_file_as_string("res://scripts/combat_feel/weapon_target_interaction_resolver.gd").to_lower()
	for forbidden: String in ["m4a1", "qbz", "type_81", "glock", "fishing_rod", "whip", "swarmling", "rusher", "guard"]:
		if source.contains(forbidden):
			return "identity branch leaked into resolver: %s" % forbidden
	return true


func _test_no_player_mechanism_input() -> Variant:
	var profiles: Array[Dictionary] = [
		INTERACTION.compile_melee({}, _primitive("broad", "bash")),
		INTERACTION.compile_ranged({"impact_force": "medium", "penetration": "medium", "cadence": "balanced"}),
	]
	for profile: Dictionary in profiles:
		if bool(profile.get("player_confirmation_required", true)) or bool(profile.get("player_mechanism_input_used", true)):
			return profile
	return true


func _primitive(surface: String, family: String) -> Resource:
	var primitive: Resource = PRIMITIVE.new()
	primitive.contact_surface = surface
	primitive.motion_family = family
	return primitive
