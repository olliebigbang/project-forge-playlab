extends SceneTree

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const ASSET_LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const ANCHOR_RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")
const AXIS_RESOLVER := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const AUTOMATIC_VISUAL_RIG := preload("res://scripts/combat_feel/automatic_pixel_visual_rig_builder.gd")
const PIXEL_SCAFFOLD := preload("res://scripts/combat_feel/mechanism_pixel_scaffold.gd")
const SCAFFOLD_PIPELINE := preload("res://scripts/combat_feel/mechanism_visual_scaffold_pipeline.gd")
const VISUAL_BRIEF := preload("res://scripts/combat_feel/mechanism_visual_brief.gd")
const READABILITY_GATE := preload("res://scripts/combat_feel/mechanism_visual_readability_gate.gd")
const STATEFUL_PIXEL_MORPHER := preload("res://scripts/combat_feel/stateful_pixel_weapon_morpher.gd")
const VISUAL_PROMPT := preload("res://scripts/services/open_identity_visual_prompt.gd")

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_axes_compile_to_distinct_anonymous_drawing_contracts()
	_test_every_structural_axis_changes_the_drawing_contract()
	_test_every_structural_axis_changes_the_pixel_scaffold()
	_test_stateful_pixels_replace_the_closed_sprite_with_a_filled_active_silhouette()
	_test_long_radial_deployment_opens_back_from_the_distal_hub()
	_test_prompt_carries_mechanism_structure_before_generation()
	_test_four_existing_structures_pass_the_readability_gate()
	_test_four_axis_scaffolds_are_distinct_and_machine_readable()
	_test_formal_pipeline_prepares_a_locked_generator_reference()
	_test_formal_pipeline_resolves_all_matrix_scaffolds()
	_test_formal_pipeline_rejects_structural_drift()
	_test_formal_pipeline_has_no_identity_name_branches()
	_test_fallback_persists_honest_evidence()
	_test_a_straight_bar_cannot_pass_as_a_continuous_soft_body()
	_test_a_textured_nearly_straight_bar_cannot_fake_soft_or_linked_structure()
	_test_a_collinear_second_half_cannot_pass_as_an_independent_tether()
	_test_a_smooth_line_cannot_pass_as_visible_linked_segments()
	_test_a_thin_end_cannot_pass_as_a_broad_contact_face()
	_test_a_broad_terminal_region_can_taper_at_its_outermost_pixel()
	_test_chroma_background_cannot_become_weapon_pixels()
	_test_generation_handoff_records_structure_and_bounded_ai_retries()
	print("MECHANISM_VISUAL_GENERATION_TESTS passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_axes_compile_to_distinct_anonymous_drawing_contracts() -> void:
	var loader: Variant = ASSET_LOADER.new()
	var clauses: Array[String] = []
	var role_sets: Array = []
	for asset_id: String in ["fishing_rod_builtin", "continuous_lash_builtin", "linked_braid_builtin", "rigid_staff_builtin"]:
		var loaded: Dictionary = loader.load_soft_weapon_asset(asset_id)
		var profile := loaded.get("affordance_profile") as Resource
		var brief := VISUAL_BRIEF.compile(profile.to_dict(), "ai_test_axes") if profile != null else {}
		clauses.append(str(brief.get("prompt_clause", "")))
		role_sets.append(brief.get("required_roles", []))
	var source := (
		FileAccess.get_file_as_string("res://scripts/combat_feel/mechanism_visual_brief.gd")
		+ FileAccess.get_file_as_string("res://scripts/combat_feel/mechanism_pixel_scaffold.gd")
	).to_lower()
	var ok := clauses.size() == 4 and clauses[0] != clauses[1] and clauses[1] != clauses[2] and clauses[2] != clauses[3]
	ok = ok and role_sets[0] == ["rigid_root", "deform_body", "tether", "terminal"]
	ok = ok and role_sets[1] == ["rigid_root", "deform_body"]
	ok = ok and role_sets[2] == ["rigid_root", "deform_body", "terminal"]
	ok = ok and role_sets[3] == ["rigid_root"]
	for forbidden: String in ["fishing_rod", "whip", "braid", "staff", "鱼竿", "鞭", "辫"]:
		ok = ok and not source.contains(forbidden)
	_check(ok, "01 mechanism axes compile into four distinct name-free pixel drawing contracts")


func _test_every_structural_axis_changes_the_drawing_contract() -> void:
	var baseline := {
		"handle_length": "short",
		"body_length": "medium",
		"grip_topology": "one_hand_handle",
		"rigidity": "rigid",
		"mass_distribution": "balanced",
		"contact_surface": "whole_body",
		"secondary_contact_surface": "none",
		"flex_topology": "none",
		"tether_topology": "none",
		"terminal_load": "none",
		"tether_mode": "none",
		"tether_deployment": "none",
		"state_topology": "fixed",
		"activation_mode": "passive",
		"functional_output": "contact_only",
	}
	var alternatives := {
		"handle_length": "long",
		"body_length": "long",
		"grip_topology": "clamp_grip",
		"rigidity": "semi_rigid",
		"mass_distribution": "front",
		"contact_surface": "broad",
		"secondary_contact_surface": "edge",
		"flex_topology": "linked_segments",
		"tether_topology": "flexible_line",
		"terminal_load": "heavy",
		"tether_mode": "hook",
		"tether_deployment": "cast_retract",
		"state_topology": "radial_expand",
		"activation_mode": "continuous_hold",
		"functional_output": "directed_stream",
	}
	var baseline_contract := str(VISUAL_BRIEF.compile(baseline, "ai_test_axes").get("prompt_clause", ""))
	var unchanged: Array[String] = []
	for axis: String in VISUAL_BRIEF.STRUCTURAL_AXES:
		var varied := baseline.duplicate(true)
		varied[axis] = alternatives[axis]
		if str(VISUAL_BRIEF.compile(varied, "ai_test_axes").get("prompt_clause", "")) == baseline_contract:
			unchanged.append(axis)
	var maximum_contract := str(VISUAL_BRIEF.compile(alternatives, "ai_test_axes").get("prompt_clause", ""))
	var complete_markers := ["Held geometry:", "Contacts:", "Primary body:", "Attached path:", "End:", "Hook cue:", "Deployment:", "State:", "Activation:", "Output:", "At 96px"]
	var ok := Array(VISUAL_BRIEF.STRUCTURAL_AXES) == Array(AXIS_RESOLVER.REQUIRED_AXES)
	ok = ok and alternatives.size() == AXIS_RESOLVER.REQUIRED_AXES.size()
	ok = ok and unchanged.is_empty() and maximum_contract.length() <= 920
	for marker: String in complete_markers:
		ok = ok and maximum_contract.contains(marker)
	_check(ok, "02 every declared structural mechanism axis changes one complete bounded pixel drawing contract", {
		"unchanged_axes": unchanged,
		"maximum_contract_length": maximum_contract.length(),
		"maximum_contract": maximum_contract,
	})


func _test_every_structural_axis_changes_the_pixel_scaffold() -> void:
	var baseline := {
		"handle_length": "short",
		"body_length": "medium",
		"grip_topology": "one_hand_handle",
		"rigidity": "rigid",
		"mass_distribution": "balanced",
		"contact_surface": "whole_body",
		"secondary_contact_surface": "none",
		"flex_topology": "none",
		"tether_topology": "none",
		"terminal_load": "none",
		"tether_mode": "none",
		"tether_deployment": "none",
		"state_topology": "fixed",
		"activation_mode": "passive",
		"functional_output": "contact_only",
	}
	var alternatives := {
		"handle_length": "long",
		"body_length": "long",
		"grip_topology": "clamp_grip",
		"rigidity": "semi_rigid",
		"mass_distribution": "front",
		"contact_surface": "broad",
		"secondary_contact_surface": "edge",
		"flex_topology": "linked_segments",
		"tether_topology": "flexible_line",
		"terminal_load": "heavy",
		"tether_mode": "hook",
		"tether_deployment": "cast_retract",
		"state_topology": "radial_expand",
		"activation_mode": "continuous_hold",
		"functional_output": "directed_stream",
	}
	var baseline_build := PIXEL_SCAFFOLD.build(baseline)
	var baseline_image := baseline_build.get("image") as Image
	var weak_or_unchanged: Array[String] = []
	var changed_pixel_counts := {}
	for axis: String in VISUAL_BRIEF.STRUCTURAL_AXES:
		var varied := baseline.duplicate(true)
		varied[axis] = alternatives[axis]
		var varied_build := PIXEL_SCAFFOLD.build(varied)
		var varied_image := varied_build.get("image") as Image
		var changed_pixels := _changed_pixel_count(baseline_image, varied_image)
		changed_pixel_counts[axis] = changed_pixels
		if changed_pixels < 32:
			weak_or_unchanged.append(axis)
	_check(
		weak_or_unchanged.is_empty(),
		"02a every mechanism axis alone changes at least 32 pixels in the final 96px scaffold",
		{"weak_or_unchanged": weak_or_unchanged, "changed_pixel_counts": changed_pixel_counts}
	)


func _test_stateful_pixels_replace_the_closed_sprite_with_a_filled_active_silhouette() -> void:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(8, 44, 24, 9), Color("8b5a35"))
	image.fill_rect(Rect2i(26, 46, 58, 5), Color("111827"))
	image.fill_rect(Rect2i(34, 40, 48, 14), Color("26384f"))
	image.fill_rect(Rect2i(39, 43, 40, 8), Color("405a78"))
	var grip := Vector2(18.0, 48.0)
	var strike := Vector2(84.0, 48.0)
	var closed := STATEFUL_PIXEL_MORPHER.deform_local(image, grip, strike, "fixed", 0.0)
	var opened := STATEFUL_PIXEL_MORPHER.deform_local(image, grip, strike, "radial_expand", 1.0)
	var closed_metrics := closed.get("metrics", {}) as Dictionary
	var opened_metrics := opened.get("metrics", {}) as Dictionary
	var ok := (
		bool(opened_metrics.get("closed_sprite_replaced", false))
		and int(opened_metrics.get("generated_fill_pixels", 0)) >= 700
		and int(opened_metrics.get("retained_source_pixels", 99999)) < int(closed_metrics.get("pixel_count", 0))
		and float(opened_metrics.get("normal_span", 0.0)) >= float(closed_metrics.get("normal_span", 0.0)) * 2.8
		and float(opened_metrics.get("filled_area_ratio", 0.0)) >= 0.24
	)
	_check(ok, "02b active state replaces the closed sprite with a filled source-palette pixel silhouette rather than guide lines", {
		"closed": closed_metrics,
		"opened": opened_metrics,
	})


