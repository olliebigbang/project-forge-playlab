class_name MechanismAxisResolver
extends RefCounted

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")

const REQUIRED_AXES: PackedStringArray = [
	"handle_length",
	"body_length",
	"grip_topology",
	"rigidity",
	"mass_distribution",
	"contact_surface",
	"secondary_contact_surface",
	"flex_topology",
	"tether_topology",
	"terminal_load",
	"tether_mode",
	"tether_deployment",
]
const SOFT_AXES: PackedStringArray = ["flex_topology", "tether_topology", "terminal_load", "tether_mode", "tether_deployment"]
const DECLARATION_VALUES := {
	"handle_length": ["none", "short", "medium", "long"],
	"body_length": ["short", "medium", "long"],
	"grip_topology": ["one_hand_handle", "two_hand_handle", "body_grip", "clamp_grip"],
	"rigidity": ["rigid", "semi_rigid", "flexible"],
	"mass_distribution": ["rear", "balanced", "front"],
	"contact_surface": ["point", "edge", "broad", "whole_body"],
	"secondary_contact_surface": ["none", "point", "edge", "broad", "whole_body"],
	"flex_topology": ["none", "bending_shaft", "flexible_line", "linked_segments"],
	"tether_topology": ["none", "flexible_line", "linked_segments"],
	"terminal_load": ["none", "light", "heavy"],
	"tether_mode": ["none", "wrap", "hook"],
	"tether_deployment": ["none", "fixed_length", "cast_retract", "launch_tension"],
}
const REQUIRED_FLAGS: PackedStringArray = [
	"has_point",
	"has_edge",
	"has_broad_face",
	"has_barrel",
	"has_stock",
]
const AXIS_LABELS_ZH := {
	"handle_length": "握柄长度",
	"body_length": "主体长度",
	"grip_topology": "握持方式",
	"rigidity": "软硬程度",
	"mass_distribution": "重量分布",
	"contact_surface": "主要接触方式",
	"secondary_contact_surface": "第二接触方式",
	"flex_topology": "柔性结构",
	"tether_topology": "牵引段结构",
	"terminal_load": "末端负载",
	"tether_mode": "缠钩方式",
	"tether_deployment": "软线展开方式",
}
const OPTION_LABELS_ZH := {
	"handle_length": {"none": "没有独立握柄", "short": "短柄", "medium": "中等握柄", "long": "长柄"},
	"body_length": {"short": "短小主体", "medium": "中等主体", "long": "长主体"},
	"grip_topology": {
		"one_hand_handle": "单手握柄",
		"two_hand_handle": "双手握柄",
		"body_grip": "直接抱住或抓住主体",
		"clamp_grip": "夹住或钳住",
	},
	"rigidity": {"rigid": "硬，不会明显弯", "semi_rigid": "会略微弯曲", "flexible": "明显柔软"},
	"mass_distribution": {"rear": "重量靠近手", "balanced": "重量居中", "front": "重量靠近打击端"},
	"contact_surface": {"point": "尖端刺", "edge": "边缘砍", "broad": "宽面拍", "whole_body": "整件东西撞"},
	"secondary_contact_surface": {"none": "没有", "point": "另有尖端", "edge": "另有边缘", "broad": "另有宽面", "whole_body": "也能整件撞"},
	"flex_topology": {
		"none": "不是柔性结构",
		"bending_shaft": "整根连续弯曲",
		"flexible_line": "绳线逐段传力",
		"linked_segments": "多节连接摆动",
	},
	"tether_topology": {
		"none": "没有独立牵引段",
		"flexible_line": "另接一段柔性绳线",
		"linked_segments": "另接一段活动链节",
	},
	"terminal_load": {"none": "末端无额外负载", "light": "轻末端", "heavy": "重末端"},
	"tether_mode": {"none": "不能缠钩", "wrap": "缠住并限制", "hook": "钩住并拉回"},
	"tether_deployment": {
		"none": "没有独立软线",
		"fixed_length": "固定长度跟随",
		"cast_retract": "甩出后收回",
		"launch_tension": "发射后绷紧",
	},
}

