class_name EnemyIdentityVisualLanguage
extends RefCounted

const SCHEMA := "forge-enemy-identity-visual-language-v1"
const DEFAULT_AXES := {
	"body_plan": "biped",
	"scale": "medium",
	"material": "metal",
	"palette": "industrial",
	"signature_feature": "shoulder_core",
}
const LEGAL := {
	"body_plan": ["biped", "quadruped", "arachnid", "serpentine", "floating", "tracked"],
	"scale": ["small", "medium", "large"],
	"material": ["flesh", "chitin", "metal", "stone", "spectral"],
	"palette": ["ember", "venom", "frost", "arcane", "electric", "industrial"],
	"signature_feature": ["mandibles", "horns", "dorsal_spines", "halo", "tail", "shoulder_core"],
}
const PARAMETER_OWNERS := {
	"body_plan": "body_plan",
	"scale_multiplier": "scale",
	"material_color": "material",
	"accent_color": "palette",
	"signature_feature": "signature_feature",
}


static func compile(raw_axes: Dictionary) -> Dictionary:
	var axes := raw_axes if not raw_axes.is_empty() else DEFAULT_AXES
	if axes.size() != LEGAL.size():
		return _failure("ENEMY_IDENTITY_VISUAL_AXES_INVALID")
	for key: String in LEGAL:
		if not axes.has(key) or str(axes.get(key, "")) not in (LEGAL[key] as Array):
			return _failure("ENEMY_IDENTITY_VISUAL_AXIS_INVALID:%s" % key)
	var result := {
		"ok": true,
		"schema": SCHEMA,
		"body_plan": str(axes["body_plan"]),
		"scale_multiplier": _scale_multiplier(str(axes["scale"])),
		"material_color": _material_color(str(axes["material"])),
		"accent_color": _accent_color(str(axes["palette"])),
		"signature_feature": str(axes["signature_feature"]),
		"parameter_owners": PARAMETER_OWNERS.duplicate(true),
		"player_confirmation_required": false,
	}
	result["visual_signature"] = JSON.stringify({
		"body_plan": result["body_plan"],
		"scale_multiplier": result["scale_multiplier"],
		"material_color": result["material_color"],
		"accent_color": result["accent_color"],
		"signature_feature": result["signature_feature"],
	}).sha256_text().left(16)
	return result


static func _scale_multiplier(scale: String) -> float:
	match scale:
		"small": return 0.78
		"large": return 1.24
		_: return 1.0


static func _material_color(material: String) -> String:
	match material:
		"flesh": return "b45353"
		"chitin": return "52525b"
		"stone": return "78716c"
		"spectral": return "6366f1"
		_: return "64748b"


static func _accent_color(palette: String) -> String:
	match palette:
		"ember": return "fb923c"
		"venom": return "a3e635"
		"frost": return "67e8f9"
		"arcane": return "c084fc"
		"electric": return "fde047"
		_: return "f59e0b"


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "schema": SCHEMA, "error": error, "player_confirmation_required": false}