func _test_long_radial_deployment_opens_back_from_the_distal_hub() -> void:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(8, 44, 24, 9), Color("8b5a35"))
	image.fill_rect(Rect2i(26, 46, 58, 5), Color("26384f"))
	var grip := Vector2(18.0, 48.0)
	var strike := Vector2(84.0, 48.0)
	var opened := STATEFUL_PIXEL_MORPHER.deform_local(image, grip, strike, "radial_expand", 1.0, {
		"handle_length": "long",
		"body_length": "long",
	})
	var metrics := opened.get("metrics", {}) as Dictionary
	var maximum_generated_axial := -INF
	var minimum_generated_axial := INF
	for pixel: Dictionary in opened.get("pixels", []):
		if not bool(pixel.get("generated", false)):
			continue
		var position := Vector2(pixel.get("position", Vector2.ZERO))
		maximum_generated_axial = maxf(maximum_generated_axial, position.x)
		minimum_generated_axial = minf(minimum_generated_axial, position.x)
	var length := grip.distance_to(strike)
	var ok := (
		str(metrics.get("radial_canopy_direction", "")) == "toward_grip"
		and is_equal_approx(float(metrics.get("radial_hub_ratio", 0.0)), 0.90)
		and maximum_generated_axial <= length + 1.0
		and minimum_generated_axial < length * 0.62
	)
	_check(ok, "02c a long radial object keeps its handle at the hand and opens its solid canopy back from the distal hub", {
		"metrics": metrics,
		"generated_axial_range": [minimum_generated_axial, maximum_generated_axial],
		"grip_to_strike": length,
	})


