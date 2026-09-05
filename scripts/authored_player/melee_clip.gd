extends RefCounted
## Source-frame ranges reviewed from the actual PNGs. These are animation
## phase annotations, not new damage events. Runtime retains all axis timings.
const CLIPS := {
	"thrust": {"key": "combat/SwordCombo03", "startup": [0, 0], "active": [1, 1], "recovery": [2, 4]},
	"sweep": {"key": "combat/StandingSlash", "startup": [0, 0], "active": [1, 2], "recovery": [3, 4]},
	"bash": {"key": "combat/StandingSlash", "startup": [0, 0], "active": [1, 2], "recovery": [3, 4]},
	"slam": {"key": "combat/SwordSlash01", "startup": [0, 1], "active": [2, 2], "recovery": [3, 7]},
	"spin": {"key": "combat/SwordCombo01", "startup": [0, 2], "active": [3, 3], "recovery": [4, 5]},
}

# A rigid one-hand blade uses the pack's authored sword choreography as one
# coherent presentation sequence. Runtime phases and contacts still come from
# the mechanism compiler; these ranges only select the original body frames.
const BLADE_COMBO := {
	1: {"key": "combat/SwordCombo01", "startup": [0, 2], "active": [3, 3], "recovery": [4, 5]},
	2: {"key": "combat/SwordCombo02", "startup": [0, 1], "active": [2, 2], "recovery": [3, 4]},
	3: {"key": "combat/SwordCombo04", "startup": [0, 2], "active": [3, 4], "recovery": [5, 7]},
}
const BLADE_CHARGE := {"key": "combat/SwordSlash01", "startup": [0, 1], "active": [2, 2], "recovery": [3, 7]}
const BLADE_DODGE := {"key": "combat/StandingSlash", "startup": [0, 0], "active": [1, 2], "recovery": [3, 4]}

# These are body-action presentations selected from anonymous structure. The
# generated object remains visible and all contact timing/path data still comes
# from MotionPrimitive. Point polearms use three different source actions for a
# jab, rising rake and overhead plant. Weighted flexible endpoints use throw/
# pull source actions while their real terminal pixels follow the compiled arc.
const PRESENTATION_CLIPS := {
	"pole_jab": {"key": "combat/SwordCombo03", "startup": [0, 0], "active": [1, 1], "recovery": [2, 4]},
	"pole_rake": {"key": "combat/StandingSlash", "startup": [0, 0], "active": [1, 2], "recovery": [3, 4]},
	"pole_pin": {"key": "combat/SwordSlash01", "startup": [0, 1], "active": [2, 2], "recovery": [3, 7]},
	"pole_charge": {"key": "combat/SwordSlash01", "startup": [0, 1], "active": [2, 2], "recovery": [3, 7]},
	"pole_dodge": {"key": "combat/SwordCombo03", "startup": [0, 0], "active": [1, 1], "recovery": [2, 4]},
	"weighted_cast_low": {"key": "combat/ThrowUnderarm", "startup": [0, 1], "active": [2, 3], "recovery": [4, 5]},
	"weighted_lash_cross": {"key": "combat/ThrowOverarm", "startup": [0, 1], "active": [2, 2], "recovery": [3, 4]},
	"weighted_retract": {"key": "body/Pull", "startup": [0, 1], "active": [2, 3], "recovery": [4, 5]},
	"weighted_cast_charge": {"key": "combat/ThrowOverarm", "startup": [0, 1], "active": [2, 2], "recovery": [3, 4]},
	"weighted_dodge_lash": {"key": "combat/ThrowUnderarm", "startup": [0, 0], "active": [1, 3], "recovery": [4, 5]},
}

static func sample(rig: RefCounted, family: String, phase: String, ratio: float) -> Dictionary:
	var spec: Dictionary = CLIPS.get(family, CLIPS.sweep)
	return _sample_spec(rig, spec, phase, ratio)

static func sample_blade(rig: RefCounted, combo_index: int, attack_kind: String, phase: String, ratio: float) -> Dictionary:
	var spec: Dictionary
	if attack_kind == "charge": spec = BLADE_CHARGE
	elif attack_kind == "dodge": spec = BLADE_DODGE
	else: spec = BLADE_COMBO.get(clampi(combo_index, 1, 3), BLADE_COMBO[1])
	return _sample_spec(rig, spec, phase, ratio)

static func sample_presentation(rig: RefCounted, family: String, phase: String, ratio: float) -> Dictionary:
	var spec: Dictionary = PRESENTATION_CLIPS.get(family, {})
	if spec.is_empty():
		return sample(rig, "sweep", phase, ratio)
	return _sample_spec(rig, spec, phase, ratio)

static func _sample_spec(rig: RefCounted, spec: Dictionary, phase: String, ratio: float) -> Dictionary:
	var bounds: Array = spec.get(phase, spec.startup)
	var key := str(spec.key)
	var group := key.get_slice("/", 0)
	var metadata: Dictionary = rig.metadata[group]
	var tag: Dictionary = metadata.tags[key.get_slice("/", 1)]
	var duration := 0.0
	for index: int in range(bounds[0], bounds[1] + 1): duration += float(metadata.durations[tag.first + index])
	var time := clampf(ratio, 0, 0.99999) * duration
	var chosen: int = bounds[1]
	for index: int in range(bounds[0], bounds[1] + 1):
		var dt := float(metadata.durations[tag.first + index])
		if time < dt: chosen = index; break
		time -= dt
	return rig.frame(key, chosen)
