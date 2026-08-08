class_name ComboRecipe
extends Resource

@export var hit_1: Resource
@export var hit_2: Resource
@export var hit_3: Resource
@export var charge_attack: Resource
@export var dodge_attack: Resource
@export var compile_reason := ""
@export var mechanism_axes: Dictionary = {}
@export var primitive_scores: Dictionary = {}
var recipe_signature: String:
	get:
		return signature()


func primitive_for(combo_index: int) -> Resource:
	match combo_index:
		1: return hit_1
		2: return hit_2
		3: return hit_3
		_: return null


func primitive_for_attack(attack_kind: String, combo_index: int = 0) -> Resource:
	match attack_kind:
		"normal": return primitive_for(combo_index)
		"charge": return charge_attack
		"dodge": return dodge_attack
		_: return null


func primitives() -> Array[Resource]:
	var values: Array[Resource] = [hit_1, hit_2, hit_3]
	return values


func all_primitives() -> Array[Resource]:
	var values: Array[Resource] = [hit_1, hit_2, hit_3, charge_attack, dodge_attack]
	return values


func primitive_sequence() -> PackedStringArray:
	var sequence := PackedStringArray()
	for primitive: Variant in primitives():
		sequence.append(str(primitive.motion_family) if primitive != null else "missing")
	return sequence


func signature() -> String:
	var segments: Array[String] = []
	for primitive: Variant in all_primitives():
		if primitive == null:
			segments.append("missing")
			continue
		segments.append(JSON.stringify(primitive.to_dict()))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("|".join(segments).to_utf8_buffer())
	return context.finish().hex_encode()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var values := primitives()
	if values.size() != 3:
		errors.append("COMBO_RECIPE_MUST_HAVE_THREE_HITS")
		return errors
	for index: int in range(values.size()):
		var primitive: Variant = values[index]
		if primitive == null:
			errors.append("MISSING_HIT_%d" % (index + 1))
			continue
		for error: String in primitive.validation_errors():
			errors.append("HIT_%d_%s" % [index + 1, error])
	if hit_1 != null and hit_2 != null and is_same(hit_1, hit_2):
		errors.append("HIT_1_AND_HIT_2_SHARE_INSTANCE")
	if hit_1 != null and hit_3 != null and is_same(hit_1, hit_3):
		errors.append("HIT_1_AND_HIT_3_SHARE_INSTANCE")
	if hit_2 != null and hit_3 != null and is_same(hit_2, hit_3):
		errors.append("HIT_2_AND_HIT_3_SHARE_INSTANCE")
	for entry: Dictionary in [
		{"name": "CHARGE", "primitive": charge_attack},
		{"name": "DODGE", "primitive": dodge_attack},
	]:
		var special: Variant = entry["primitive"]
		if special == null:
			errors.append("MISSING_%s_ATTACK" % str(entry["name"]))
			continue
		for error: String in special.validation_errors():
			errors.append("%s_%s" % [str(entry["name"]), error])
	if compile_reason.is_empty():
		errors.append("MISSING_COMPILE_REASON")
	if compile_reason.begins_with("orthogonal affordance composition"):
		if mechanism_axes.is_empty():
			errors.append("MISSING_MECHANISM_AXES")
		if primitive_scores.is_empty():
			errors.append("MISSING_PRIMITIVE_SCORES")
	return errors


func to_dict() -> Dictionary:
	var first: Variant = hit_1
	var second: Variant = hit_2
	var third: Variant = hit_3
	return {
		"hit_1": first.to_dict() if first != null else null,
		"hit_2": second.to_dict() if second != null else null,
		"hit_3": third.to_dict() if third != null else null,
		"charge_attack": charge_attack.to_dict() if charge_attack != null else null,
		"dodge_attack": dodge_attack.to_dict() if dodge_attack != null else null,
		"recipe_signature": signature(),
		"compile_reason": compile_reason,
		"mechanism_axes": mechanism_axes.duplicate(true),
		"primitive_scores": primitive_scores.duplicate(true),
	}