func _test_prompt_carries_mechanism_structure_before_generation() -> void:
	var blueprint := WeaponBlueprint.new()
	blueprint.player_identity_text = "匿名物件甲"
	blueprint.source_identity = blueprint.player_identity_text
	blueprint.visual_description = blueprint.player_identity_text
	blueprint.behavior_family = "heavy_melee"
	blueprint.delivery = "whole_object_strike"
	blueprint.impact_mode = "body_contact"
	blueprint.affordance = _profile("bending_shaft", "flexible_line", "light").to_dict()
	blueprint.affordance_source = "ai_test_axes"
	var prompt := VISUAL_PROMPT.build(blueprint)
	var ok := VISUAL_PROMPT.POLICY_VERSION == "forge-open-identity-v3"
	ok = ok and prompt.contains("Mechanism-readable pixel silhouette contract")
	ok = ok and prompt.contains("clearly curved centerline")
	ok = ok and prompt.contains("second thin continuous tether")
	ok = ok and prompt.contains("small but distinct terminal piece")
	ok = ok and blueprint.visual_structure_brief_source == VISUAL_BRIEF.SOURCE
	ok = ok and not bool(blueprint.visual_structure_brief.get("player_confirmation_required", true))
	_check(ok, "03 FLUX prompt v3 carries the AI-axis structure contract before any pixels are generated", prompt)


func _test_four_existing_structures_pass_the_readability_gate() -> void:
	var loader: Variant = ASSET_LOADER.new()
	var ok := true
	var failures: Array = []
	for asset_id: String in ["fishing_rod_builtin", "continuous_lash_builtin", "linked_braid_builtin", "rigid_staff_builtin"]:
		var loaded: Dictionary = loader.load_soft_weapon_asset(asset_id)
		var asset := loaded.get("asset") as WeaponVisualAsset
		var profile := loaded.get("affordance_profile") as Resource
		var brief := VISUAL_BRIEF.compile(profile.to_dict(), "ai_test_axes") if profile != null else {}
		var gate := READABILITY_GATE.evaluate(asset, profile, brief)
		if not bool(gate.get("ok", false)):
			failures.append({"asset": asset_id, "gate": gate})
		ok = ok and bool(gate.get("ok", false)) and not bool(gate.get("player_confirmation_required", true))
	_check(ok, "04 composite shaft+tether continuous body linked body and rigid control pass one structural readability gate", failures)