# Conservative thresholds calibrated against the real pan, mop, shotgun,
# longsword, spear, chair and generated chicken silhouettes. A value is only
# accepted automatically when the full Anchor +/-2 px and Mask +/-1 px range
# stays on one side of the boundary.
const FRONT_MASS_STABLE_MIN := 0.55
const REAR_MASS_STABLE_MAX := 0.22
const BALANCED_MASS_STABLE_MIN := 0.30
const BALANCED_MASS_STABLE_MAX := 0.50
const BROAD_CONTACT_STABLE_SPAN_MIN := 0.24
const BROAD_CONTACT_STABLE_CURVATURE_MAX := 8.0
const TRUSTED_AI_SOURCE_PREFIXES: PackedStringArray = [
	"ai_",
	"semantic_ai_",
	"anthropic_",
	"anthropic-",
	"anthropic:",
	"anthropic ",
]


static func draft(asset: WeaponVisualAsset, declarations: Dictionary = {}) -> Dictionary:
	if asset == null or asset.source_image == null or asset.source_image.is_empty():
		return _failure("MISSING_SILHOUETTE")
	var normalized_declarations := _with_soft_defaults(declarations)
	var declaration_error := _declaration_error(normalized_declarations)
	if not declaration_error.is_empty():
		return _failure(declaration_error)
	var measurements := asset.silhouette_mechanics()
	var stability := asset.silhouette_mechanics_stability(2.0)
	if measurements.is_empty() or stability.is_empty():
		return _failure("UNMEASURABLE_SILHOUETTE")

	var axes := {
		"handle_length": _unobservable_axis("handle_length", "real scale and handle/body boundary are not recoverable from a normalized sprite"),
		"body_length": _unobservable_axis("body_length", "real scale is removed when the sprite is normalized to its canvas"),
		"grip_topology": _unobservable_axis("grip_topology", "a second anchor may be generated from a prior behavior choice, so it is not independent evidence"),
		"rigidity": _unobservable_axis("rigidity", "a still alpha silhouette does not show how the object bends during motion"),
		"mass_distribution": _mass_axis(measurements, stability),
		"contact_surface": _contact_axis(measurements, stability),
		"secondary_contact_surface": _unobservable_axis("secondary_contact_surface", "one Grip-to-Strike ray cannot establish a second functional contact"),
		"flex_topology": _unobservable_axis("flex_topology", "a still silhouette does not show whether flexibility propagates through a bending shaft, a continuous line, or linked segments"),
		"tether_topology": _unobservable_axis("tether_topology", "a still silhouette does not establish whether a separate line or linked section moves independently from the main body"),
		"terminal_load": _unobservable_axis("terminal_load", "alpha area does not establish the relative moving mass concentrated at the flexible endpoint"),
		"tether_mode": _unobservable_axis("tether_mode", "hooking or wrapping is a functional action and cannot be inferred from one contact ray alone"),
		"tether_deployment": _unobservable_axis("tether_deployment", "a still silhouette cannot establish whether an attached line stays extended, pays out and retracts, or launches and remains tensioned"),
	}
	for axis: String in REQUIRED_AXES:
		if normalized_declarations.has(axis):
			axes[axis] = _declared_axis(axis, normalized_declarations[axis], axes[axis])

	var needs_ai_axes := PackedStringArray()
	for axis: String in REQUIRED_AXES:
		var axis_result: Dictionary = axes[axis]
		if str(axis_result.get("value", "")).is_empty():
			needs_ai_axes.append(axis)

	var result := {
		"ok": true,
		"complete": needs_ai_axes.is_empty(),
		"automatic": false,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
		"identity_inputs_used": false,
		"measurements": measurements,
		"stability": stability,
		"axes": axes,
		"needs_ai_axes": needs_ai_axes,
		"profile": null,
	}
	if not needs_ai_axes.is_empty():
		return result

	var profile: Resource = _build_profile(axes, normalized_declarations)
	var profile_errors: Array[String] = profile.validation_errors()
	if not profile_errors.is_empty():
		result["ok"] = false
		result["complete"] = false
		result["error"] = "INVALID_AFFORDANCE_COMBINATION"
		result["validation_errors"] = profile_errors
		return result
	result["profile"] = profile
	return result


