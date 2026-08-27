class_name EnemyAttackRuntimeDriver
extends RefCounted

const COMPILER := preload("res://scripts/enemy_attack/enemy_attack_mechanism_compiler.gd")
const SELECTOR := preload("res://scripts/enemy_attack/enemy_attack_selector.gd")

const SCHEMA := "forge-enemy-attack-runtime-driver-v1"
const ATTACK_PHASES: PackedStringArray = ["telegraph", "commit", "active"]

var compiled_attacks: Array[Dictionary] = []
var current_attack: Dictionary = {}
var phase := "idle"
var phase_elapsed := 0.0
var locked_direction := Vector2.LEFT
var locked_point := Vector2.ZERO
var tracked_target := Vector2.ZERO
var attack_origin := Vector2.ZERO
var previous_mechanism_signature := ""
var cooldown_remaining_by_key: Dictionary = {}
var active_hit_registered := false
var last_transition_reason := ""


func configure(declarations: Array) -> Dictionary:
	compiled_attacks.clear()
	reset()
	for index: int in range(declarations.size()):
		var raw: Variant = declarations[index]
		if not raw is Dictionary:
			return _failure("ATTACK_DECLARATION_NOT_DICTIONARY:%d" % index)
		var compiled: Dictionary = COMPILER.compile(raw as Dictionary)
		if not bool(compiled.get("ok", false)):
			var failure := _failure("ATTACK_DECLARATION_COMPILE_FAILED:%d" % index)
			failure["compiler_error"] = compiled.duplicate(true)
			compiled_attacks.clear()
			return failure
		compiled_attacks.append(compiled)
	if compiled_attacks.is_empty():
		return _failure("ATTACK_DECLARATIONS_EMPTY")
	return {
		"ok": true,
		"schema": SCHEMA,
		"compiled_attack_count": compiled_attacks.size(),
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}


func reset() -> void:
	current_attack.clear()
	phase = "idle"
	phase_elapsed = 0.0
	active_hit_registered = false
	last_transition_reason = ""


func begin_attack(context: Dictionary, source_position: Vector2, target_position: Vector2) -> Dictionary:
	if phase != "idle":
		return _failure("ATTACK_ALREADY_RUNNING")
	var selection_context := context.duplicate(true)
	selection_context["cooldown_remaining_by_key"] = cooldown_remaining_by_key.duplicate(true)
	selection_context["previous_mechanism_signature"] = previous_mechanism_signature
	var selected: Dictionary = SELECTOR.select_attack(compiled_attacks, selection_context)
	if not bool(selected.get("ok", false)):
		return selected
	current_attack = (selected.get("selected_attack", {}) as Dictionary).duplicate(true)
	phase = "telegraph"
	phase_elapsed = 0.0
	attack_origin = source_position
	tracked_target = target_position
	active_hit_registered = false
	last_transition_reason = "selected"
	_update_tracking(source_position, target_position)
	return snapshot().merged({
		"selected": true,
		"selection_score": float(selected.get("score", 0.0)),
	}, true)


func step(delta: float, source_position: Vector2, target_position: Vector2) -> Dictionary:
	_tick_cooldowns(delta)
	var active_seconds_this_step := 0.0
	var entered_active := false
	var completed_attack := false
	var remaining := maxf(0.0, delta)
	var transition_guard := 0
	while remaining > 0.000001 and phase != "idle" and transition_guard < 8:
		transition_guard += 1
		_update_tracking(source_position, target_position)
		var duration := _phase_duration(phase)
		var phase_remaining := maxf(0.0, duration - phase_elapsed)
		var consumed := minf(remaining, phase_remaining)
		if phase == "active":
			active_seconds_this_step += consumed
		phase_elapsed += consumed
		remaining -= consumed
		if phase_elapsed + 0.000001 < duration:
			break
		var transition := _advance_phase(source_position, target_position)
		entered_active = entered_active or str(transition.get("entered", "")) == "active"
		completed_attack = completed_attack or bool(transition.get("completed", false))
		if phase_remaining <= 0.000001 and consumed <= 0.000001 and phase != "idle":
			continue
	var result := snapshot()
	result["active_seconds_this_step"] = active_seconds_this_step
	result["entered_active"] = entered_active
	result["completed_attack"] = completed_attack
	return result


