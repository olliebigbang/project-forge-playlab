class_name OpenIdentityVisualPrompt
extends RefCounted

const POLICY_VERSION := "forge-open-identity-v2"
const MAX_IDENTITY_CHARACTERS := 320
const MAX_DESCRIPTION_CHARACTERS := 320
const MAX_FEATURE_CHARACTERS := 72
const MAX_FEATURES := 6

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
	var delivery := _behavior_term(blueprint.delivery)
	var impact := _behavior_term(blueprint.impact_mode)
	var effect := _behavior_term(blueprint.effect_type)
	return (
		"Recognizable original object, player identity text: %s. " +
		"Visual description from the same player evidence: %s. The generated prop must remain recognizably this same object. " +
		"Behavior contract, which describes action only and never object identity: delivery action %s; impact action %s; effect %s. " +
		"Combat behavior may add a Forge fixture or readable functional region, but must not replace, " +
		"redesign, or rename the source object as a different object. Preserve its ordinary object identity.%s " +
		"Prompt policy: %s."
	) % [identity, description, delivery, impact, effect, feature_text, POLICY_VERSION]

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