static func resolve_ai(asset: WeaponVisualAsset, ai_affordance: Dictionary, source: String) -> Dictionary:
	var normalized_affordance := _with_soft_defaults(ai_affordance)
	var contract := validate_ai_declaration(normalized_affordance, source)
	if not bool(contract.get("ok", false)):
		return contract

	var geometry: Dictionary = draft(asset)
	if not bool(geometry.get("ok", false)):
		var geometry_failure := _ai_failure(str(geometry.get("error", "UNMEASURABLE_SILHOUETTE")), source)
		geometry_failure["geometry"] = geometry
		return geometry_failure
	var conflicts := _geometry_conflicts(geometry, normalized_affordance)
	if not conflicts.is_empty():
		var conflict_failure := _ai_failure("AI_GEOMETRY_CONFLICT", source)
		conflict_failure["conflicts"] = conflicts
		conflict_failure["geometry"] = geometry
		return conflict_failure

	var confidence := float(normalized_affordance.get("confidence", 0.0))
	var evidence: Array = []
	for item: Variant in normalized_affordance.get("evidence_parts", []):
		evidence.append(str(item))
	var declarations := {}
	for axis: String in REQUIRED_AXES:
		declarations[axis] = {
			"value": str(normalized_affordance.get(axis, "")),
			"confidence": confidence,
			"evidence": evidence,
		}
	for flag: String in REQUIRED_FLAGS:
		declarations[flag] = normalized_affordance[flag]

	var resolved: Dictionary = draft(asset, declarations)
	if not bool(resolved.get("ok", false)) or not bool(resolved.get("complete", false)):
		var resolved_failure := _ai_failure(str(resolved.get("error", "AI_AFFORDANCE_INCOMPLETE")), source)
		resolved_failure["resolution"] = resolved
		return resolved_failure
	for axis: String in REQUIRED_AXES:
		var axis_result: Dictionary = (resolved.get("axes", {}) as Dictionary).get(axis, {})
		axis_result["status"] = "ai_declared"
		axis_result["source"] = "ai_semantic_affordance"
	var profile := resolved.get("profile") as Resource
	if profile != null:
		var profile_evidence := PackedStringArray(profile.evidence_parts)
		profile_evidence.append("affordance_source: %s" % source)
		profile.evidence_parts = profile_evidence
		profile.confidence = confidence
	resolved["automatic"] = true
	resolved["source"] = source
	resolved["player_mechanism_input_used"] = false
	resolved["player_confirmation_required"] = false
	resolved["retry_required"] = false
	resolved["geometry_validation"] = geometry
	return resolved


static func validate_ai_declaration(ai_affordance: Dictionary, source: String) -> Dictionary:
	var source_error := _ai_source_error(source)
	if not source_error.is_empty():
		return _ai_failure(source_error, source)
	var affordance_error := _ai_affordance_error(_with_soft_defaults(ai_affordance))
	if not affordance_error.is_empty():
		return _ai_failure(affordance_error, source)
	return {
		"ok": true,
		"complete": true,
		"source": source,
		"geometry_validation_pending": true,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
		"retry_required": false,
	}


