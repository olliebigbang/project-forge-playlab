class_name BlueprintDelta
extends RefCounted

var requested_change: String = ""
var accepted_change: String = ""
var cadence_delta: String = "unchanged"
var weight_delta: String = "unchanged"
var effect_delta: String = "unchanged"
var drawback_delta: String = "unchanged"
var visual_delta: String = "unchanged"
var player_summary: String = ""
var tradeoff: String = ""

func is_valid() -> bool:
	if accepted_change.is_empty():
		return false
	if drawback_delta == "removed" and tradeoff.is_empty():
		return false
	return not player_summary.is_empty()

func to_dict() -> Dictionary:
	return {
		"requested_change": requested_change, "accepted_change": accepted_change,
		"cadence_delta": cadence_delta, "weight_delta": weight_delta,
		"effect_delta": effect_delta, "drawback_delta": drawback_delta,
		"visual_delta": visual_delta, "player_summary": player_summary, "tradeoff": tradeoff
	}