func _test_four_axis_scaffolds_are_distinct_and_machine_readable() -> void:
	var ok := true
	var failures: Array = []
	var image_hashes: Array[int] = []
	for affordance: Dictionary in _matrix_affordances():
		var built := PIXEL_SCAFFOLD.build(affordance)
		if not bool(built.get("ok", false)) or not built.get("image") is Image:
			failures.append({"case": affordance.get("case_id", ""), "scaffold": built})
			ok = false
			continue
		var image := built.get("image") as Image
		image_hashes.append(hash(image.get_data()))
		var contract: Dictionary = built.get("contract", {})
		var anchors: Dictionary = contract.get("anchors", {})
		var asset := WeaponVisualAsset.new()
		asset.source_image = image
		asset.canvas_size = image.get_size()
		asset.opaque_bounds = ANCHOR_RESOLVER.alpha_bounds(image)
		asset.grip_primary = _vector_from_pair(anchors.get("GripPrimary", []))
		asset.grip_secondary = asset.grip_primary.lerp(_vector_from_pair(anchors.get("StrikePoint", [])), 0.12)
		asset.tip = _vector_from_pair(anchors.get("StrikePoint", []))
		asset.tether_origin = _vector_from_pair(anchors.get("TetherOrigin", []))
		asset.spin_pivot = ANCHOR_RESOLVER.alpha_centroid(image, asset.opaque_bounds)
		var resolution := AXIS_RESOLVER.resolve_ai(asset, affordance, "ai_test_scaffold")
		if not bool(resolution.get("ok", false)) or not resolution.get("profile") is Resource:
			failures.append({"case": affordance.get("case_id", ""), "resolution": resolution})
			ok = false
			continue
		var profile := resolution.get("profile") as Resource
		if str(profile.flex_topology) != "none" or str(profile.tether_topology) != "none":
			var rig_build := AUTOMATIC_VISUAL_RIG.build(asset, profile)
			if not bool(rig_build.get("ok", false)):
				failures.append({"case": affordance.get("case_id", ""), "visual_rig": rig_build})
				ok = false
				continue
			asset.visual_rig = rig_build.get("rig") as PixelWeaponVisualRig
			asset.visual_rig_source = str(rig_build.get("source", ""))
		var brief := VISUAL_BRIEF.compile(affordance, "ai_test_scaffold")
		var gate := READABILITY_GATE.evaluate(asset, profile, brief)
		if not bool(gate.get("ok", false)):
			failures.append({"case": affordance.get("case_id", ""), "gate": gate})
			ok = false
		ok = ok and not bool(built.get("player_confirmation_required", true))
		ok = ok and contract.get("required_roles", []) == brief.get("required_roles", [])
	var unique_hashes := {}
	for image_hash: int in image_hashes:
		unique_hashes[image_hash] = true
	ok = ok and image_hashes.size() == 4
	ok = ok and unique_hashes.size() == 4
	_check(ok, "04a four AI-axis scaffolds are visibly distinct and pass the same automatic mechanism gate", failures)


func _test_formal_pipeline_prepares_a_locked_generator_reference() -> void:
	var blueprint := _blueprint_for_affordance(_matrix_affordances()[0])
	var prepared := SCAFFOLD_PIPELINE.prepare(blueprint)
	var scaffold := prepared.get("scaffold_image") as Image
	var reference := prepared.get("reference_image") as Image
	var palette := prepared.get("palette_image") as Image
	var contract: Dictionary = prepared.get("contract", {})
	var brief: Dictionary = prepared.get("visual_structure_brief", {})
	var ok := bool(prepared.get("ok", false))
	ok = ok and scaffold != null and scaffold.get_size() == Vector2i(96, 96)
	ok = ok and reference != null and reference.get_size() == Vector2i(512, 512)
	ok = ok and reference.get_pixel(0, 0).to_html(false) == "ff26ff"
	ok = ok and palette != null and palette.get_size() == Vector2i(7, 1)
	ok = ok and str(contract.get("structure_authority", "")) == "mechanism_axes"
	ok = ok and str(contract.get("generator_authority", "")) == "style_and_color_only"
	ok = ok and contract.get("required_roles", []) == brief.get("required_roles", [])
	ok = ok and not bool(prepared.get("player_confirmation_required", true))
	_check(ok, "04b formal pipeline turns AI axes into a locked 96px scaffold and a 512px generator reference", prepared)


func _test_formal_pipeline_resolves_all_matrix_scaffolds() -> void:
	var ok := true
	var failures: Array = []
	for affordance: Dictionary in _matrix_affordances():
		var blueprint := _blueprint_for_affordance(affordance)
		var fallback := SCAFFOLD_PIPELINE.fallback(blueprint)
		var asset := fallback.get("asset") as WeaponVisualAsset
		if not bool(fallback.get("ok", false)) or asset == null:
			ok = false
			failures.append({"case": affordance.get("case_id", ""), "fallback": fallback})
			continue
		var opaque_anchors := (
			asset.source_image.get_pixelv(Vector2i(asset.grip_primary.round())).a > 0.1
			and asset.source_image.get_pixelv(Vector2i(asset.tip.round())).a > 0.1
			and asset.source_image.get_pixelv(Vector2i(asset.tether_origin.round())).a > 0.1
		)
		var resolution := AXIS_RESOLVER.resolve_ai(asset, affordance, "ai_formal_pipeline_test")
		if not bool(resolution.get("ok", false)) or not resolution.get("profile") is Resource:
			ok = false
			failures.append({"case": affordance.get("case_id", ""), "resolution": resolution})
			continue
		var profile := resolution.get("profile") as Resource
		if str(profile.flex_topology) != "none" or str(profile.tether_topology) != "none":
			var rig_build := AUTOMATIC_VISUAL_RIG.build(asset, profile)
			if not bool(rig_build.get("ok", false)):
				ok = false
				failures.append({"case": affordance.get("case_id", ""), "visual_rig": rig_build})
				continue
			asset.visual_rig = rig_build.get("rig") as PixelWeaponVisualRig
			asset.visual_rig_source = str(rig_build.get("source", ""))
		var gate := READABILITY_GATE.evaluate(asset, profile, VISUAL_BRIEF.compile(affordance, "ai_formal_pipeline_test"))
		var preflight: Dictionary = fallback.get("preflight", {})
		if not opaque_anchors or not bool(gate.get("ok", false)) or float(preflight.get("scaffold_alpha_iou", 0.0)) < 0.999:
			ok = false
			failures.append({
				"case": affordance.get("case_id", ""),
				"opaque_anchors": opaque_anchors,
				"preflight": preflight,
				"gate": gate,
			})
	_check(ok, "04c all four formal mechanism fallbacks resolve real Alpha anchors rigs and collision-readable structure", failures)


