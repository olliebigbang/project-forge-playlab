extends SceneTree
const UI := preload("res://scripts/sunny_expedition/session.gd")
const LEGACY := preload("res://scripts/art_vertical_slice_v1/church_expedition.gd")
const LIBRARY := preload("res://scripts/art_vertical_slice_v1/expedition_library.gd")
const STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")
const CLIPS := preload("res://scripts/authored_player/melee_clip.gd")
const ENEMY_CATALOG := preload("res://scripts/enemy_attack/offline_enemy_blueprint_catalog.gd")
const SUNNY_RULES := preload("res://scripts/sunny_expedition/rules.gd")
const MECHANISM_UPGRADES := preload("res://scripts/sunny_expedition/mechanism_upgrade_system.gd")
const META_PROGRESSION := preload("res://scripts/sunny_expedition/meta_progression.gd")
const STORY := preload("res://scripts/sunny_expedition/story_content.gd")
const EXPEDITION_STORE := preload("res://scripts/art_vertical_slice_v1/expedition_store.gd")
const ENEMY_VISUAL := preload("res://scripts/sunny_expedition/enemy_visual_adapter.gd")
const RANGED_AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const ENEMY_ATTACK_RUNTIME := preload("res://scripts/enemy_attack/enemy_attack_runtime_driver.gd")
var failures: Array[String] = []
var checks := 0
class WaitingService extends RefCounted:
	var art_style_id := ""
	var use_semantic_cache := true
	func start(_text: String, _python: String) -> Dictionary: return {"status": "running", "stage": "object_identity"}
	func poll() -> Dictionary: return {"status": "running", "stage": "object_identity"}
	func cancel_current() -> void: pass

