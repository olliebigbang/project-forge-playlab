extends RefCounted
const STORE := preload("res://scripts/combat_feel/weapon_library_store.gd")
const ARMORY := preload("res://scripts/combat_feel/player_weapon_armory.gd")
const STYLE := preload("res://scripts/art_vertical_slice_v1/church_pixel_style.gd")
const FACTORY := preload("res://scripts/combat_feel/weapon_entry_factory.gd")
const RANGED := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const VALIDATOR := preload("res://scripts/art_vertical_slice_v1/church_forge.gd")
const STARTER_ROOT := "res://assets/church_expedition_starters"
var style_id := STYLE.ID
var diagnostics: Array[String] = []
var armory: RefCounted = ARMORY.new()

func load_all(include_user: bool = true) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	diagnostics.clear()
	var known := {}
	if include_user:
		armory.allow_legacy_cache_updates = false
		for candidate: Dictionary in armory.load_entries():
			var prepared := prepare(candidate, style_id)
			if prepared.get("ok", false):
				prepared["shelf_source"] = "我的已保存武器"
				output.append(prepared); known[prepared.identity] = true
			else: diagnostics.append(str(candidate.get("display_name", "武器")) + "：" + str(prepared.get("error", "校验失败")))
	var packaged := STORE.new(); packaged.root_path = STARTER_ROOT
	for candidate: Dictionary in packaged.load_entries():
		if known.has(candidate.identity): continue
		candidate = prepare(candidate, style_id)
		var valid := VALIDATOR.validate_entry(candidate, style_id)
		if valid.get("ok", false):
			candidate["shelf_source"] = "随游戏提供 · 既有 AI 成品（非实时生成）"
			candidate["bundled_starter"] = true
			output.append(candidate)
		else: diagnostics.append(str(valid.get("error", "内置成品不可用")))
	# A bundled weapon can later be saved as a user weapon, and old cache
	# migrations can also preserve the same item under a different content key.
	# Keep the newest/user copy, but compare all player-facing identity fields so
	# different archive keys never become duplicate shelf cards.
	output = deduplicate_shelf(output)
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.identity) < str(b.identity))
	return output

static func deduplicate_shelf(entries: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var seen := {}
	for candidate: Dictionary in entries:
		var keys := _identity_keys(candidate)
		var duplicate := false
		for key: String in keys:
			if seen.has(key): duplicate = true; break
		if duplicate: continue
		output.append(candidate)
		for key: String in keys: seen[key] = true
	return output

static func _identity_keys(entry: Dictionary) -> Array[String]:
	var values: Array[String] = [str(entry.get("identity", "")), str(entry.get("display_name", ""))]
	var blueprint := entry.get("blueprint") as WeaponBlueprint
	if blueprint != null:
		values.append(blueprint.display_name)
		values.append(blueprint.player_identity_text)
	var keys: Array[String] = []
	for value: String in values:
		var normalized := value.strip_edges().to_lower()
		for separator: String in [" ", "\t", "\r", "\n", "·", "-", "_", "—", "–"]: normalized = normalized.replace(separator, "")
		if not normalized.is_empty() and normalized not in keys: keys.append(normalized)
	return keys

static func prepare(candidate: Dictionary, target_style: String = STYLE.ID) -> Dictionary:
	var candidate_blueprint := candidate.get("blueprint") as WeaponBlueprint
	if candidate_blueprint != null and str(candidate_blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
		var cached_runtime := candidate_blueprint.modifiers.get("ranged_runtime_profile", {}) as Dictionary
		if not cached_runtime.has("muzzle_climb_cap_degrees"):
			# In-memory schema migration only. Old saved/package records are never
			# overwritten merely because a new axis-owned runtime output was added.
			var migrated := candidate.duplicate(true)
			var migrated_blueprint := WeaponBlueprint.from_dict(candidate_blueprint.to_dict())
			var migrated_runtime := RANGED.compile(migrated_blueprint.affordance, migrated_blueprint.affordance_source)
			if not bool(migrated_runtime.get("ok", false)): return migrated_runtime
			migrated_blueprint.modifiers["ranged_runtime_profile"] = migrated_runtime.duplicate(true)
			migrated["blueprint"] = migrated_blueprint
			migrated["ranged_runtime_profile"] = migrated_runtime
			candidate = migrated
	if VALIDATOR.validate_entry(candidate, target_style).get("ok", false): return candidate.duplicate(true)
	if not candidate.get("ok", false) or not candidate.get("accepted_visual", false): return {"ok": false, "error": "SAVED_VISUAL_NOT_ACCEPTED"}
	var bp := candidate.get("blueprint") as WeaponBlueprint
	var asset := candidate.get("asset") as WeaponVisualAsset
	if bp == null or asset == null: return {"ok": false, "error": "SAVED_WEAPON_INCOMPLETE"}
	var normalized := STYLE.normalize(asset.source_image, target_style)
	if not normalized.get("ok", false): return normalized
	# Recolour a separate copy only. Exact Alpha and anchors retained; recompile
	# as a NEW package on explicit save. Original user weapon is never overwritten.
	bp = WeaponBlueprint.from_dict(bp.to_dict())
	var original: WeaponVisualAsset = asset
	asset = WeaponVisualAsset.new()
	for name: String in STORE.ANCHORS + ["canvas_size", "opaque_bounds", "anchor_confidence", "anchor_source", "orientation_flipped", "orientation_source", "visual_rig_source"]:
		asset.set(name, original.get(name))
	# Rigs describe the unchanged Alpha; sharing the already validated binding
	# is safe here because prepare/finish never mutates an existing binding.
	asset.visual_rig = original.visual_rig
	asset.source_image = normalized.image
	asset.texture = ImageTexture.create_from_image(normalized.image)
	bp.modifiers["art_style_id"] = target_style; bp.modifiers["art_style_version"] = STYLE.version(target_style)
	bp.modifiers["art_style_report"] = STYLE.inspect(asset.source_image, target_style)
	var manifest := {"visual_mode": "local_palette_adaptation_of_saved_weapon"}
	if bp.affordance.get("weapon_domain", "") == "handheld_firearm":
		var gate: Dictionary = candidate.get("visual_evidence", {}).get("gate", {})
		if not gate.get("ok", false): return {"ok": false, "error": "SAVED_FIREARM_IDENTITY_EVIDENCE_MISSING"}
		manifest["firearm_visual_identity_gate"] = gate
	var ready := FACTORY.finish(bp, {"asset": asset, "manifest": manifest})
	if not ready.get("ok", false): return ready
	ready.visual_evidence["art_style"] = bp.modifiers.art_style_report
	ready.visual_evidence["adapted_from_key"] = candidate.get("library_key", "")
	return ready