func _test_formal_pipeline_rejects_structural_drift() -> void:
	var blueprint := _blueprint_for_affordance(_matrix_affordances()[0])
	var unrelated := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	unrelated.fill(Color.TRANSPARENT)
	unrelated.fill_rect(Rect2i(0, 0, 10, 10), Color.WHITE)
	var resolved := SCAFFOLD_PIPELINE.resolve_asset(unrelated, blueprint)
	var prepared := SCAFFOLD_PIPELINE.prepare(blueprint)
	var rejection_directory := "user://playlab/tests/mechanism-scaffold-rejection"
	var persisted := SCAFFOLD_PIPELINE.persist_generation_rejection(
		rejection_directory,
		prepared,
		resolved,
		{"status": "success", "producer": "test_external_generator"}
	)
	var rejection_manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		rejection_directory.path_join("manifest.json")
	))
	var rejection_manifest: Dictionary = rejection_manifest_value if rejection_manifest_value is Dictionary else {}
	var ok := not bool(resolved.get("ok", true))
	ok = ok and str(resolved.get("error", "")) == "MECHANISM_SCAFFOLD_ALPHA_IOU_TOO_LOW"
	ok = ok and bool(resolved.get("retry_required", false))
	ok = ok and not bool(resolved.get("player_confirmation_required", true))
	ok = ok and bool(persisted.get("ok", false))
	ok = ok and str(rejection_manifest.get("mechanism_acceptance_status", "")) == "rejected"
	ok = ok and not bool(rejection_manifest.get("mechanism_output_accepted", true))
	ok = ok and FileAccess.file_exists(rejection_directory.path_join("mechanism_scaffold_rejection.json"))
	_check(ok, "04d a generator output that abandons the mechanism scaffold is rejected automatically with evidence", {
		"resolution": resolved,
		"manifest": rejection_manifest,
	})


func _test_formal_pipeline_has_no_identity_name_branches() -> void:
	var source := (
		FileAccess.get_file_as_string("res://scripts/combat_feel/mechanism_visual_scaffold_pipeline.gd")
		+ FileAccess.get_file_as_string("res://scripts/services/local_comfy_forge_visual_provider.gd")
		+ FileAccess.get_file_as_string("res://scripts/combat_feel/mechanism_visual_readability_gate.gd")
		+ FileAccess.get_file_as_string("res://scripts/combat_feel/mechanism_pixel_scaffold.gd")
		+ FileAccess.get_file_as_string("res://scripts/combat_feel/mechanism_axis_resolver.gd")
		+ FileAccess.get_file_as_string("res://scripts/combat_feel/general_object_ai_resolver.gd")
	).to_lower()
	var forbidden_hits: Array[String] = []
	for forbidden: String in [
		"fishing_rod", "whip", "braid", "staff", "鱼竿", "鞭", "辫",
		"tennis", "racket", "extinguisher", "yo-yo", "yoyo", "网球拍", "灭火器", "溜溜球",
	]:
		if source.contains(forbidden):
			forbidden_hits.append(forbidden)
	var ok := forbidden_hits.is_empty()
	ok = ok and source.contains("structure_authority")
	ok = ok and source.contains("style_and_color_only")
	ok = ok and source.contains("mechanism_scaffold_reference")
	_check(ok, "04e formal drawing and provider paths branch on mechanism axes rather than weapon names", forbidden_hits)


