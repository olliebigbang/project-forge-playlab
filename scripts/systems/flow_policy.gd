class_name FlowPolicy
extends RefCounted

var in_combat: bool = false
var intermission_change_used: bool = false

func can_open_forge() -> bool:
	return not in_combat

func can_apply_intermission_change() -> bool:
	return not in_combat and not intermission_change_used

func consume_intermission_change() -> bool:
	if not can_apply_intermission_change():
		return false
	intermission_change_used = true
	return true

