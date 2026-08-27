class_name OpenIdentityVisualPrompt
extends RefCounted

const MECHANISM_VISUAL_BRIEF := preload("res://scripts/combat_feel/mechanism_visual_brief.gd")
const FIREARM_VISUAL_BRIEF := preload("res://scripts/combat_feel/firearm_visual_brief.gd")
const FIREARM_VISUAL_IDENTITY_CARD := preload("res://scripts/combat_feel/firearm_visual_identity_card.gd")
const POLICY_VERSION := "forge-open-identity-v3"
const MAX_IDENTITY_CHARACTERS := 320
const MAX_DESCRIPTION_CHARACTERS := 320
const MAX_FEATURE_CHARACTERS := 72
const MAX_FEATURES := 6
const MAX_RETRY_CHARACTERS := 140
const MAX_STRUCTURE_CHARACTERS := 1200

static func build(blueprint: WeaponBlueprint) -> String:
	var identity := _model_text(blueprint.player_identity_text, MAX_IDENTITY_CHARACTERS)
	if identity.is_empty():
		identity = _model_text(blueprint.source_identity, MAX_IDENTITY_CHARACTERS)
	var description := _model_text(blueprint.visual_description, MAX_DESCRIPTION_CHARACTERS)
	if description.is_empty():
		description = identity
	var features: Array[String] = []
	for feature: String in blueprint.preserved_visual_features:
		var safe_feature := _model_text(feature, MAX_FEATURE_CHARACTERS)
		if not safe_feature.is_empty():
			features.append(safe_feature)
		if features.size() >= MAX_FEATURES:
			break
	var feature_text := " Preserve this evidence: %s." % ", ".join(features) if not features.is_empty() else ""
	var structure_text := ""
	if not blueprint.affordance.is_empty():
		if blueprint.visual_structure_brief.is_empty():
			if blueprint.behavior_family == "sustained_ranged" and str(blueprint.affordance.get("weapon_domain", "")) == "handheld_firearm":
				blueprint.visual_structure_brief = FIREARM_VISUAL_BRIEF.compile(
					blueprint.affordance,
					blueprint.affordance_source,
					FIREARM_VISUAL_IDENTITY_CARD.compile(blueprint)
				)
			else:
				blueprint.visual_structure_brief = MECHANISM_VISUAL_BRIEF.compile(
					blueprint.affordance,
					blueprint.affordance_source
				)
			blueprint.visual_structure_brief_source = str(blueprint.visual_structure_brief.get("source", ""))
		var structure_clause := _model_text(
			str(blueprint.visual_structure_brief.get("prompt_clause", "")),
			MAX_STRUCTURE_CHARACTERS
		)
		if not structure_clause.is_empty():
			structure_text = " %s" % structure_clause
	var retry_text := _model_text(str(blueprint.modifiers.get("mechanism_visual_retry_prompt", "")), MAX_RETRY_CHARACTERS)
	if not retry_text.is_empty():
		structure_text += " Automatic structural redraw instruction: %s" % retry_text
	var delivery := _behavior_term(blueprint.delivery)
	var impact := _behavior_term(blueprint.impact_mode)
	var effect := _behavior_term(blueprint.effect_type)
	return (
		"Recognizable original object, player identity text: %s. " +
		"Visual description from the same player evidence: %s.%s Keep exactly this same object's ordinary identity. " +
		"Behavior contract, action only and never identity: delivery action %s; impact action %s; effect %s. " +
		"A readable functional fixture is allowed, but it must not replace, redesign, or rename the object.%s " +
		"Prompt policy: %s."
	) % [identity, description, structure_text, delivery, impact, effect, feature_text, POLICY_VERSION]

static func _behavior_term(value: String) -> String:
	var term := _model_text(value.replace("_", " "), MAX_FEATURE_CHARACTERS)
	return term if not term.is_empty() else "unspecified"

static func _model_text(value: String, maximum: int) -> String:
	var safe := value.strip_edges()
	for whitespace: String in ["\r", "\n", "\t"]:
		safe = safe.replace(whitespace, " ")
	# ComfyUI/CLIP treats these characters as weighting syntax. The player's
	# verbatim field remains unchanged on WeaponBlueprint; only the model-facing
	# projection is neutralized.
	for syntax: String in ["(", ")", "[", "]", "{", "}", "<", ">", ":"]:
		safe = safe.replace(syntax, " ")
	while safe.contains("  "):
		safe = safe.replace("  ", " ")
	return safe.left(maximum).strip_edges()