func _test_fallback_persists_honest_evidence() -> void:
	var blueprint := _blueprint_for_affordance(_matrix_affordances()[2])
	blueprint.visual_prompt = "anonymous identity-preserving pixel object"
	var fallback := SCAFFOLD_PIPELINE.fallback(blueprint)
	var directory := "user://playlab/tests/mechanism-scaffold-fallback"
	var persisted := SCAFFOLD_PIPELINE.persist_fallback(
		directory,
		blueprint,
		fallback,
		"TEST_EXTERNAL_PROVIDER_UNAVAILABLE"
	)
	var manifest_path := directory.path_join("manifest.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var manifest: Dictionary = parsed if parsed is Dictionary else {}
	var sprite := Image.load_from_file(directory.path_join("processed_sprite.png"))
	var ok := bool(persisted.get("ok", false))
	ok = ok and sprite != null and sprite.get_size() == Vector2i(96, 96)
	ok = ok and str(manifest.get("visual_mode", "")) == "mechanism_scaffold_fallback"
	ok = ok and not bool(manifest.get("external_generator_succeeded", true))
	ok = ok and str(manifest.get("structure_authority", "")) == "mechanism_axes"
	ok = ok and str(manifest.get("generator_authority", "")) == "none"
	ok = ok and not bool(manifest.get("player_mechanism_confirmation_required", true))
	ok = ok and FileAccess.file_exists(directory.path_join("mechanism_scaffold_handoff.json"))
	_check(ok, "04f fallback persists an honest usable sprite and never pretends an external generator succeeded", manifest)


func _test_a_straight_bar_cannot_pass_as_a_continuous_soft_body() -> void:
	var asset := _straight_asset(false)
	var profile := _profile("flexible_line", "none", "none")
	var built: Dictionary = ASSET_LOADER.new().build_automatic_visual_rig(asset, profile)
	var gate := READABILITY_GATE.evaluate(asset, profile, VISUAL_BRIEF.compile(profile.to_dict(), "ai_test_axes"))
	var errors: Array = gate.get("errors", [])
	var ok := bool(built.get("ok", false)) and not bool(gate.get("ok", true))
	ok = ok and errors.has("AI_VISUAL_READABILITY_SOFT_BODY_LOOKS_RIGID")
	_check(ok, "05 a generic straight bar is rejected when AI axes require a continuous flexible body", gate)


func _test_a_collinear_second_half_cannot_pass_as_an_independent_tether() -> void:
	var asset := _straight_asset(true)
	var profile := _profile("bending_shaft", "flexible_line", "light")
	var built: Dictionary = ASSET_LOADER.new().build_automatic_visual_rig(asset, profile)
	var gate := READABILITY_GATE.evaluate(asset, profile, VISUAL_BRIEF.compile(profile.to_dict(), "ai_test_axes"))
	var errors: Array = gate.get("errors", [])
	var ok := bool(built.get("ok", false)) and not bool(gate.get("ok", true))
	ok = ok and errors.has("AI_VISUAL_READABILITY_TETHER_NOT_INDEPENDENT")
	_check(ok, "06 splitting a straight bar in half cannot fake an independently visible tether", gate)


func _test_a_textured_nearly_straight_bar_cannot_fake_soft_or_linked_structure() -> void:
	var soft_asset := _textured_nearly_straight_asset()
	var soft_profile := _profile("flexible_line", "none", "none")
	var soft_built: Dictionary = ASSET_LOADER.new().build_automatic_visual_rig(soft_asset, soft_profile)
	var soft_gate := READABILITY_GATE.evaluate(
		soft_asset,
		soft_profile,
		VISUAL_BRIEF.compile(soft_profile.to_dict(), "ai_test_axes")
	)
	var linked_asset := _textured_nearly_straight_asset()
	var linked_profile := _profile("linked_segments", "none", "none")
	var linked_built: Dictionary = ASSET_LOADER.new().build_automatic_visual_rig(linked_asset, linked_profile)
	var linked_gate := READABILITY_GATE.evaluate(
		linked_asset,
		linked_profile,
		VISUAL_BRIEF.compile(linked_profile.to_dict(), "ai_test_axes")
	)
	var ok := bool(soft_built.get("ok", false)) and bool(linked_built.get("ok", false))
	ok = ok and (soft_gate.get("errors", []) as Array).has("AI_VISUAL_READABILITY_SOFT_BODY_LOOKS_RIGID")
	ok = ok and (linked_gate.get("errors", []) as Array).has("AI_VISUAL_READABILITY_LINKS_NOT_VISIBLE")
	_check(ok, "06a wood grain pixel stairs and one decorative band cannot disguise a bar as soft or linked", {
		"soft_gate": soft_gate,
		"linked_gate": linked_gate,
	})


func _test_a_smooth_line_cannot_pass_as_visible_linked_segments() -> void:
	var asset := _straight_asset(true)
	var profile := _profile("linked_segments", "none", "light")
	var built: Dictionary = ASSET_LOADER.new().build_automatic_visual_rig(asset, profile)
	var gate := READABILITY_GATE.evaluate(asset, profile, VISUAL_BRIEF.compile(profile.to_dict(), "ai_test_axes"))
	var errors: Array = gate.get("errors", [])
	var ok := bool(built.get("ok", false)) and not bool(gate.get("ok", true))
	ok = ok and errors.has("AI_VISUAL_READABILITY_LINKS_NOT_VISIBLE")
	_check(ok, "07 one smooth line cannot fake repeated linked sections", gate)


func _test_a_thin_end_cannot_pass_as_a_broad_contact_face() -> void:
	var asset := _straight_asset(false)
	var profile := _profile("none", "none", "none")
	profile.contact_surface = "broad"
	profile.has_broad_face = true
	var gate := READABILITY_GATE.evaluate(asset, profile, VISUAL_BRIEF.compile(profile.to_dict(), "ai_test_axes"))
	var errors: Array = gate.get("errors", [])
	var ok := not bool(gate.get("ok", true))
	ok = ok and errors.has("AI_VISUAL_READABILITY_BROAD_CONTACT_TOO_NARROW")
	_check(ok, "08 a thin line end cannot fake a broad contact face", gate)


func _test_a_broad_terminal_region_can_taper_at_its_outermost_pixel() -> void:
	var asset := _tapered_broad_region_asset()
	var profile := _profile("none", "none", "none")
	profile.contact_surface = "broad"
	profile.has_broad_face = true
	var gate := READABILITY_GATE.evaluate(asset, profile, VISUAL_BRIEF.compile(profile.to_dict(), "ai_test_axes"))
	var metrics: Dictionary = gate.get("metrics", {})
	var local_span := float((metrics.get("silhouette", {}) as Dictionary).get("contact_span_ratio", 0.0))
	var region_span := float(metrics.get("terminal_broad_span_ratio", 0.0))
	var ok := bool(gate.get("ok", false))
	ok = ok and region_span >= 0.17 and region_span > local_span
	_check(ok, "08a a visible broad terminal region is accepted even when its outermost contact corner tapers", gate)


func _test_chroma_background_cannot_become_weapon_pixels() -> void:
	var asset := _straight_asset(false)
	asset.source_image.fill_rect(Rect2i(54, 35, 18, 18), Color("ff26ff"))
	asset.opaque_bounds = asset.source_image.get_used_rect()
	var profile := _profile("none", "none", "none")
	var gate := READABILITY_GATE.evaluate(asset, profile, VISUAL_BRIEF.compile(profile.to_dict(), "ai_test_axes"))
	var errors: Array = gate.get("errors", [])
	var ok := not bool(gate.get("ok", true)) and errors.has("AI_VISUAL_READABILITY_CHROMA_RESIDUE")
	_check(ok, "08b enclosed chroma background cannot become accepted weapon pixels", gate)


func _test_generation_handoff_records_structure_and_bounded_ai_retries() -> void:
	var provider_source := FileAccess.get_file_as_string("res://scripts/services/local_comfy_forge_visual_provider.gd")
	var bridge_source := FileAccess.get_file_as_string("res://tools/comfyui/bridge/forge_comfy_bridge.py")
	var flux_bridge_source := FileAccess.get_file_as_string("res://tools/comfyui/flux2/bridge/flux2_profile_bridge.py")
	var flow_source := FileAccess.get_file_as_string("res://scripts/open_identity_spike.gd")
	var ok := provider_source.contains("--visual-structure-brief") and provider_source.contains("--visual-retry-count")
	ok = ok and bridge_source.contains("visual_structure_brief.json") and bridge_source.contains("forge-open-identity-v3")
	ok = ok and flux_bridge_source.contains("visual_structure_brief.json") and flux_bridge_source.contains("forge-open-identity-v3")
	ok = ok and flux_bridge_source.contains("visual_retry_count") and flux_bridge_source.contains("OPEN_IDENTITY_INPUT_MARKER")
	ok = ok and flow_source.contains("MAX_MECHANISM_VISUAL_RETRIES := 2")
	ok = ok and flow_source.contains("_begin_automatic_mechanism_visual_retry")
	ok = ok and flow_source.contains("_activate_mechanism_scaffold_fallback")
	ok = ok and flow_source.contains('or error.begins_with("MECHANISM_SCAFFOLD_")')
	ok = ok and flow_source.contains('_activate_mechanism_scaffold_fallback("EXTERNAL_VISUAL_PROVIDER_NOT_CONFIGURED")')
	ok = ok and flow_source.contains('or error == "AI_GEOMETRY_CONFLICT"')
	ok = ok and flow_source.contains('"player_confirmation_required": false')
	ok = ok and provider_source.contains('"--reference", structural_reference')
	ok = ok and provider_source.contains('effective_control_strength = maxf(effective_control_strength, 0.80)')
	ok = ok and provider_source.contains("MECHANISM_SCAFFOLD_PIPELINE.resolve_asset")
	_check(ok, "09 generation records its structure contract and readability failure gets at most two AI redraws without asking the player how to attack")


func _straight_asset(with_terminal: bool) -> WeaponVisualAsset:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(4, 43, 18, 11), Color("8b5a2b"))
	_draw_line(image, Vector2i(18, 48), Vector2i(88, 48), Color("587ca8"), 2)
	if with_terminal:
		image.fill_rect(Rect2i(84, 44, 9, 9), Color("d99b3d"))
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.canvas_size = image.get_size()
	asset.opaque_bounds = image.get_used_rect()
	asset.grip_primary = Vector2(12.0, 48.0)
	asset.grip_secondary = Vector2(17.0, 48.0)
	asset.tip = Vector2(88.0, 48.0)
	asset.tether_origin = asset.tip
	return asset