func _initialize() -> void:
	for key: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]: OS.unset_environment(key)
	OS.set_environment("FORGE_WEAPON_LIBRARY_ROOT", "res://.tools/sunny-tests/%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()])
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func run() -> void:
	var old_catalog := LIBRARY.new()
	var old_entries := old_catalog.load_all(false)
	var ui := UI.new(); ui.include_user_library = false; root.add_child(ui)
	await process_frame; ui.set_process(false); ui.arena.audio_enabled = false
	check(ui.flow == "hub" and ui.shelf.size() == 5, "Complete Sunny entry, five real AI packages; got=%s diagnostics=%s notice=%s" % [ui.shelf.map(func(entry: Dictionary) -> String: return str(entry.identity)), old_catalog.diagnostics, ui.library_notice])
	check(ui.meta_progress_label.position.y < 80.0 and ui.meta_progress_label.text.contains("工坊见闻") and ui.meta_progress_label.tooltip_text.contains("完整通关"), "Workshop insight is prominent in the hub header and explains when it settles")
	check(ui.campaign_chapter_count == 3 and SUNNY_RULES.CHAPTERS.size() == 3, "Sunny defaults to a three-leg first story chapter")
	check(ui.trial_run_button != null and ui.new_run_button.text.contains("故事远征"), "Hub separates the formal story expedition from the eight-enemy weapon trial")
	check(STORY.QUEST_SUMMARY.contains("忘潮") and STORY.route_ids().size() == 3, "First-region premise and three route contracts are authored content, not combat placeholder text")
	check(ui.campaign_store.directory.ends_with("sunny-expedition-v1"), "Separate checkpoint directory; Church saves untouched")
	check(not DirAccess.dir_exists_absolute(ui.campaign_store.directory), "Opening hub has no save mutation")
	check(ui.arena.background_textures.size() >= 1, "Single level has a ready background texture")
	var sunny_catalog := ENEMY_CATALOG.load_validated(SUNNY_RULES.SUNNY_CATALOG_PATH)
	check(bool(sunny_catalog.get("ok", false)), "Sunny enemy catalog passes the same local mechanism contract")
	var sunny_profiles: Dictionary = sunny_catalog.get("profiles_by_id", {})
	check(sunny_profiles.size() == 4, "Sunny campaign has four accepted enemy roles")
	var seen_roles := {}
	for ordinal: int in range(4):
		var profile := SUNNY_RULES.make_profile(0, ordinal, 0)
		seen_roles[str(profile.get("catalog_id", ""))] = true
	var elite_profile := SUNNY_RULES.make_profile(0, 0, 0, true)
	var champion_profile := SUNNY_RULES.make_profile(0, SUNNY_RULES.ROSTER.size(), 0, false)
	var champion_profiles_by_family := {}
	for ordinal: int in range(SUNNY_RULES.ROSTER.size(), SUNNY_RULES.ROSTER.size() + SUNNY_RULES.CHAMPION_INTERVAL * 5):
		var candidate := SUNNY_RULES.make_profile(0, ordinal, 0, false)
		if not bool(candidate.get("expedition_champion", false)):
			continue
		var declarations := candidate.get("enemy_modifier_declarations", []) as Array
		if declarations.size() == 1:
			champion_profiles_by_family[str((declarations[0] as Dictionary).get("family", ""))] = candidate
	seen_roles[str(elite_profile.get("catalog_id", ""))] = true
	check(seen_roles.size() == 4 and seen_roles.has("spring_hopper") and seen_roles.has("spore_raider") and seen_roles.has("wind_wisp") and seen_roles.has("thorn_guardian"), "All four fantasy roles enter the single-level spawn plan")
	check(SUNNY_RULES.SEAL_COUNT == 4 and SUNNY_RULES.SEGMENT_ENEMY_BUDGETS == [2, 2, 2, 1] and SUNNY_RULES.initial_spawns(0) == 2, "Quick route keeps four objectives and budgets seven ordinary enemies by segment")
	check(SUNNY_RULES.TOTAL_ENEMY_BUDGET == 8 and SUNNY_RULES.REGULAR_ENEMY_BUDGET + 1 == SUNNY_RULES.TOTAL_ENEMY_BUDGET and SUNNY_RULES.SEAL_SECONDS == 8.0, "Quick play is capped at eight total enemies with short roadpost holds")
	check(SUNNY_RULES.STORY_TOTAL_ENEMY_BUDGETS == [12, 14, 16] and SUNNY_RULES.story_segment_spawns(2, 3) == 3, "Formal story legs use escalating finite encounter budgets while trial stays short")
	for route_id: String in STORY.route_ids():
		var route_effects := STORY.route_combat(route_id)
		check(not route_effects.is_empty() and STORY.route(route_id).effect.length() > 0, "Story route %s declares both player-facing promise and combat parameters" % route_id)
	check(ui.start_story_run(23).get("ok", false) and ui.flow == "route_choice" and ui.campaign_chapter_count == 3, "Formal expedition opens with an authored route decision before combat")
	ui.dialog_primary.emit_signal(&"button_down")
	check(ui.flow == "briefing" and ui.story_route == "brook", "Brook route responds to the actual primary Button activation signal")
	check(ui.start_story_run(24).get("ok", false) and ui.flow == "route_choice", "Story route choice can be reopened for button regression coverage")
	ui.dialog_secondary.emit_signal(&"button_down")
	check(ui.flow == "briefing" and ui.story_route == "grove", "Grove route responds to the actual secondary Button activation signal")
	check(ui.start_story_run(23).get("ok", false) and ui.flow == "route_choice", "Story route choice can be reopened for the third button")
	ui.dialog_tertiary.emit_signal(&"button_down")
	check(ui.flow == "briefing" and ui.story_route == "ridge", "Ridge route responds to the actual tertiary Button activation signal")
	check(ui.begin_chapter().get("ok", false), "First formal story leg enters the shared combat runtime")
	check(ui.arena.journey_mode == STORY.MODE_STORY and ui.arena.stage_name == "sunny_story_expedition" and ui.arena.spawn_tells.size() == SUNNY_RULES.story_segment_spawns(0, 0), "Story combat replaces the two-enemy trial opening with the first leg budget")
	check(ui.arena.structure_cores == ["stability"] and ui.build_status_label.text.contains("旧风坡"), "Risk route grants its declared core and remains visible in the combat build strip")
	ui.arena.stop()
	ui._chapter_finished({"elapsed_seconds": 120.0, "defeated": 12, "damage_taken": 20})
	check(ui.flow == "route_choice" and ui.run_chapter == 1 and ui.dialog_body.text.contains("主动删去"), "Clearing a story leg reaches its interlude and asks for the next meaningful route")
	check(ui.choose_story_route("grove").get("ok", false) and ui.campaign_store.read_state().checkpoint.story_route == "grove", "Inter-leg route choice is checkpointed for interruption recovery")
	var carry_taken: Array[String] = []
	var carry_choices := MECHANISM_UPGRADES.build_choices(ui.entry.blueprint, ui.entry.blueprint.modifiers.get("ranged_runtime_profile", {}), 0, 23, carry_taken)
	var carry_option: Dictionary = carry_choices[0]
	ui.story_carry = {"forge_materials": 4, "structure_cores": ["control"], "upgrades": [{"id": carry_option.id, "title": carry_option.title, "effects": carry_option.effects}]}
	check(ui._checkpoint().get("ok", false) and EXPEDITION_STORE.valid(ui.campaign_store.read_state()), "Story build, materials and cores use the bounded interruption-save contract")
	check(ui.begin_chapter().get("ok", false), "Second story leg resumes after its route decision")
	check(ui.arena.forge_materials == 7 and ui.arena.structure_cores.has("control") and ui.arena.upgrade_history.size() == 1, "Chosen build and unspent loot persist while the grove route adds its declared three materials")
	check(str(ui.arena.upgrade_history[0].id) == str(carry_option.id) and ui.build_status_label.text.contains(str(carry_option.title)), "Restored mechanism choice remains active and visible instead of resetting between story legs")
	ui.arena.stop()
	ui.return_to_forge()
	check(MECHANISM_UPGRADES.CHOICE_COUNT == 3, "First three roadposts offer a three-choice mechanism build")
	check(bool(champion_profile.get("expedition_champion", false)) and str(champion_profile.get("reward_core_family", "")) == "control" and str((champion_profile.enemy_modifier_declarations[0] as Dictionary).get("family", "")) == "residue", "Periodic champion is compiled from its hazard axes and drops the matching anonymous core")
	check(champion_profiles_by_family.has("echo") and champion_profiles_by_family.has("residue") and champion_profiles_by_family.has("barrier"), "One route cadence can surface all three anonymous champion skills")
	var champion_skin_labels := {}
	var champion_skin_markers := {}
	for family: String in ["echo", "residue", "barrier"]:
		var skin := ENEMY_VISUAL.modifier_skin(family)
		champion_skin_labels[str(skin.get("label", ""))] = true
		champion_skin_markers[str(skin.get("silhouette_marker", ""))] = true
	check(champion_skin_labels.size() == 3 and champion_skin_markers.size() == 3, "Champion skills expose three distinct readable skin contracts")
	var no_taken: Array[String] = []
	var seed_choices_a: Array[Dictionary] = MECHANISM_UPGRADES.build_choices(ui.shelf[0].blueprint, ui.shelf[0].blueprint.modifiers.get("ranged_runtime_profile", {}), 0, 14, no_taken)
	var seed_choices_b: Array[Dictionary] = MECHANISM_UPGRADES.build_choices(ui.shelf[0].blueprint, ui.shelf[0].blueprint.modifiers.get("ranged_runtime_profile", {}), 0, 15, no_taken)
	check(JSON.stringify(seed_choices_a) != JSON.stringify(seed_choices_b), "A new run seed changes the offered mechanism build without changing the map direction")
	var core_choices: Array[Dictionary] = MECHANISM_UPGRADES.build_choices(ui.shelf[0].blueprint, ui.shelf[0].blueprint.modifiers.get("ranged_runtime_profile", {}), 0, 14, no_taken, {"material_count": 6, "material_cost": 3, "core_family": "stability"})
	var infused_choices: Array = core_choices.filter(func(option: Dictionary) -> bool: return bool(option.get("core_infused", false)))
	check(infused_choices.size() == 1 and str((infused_choices[0] as Dictionary).get("module_family", "")) == "stability", "A stored core guarantees exactly one compatible infused card without using object identity")
	check(core_choices.all(func(option: Dictionary) -> bool: return int(option.get("material_cost", 0)) == 3), "Every offered roadpost module has the same explicit forge-material cost")
	var first_clear: Dictionary = META_PROGRESSION.record_completion(META_PROGRESSION.empty(), ui.shelf[0].blueprint)
	var sampled_meta_families := {}
	for shelf_entry: Dictionary in ui.shelf:
		sampled_meta_families[META_PROGRESSION.family_for(shelf_entry.blueprint)] = true
	check(sampled_meta_families.size() >= 4, "The same family resolver spans firearms, rigid contacts and flexible objects without name-specific saves")
	var first_meta: Dictionary = first_clear.progression
	var first_reward: Dictionary = first_clear.reward
	check(int(first_meta.insight) == 2 and int(first_meta.completed_runs) == 1 and bool(first_reward.new_family), "First clear grants one clear insight plus one new mechanism-family insight")
	check(int(META_PROGRESSION.runtime_context(first_meta).rerolls_per_run) == 1 and (first_reward.new_unlocks as Array).has("reroll_1"), "First clear unlocks one capped roadpost reroll for future runs")
	var repeat_clear: Dictionary = META_PROGRESSION.record_completion(first_meta, ui.shelf[0].blueprint)
	check(int(repeat_clear.progression.insight) == 3 and not bool(repeat_clear.reward.new_family) and (repeat_clear.progression.mastered_families as Array).size() == 1, "Repeating a known structure advances slowly without duplicating family mastery")
	var advanced_meta := {"schema": META_PROGRESSION.SCHEMA, "insight": 4, "completed_runs": 2, "mastered_families": []}
	var advanced_context: Dictionary = META_PROGRESSION.runtime_context(advanced_meta)
	check(bool(advanced_context.advanced_modules_unlocked) and int(advanced_context.rerolls_per_run) == 1 and not advanced_context.has("damage"), "Meta progression unlocks breadth, not hidden permanent combat power")
	var saw_advanced := false
	for offer_seed: int in range(16):
		var advanced_choices: Array[Dictionary] = MECHANISM_UPGRADES.build_choices(ui.shelf[0].blueprint, ui.shelf[0].blueprint.modifiers.get("ranged_runtime_profile", {}), 0, offer_seed, no_taken, {}, advanced_context)
		for option: Dictionary in advanced_choices:
			saw_advanced = saw_advanced or str(option.get("meta_unlock", "")) == "advanced_modules"
	check(saw_advanced and seed_choices_a.all(func(option: Dictionary) -> bool: return not option.has("meta_unlock")), "Advanced cards enter only the unlocked pool and retain explicit tradeoffs")
	var save_candidate := {"schema": EXPEDITION_STORE.SCHEMA, "checkpoint": {}, "history": [], "selected_key": "", "meta_progression": advanced_meta}
	check(EXPEDITION_STORE.valid(save_candidate), "Versioned campaign store accepts the bounded optional meta-progression contract")
	var invalid_save: Dictionary = save_candidate.duplicate(true)
	invalid_save.meta_progression.insight = -1
	check(not EXPEDITION_STORE.valid(invalid_save), "Campaign store rejects corrupt negative progression instead of loading it")
	var invalid_carry: Dictionary = save_candidate.duplicate(true)
	invalid_carry.checkpoint = {"chapter": 1, "seed": 1, "health": 100, "supplies": 2, "weapon_key": "a".repeat(64), "metrics": {}, "run_mode": "story", "story_route": "brook", "story_carry": {"forge_materials": 2, "structure_cores": ["made_up_core"], "upgrades": []}}
	check(not EXPEDITION_STORE.valid(invalid_carry), "Campaign store rejects invented story cores instead of replaying untrusted effects")
	var m4_entry: Dictionary = {}
	for shelf_entry: Dictionary in ui.shelf:
		if str(shelf_entry.identity).contains("M4A1"): m4_entry = shelf_entry; break
	var m4_blueprint: WeaponBlueprint = m4_entry.get("blueprint") as WeaponBlueprint
	var m4_runtime := RANGED_AXES.compile(m4_blueprint.affordance, m4_blueprint.affordance_source) if m4_blueprint != null else {}
	var m249_payload := JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/firearm_ai_m249_response_v4.json")) as Dictionary
	var m249_declaration := (m249_payload.get("declaration", {}) as Dictionary).duplicate(true)
	m249_declaration["source"] = "AI_TEST_FIXTURE_FIREARM_IDENTITY_V4"
	m249_declaration["confidence"] = 0.98
	var m249_runtime := RANGED_AXES.compile(m249_declaration, "AI_TEST_FIXTURE_FIREARM_IDENTITY_V4")
	check(float(m4_runtime.get("muzzle_climb_cap_degrees", 0.0)) == 4.0 and float(m249_runtime.get("muzzle_climb_cap_degrees", 0.0)) == 16.0, "Declared low/high climb axes keep M4 controllable and M249 dramatic: M4=%s M249=%s" % [m4_runtime, m249_runtime])
	var roadposts: Array = SUNNY_RULES.ROADPOSTS
	check(roadposts[0].x < roadposts[1].x and roadposts[1].x < roadposts[2].x and roadposts[2].x < roadposts[3].x, "Roadposts form a strictly forward side-scrolling route")
	check(SUNNY_RULES.ROUTE_WORLD_LENGTH > 1280.0 * 3.0 and roadposts[-1].x > 1280.0 * 2.0, "Route spans several real viewports instead of one static arena")
	check(SUNNY_RULES.seal_health_reward(0) == 10.0 and SUNNY_RULES.seal_supply_reward(0) == 1, "Continuous level earns limited roadpost sustain without erasing attrition")
	check(sunny_profiles.spring_hopper.mass_class == "light" and float(sunny_profiles.spring_hopper.armor_integrity) == 0.0, "Spring mushroom is a light unarmored control target")
	check(sunny_profiles.spore_raider.mass_class == "medium" and float(sunny_profiles.spore_raider.armor_integrity) > 0.0, "Spore raider resists light displacement better than the spring mushroom")
	check(sunny_profiles.wind_wisp.mass_class == "light" and float(sunny_profiles.wind_wisp.move_speed) > float(sunny_profiles.thorn_guardian.move_speed), "Wisp and thorn guardian have different mass and mobility answers")
	check(sunny_profiles.thorn_guardian.mass_class == "heavy" and float(sunny_profiles.thorn_guardian.armor_integrity) == 1.0, "Thorn guardian is the heavy armored finish")
	var spring_attacks := sunny_profiles.spring_hopper.attack_declarations as Array
	var spore_attacks := sunny_profiles.spore_raider.attack_declarations as Array
	var wind_attacks := sunny_profiles.wind_wisp.attack_declarations as Array
	var thorn_attacks := sunny_profiles.thorn_guardian.attack_declarations as Array
	check(str((spring_attacks[1].axes as Dictionary).get("hazard_mode", "")) == "lingering", "Spring landing leaves a compiled lingering ground answer")
	check(str((spore_attacks[0].axes as Dictionary).get("delivery", "")) == "rush" and str((spore_attacks[0].axes as Dictionary).get("tempo", "")) == "committed" and str((spore_attacks[0].axes as Dictionary).get("recovery", "")) == "extended", "Spore raider keeps the readable interruptible line charge role")
	check(str((wind_attacks[0].axes as Dictionary).get("delivery", "")) == "contact" and str((wind_attacks[0].axes as Dictionary).get("target_lock", "")) == "live_until_active", "Wisp close answer tracks briefly without reusing the raider rush")
	check(str((wind_attacks[1].axes as Dictionary).get("delivery", "")) == "marked_impact" and str((wind_attacks[1].axes as Dictionary).get("hit_shape", "")) == "strip" and str((wind_attacks[1].axes as Dictionary).get("hazard_mode", "")) == "pulsing", "Wisp far answer compiles a warned pulsing lane seal")
	var wisp_runtime := ENEMY_ATTACK_RUNTIME.new()
	check(bool(wisp_runtime.configure(wind_attacks).get("ok", false)), "Wisp role declarations configure through the generic attack runtime")
	var wisp_far_start := wisp_runtime.begin_attack({"distance_pixels": 430.0, "depth_delta_pixels": 40.0, "available_coordination_budget": 1, "clear_path": true}, Vector2.ZERO, Vector2(430, 40))
	check(bool(wisp_far_start.get("ok", false)) and str(wisp_far_start.get("delivery", "")) == "marked_impact", "Far wisp selects its road-blocking pressure slot")
	# The warning follows during telegraph, freezes at commit, then must ignore a
	# later player move. This mirrors what the player sees and can react to.
	wisp_runtime.step(0.78, Vector2.ZERO, Vector2(460, 30))
	var wisp_far_active := wisp_runtime.step(0.20, Vector2.ZERO, Vector2(500, -50))
	var wisp_lane_event := wisp_far_active.get("activation_event", {}) as Dictionary
	check(str(wisp_lane_event.get("delivery", "")) == "marked_impact" and Vector2(wisp_lane_event.get("origin", Vector2.ZERO)) == Vector2(460, 30) and str((wisp_lane_event.get("hit_region", {}) as Dictionary).get("shape", "")) == "strip", "Wisp lane freezes the warned commit point instead of secretly following the player")
	check(str((thorn_attacks[0].axes as Dictionary).get("defense_mode", "")) == "frontal_guard" and str((thorn_attacks[1].axes as Dictionary).get("defense_mode", "")) == "channel_guard", "Thorn close and far actions expose different directional defense windows")
	check((elite_profile.get("enemy_modifier_declarations", []) as Array).size() == 1 and str((elite_profile.enemy_modifier_declarations[0] as Dictionary).get("family", "")) == "barrier", "Final guardian receives one visible compiled barrier charge")
	check(is_equal_approx(float(elite_profile.get("attack_tempo_multiplier", -1.0)), 1.0), "Sunny clean tempo no longer claims the old 1.03 value that runtime clamped to zero effect")
	var visual_kinds := {}
	var visual_textures := {}
	for enemy_id: String in ["spring_hopper", "spore_raider", "wind_wisp", "thorn_guardian"]:
		var sample: Dictionary = ui.arena.enemy_frame_sample({"blueprint_id": enemy_id, "id": 900, "facing": 1.0, "expedition_elite": enemy_id == "thorn_guardian"}, {})
		visual_kinds[str(sample.visual_kind)] = true
		visual_textures[int((sample.texture as Texture2D).get_instance_id())] = true
		check(Rect2i(sample.used).has_area() and (sample.image as Image).get_region(sample.region).get_used_rect().has_area(), "Enemy frame uses real non-empty Alpha: " + enemy_id)
	check(visual_kinds.size() == 4 and visual_textures.size() == 4, "Four fantasy roles have four distinct same-family silhouettes")
	var spore_spec: Dictionary = ui.arena._enemy_visual_spec("spore_raider")
	check((spore_spec.secondary_action_texture as Texture2D).get_width() == int(spore_spec.secondary_action_frame_size.x) * int(spore_spec.secondary_action_frames), "Spore breath sheet has ten complete authored frames")
	var thorn_spec: Dictionary = ui.arena._enemy_visual_spec("thorn_guardian")
	check((thorn_spec.action_texture as Texture2D).get_width() == int(thorn_spec.action_frame_size.x) * int(thorn_spec.action_frames), "Thorn guardian shoot sheet has twelve complete authored frames")
	var smear: Dictionary = ui.arena.source_rig.frame("combat/StandingSlash", 1)
	check(smear.body_pixels.size() == 104, "Torso motion fleck excluded without editing source")
	check(ui.arena.source_rig._usable_arm(ui.arena.source_rig.full_arm_frame(smear), "RightArm"), "Smear source frame uses a clear original limb")
	var thrust: Dictionary = ui.arena.source_rig.frame("combat/SwordCombo03", 1)
	check(thrust.body_pixels.size() == 88, "Real nine-pixel neck island retained beside Head")
	check(ui.arena._enemy_ground_draw_offset() == ui.arena.FEET_OFFSET, "Ground warnings and ground hits share feet projection")
	for i: int in range(ui.shelf.size()):
		var item: Dictionary = ui.shelf[i]
		check(UI.validate_entry(item, "sunny_v1").get("ok", false), "Sunny accepted style + real alpha + runtime")
		check(LEGACY.validate_entry(old_entries[i]).get("ok", false), "Old Church item unchanged")
		var original: WeaponVisualAsset = old_entries[i].asset
		var styled: WeaponVisualAsset = item.asset
		check(original.grip_primary == styled.grip_primary and original.grip_secondary == styled.grip_secondary and original.tip == styled.tip, "Palette conversion preserves grips and contacts")
		var same_alpha := true
		for y: int in range(96):
			for x: int in range(96):
				if original.source_image.get_pixel(x, y).a != styled.source_image.get_pixel(x, y).a: same_alpha = false
		check(same_alpha, "Exact alpha retained, no inflated silhouette")
		ui.select_weapon(i)
		if i == 0:
			ui.meta_progression = advanced_meta.duplicate(true)
			ui.campaign["meta_progression"] = ui.meta_progression.duplicate(true)
		check(ui.start_trial_run(14).get("ok", false), "Trial start persists this chosen weapon")
		check(ui.begin_chapter().get("ok", false), "Real arena configured")
		var arena: Node = ui.arena
		if i == 0:
			check(arena.upgrade_rerolls_remaining == 1 and bool(arena.meta_context.advanced_modules_unlocked), "A new run receives only the meta abilities earned before departure")
		check(arena.stage_name == "sunny_trial_route", "No accidental Church runtime entry")
		check(arena._world_bounds().size.x > 4000.0 and arena.seal_position == roadposts[0], "Combat uses wide authoritative world coordinates")
		if i == 0:
			arena.enemies.clear()
			arena._spawn_enemy_blueprint(elite_profile, Vector2(arena.player_position) + Vector2(260, 0))
			var elite_runtime: Variant = arena.enemies[0].attack_runtime
			check(int(elite_runtime.snapshot().get("barrier_charges_remaining", 0)) == 1, "Elite modifier declarations reach the live arena runtime")
			var guarded_outcome: Dictionary = arena._resolve_enemy_defense(arena.enemies[0], {"health_damage": 20.0, "stagger_seconds": 0.2, "interrupt_strength": 0.2}, arena.player_position)
			check(is_equal_approx(float(guarded_outcome.get("health_damage", 0.0)), 3.6) and is_equal_approx(float(guarded_outcome.get("interrupt_strength", 0.0)), 0.05) and str((guarded_outcome.enemy_defense as Dictionary).get("source", "")) == "barrier", "Live barrier reduces damage and interrupt strength instead of being display-only")
			arena.enemy_attack_hazards.clear()
			arena.player_health = 100.0
			arena.invulnerable_timer = 0.0
			arena._spawn_enemy_attack_hazard(arena.enemies[0], {
				"schema": "forge-enemy-attack-echo-event-v1",
				"delivery": "contact",
				"origin": arena.player_position - Vector2(24, 0),
				"locked_direction": Vector2.RIGHT,
				"hazard_lifetime_seconds": 0.24,
				"hit_region": {"shape": "capsule", "length_pixels": 64.0, "width_pixels": 36.0, "path_mode": "same_lane", "depth_tolerance_pixels": 38.0},
				"danger_zone": {"mode": "instant", "contact_mode": "single"},
				"damage_multiplier": 0.58,
			})
			check(arena.enemy_attack_hazards.size() == 1 and str((arena.enemy_attack_hazards[0] as Dictionary).get("effect_family", "")) == "echo", "A delayed close/rush echo reaches the world hazard bridge")
			arena._update_enemy_attack_hazards(0.02)
			check(arena.player_health < 100.0, "A visibly repeated close-region echo uses the compiled region for real damage")
			arena.enemy_attack_hazards.clear()
			arena.player_health = 100.0
			arena.invulnerable_timer = 0.0
			arena._spawn_enemy_attack_hazard(arena.enemies[0], {
				"schema": "forge-enemy-attack-activation-event-v1",
				"delivery": "rush",
				"origin": arena.player_position - Vector2(35, 0),
				"locked_direction": Vector2.RIGHT,
				"hazard_lifetime_seconds": 1.65,
				"hit_region": {"shape": "strip", "length_pixels": 92.0, "width_pixels": 42.0, "path_mode": "same_lane", "depth_tolerance_pixels": 44.0},
				"danger_zone": {"mode": "lingering", "contact_mode": "continuous", "repeat_hit_cooldown_seconds": 0.38, "damage_multiplier": 0.45, "persists_after_active": true, "modifier_source": "residue"},
			})
			check(arena.enemy_attack_hazards.size() == 1 and str((arena.enemy_attack_hazards[0] as Dictionary).get("effect_family", "")) == "residue", "A residue rush leaves its compiled path in the world instead of becoming zero-effect")
			arena._update_enemy_attack_hazards(0.02)
			check(arena.player_health < 100.0 and arena.enemy_attack_hazards.size() == 1, "The residual rush path remains and deals reduced repeatable damage")
			arena.enemy_attack_hazards.clear()
			arena.player_health = 100.0
			arena.invulnerable_timer = 0.0
			arena._spawn_enemy_attack_hazard(arena.enemies[0], {"delivery": "marked_impact", "origin": arena.player_position, "hazard_lifetime_seconds": 1.8, "hit_region": {"shape": "circle", "radius_pixels": 44.0}, "danger_zone": {"mode": "lingering", "contact_mode": "continuous", "repeat_hit_cooldown_seconds": 0.32, "damage_multiplier": 0.45}})
			arena._update_enemy_attack_hazards(0.10)
			check(arena.player_health < 100.0 and arena.enemy_attack_hazards.size() == 1, "Live lingering zone deals repeatable damage and remains in the arena")
			arena.enemy_attack_hazards.clear()
			arena.projectiles.clear()
			arena.weapon_muzzle_climb_degrees = float(arena.ranged_runtime_profile.get("muzzle_climb_cap_degrees", 0.0))
			var base_projectile_life := float(arena.ranged_runtime_profile.get("projectile_life_seconds", 0.0))
			arena._fire_bullet()
			var steep_projectile: Dictionary = arena.projectiles[0]
			var horizontal_factor := float(steep_projectile.get("ballistic_horizontal_factor", 1.0))
			check(horizontal_factor < 1.0 and is_equal_approx(float(steep_projectile.life) * horizontal_factor, base_projectile_life), "Angled recoil round keeps its declared horizontal lifetime")
			check(steep_projectile.has("ground_lane_origin_y") and is_equal_approx(float(steep_projectile.ground_lane_origin_y), arena.player_position.y), "Shot records its real starting lane")
			arena.projectiles.clear()
			arena.weapon_muzzle_climb_degrees = 0.0
			arena.sustained_muzzle_climb_degrees = 0.0
			arena.enemies.clear()
			var diagonal_enemy_position: Vector2 = Vector2(arena.player_position) + Vector2(320, -70)
			arena._spawn_enemy_blueprint(sunny_profiles.wind_wisp, diagonal_enemy_position)
			var diagonal_enemy: Dictionary = arena.enemies[0]
			var collision_sample: Dictionary = arena._collision_sample(diagonal_enemy)
			var opaque_point := Vector2.ZERO
			var found_opaque := false
			var sample_bounds := Rect2(collision_sample.bounds)
			for sample_y: int in range(floori(sample_bounds.position.y), ceili(sample_bounds.end.y), 2):
				for sample_x: int in range(floori(sample_bounds.position.x), ceili(sample_bounds.end.x), 2):
					var candidate := Vector2(sample_x, sample_y)
					if arena._alpha_contact(candidate, 1.0, collision_sample):
						opaque_point = candidate
						found_opaque = true
						break
				if found_opaque: break
			var lane_delta: float = diagonal_enemy_position.y - Vector2(arena.player_position).y
			var diagonal_probe := {"ground_lane_y": arena.player_position.y, "ground_lane_origin_y": arena.player_position.y, "origin": Vector2(opaque_point.x - 120, opaque_point.y - lane_delta), "projectile_radius_pixels": 1.0}
			var flat_probe := diagonal_probe.duplicate(true)
			flat_probe.origin = Vector2(opaque_point.x - 120, opaque_point.y)
			check(found_opaque and arena._projectile_contacts_enemy(opaque_point, opaque_point, diagonal_probe, diagonal_enemy), "A visible recoil diagonal can hit the matching higher/lower enemy lane")
			check(not arena._projectile_contacts_enemy(opaque_point, opaque_point, flat_probe, diagonal_enemy), "A flat shot still cannot phantom-hit a different ground lane")
			arena.enemies.clear()
			var material_before_reward: int = arena.forge_materials
			var normal_reward_profile := SUNNY_RULES.make_profile(0, 0, 0)
			arena._spawn_enemy_blueprint(normal_reward_profile, arena.player_position + Vector2(180, 0))
			var normal_reward_enemy: Dictionary = arena.enemies[0]
			arena._damage_enemy(normal_reward_enemy, float(normal_reward_enemy.max_hp) + 1.0)
			arena._damage_enemy(normal_reward_enemy, 1.0)
			check(arena.forge_materials == material_before_reward + 1, "An ordinary enemy grants one material exactly once on real lethal damage")
			arena.enemies.clear()
			arena._spawn_enemy_blueprint(normal_reward_profile, arena.player_position + Vector2(180, 0))
			var residual_reward_enemy: Dictionary = arena.enemies[0]
			residual_reward_enemy.hp = 0.1
			residual_reward_enemy.burn = 1.0
			arena._update_enemies(0.1)
			check(arena.forge_materials == material_before_reward + 2, "A residual-damage death enters the same reward ledger before filtering")
			arena.enemies.clear()
			arena._spawn_enemy_blueprint(champion_profile, arena.player_position + Vector2(180, 0))
			var champion_reward_enemy: Dictionary = arena.enemies[0]
			arena._damage_enemy(champion_reward_enemy, float(champion_reward_enemy.max_hp) + 1.0)
			check(arena.forge_materials == material_before_reward + 4 and arena.structure_cores == ["control"], "A mechanism champion grants two materials plus its compiled structure core")
			arena.enemies.clear()
		var opening_roles := {}
		for tell: Dictionary in arena.spawn_tells: opening_roles[str(tell.profile.get("catalog_id", ""))] = true
		check(opening_roles.size() == SUNNY_RULES.segment_spawns(0) and arena.spawn_tells.size() == 2, "Opening roadpost schedules only its two-enemy budget")
		check(not arena._objective_completion_allowed(), "Road barrier stays locked while the segment wave remains")
		arena.seal_progress = SUNNY_RULES.SEAL_SECONDS
		arena.player_position = arena.seal_position
		arena._process(0.1)
		check(arena.seal_index == 0 and arena.seal_progress == SUNNY_RULES.SEAL_SECONDS, "Full roadpost waits at one hundred percent until the local wave is cleared")
		arena.spawn_tells.clear(); arena.enemies.clear()
		var upgrade_before: Dictionary = arena.combat_upgrade_snapshot()
		arena._process(0.1)
		check(ui.flow == "upgrade" and arena.seal_index == 0, "Cleared roadpost pauses forward travel for a build choice")
		check(ui.pending_upgrade_choices.size() == 3, "Exactly three run-only choices are visible")
		var choice_ids := {}
		var choice_categories := {}
		var choices_are_structural := true
		var contact_basis_seen: bool = arena._uses_firearm_runtime()
		for option: Dictionary in ui.pending_upgrade_choices:
			choice_ids[str(option.id)] = true
			choice_categories[str(option.category)] = true
			choices_are_structural = choices_are_structural and not str(option.basis).is_empty() and not JSON.stringify(option).contains(str(item.identity))
			contact_basis_seen = contact_basis_seen or str(option.basis).contains(str(arena.blueprint.affordance.get("contact_surface", "")))
		check(choice_ids.size() == 3 and choice_categories.size() == 3, "Choice columns are distinct advantage, style and tradeoff mechanisms")
		check(choices_are_structural and contact_basis_seen, "Choice evidence comes from axes/runtime, never the object name")
		if i == 0:
			var ids_before_reroll: Array[String] = []
			for option: Dictionary in ui.pending_upgrade_choices: ids_before_reroll.append(str(option.id))
			var materials_before_reroll: int = arena.forge_materials
			var cores_before_reroll: Array = arena.structure_cores.duplicate()
			var rerolled: Dictionary = ui.reroll_upgrade_choices()
			var ids_after_reroll: Array[String] = []
			for option: Dictionary in ui.pending_upgrade_choices: ids_after_reroll.append(str(option.id))
			check(bool(rerolled.get("ok", false)) and ids_after_reroll != ids_before_reroll and arena.upgrade_rerolls_remaining == 0, "Reroll deterministically replaces the three-card offer and spends exactly one run charge")
			check(arena.forge_materials == materials_before_reroll and arena.structure_cores == cores_before_reroll and int(arena.metrics.upgrade_rerolls_used) == 1, "Reroll preserves earned materials/cores and records its real use")
		var chosen_index := i % 3
		if i == 0:
			for option_index: int in range(ui.pending_upgrade_choices.size()):
				if bool(ui.pending_upgrade_choices[option_index].get("core_infused", false)):
					chosen_index = option_index
					break
		var chosen_upgrade: Dictionary = ui.choose_upgrade(chosen_index)
		check(chosen_upgrade.get("ok", false) and ui.flow == "combat", "Selecting a choice resumes the same horizontal run")
		check(arena.combat_upgrade_snapshot() != upgrade_before and arena.upgrade_history.size() == 1, "Selected upgrade has a non-zero combat effect and is recorded")
		if i == 0:
			check(str(chosen_upgrade.record.get("core_consumed", "")) == "control" and arena.structure_cores.is_empty() and arena.forge_materials == 1, "Selecting the infused card spends three materials and consumes its matching core")
		arena._process(0.1)
		check(arena.seal_index == 1 and arena.metrics.upgrades.size() == 1, "Road barrier opens only after the applied choice")
		arena.seal_progress = 0.0
		arena.player_position = Vector2(1500, arena.seal_position.y)
		arena._update_route_camera(1.0)
		check(arena.route_camera_x > 0.0 and arena.player_position.x - arena.route_camera_x <= 1080.0, "Camera follows world travel without moving combat coordinates")
		arena.route_camera_x = 0.0
		arena.player_position = arena.seal_position
		arena._process(0.1)
		check(arena.seal_progress == 0.0 and arena.spawn_tells.size() == SUNNY_RULES.segment_spawns(1), "Approaching the next roadpost schedules exactly its finite wave before charging")
		arena.spawn_tells.clear(); arena.enemies.clear()
		arena._process(0.1)
		check(arena.seal_progress > 0, "Earn progress on actual visible objective after its finite wave is cleared")
		ui.pause_run(); var clock: float = arena.chapter_clock; ui._process(1)
		check(arena.chapter_clock == clock, "Pause freezes clock")
		ui.resume_combat()
		if arena.melee_runtime.profile != null:
			var recipe: Resource = arena.melee_runtime.profile.combo_recipe
			var grammar := str(arena.melee_runtime.profile.compile_trace.get("presentation_grammar", "generic"))
			var seen_presentations := PackedStringArray()
			var seen_planes := PackedStringArray()
			var combo_body_clips: Dictionary = {}
			for slot: String in ["hit_1", "hit_2", "hit_3", "charge_attack", "dodge_attack"]:
				var p: Resource = recipe.get(slot)
				seen_presentations.append(str(p.presentation_family))
				seen_planes.append(str(p.trajectory_plane))
				print("MOTION ", item.identity, " ", slot, " ", p.motion_family, " ", p.contact_anchor, " angles=", p.start_angle, "..", p.end_angle)
				for phase: String in ["startup", "active", "recovery"]:
					for step: int in range(11):
						var frame: Dictionary
						var spec: Dictionary
						if p.presentation_family == "default":
							frame = CLIPS.sample(arena.source_rig, p.motion_family, phase, step / 10.0)
							spec = CLIPS.CLIPS[p.motion_family]
						else:
							frame = CLIPS.sample_presentation(arena.source_rig, p.presentation_family, phase, step / 10.0)
							spec = CLIPS.PRESENTATION_CLIPS[p.presentation_family]
						check(frame.key == spec.key and frame.index >= spec[phase][0] and frame.index <= spec[phase][1], "Authored phase stays in its reviewed range")
						if slot in ["hit_1", "hit_2", "hit_3"]: combo_body_clips[str(spec.key)] = true
				if p.presentation_family == "default" and p.motion_family == "sweep" and slot == "hit_2": check(absf(p.end_angle - p.start_angle) > 1.5, "Reverse sweep not collapsed")
			if grammar == "polearm_point":
				check(seen_presentations == PackedStringArray(["pole_jab", "pole_rake", "pole_pin", "pole_charge", "pole_dodge"]), "Rigid two-hand point lever uses the complete pole action sequence")
				check(seen_planes == PackedStringArray(["thrust_line", "ground_sweep", "screen_arc", "screen_arc", "thrust_line"]), "Pole sequence declares thrust, ground sweep and screen-plane plant explicitly")
				check(combo_body_clips.size() == 3, "Pole combo uses three distinct authored body actions instead of one repeated push")
				check(recipe.hit_2.start_angle < -2.50 and recipe.hit_2.end_angle > 0.20 and recipe.hit_3.start_angle < -0.70 and recipe.hit_3.end_angle > 0.35, "Pole combo contains a rear-to-front ground sweep and overhead plant")
				var rear_projection: Dictionary = arena.melee_runtime._trajectory_projection(float(recipe.hit_2.start_angle), str(recipe.hit_2.trajectory_plane), 1.0)
				var edge_projection: Dictionary = arena.melee_runtime._trajectory_projection(-PI * 0.5, str(recipe.hit_2.trajectory_plane), 1.0)
				var front_projection: Dictionary = arena.melee_runtime._trajectory_projection(float(recipe.hit_2.end_angle), str(recipe.hit_2.trajectory_plane), 1.0)
				check(float(rear_projection.depth_layer) < -0.25 and float(front_projection.depth_layer) > 0.25, "Ground sweep crosses from the rear draw layer to the front draw layer")
				check(float(edge_projection.longitudinal_scale) <= 0.31, "Ground sweep visibly foreshortens when the pole points through camera depth")
				arena.melee_runtime.configure(item.blueprint, item.asset)
				var live_sequence := PackedStringArray()
				for _attack: int in range(3):
					arena.melee_runtime.input_attack(true, false)
					live_sequence.append(str(arena.melee_runtime.primitive().presentation_family))
					for _tick: int in range(240):
						if not arena.melee_runtime.busy(): break
						arena.melee_runtime.tick(1.0 / 120.0)
				check(live_sequence == PackedStringArray(["pole_jab", "pole_rake", "pole_pin"]), "Three normal player taps actually advance through jab, rake and plant")
			elif grammar == "weighted_flexible":
				check(seen_presentations == PackedStringArray(["weighted_cast_low", "weighted_lash_cross", "weighted_retract", "weighted_cast_charge", "weighted_dodge_lash"]), "Flexible terminal load uses cast lash retract actions without a sword spin")
				check(seen_planes == PackedStringArray(["ground_orbit", "ground_sweep", "ground_orbit", "ground_orbit", "ground_sweep"]), "Flexible terminal load declares ground-plane orbits instead of screen-plane circles")
				var minimum := Vector2(INF, INF)
				var maximum := Vector2(-INF, -INF)
				for ratio: float in [0.0, 0.08, 0.20, 0.30, 0.46, 0.64, 0.82, 0.93, 1.0]:
					var terminal: Vector2 = arena._weighted_flexible_contact(Vector2.ZERO, Vector2(64, 0), ratio, "weighted_lash_cross")
					minimum.x = minf(minimum.x, terminal.x); minimum.y = minf(minimum.y, terminal.y)
					maximum.x = maxf(maximum.x, terminal.x); maximum.y = maxf(maximum.y, terminal.y)
				var horizontal_span := maximum.x - minimum.x
				var depth_span := maximum.y - minimum.y
				check(minimum.x < -55.0 and maximum.x > 58.0 and depth_span > 20.0 and horizontal_span > depth_span * 2.5, "Weighted terminal performs a broad horizontal orbit with restrained projected depth")
				check(arena._weighted_flexible_contact(Vector2.ZERO, Vector2(64, 0), 1.0, "weighted_lash_cross").is_equal_approx(Vector2(64, 0)), "Weighted terminal visibly returns to its resting contact")
				var body_source: PackedVector2Array = item.asset.visual_rig.source_path_for_role("deform_body")
				var tether_source: PackedVector2Array = item.asset.visual_rig.source_path_for_role("tether")
				var orbit_finish := Vector2(-58, -12)
				var split_paths: Dictionary = arena._weighted_flexible_paths(Vector2.ZERO, orbit_finish, body_source, tether_source, "weighted_lash_cross", -1.0)
				var orbit_body: PackedVector2Array = split_paths.get("body", PackedVector2Array())
				var orbit_tether: PackedVector2Array = split_paths.get("tether", PackedVector2Array())
				check(orbit_body.size() > 2 and orbit_tether.size() > 2, "Weighted body and attached segment both receive the same visible orbit")
				check(orbit_body[0].is_equal_approx(Vector2.ZERO) and orbit_body[-1].is_equal_approx(orbit_tether[0]) and orbit_tether[-1].is_equal_approx(orbit_finish), "Weighted split path is continuous from the held pixel to the terminal pixel")
				var measured_source_length: float = arena._polyline_length(body_source) + arena._polyline_length(tether_source)
				var measured_live_length: float = arena._polyline_length(orbit_body) + arena._polyline_length(orbit_tether)
				check(absf(measured_live_length - measured_source_length * arena._weapon_fit().draw_scale) < 1.0, "Weighted orbit preserves the measured complete source length")
				var folded_paths: Dictionary = arena._weighted_flexible_paths(Vector2.ZERO, Vector2(12, 0), body_source, tether_source, "weighted_lash_cross", -1.0)
				var folded_body: PackedVector2Array = folded_paths.get("body", PackedVector2Array())
				var folded_tether: PackedVector2Array = folded_paths.get("tether", PackedVector2Array())
				var folded_length: float = arena._polyline_length(folded_body) + arena._polyline_length(folded_tether)
				check(folded_body[0].is_equal_approx(Vector2.ZERO) and folded_tether[-1].is_equal_approx(Vector2(12, 0)) and absf(folded_length - measured_source_length * arena._weapon_fit().draw_scale) < 1.0, "A slack weighted structure keeps its real length even when its endpoints are close")
		ui.pause_run(); ui.return_to_forge()
		check(ui.continue_run().get("ok", false) and ui.entry.identity == item.identity, "Continue reloads exact selected weapon")
		ui.return_to_forge()
	ui.open_forge(); ui.configure_dependencies(func() -> RefCounted: return WaitingService.new())
	ui.begin_generation("一个带短柄的普通物品")
	check(ui.service.art_style_id == "sunny_v1", "General object AI requests Sunny style")
	var token := ui.generation_token
	ui.cancel_generation()
	check(not ui.accept_generation_result(token, {"status":"success","ok":true,"entry":ui.shelf[0]}), "Late cancelled result cannot replace current weapon")
	ui.begin_generation("另一件物品")
	ui.accept_generation_result(ui.generation_token, {"status":"failed","error":"OFFLINE_TEST_FAILURE"})
	check(ui.state == "failed" and ui.entry.is_empty(), "Failure has no fake item")
	ui.return_to_forge(); ui.select_weapon(0); ui.start_trial_run(7); ui.begin_chapter()
	# Contract-test signal only. Actual duration/gameplay is covered by the bot.
	ui._chapter_finished({"elapsed_seconds":95.0,"defeated":8,"damage_taken":70})
	check(ui.flow == "result" and ui.completed_run and ui.run_chapter == 1, "Single level goes straight to results without a camp")
	var saved_campaign: Dictionary = ui.campaign_store.read_state()
	check(saved_campaign.history.size() == 1, "Result persisted")
	check(int(saved_campaign.meta_progression.insight) == 6 and int(saved_campaign.meta_progression.completed_runs) == 3, "Completed run persists capped workshop insight beside, not inside, the weapon")
	check(int(saved_campaign.history[0].metrics.meta_reward.insight_earned) == 2 and bool(saved_campaign.history[0].metrics.meta_reward.new_family), "Result history records the newly mastered anonymous mechanism family")
	print("SUNNY TESTS ", checks, " checks ", failures.size(), " failures ", failures)
	print("Tests finished: passed=", checks - failures.size(), " failed=", failures.size())
	ui.free(); quit(0 if failures.is_empty() else 1)
