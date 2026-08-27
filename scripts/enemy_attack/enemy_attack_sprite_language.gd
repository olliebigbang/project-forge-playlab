class_name EnemyAttackSpriteLanguage
extends RefCounted

const ATTACK_VISUAL := preload("res://scripts/enemy_attack/enemy_attack_visual_language.gd")
const SCHEMA := "forge-enemy-attack-sprite-language-v1"

const SPRITE_PARAMETER_OWNERS := {
	"tool_family": "delivery",
	"accent_color": "delivery",
	"sensor_family": "target_lock",
	"tool_head": "hit_shape",
	"stance_family": "depth_path",
	"animation_hz": "tempo",
	"body_width": "stability",
	"body_height": "stability",
	"body_color": "stability",
	"armor_plate_count": "stability",
	"recovery_drop_pixels": "recovery",
}


static func compile(compiled_attack: Dictionary) -> Dictionary:
	var axes := compiled_attack.get("axes", {}) as Dictionary
	if axes.is_empty():
		return _failure("ATTACK_SPRITE_AXES_MISSING")
	for axis: String in [
		"delivery", "target_lock", "hit_shape", "depth_path", "tempo", "stability", "recovery",
	]:
		if str(axes.get(axis, "")).is_empty():
			return _failure("ATTACK_SPRITE_AXIS_MISSING:%s" % axis)

	var attack_visual: Dictionary = ATTACK_VISUAL.compile(compiled_attack)
	if not bool(attack_visual.get("ok", false)):
		return _failure(str(attack_visual.get("error", "ATTACK_VISUAL_COMPILE_FAILED")))
	var frame := _stability_frame(str(axes["stability"]))
	var result := {
		"ok": true,
		"schema": SCHEMA,
		"tool_family": _tool_family(str(axes["delivery"])),
		"accent_color": str(attack_visual["primary_color"]),
		"sensor_family": _sensor_family(str(axes["target_lock"])),
		"tool_head": _tool_head(str(axes["hit_shape"])),
		"stance_family": _stance_family(str(axes["depth_path"])),
		"animation_hz": _animation_hz(str(axes["tempo"])),
		"body_width": float(frame["body_width"]),
		"body_height": float(frame["body_height"]),
		"body_color": str(frame["body_color"]),
		"armor_plate_count": int(frame["armor_plate_count"]),
		"recovery_drop_pixels": _recovery_drop(str(axes["recovery"])),
		"sprite_parameter_owners": SPRITE_PARAMETER_OWNERS.duplicate(true),
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
	var signature_source := result.duplicate(true)
	signature_source.erase("ok")
	signature_source.erase("schema")
	signature_source.erase("sprite_parameter_owners")
	signature_source.erase("identity_inputs_used")
	signature_source.erase("player_confirmation_required")
	result["sprite_signature"] = JSON.stringify(signature_source).sha256_text().left(16)
	return result


static func _tool_family(delivery: String) -> String:
	match delivery:
		"rush": return "ram_prongs"
		"projectile": return "barrel"
		"marked_impact": return "focus_orb"
		_: return "swing_limb"


static func _sensor_family(target_lock: String) -> String:
	match target_lock:
		"direction_on_commit": return "direction_slit"
		"point_on_commit": return "point_diamond"
		_: return "tracking_eye"


static func _tool_head(hit_shape: String) -> String:
	match hit_shape:
		"arc": return "blade"
		"circle": return "orb"
		"strip": return "wedge"
		_: return "rod"


static func _stance_family(depth_path: String) -> String:
	match depth_path:
		"cross_depth": return "staggered"
		"depth_band": return "wide"
		_: return "narrow"


static func _animation_hz(tempo: String) -> float:
	match tempo:
		"quick": return 7.0
		"committed": return 2.0
		_: return 4.0


static func _stability_frame(stability: String) -> Dictionary:
	match stability:
		"armored_commit":
			return {
				"body_width": 42.0, "body_height": 38.0,
				"body_color": "64748b", "armor_plate_count": 3,
			}
		"tell_interruptible":
			return {
				"body_width": 32.0, "body_height": 34.0,
				"body_color": "d97706", "armor_plate_count": 1,
			}
		_:
			return {
				"body_width": 24.0, "body_height": 28.0,
				"body_color": "0891b2", "armor_plate_count": 0,
			}


static func _recovery_drop(recovery: String) -> float:
	match recovery:
		"extended": return 12.0
		"punishable": return 7.0
		_: return 2.0


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"schema": SCHEMA,
		"error": error,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
