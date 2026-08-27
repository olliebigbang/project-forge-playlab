class_name EnemyAttackVisualLanguage
extends RefCounted

const SCHEMA := "forge-enemy-attack-visual-language-v1"

const VISUAL_PARAMETER_OWNERS := {
	"primary_color": "delivery",
	"marker_family": "delivery",
	"lock_marker": "target_lock",
	"pulse_hz": "tempo",
	"stability_marker": "stability",
	"recovery_marker": "recovery",
}


static func compile(compiled_attack: Dictionary) -> Dictionary:
	var axes := compiled_attack.get("axes", {}) as Dictionary
	if axes.is_empty():
		return _failure("ATTACK_VISUAL_AXES_MISSING")
	for axis: String in ["delivery", "target_lock", "tempo", "stability", "recovery"]:
		if str(axes.get(axis, "")).is_empty():
			return _failure("ATTACK_VISUAL_AXIS_MISSING:%s" % axis)

	var delivery := str(axes["delivery"])
	var target_lock := str(axes["target_lock"])
	var tempo := str(axes["tempo"])
	var stability := str(axes["stability"])
	var recovery := str(axes["recovery"])
	var delivery_visual := _delivery_visual(delivery)
	var result := {
		"ok": true,
		"schema": SCHEMA,
		"delivery": delivery,
		"primary_color": str(delivery_visual["primary_color"]),
		"marker_family": str(delivery_visual["marker_family"]),
		"lock_marker": _lock_marker(target_lock),
		"pulse_hz": _pulse_hz(tempo),
		"stability_marker": _stability_marker(stability),
		"recovery_marker": _recovery_marker(recovery),
		"visual_parameter_owners": VISUAL_PARAMETER_OWNERS.duplicate(true),
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
	result["visual_signature"] = JSON.stringify({
		"delivery": delivery,
		"marker_family": result["marker_family"],
		"lock_marker": result["lock_marker"],
		"pulse_hz": result["pulse_hz"],
		"stability_marker": result["stability_marker"],
		"recovery_marker": result["recovery_marker"],
	}).sha256_text().left(16)
	return result


static func _delivery_visual(delivery: String) -> Dictionary:
	match delivery:
		"rush":
			return {"primary_color": "ef4444", "marker_family": "chevron_lane"}
		"projectile":
			return {"primary_color": "fb923c", "marker_family": "dashed_launch"}
		"marked_impact":
			return {"primary_color": "f472b6", "marker_family": "concentric_target"}
		_:
			return {"primary_color": "facc15", "marker_family": "body_sweep"}


static func _lock_marker(target_lock: String) -> String:
	match target_lock:
		"direction_on_commit":
			return "direction_gate"
		"point_on_commit":
			return "point_brackets"
		_:
			return "tracking_tether"


static func _pulse_hz(tempo: String) -> float:
	match tempo:
		"quick":
			return 5.0
		"committed":
			return 1.8
		_:
			return 3.0


static func _stability_marker(stability: String) -> String:
	match stability:
		"armored_commit":
			return "shield_frame"
		"tell_interruptible":
			return "open_ring"
		_:
			return "broken_ring"


static func _recovery_marker(recovery: String) -> String:
	match recovery:
		"extended":
			return "triple_bars"
		"punishable":
			return "double_bars"
		_:
			return "single_bar"


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"schema": SCHEMA,
		"error": error,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