func try_interrupt(target_interaction: Dictionary) -> Dictionary:
	if phase not in ATTACK_PHASES or current_attack.is_empty():
		return {"interrupted": false, "reason": "NO_INTERRUPTIBLE_ATTACK_PHASE", "phase": phase}
	var interruptibility := current_attack.get("interruptibility", {}) as Dictionary
	if not bool(interruptibility.get(phase, false)):
		return {"interrupted": false, "reason": "PHASE_PROTECTED", "phase": phase}
	var qualifies := bool(target_interaction.get("interrupts_attack", false)) \
		or bool(target_interaction.get("immobilize", false)) \
		or bool(target_interaction.get("armor_break", false))
	if not qualifies:
		return {"interrupted": false, "reason": "REACTION_DOES_NOT_INTERRUPT", "phase": phase}
	var strength := float(target_interaction.get("interrupt_strength", target_interaction.get("stagger", 0.0)))
	if bool(target_interaction.get("armor_break", false)):
		strength = maxf(strength, 2.0)
	var threshold := float(interruptibility.get("minimum_interrupt_strength", 1.0))
	if strength + 0.000001 < threshold:
		return {
			"interrupted": false,
			"reason": "INTERRUPT_STRENGTH_BELOW_THRESHOLD",
			"phase": phase,
			"strength": strength,
			"threshold": threshold,
		}
	force_recovery("weapon_target_interaction")
	return {
		"interrupted": true,
		"reason": last_transition_reason,
		"phase": phase,
		"strength": strength,
		"threshold": threshold,
	}


func force_recovery(reason: String) -> void:
	if current_attack.is_empty():
		return
	phase = "recovery"
	phase_elapsed = 0.0
	active_hit_registered = true
	last_transition_reason = reason


func register_active_hit() -> void:
	active_hit_registered = true


func is_running() -> bool:
	return phase != "idle" and not current_attack.is_empty()


func is_attack_dangerous() -> bool:
	return phase == "active"


func is_telegraphing() -> bool:
	return phase in ["telegraph", "commit"]


func current_delivery() -> String:
	return str((current_attack.get("axes", {}) as Dictionary).get("delivery", ""))


func current_hit_contains(source_position: Vector2, target_position: Vector2) -> bool:
	if current_attack.is_empty():
		return false
	var region := current_attack.get("hit_region", {}) as Dictionary
	var delivery := current_delivery()
	var origin := source_position
	if str(region.get("origin_mode", "attacker")) == "locked_point":
		origin = locked_point
	var offset := target_position - origin
	var depth_tolerance := float(region.get("depth_tolerance_pixels", 100000.0))
	if str(region.get("path_mode", "same_lane")) == "same_lane" and absf(offset.y) > depth_tolerance:
		return false
	match str(region.get("shape", "capsule")):
		"circle":
			return offset.length() <= float(region.get("radius_pixels", 0.0))
		"arc":
			var radius := float(region.get("radius_pixels", 0.0))
			if offset.length() > radius or offset.length() <= 0.001:
				return false
			return absf(locked_direction.angle_to(offset.normalized())) <= deg_to_rad(float(region.get("arc_degrees", 0.0)) * 0.5)
		"strip", "capsule":
			var direction := locked_direction.normalized()
			var forward := offset.dot(direction)
			var sideways := absf(offset.cross(direction))
			var length := float(region.get("length_pixels", 0.0))
			var half_width := float(region.get("width_pixels", 0.0)) * 0.5
			if delivery == "rush":
				return offset.length() <= maxf(half_width, 28.0)
			return forward >= 0.0 and forward <= length and sideways <= half_width
	return false


func telegraph_total_seconds() -> float:
	if current_attack.is_empty() and not compiled_attacks.is_empty():
		return _timeline_seconds(compiled_attacks[0], "telegraph_seconds") + _timeline_seconds(compiled_attacks[0], "commit_seconds")
	return _timeline_seconds(current_attack, "telegraph_seconds") + _timeline_seconds(current_attack, "commit_seconds")


func recovery_total_seconds() -> float:
	if current_attack.is_empty() and not compiled_attacks.is_empty():
		return _timeline_seconds(compiled_attacks[0], "recovery_seconds")
	return _timeline_seconds(current_attack, "recovery_seconds")