static func _mass_axis(measurements: Dictionary, stability: Dictionary) -> Dictionary:
	var metric: Dictionary = (stability.get("metrics", {}) as Dictionary).get("mass_projection_ratio", {})
	var base := float(measurements.get("mass_projection_ratio", 0.0))
	var minimum := float(metric.get("min", base))
	var maximum := float(metric.get("max", base))
	var invalid := int(metric.get("invalid_sample_count", 1))
	var suggestion := "balanced"
	if base >= FRONT_MASS_STABLE_MIN:
		suggestion = "front"
	elif base <= REAR_MASS_STABLE_MAX:
		suggestion = "rear"
	var evidence := [
		"alpha-centroid projection along GripPrimary->outer contact = %.4f" % base,
		"Anchor +/-2 px and Mask erosion/dilation 1 px interval = %.4f..%.4f; invalid samples = %d" % [minimum, maximum, invalid],
	]
	if invalid == 0:
		if minimum >= FRONT_MASS_STABLE_MIN:
			return _measured_axis("front", 0.82, evidence, DECLARATION_VALUES["mass_distribution"])
		if maximum <= REAR_MASS_STABLE_MAX:
			return _measured_axis("rear", 0.82, evidence, DECLARATION_VALUES["mass_distribution"])
		if minimum >= BALANCED_MASS_STABLE_MIN and maximum <= BALANCED_MASS_STABLE_MAX:
			return _measured_axis("balanced", 0.78, evidence, DECLARATION_VALUES["mass_distribution"])
	return _unresolved_axis(
		"mass_distribution",
		suggestion,
		"alpha+anchors_boundary_or_instability",
		evidence,
		DECLARATION_VALUES["mass_distribution"]
	)


static func _contact_axis(measurements: Dictionary, stability: Dictionary) -> Dictionary:
	var metrics: Dictionary = stability.get("metrics", {})
	var span_metric: Dictionary = metrics.get("contact_span_ratio", {})
	var curvature_metric: Dictionary = metrics.get("normalized_local_curvature", {})
	var span := float(measurements.get("contact_span_ratio", 0.0))
	var curvature := float(measurements.get("normalized_local_curvature", 0.0))
	var span_minimum := float(span_metric.get("min", span))
	var span_maximum := float(span_metric.get("max", span))
	var curvature_minimum := float(curvature_metric.get("min", curvature))
	var curvature_maximum := float(curvature_metric.get("max", curvature))
	var invalid := maxi(
		int(span_metric.get("invalid_sample_count", 1)),
		int(curvature_metric.get("invalid_sample_count", 1))
	)
	var evidence := [
		"outer contact span/Feret = %.4f; normalized local curvature = %.4f" % [span, curvature],
		"Anchor +/-2 px and Mask erosion/dilation 1 px span = %.4f..%.4f, curvature = %.4f..%.4f; invalid samples = %d" % [span_minimum, span_maximum, curvature_minimum, curvature_maximum, invalid],
		"a narrow contour cannot distinguish a point, an edge, or whole-object impact without functional intent",
	]
	if (
		invalid == 0
		and span_minimum >= BROAD_CONTACT_STABLE_SPAN_MIN
		and curvature_maximum <= BROAD_CONTACT_STABLE_CURVATURE_MAX
	):
		return _measured_axis("broad", 0.82, evidence, DECLARATION_VALUES["contact_surface"])

	var candidates: Array = DECLARATION_VALUES["contact_surface"]
	var morphology := "ambiguous"
	if invalid > 0:
		morphology = "unstable_contact_ray"
	elif span_maximum <= 0.17 and curvature_minimum >= 10.0:
		morphology = "narrow_contact"
		candidates = ["point", "edge", "whole_body"]
	elif span >= 0.20 and curvature <= 10.0:
		morphology = "broad_contact"
		candidates = ["broad", "whole_body"]
	var result := _unresolved_axis("contact_surface", "", "alpha_morphology_only", evidence, candidates)
	result["morphology"] = morphology
	return result


static func _unobservable_axis(axis: String, reason: String) -> Dictionary:
	return _unresolved_axis(axis, "", "not_observable_from_single_image", [reason], DECLARATION_VALUES[axis])


static func _unresolved_axis(
	_axis: String,
	suggestion: String,
	source: String,
	evidence: Array,
	candidates: Array
) -> Dictionary:
	return {
		"value": "",
		"suggestion": suggestion,
		"status": "needs_ai",
		"confidence": 0.0,
		"source": source,
		"evidence": evidence,
		"candidates": candidates.duplicate(),
	}


