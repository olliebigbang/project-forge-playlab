class_name ComboRecipe
extends Resource

@export var hit_1: Resource
@export var hit_2: Resource
@export var hit_3: Resource


func primitive_for(combo_index: int) -> Resource:
	match combo_index:
		1: return hit_1
		2: return hit_2
		3: return hit_3
		_: return null


func primitives() -> Array[Resource]:
	var values: Array[Resource] = [hit_1, hit_2, hit_3]
	return values


func primitive_sequence() -> PackedStringArray:
	var sequence := PackedStringArray()
	for primitive: Variant in primitives():
		sequence.append(str(primitive.motion_family) if primitive != null else "missing")
	return sequence


func signature() -> String:
	var segments: Array[String] = []
	for primitive: Variant in primitives():
		if primitive == null:
			segments.append("missing")
			continue
		segments.append("%s:%.3f,%.3f,%.1f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [
			primitive.motion_family,
			primitive.start_angle,
			primitive.end_angle,
			primitive.extension_pixels,
			primitive.startup_multiplier,
			primitive.active_multiplier,
			primitive.recovery_multiplier,
			primitive.reach_multiplier,
			primitive.movement_multiplier,
			primitive.hitbox_multiplier,
		])
	return "|".join(segments)


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
	return errors


func to_dict() -> Dictionary:
	var first: Variant = hit_1
	var second: Variant = hit_2
	var third: Variant = hit_3
	return {
		"hit_1": first.to_dict() if first != null else null,
		"hit_2": second.to_dict() if second != null else null,
		"hit_3": third.to_dict() if third != null else null,
	}