func snapshot() -> Dictionary:
	var attack := current_attack.duplicate(true)
	return {
		"ok": true,
		"schema": SCHEMA,
		"phase": phase,
		"phase_elapsed": phase_elapsed,
		"attack_key": str(attack.get("attack_key", "")),
		"mechanism_signature": str(attack.get("mechanism_signature", "")),
		"delivery": str((attack.get("axes", {}) as Dictionary).get("delivery", "")),
		"locked_direction": locked_direction,
		"locked_point": locked_point,
		"tracked_target": tracked_target,
		"telegraph": (attack.get("telegraph", {}) as Dictionary).duplicate(true),
		"hit_region": (attack.get("hit_region", {}) as Dictionary).duplicate(true),
		"attack_motion": (attack.get("attack_motion", {}) as Dictionary).duplicate(true),
		"recovery": (attack.get("recovery", {}) as Dictionary).duplicate(true),
		"active_hit_registered": active_hit_registered,
		"last_transition_reason": last_transition_reason,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}


func _advance_phase(source_position: Vector2, target_position: Vector2) -> Dictionary:
	match phase:
		"telegraph":
			phase = "commit"
			phase_elapsed = 0.0
			last_transition_reason = "telegraph_complete"
			_lock_if_event("commit_start", source_position, target_position)
			return {"entered": phase}
		"commit":
			phase = "active"
			phase_elapsed = 0.0
			last_transition_reason = "commit_complete"
			_lock_if_event("active_start", source_position, target_position)
			return {"entered": phase}
		"active":
			phase = "recovery"
			phase_elapsed = 0.0
			last_transition_reason = "active_complete"
			return {"entered": phase}
		"recovery":
			var attack_key := str(current_attack.get("attack_key", ""))
			if not attack_key.is_empty():
				cooldown_remaining_by_key[attack_key] = maxf(float(cooldown_remaining_by_key.get(attack_key, 0.0)), 0.18)
			previous_mechanism_signature = str(current_attack.get("mechanism_signature", ""))
			current_attack.clear()
			phase = "idle"
			phase_elapsed = 0.0
			last_transition_reason = "recovery_complete"
			return {"entered": phase, "completed": true}
	return {}


func _update_tracking(source_position: Vector2, target_position: Vector2) -> void:
	if current_attack.is_empty():
		return
	var telegraph := current_attack.get("telegraph", {}) as Dictionary
	var tracking_phases := telegraph.get("tracks_target_during", []) as Array
	if phase in tracking_phases:
		tracked_target = target_position
		locked_direction = _safe_direction(source_position, target_position, locked_direction)
		locked_point = target_position


func _lock_if_event(event_name: String, source_position: Vector2, target_position: Vector2) -> void:
	var telegraph := current_attack.get("telegraph", {}) as Dictionary
	if str(telegraph.get("lock_event", "")) != event_name:
		return
	tracked_target = target_position
	locked_direction = _safe_direction(source_position, target_position, locked_direction)
	locked_point = target_position


func _phase_duration(value: String) -> float:
	match value:
		"telegraph": return _timeline_seconds(current_attack, "telegraph_seconds")
		"commit": return _timeline_seconds(current_attack, "commit_seconds")
		"active": return _timeline_seconds(current_attack, "active_seconds")
		"recovery": return _timeline_seconds(current_attack, "recovery_seconds")
	return 0.0


func _timeline_seconds(attack: Dictionary, key: String) -> float:
	return maxf(0.0, float((attack.get("timeline", {}) as Dictionary).get(key, 0.0)))


func _tick_cooldowns(delta: float) -> void:
	for key: Variant in cooldown_remaining_by_key.keys():
		var remaining := maxf(0.0, float(cooldown_remaining_by_key[key]) - maxf(0.0, delta))
		if remaining <= 0.0:
			cooldown_remaining_by_key.erase(key)
		else:
			cooldown_remaining_by_key[key] = remaining


func _safe_direction(source_position: Vector2, target_position: Vector2, fallback: Vector2) -> Vector2:
	var direction := target_position - source_position
	return fallback if direction.length() <= 0.001 else direction.normalized()


func _failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"schema": SCHEMA,
		"error": code,
		"identity_inputs_used": false,
		"player_confirmation_required": false,
	}