static func _measured_axis(value: String, confidence: float, evidence: Array, candidates: Array) -> Dictionary:
	return {
		"value": value,
		"suggestion": value,
		"status": "measured",
		"confidence": confidence,
		"source": "alpha+GripPrimary+StrikePoint",
		"evidence": evidence,
		"candidates": candidates.duplicate(),
	}


static func _declared_axis(axis: String, raw: Variant, previous: Dictionary) -> Dictionary:
	var declaration := _normalize_declaration(raw)
	var evidence: Array = declaration["evidence"]
	for prior: Variant in previous.get("evidence", []):
		evidence.append(str(prior))
	return {
		"value": str(declaration["value"]),
		"suggestion": str(previous.get("suggestion", "")),
		"status": "structured_declared",
		"confidence": float(declaration["confidence"]),
		"source": "structured_semantic_evidence",
		"evidence": evidence,
		"candidates": (DECLARATION_VALUES[axis] as Array).duplicate(),
	}


static func _normalize_declaration(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		var evidence: Array = []
		var raw_evidence: Variant = raw.get("evidence", [])
		if raw_evidence is Array or raw_evidence is PackedStringArray:
			for item: Variant in raw_evidence:
				evidence.append(str(item))
		elif not str(raw_evidence).is_empty():
			evidence.append(str(raw_evidence))
		if evidence.is_empty():
			evidence.append("explicit mechanism-axis declaration")
		return {
			"value": str(raw.get("value", "")),
			"confidence": float(raw.get("confidence", 0.95)),
			"evidence": evidence,
		}
	return {
		"value": str(raw),
		"confidence": 0.95,
		"evidence": ["explicit mechanism-axis declaration"],
	}


static func _with_soft_defaults(raw: Dictionary) -> Dictionary:
	var normalized := raw.duplicate(true)
	var rigidity_value := ""
	if normalized.has("rigidity"):
		rigidity_value = str(_normalize_declaration(normalized["rigidity"])["value"])
	if not rigidity_value.is_empty() and rigidity_value != "flexible":
		for axis: String in SOFT_AXES:
			if not normalized.has(axis):
				normalized[axis] = "none"
	return normalized


static func _declaration_error(declarations: Dictionary) -> String:
	for axis: String in REQUIRED_AXES:
		if not declarations.has(axis):
			continue
		var declaration := _normalize_declaration(declarations[axis])
		if str(declaration["value"]) not in DECLARATION_VALUES[axis]:
			return "INVALID_DECLARATION:%s" % axis
		var confidence := float(declaration["confidence"])
		if not is_finite(confidence) or confidence < 0.65 or confidence > 1.0:
			return "INVALID_DECLARATION_CONFIDENCE:%s" % axis
	for flag: String in REQUIRED_FLAGS:
		if declarations.has(flag) and not declarations[flag] is bool:
			return "INVALID_DECLARATION:%s" % flag
	return ""


static func _build_profile(axes: Dictionary, declarations: Dictionary) -> Resource:
	var profile: Resource = AFFORDANCE.new()
	var confidences: Array[float] = []
	var evidence := PackedStringArray()
	for axis: String in REQUIRED_AXES:
		var axis_result: Dictionary = axes[axis]
		profile.set(axis, str(axis_result["value"]))
		confidences.append(float(axis_result["confidence"]))
		for item: Variant in axis_result.get("evidence", []):
			var line := "%s: %s" % [axis, str(item)]
			if not evidence.has(line):
				evidence.append(line)
	var main_surface := str(profile.contact_surface)
	var secondary_surface := str(profile.secondary_contact_surface)
	profile.has_point = main_surface == "point" or secondary_surface == "point" or bool(declarations.get("has_point", false))
	profile.has_edge = main_surface == "edge" or secondary_surface == "edge" or bool(declarations.get("has_edge", false))
	profile.has_broad_face = main_surface == "broad" or secondary_surface == "broad" or bool(declarations.get("has_broad_face", false))
	profile.has_barrel = bool(declarations.get("has_barrel", false))
	profile.has_stock = bool(declarations.get("has_stock", false))
	var confidence := 1.0
	for value: float in confidences:
		confidence = minf(confidence, value)
	profile.confidence = confidence
	profile.evidence_parts = evidence
	return profile


static func _ai_source_error(source: String) -> String:
	var normalized := source.strip_edges().to_lower()
	if normalized.is_empty():
		return "AI_AFFORDANCE_SOURCE_MISSING"
	if normalized == "anthropic":
		return ""
	for prefix: String in TRUSTED_AI_SOURCE_PREFIXES:
		if normalized.begins_with(prefix):
			return ""
	return "UNTRUSTED_AI_AFFORDANCE_SOURCE"


static func _ai_affordance_error(ai_affordance: Dictionary) -> String:
	if ai_affordance.is_empty():
		return "AI_AFFORDANCE_MISSING"
	for axis: String in REQUIRED_AXES:
		if not ai_affordance.has(axis):
			return "AI_AFFORDANCE_MISSING_AXIS:%s" % axis
		if str(ai_affordance[axis]) not in DECLARATION_VALUES[axis]:
			return "AI_AFFORDANCE_INVALID_AXIS:%s" % axis
	for flag: String in REQUIRED_FLAGS:
		if not ai_affordance.has(flag):
			return "AI_AFFORDANCE_MISSING_FLAG:%s" % flag
		if not ai_affordance[flag] is bool:
			return "AI_AFFORDANCE_INVALID_FLAG:%s" % flag
	if not ai_affordance.has("confidence"):
		return "AI_AFFORDANCE_CONFIDENCE_MISSING"
	var confidence := float(ai_affordance.get("confidence", NAN))
	if not is_finite(confidence) or confidence < 0.65 or confidence > 1.0:
		return "AI_AFFORDANCE_CONFIDENCE_INVALID"
	if not ai_affordance.has("evidence_parts"):
		return "AI_AFFORDANCE_EVIDENCE_MISSING"
	var raw_evidence: Variant = ai_affordance.get("evidence_parts", [])
	if not (raw_evidence is Array or raw_evidence is PackedStringArray) or raw_evidence.is_empty():
		return "AI_AFFORDANCE_EVIDENCE_INVALID"
	for item: Variant in raw_evidence:
		if str(item).strip_edges().is_empty():
			return "AI_AFFORDANCE_EVIDENCE_INVALID"
	return ""


static func _geometry_conflicts(geometry: Dictionary, ai_affordance: Dictionary) -> Array[Dictionary]:
	var conflicts: Array[Dictionary] = []
	var axes: Dictionary = geometry.get("axes", {})
	var mass: Dictionary = axes.get("mass_distribution", {})
	var measured_mass := str(mass.get("value", ""))
	var ai_mass := str(ai_affordance.get("mass_distribution", ""))
	if str(mass.get("status", "")) == "measured" and not measured_mass.is_empty() and measured_mass != ai_mass:
		conflicts.append({
			"axis": "mass_distribution",
			"ai_value": ai_mass,
			"geometry_value": measured_mass,
			"rule": "stable_alpha_mass_projection",
		})
	var contact: Dictionary = axes.get("contact_surface", {})
	var measured_contact := str(contact.get("value", ""))
	var ai_contact := str(ai_affordance.get("contact_surface", ""))
	var straight_primary_path := (
		str(ai_affordance.get("flex_topology", "none")) == "none"
		and str(ai_affordance.get("tether_topology", "none")) == "none"
	)
	if (
		straight_primary_path
		and
		str(contact.get("status", "")) == "measured"
		and measured_contact == "broad"
		and ai_contact not in ["broad", "whole_body"]
	):
		conflicts.append({
			"axis": "contact_surface",
			"ai_value": ai_contact,
			"geometry_value": measured_contact,
			"rule": "stable_broad_contact_morphology",
		})
	return conflicts


static func _ai_failure(error: String, source: String) -> Dictionary:
	var result := _failure(error)
	result["source"] = source
	result["retry_required"] = true
	return result


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"complete": false,
		"automatic": false,
		"player_mechanism_input_used": false,
		"player_confirmation_required": false,
		"identity_inputs_used": false,
		"error": error,
		"profile": null,
	}
