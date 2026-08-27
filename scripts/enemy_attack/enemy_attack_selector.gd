class_name EnemyAttackSelector
extends RefCounted

const ATTACK_SCHEMA := "forge-enemy-attack-mechanism-v1"
const REPEAT_PENALTY := 18.0
const SCORE_EPSILON := 0.0001


static func select_attack(compiled_attacks: Array, context: Dictionary) -> Dictionary:
	var context_error := _context_error(context)
	if not context_error.is_empty():
		return _failure(context_error)

	var distance := float(context["distance_pixels"])
	var depth_delta := absf(float(context["depth_delta_pixels"]))
	var budget := int(context["available_coordination_budget"])
	var clear_path := bool(context["clear_path"])
	var previous_signature := str(context.get("previous_mechanism_signature", ""))
	var cooldowns := context.get("cooldown_remaining_by_key", {}) as Dictionary
	var considered: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	var best_attack: Dictionary = {}
	var best_score := -INF
	var best_rank := 1000000
	var best_index := 1000000
	var best_breakdown: Dictionary = {}

	for index: int in range(compiled_attacks.size()):
		var raw_candidate: Variant = compiled_attacks[index]
		if not raw_candidate is Dictionary:
			rejected.append({"index": index, "reason": "NOT_COMPILED_ATTACK"})
			continue
		var candidate := raw_candidate as Dictionary
		if not bool(candidate.get("ok", false)) or str(candidate.get("schema", "")) != ATTACK_SCHEMA:
			rejected.append({"index": index, "reason": "NOT_COMPILED_ATTACK"})
			continue

		var attack_key := str(candidate.get("attack_key", ""))
		var selection_value: Variant = candidate.get("selection", null)
		if not selection_value is Dictionary:
			rejected.append({"index": index, "attack_key": attack_key, "reason": "SELECTION_DATA_MISSING"})
			continue
		var selection := selection_value as Dictionary
		var rejection := _eligibility_rejection(attack_key, selection, distance, depth_delta, budget, clear_path, cooldowns)
		if not rejection.is_empty():
			rejected.append({"index": index, "attack_key": attack_key, "reason": rejection})
			continue

		var breakdown := _score_breakdown(candidate, selection, distance, depth_delta, previous_signature)
		var score := float(breakdown["total"])
		var rank := int(selection.get("selection_rank", 999))
		considered.append({
			"index": index,
			"attack_key": attack_key,
			"mechanism_signature": str(candidate.get("mechanism_signature", "")),
			"score": score,
			"selection_rank": rank,
			"breakdown": breakdown,
		})
		if _is_better(score, rank, index, best_score, best_rank, best_index):
			best_attack = candidate
			best_score = score
			best_rank = rank
			best_index = index
			best_breakdown = breakdown

	if best_attack.is_empty():
		var failure := _failure("NO_ELIGIBLE_ATTACK")
		failure["considered"] = considered
		failure["rejected"] = rejected
		return failure
	return {
		"ok": true,
		"attack_key": str(best_attack["attack_key"]),
		"selected_attack": best_attack.duplicate(true),
		"score": best_score,
		"score_breakdown": best_breakdown,
		"considered": considered,
		"rejected": rejected,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}


static func _context_error(context: Dictionary) -> String:
	for field: String in ["distance_pixels", "depth_delta_pixels", "available_coordination_budget", "clear_path"]:
		if not context.has(field):
			return "ATTACK_SELECTION_CONTEXT_MISSING:%s" % field
	if not _is_number(context["distance_pixels"]) or not is_finite(float(context["distance_pixels"])) or float(context["distance_pixels"]) < 0.0:
		return "ATTACK_SELECTION_CONTEXT_INVALID:distance_pixels"
	if not _is_number(context["depth_delta_pixels"]) or not is_finite(float(context["depth_delta_pixels"])):
		return "ATTACK_SELECTION_CONTEXT_INVALID:depth_delta_pixels"
	if typeof(context["available_coordination_budget"]) != TYPE_INT or int(context["available_coordination_budget"]) < 0:
		return "ATTACK_SELECTION_CONTEXT_INVALID:available_coordination_budget"
	if typeof(context["clear_path"]) != TYPE_BOOL:
		return "ATTACK_SELECTION_CONTEXT_INVALID:clear_path"
	if context.has("cooldown_remaining_by_key") and not context["cooldown_remaining_by_key"] is Dictionary:
		return "ATTACK_SELECTION_CONTEXT_INVALID:cooldown_remaining_by_key"
	return ""


static func _eligibility_rejection(
	attack_key: String,
	selection: Dictionary,
	distance: float,
	depth_delta: float,
	budget: int,
	clear_path: bool,
	cooldowns: Dictionary
) -> String:
	if float(cooldowns.get(attack_key, 0.0)) > 0.0:
		return "COOLDOWN_ACTIVE"
	if int(selection.get("coordination_cost", 999)) > budget:
		return "COORDINATION_BUDGET"
	if bool(selection.get("requires_clear_path", false)) and not clear_path:
		return "PATH_BLOCKED"
	if distance < float(selection.get("minimum_distance_pixels", 0.0)) or distance > float(selection.get("maximum_distance_pixels", -1.0)):
		return "OUTSIDE_RANGE"
	if depth_delta > float(selection.get("maximum_depth_delta_pixels", -1.0)):
		return "OUTSIDE_DEPTH_FIT"
	return ""


static func _score_breakdown(
	candidate: Dictionary,
	selection: Dictionary,
	distance: float,
	depth_delta: float,
	previous_signature: String
) -> Dictionary:
	var base_priority := float(selection.get("base_priority", 0))
	var range_fit := 0.5
	if str(selection.get("preferred_range", "")) != "any":
		var minimum := float(selection["minimum_distance_pixels"])
		var ideal := float(selection["ideal_distance_pixels"])
		var maximum := float(selection["maximum_distance_pixels"])
		var half_span := maxf(1.0, maxf(ideal - minimum, maximum - ideal))
		range_fit = clampf(1.0 - absf(distance - ideal) / half_span, 0.0, 1.0)
	var range_score := range_fit * 30.0

	var depth_fit := 0.5
	if str(selection.get("depth_fit", "")) != "any":
		var maximum_depth := maxf(1.0, float(selection["maximum_depth_delta_pixels"]))
		depth_fit = clampf(1.0 - depth_delta / maximum_depth, 0.0, 1.0)
	var depth_score := depth_fit * 20.0

	var repeat_penalty := 0.0
	if not previous_signature.is_empty() and previous_signature == str(candidate.get("mechanism_signature", "")):
		repeat_penalty = REPEAT_PENALTY
	return {
		"base_priority": base_priority,
		"range_score": range_score,
		"depth_score": depth_score,
		"repeat_penalty": repeat_penalty,
		"total": base_priority + range_score + depth_score - repeat_penalty,
	}


static func _is_better(
	score: float,
	rank: int,
	index: int,
	best_score: float,
	best_rank: int,
	best_index: int
) -> bool:
	if score > best_score + SCORE_EPSILON:
		return true
	if absf(score - best_score) > SCORE_EPSILON:
		return false
	if rank < best_rank:
		return true
	if rank > best_rank:
		return false
	return index < best_index


static func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]


static func _failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
