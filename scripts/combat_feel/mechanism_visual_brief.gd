class_name MechanismVisualBrief
extends RefCounted

const SCHEMA := "forge-mechanism-visual-brief-v1"
const SOURCE := "ai_mechanism_axes_visual_compiler_v1"
const STRUCTURAL_AXES: PackedStringArray = [
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


static func compile(ai_affordance: Dictionary, affordance_source: String = "") -> Dictionary:
	if ai_affordance.is_empty():
		return {}
	var flex := str(ai_affordance.get("flex_topology", "none"))
	var tether := str(ai_affordance.get("tether_topology", "none"))
	var terminal := str(ai_affordance.get("terminal_load", "none"))
	var deployment := str(ai_affordance.get("tether_deployment", "none"))
	var required_roles: Array[String] = ["rigid_root"]
	if flex != "none":
		required_roles.append("deform_body")
	elif tether != "none":
		required_roles.append("rigid_body")
	if tether != "none":
		required_roles.append("tether")
	if terminal != "none":
		required_roles.append("terminal")

	var requirements: Array[String] = []
	requirements.append(_handle_requirement(str(ai_affordance.get("handle_length", "medium"))))
	requirements.append(_body_length_requirement(str(ai_affordance.get("body_length", "medium"))))
	requirements.append(_grip_requirement(str(ai_affordance.get("grip_topology", "one_hand_handle"))))
	requirements.append(_mass_requirement(str(ai_affordance.get("mass_distribution", "balanced"))))
	requirements.append(_contact_requirement(str(ai_affordance.get("contact_surface", "point")), false))
	var secondary_contact := str(ai_affordance.get("secondary_contact_surface", "none"))
	if secondary_contact != "none":
		requirements.append(_contact_requirement(secondary_contact, true))
	requirements.append(_primary_requirement(flex, str(ai_affordance.get("rigidity", "rigid"))))
	if tether != "none":
		requirements.append(_tether_requirement(tether))
	if terminal != "none":
		requirements.append(_terminal_requirement(terminal))
	var tether_mode := str(ai_affordance.get("tether_mode", "none"))
	if tether_mode != "none":
		requirements.append(_tether_mode_requirement(tether_mode))
	if deployment != "none":
		requirements.append(_tether_deployment_requirement(deployment))
	requirements.append("All required structures must survive at 96 by 96 pixels as chunky silhouette regions; do not replace them with motion trails or micro-detail.")

	var axes: Dictionary = {}
	for axis: String in STRUCTURAL_AXES:
		axes[axis] = str(ai_affordance.get(axis, "none"))
	var prompt_requirements := _compact_prompt_requirements(ai_affordance)
	return {
		"schema": SCHEMA,
		"source": SOURCE,
		"affordance_source": affordance_source.strip_edges(),
		"automatic": true,
		"player_confirmation_required": false,
		"axes": axes,
		"required_roles": required_roles,
		"visual_requirements": requirements,
		"prompt_clause": "Mechanism-readable pixel silhouette contract: %s" % " ".join(prompt_requirements),
		"gate_rules": _gate_rules(str(ai_affordance.get("body_length", "medium")), flex, tether, terminal),
	}


static func _compact_prompt_requirements(ai_affordance: Dictionary) -> Array[String]:
	var flex := str(ai_affordance.get("flex_topology", "none"))
	var tether := str(ai_affordance.get("tether_topology", "none"))
	var terminal := str(ai_affordance.get("terminal_load", "none"))
	var tether_mode := str(ai_affordance.get("tether_mode", "none"))
	var deployment := str(ai_affordance.get("tether_deployment", "none"))
	var result: Array[String] = [
		"Held geometry: %s; %s; %s; %s." % [
			_compact_handle(str(ai_affordance.get("handle_length", "medium"))),
			_compact_body(str(ai_affordance.get("body_length", "medium"))),
			_compact_grip(str(ai_affordance.get("grip_topology", "one_hand_handle"))),
			_compact_mass(str(ai_affordance.get("mass_distribution", "balanced"))),
		],
		"Contacts: %s primary; %s secondary." % [
			_compact_contact(str(ai_affordance.get("contact_surface", "point"))),
			_compact_contact(str(ai_affordance.get("secondary_contact_surface", "none"))),
		],
		_compact_primary(flex, str(ai_affordance.get("rigidity", "rigid"))),
	]
	if tether != "none":
		result.append(_compact_tether(tether))
	if terminal != "none":
		result.append(_compact_terminal(terminal))
	if tether_mode != "none":
		result.append(_compact_tether_mode(tether_mode))
	if deployment != "none":
		result.append(_compact_tether_deployment(deployment))
	result.append("At 96px use chunky connected regions; no trails or microdetail.")
	return result


static func _compact_handle(value: String) -> String:
	return str({
		"none": "integrated hold, no handle",
		"short": "short rigid handle",
		"medium": "medium rigid handle",
		"long": "long rigid handle",
	}.get(value, "medium rigid handle"))


static func _compact_body(value: String) -> String:
	return "%s functional body" % value


static func _compact_grip(value: String) -> String:
	return str({
		"one_hand_handle": "compact one-hand grip",
		"two_hand_handle": "two separated hand zones",
		"body_grip": "integrated body grip",
		"clamp_grip": "visible clamp or bracket grip",
	}.get(value, "compact one-hand grip"))


static func _compact_mass(value: String) -> String:
	return str({
		"rear": "rear-weighted mass",
		"front": "front-weighted mass",
		"balanced": "balanced mass",
	}.get(value, "balanced mass"))


static func _compact_contact(value: String) -> String:
	return str({
		"none": "none",
		"point": "narrow visible point",
		"edge": "long thin edge",
		"broad": "wide blunt face",
		"whole_body": "whole-body outer silhouette",
	}.get(value, "whole-body outer silhouette"))


static func _compact_primary(flex: String, rigidity: String) -> String:
	match flex:
		"bending_shaft": return "Primary body: clearly curved centerline, midpoint visibly off its end chord; never a straight bar."
		"flexible_line": return "Primary body: continuous slender curved line, tapering from grip; deep S curve with a returning tip, never a straight bar."
		"linked_segments": return "Primary body: repeated connected sections with visible joints; 3-5 chunky sections and two narrow hinge necks cut into the outer silhouette."
		_: return "Primary body: %s connected silhouette." % rigidity.replace("_", "-")


static func _compact_tether(value: String) -> String:
	if value == "linked_segments":
		return "Attached path: second articulated linked path with visible independent joints."
	return "Attached path: second thin continuous tether, visibly divergent."


static func _compact_terminal(value: String) -> String:
	if value == "heavy":
		return "End: large distinct terminal mass, wider than its path."
	return "End: small but distinct terminal piece, wider than its path."


static func _compact_tether_mode(value: String) -> String:
	if value == "hook":
		return "Hook cue: angled catching point visible at line end."
	return "Wrap cue: soft path visibly returns in a curve."


static func _compact_tether_deployment(value: String) -> String:
	match value:
		"cast_retract": return "Deployment: chunky reel or line reserve for payout and return."
		"launch_tension": return "Deployment: visible launch guide and tether reserve for a tensioned line."
		_: return "Deployment: attached path stays at one fixed visible length."


static func validation_errors(brief: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(brief.get("schema", "")) != SCHEMA:
		errors.append("MECHANISM_VISUAL_BRIEF_SCHEMA_INVALID")
	if str(brief.get("source", "")) != SOURCE:
		errors.append("MECHANISM_VISUAL_BRIEF_SOURCE_INVALID")
	if not bool(brief.get("automatic", false)):
		errors.append("MECHANISM_VISUAL_BRIEF_MUST_BE_AUTOMATIC")
	if bool(brief.get("player_confirmation_required", true)):
		errors.append("MECHANISM_VISUAL_BRIEF_PLAYER_CONFIRMATION_FORBIDDEN")
	if not brief.get("axes", {}) is Dictionary or (brief.get("axes", {}) as Dictionary).is_empty():
		errors.append("MECHANISM_VISUAL_BRIEF_AXES_MISSING")
	if not brief.get("required_roles", []) is Array or (brief.get("required_roles", []) as Array).is_empty():
		errors.append("MECHANISM_VISUAL_BRIEF_ROLES_MISSING")
	if str(brief.get("prompt_clause", "")).strip_edges().is_empty():
		errors.append("MECHANISM_VISUAL_BRIEF_PROMPT_MISSING")
	return errors


static func _handle_requirement(value: String) -> String:
	match value:
		"none": return "Show a visibly holdable root region inside the body, without inventing a detached handle."
		"short": return "Show one compact rigid held fixture before the moving body."
		"long": return "Show one long rigid held fixture clearly separated from the functional body."
		_: return "Show one readable rigid held fixture separated from the functional body."


static func _body_length_requirement(value: String) -> String:
	match value:
		"short": return "Keep the functional body compact relative to the held region while leaving its contact end readable."
		"long": return "Give the functional body a long uninterrupted silhouette span from the held region to the contact end."
		_: return "Give the functional body a clearly readable medium silhouette span from the held region to the contact end."


static func _grip_requirement(value: String) -> String:
	match value:
		"two_hand_handle": return "Make the held fixture long enough for two visibly separated hand zones."
		"body_grip": return "Do not add a separate handle; show a widened holdable region integrated into the object's body."
		"clamp_grip": return "Show a readable clamp, fork, ring, or bracket-shaped held fixture instead of a plain stick handle."
		_: return "Make the held fixture a compact one-hand region."


static func _mass_requirement(value: String) -> String:
	match value:
		"rear": return "Concentrate more visible silhouette area close to or behind the held region than at the contact end."
		"front": return "Concentrate visibly more silhouette area toward the contact end than around the held region."
		_: return "Keep the major silhouette volumes visually balanced across the held-to-contact span."


static func _contact_requirement(value: String, secondary: bool) -> String:
	var prefix := "The separate secondary contact region" if secondary else "The primary contact region"
	match value:
		"point": return "%s ends in a narrow, clearly visible point rather than a rounded blob." % prefix
		"edge": return "%s exposes a long thin edge with a readable contact direction." % prefix
		"broad": return "%s is a wide, flat or blunt face with enough pixel thickness to survive reduction." % prefix
		_: return "%s remains readable along the main body's outer silhouette rather than only at a tiny tip." % prefix


static func _primary_requirement(flex: String, rigidity: String) -> String:
	match flex:
		"bending_shaft": return "The primary body is one connected shaft with a clearly curved centerline and midpoint visibly off its end chord, never a straight bar."
		"flexible_line": return "The primary body is one continuous slender deep S-curve that visibly narrows away from the held fixture and returns at its tip, never a straight bar."
		"linked_segments": return "The primary body shows three to five chunky connected sections; at least two narrow hinge necks cut into the outer silhouette, never just decorative bands on one smooth bar."
		_:
			return "The primary body reads as one rigid connected silhouette." if rigidity == "rigid" else "The primary body reads as one connected semi-rigid silhouette."


static func _tether_requirement(value: String) -> String:
	if value == "linked_segments":
		return "Add a second articulated linked path attached after the primary body; its joints and direction must remain independently visible."
	return "Add a second thin continuous tether attached after the primary body; it must visibly depart from the primary body's direction."


static func _terminal_requirement(value: String) -> String:
	if value == "heavy":
		return "End the moving path with a large concentrated terminal mass that is wider than the preceding path."
	return "End the moving path with a small but distinct terminal piece wider than the preceding path."


static func _tether_mode_requirement(value: String) -> String:
	if value == "hook":
		return "Give the line end a visible angled catching point; it must read in the still silhouette without an effect trail."
	return "Give the soft path enough visible returning curve to wrap around a target; do not draw it as a straight ray."


static func _tether_deployment_requirement(value: String) -> String:
	match value:
		"cast_retract":
			return "Show one chunky reel, coil, or line-reserve fixture where the tether can visibly pay out and return; do not represent payout as a motion trail."
		"launch_tension":
			return "Show one readable launch guide plus a compact tether reserve so the terminal can depart and leave a tensioned connection."
		_:
			return "Keep the attached path visibly connected at one fixed resting length without a payout fixture."


static func _gate_rules(body_length: String, flex: String, tether: String, terminal: String) -> Dictionary:
	var minimum_span := 0.16
	if body_length == "medium":
		minimum_span = 0.24
	elif body_length == "long":
		minimum_span = 0.34
	return {
		"minimum_grip_to_strike_span_ratio": minimum_span,
		"minimum_soft_curvature_ratio": 0.09 if flex in ["bending_shaft", "flexible_line"] else 0.0,
		"minimum_linked_width_peaks": 3 if flex == "linked_segments" or tether == "linked_segments" else 0,
		"minimum_linked_color_transitions": 6 if flex == "linked_segments" or tether == "linked_segments" else 0,
		"minimum_tether_span_ratio": 0.16 if tether != "none" else 0.0,
		"minimum_tether_divergence_degrees": 18.0 if tether != "none" else 0.0,
		"minimum_terminal_pixels": 12 if terminal == "heavy" else (4 if terminal == "light" else 0),
	}