func _tapered_broad_region_asset() -> WeaponVisualAsset:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_draw_line(image, Vector2i(8, 72), Vector2i(55, 51), Color("8b5a2b"), 3)
	var center := Vector2(70.0, 42.0)
	var radii := Vector2(21.0, 27.0)
	for y: int in range(14, 70):
		for x: int in range(49, 93):
			var normalized := Vector2(
				(float(x) - center.x) / radii.x,
				(float(y) - center.y) / radii.y
			)
			var distance := normalized.length_squared()
			if distance <= 1.0 and distance >= 0.62:
				image.set_pixel(x, y, Color("587ca8"))
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.canvas_size = image.get_size()
	asset.opaque_bounds = image.get_used_rect()
	asset.grip_primary = Vector2(12.0, 70.0)
	asset.grip_secondary = Vector2(18.0, 67.0)
	asset.tip = Vector2(89.0, 24.0)
	asset.tether_origin = asset.tip
	return asset


func _profile(flex: String, tether: String, terminal: String) -> Resource:
	var profile: Variant = AFFORDANCE.new()
	profile.handle_length = "short"
	profile.body_length = "long"
	profile.grip_topology = "one_hand_handle"
	profile.rigidity = "flexible" if flex != "none" else "semi_rigid"
	profile.mass_distribution = "balanced"
	profile.contact_surface = "whole_body"
	profile.secondary_contact_surface = "point" if terminal != "none" else "none"
	profile.flex_topology = flex
	profile.tether_topology = tether
	profile.terminal_load = terminal
	profile.tether_mode = "hook" if tether != "none" else ("wrap" if flex == "flexible_line" else "none")
	profile.tether_deployment = "cast_retract" if tether != "none" else "none"
	profile.has_point = terminal != "none"
	profile.confidence = 0.95
	profile.evidence_parts = PackedStringArray(["anonymous mechanism visual generation test"])
	return profile


func _matrix_affordances() -> Array[Dictionary]:
	return [
		_with_affordance_metadata("anonymous_bending_tether", {
			"handle_length": "short", "body_length": "long", "grip_topology": "one_hand_handle",
			"rigidity": "flexible", "mass_distribution": "balanced", "contact_surface": "whole_body",
			"secondary_contact_surface": "point", "flex_topology": "bending_shaft",
			"tether_topology": "flexible_line", "terminal_load": "light", "tether_mode": "hook", "tether_deployment": "cast_retract",
			"has_point": true, "has_edge": false, "has_broad_face": false, "has_barrel": false, "has_stock": false,
		}),
		_with_affordance_metadata("anonymous_continuous_wrap", {
			"handle_length": "short", "body_length": "long", "grip_topology": "one_hand_handle",
			"rigidity": "flexible", "mass_distribution": "balanced", "contact_surface": "whole_body",
			"secondary_contact_surface": "none", "flex_topology": "flexible_line",
			"tether_topology": "none", "terminal_load": "none", "tether_mode": "wrap", "tether_deployment": "none",
			"has_point": false, "has_edge": false, "has_broad_face": false, "has_barrel": false, "has_stock": false,
		}),
		_with_affordance_metadata("anonymous_linked_terminal", {
			"handle_length": "short", "body_length": "long", "grip_topology": "one_hand_handle",
			"rigidity": "flexible", "mass_distribution": "balanced", "contact_surface": "whole_body",
			"secondary_contact_surface": "point", "flex_topology": "linked_segments",
			"tether_topology": "none", "terminal_load": "light", "tether_mode": "none", "tether_deployment": "none",
			"has_point": true, "has_edge": false, "has_broad_face": false, "has_barrel": false, "has_stock": false,
		}),
		_with_affordance_metadata("anonymous_rigid_broad", {
			"handle_length": "long", "body_length": "long", "grip_topology": "two_hand_handle",
			"rigidity": "rigid", "mass_distribution": "front", "contact_surface": "broad",
			"secondary_contact_surface": "none", "flex_topology": "none",
			"tether_topology": "none", "terminal_load": "none", "tether_mode": "none", "tether_deployment": "none",
			"has_point": false, "has_edge": false, "has_broad_face": true, "has_barrel": false, "has_stock": false,
		}),
	]


func _with_affordance_metadata(case_id: String, axes: Dictionary) -> Dictionary:
	var result := axes.duplicate(true)
	result["state_topology"] = str(result.get("state_topology", "fixed"))
	result["activation_mode"] = str(result.get("activation_mode", "passive"))
	result["functional_output"] = str(result.get("functional_output", "contact_only"))
	result["case_id"] = case_id
	result["confidence"] = 0.95
	result["evidence_parts"] = ["anonymous deterministic mechanism scaffold"]
	return result


func _blueprint_for_affordance(affordance: Dictionary) -> WeaponBlueprint:
	var blueprint := WeaponBlueprint.new()
	blueprint.id = "anonymous-formal-pipeline"
	blueprint.display_name = "匿名结构"
	blueprint.player_identity_text = "匿名物件"
	blueprint.source_identity = blueprint.player_identity_text
	blueprint.visual_description = blueprint.player_identity_text
	blueprint.behavior_family = "heavy_melee"
	blueprint.delivery = "whole_object_strike"
	blueprint.impact_mode = "body_contact"
	blueprint.grip_profile = "rear_grip"
	blueprint.affordance = affordance.duplicate(true)
	blueprint.affordance_source = "ai_formal_pipeline_test"
	return blueprint


func _vector_from_pair(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _changed_pixel_count(left: Image, right: Image) -> int:
	if left == null or right == null or left.get_size() != right.get_size():
		return 0
	var changed := 0
	for y: int in range(left.get_height()):
		for x: int in range(left.get_width()):
			if left.get_pixel(x, y) != right.get_pixel(x, y):
				changed += 1
	return changed


func _textured_nearly_straight_asset() -> WeaponVisualAsset:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_draw_line(image, Vector2i(10, 69), Vector2i(47, 49), Color("351f18"), 5)
	_draw_line(image, Vector2i(47, 49), Vector2i(88, 29), Color("351f18"), 5)
	_draw_line(image, Vector2i(10, 69), Vector2i(47, 49), Color("8b5a2b"), 3)
	_draw_line(image, Vector2i(47, 49), Vector2i(88, 29), Color("7b4828"), 3)
	for y: int in range(43, 56):
		for x: int in range(42, 53):
			if Vector2(x, y).distance_to(Vector2(47, 49)) <= 5.0 and image.get_pixel(x, y).a > 0.1:
				image.set_pixel(x, y, Color("d0a24a"))
	var asset := WeaponVisualAsset.new()
	asset.source_image = image
	asset.canvas_size = image.get_size()
	asset.opaque_bounds = image.get_used_rect()
	asset.grip_primary = Vector2(12.0, 68.0)
	asset.grip_secondary = Vector2(18.0, 65.0)
	asset.tip = Vector2(88.0, 29.0)
	asset.tether_origin = asset.tip
	return asset


func _draw_line(image: Image, start: Vector2i, finish: Vector2i, color: Color, radius: int) -> void:
	var delta := finish - start
	var steps := maxi(abs(delta.x), abs(delta.y))
	for step: int in range(steps + 1):
		var ratio := float(step) / maxf(1.0, float(steps))
		var center := Vector2i(roundi(lerpf(start.x, finish.x, ratio)), roundi(lerpf(start.y, finish.y, ratio)))
		for y: int in range(center.y - radius, center.y + radius + 1):
			for x: int in range(center.x - radius, center.x + radius + 1):
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
					image.set_pixel(x, y, color)


func _check(condition: bool, label: String, details: Variant = null) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL %s\n%s" % [label, JSON.stringify(details, "  ")])
