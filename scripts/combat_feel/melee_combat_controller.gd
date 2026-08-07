class_name MeleeCombatController
extends RefCounted

signal attack_started(kind: String, combo_index: int)
signal phase_changed(phase: String)

var profile: Resource
var phase := "idle"
var phase_elapsed := 0.0
var phase_duration := 0.0
var combo_index := 0
var combo_idle_seconds := 0.0
var buffered_input := false
var buffer_age := 0.0
var holding_attack := false
var held_seconds := 0.0
var charge_state := "none"
var priming_attack := false
var dodge_attack_window := 0.0
var dodge_motion_seconds := 0.0
var attack_kind := "normal"
var current_primitive: Variant
var attack_serial := 0
var active_just_started := false
var hitstop_remaining := 0.0
var hit_targets: Dictionary = {}
var last_cancel_reason := ""

func configure(value: Resource) -> void:
	profile = value
	reset()

func reset() -> void:
	phase = "idle"; phase_elapsed = 0.0; phase_duration = 0.0
	combo_index = 0; combo_idle_seconds = 0.0
	buffered_input = false; buffer_age = 0.0
	holding_attack = false; held_seconds = 0.0; charge_state = "none"; priming_attack = false
	dodge_attack_window = 0.0; dodge_motion_seconds = 0.0
	attack_kind = "normal"; attack_serial = 0; active_just_started = false
	current_primitive = null
	hitstop_remaining = 0.0; hit_targets.clear()

func press_attack() -> void:
	if profile == null: return
	if priming_attack and holding_attack:
		return
	if phase == "idle" and not holding_attack:
		if dodge_attack_window > 0.0:
			_start_attack("dodge")
			return
		holding_attack = true; held_seconds = 0.0; charge_state = "priming"
		_begin_priming_normal()
		return
	if phase in ["startup", "recovery"] or (phase == "active" and hitstop_remaining > 0.0):
		buffered_input = true; buffer_age = 0.0

func release_attack() -> void:
	if profile == null or not priming_attack: return
	holding_attack = false
	priming_attack = false
	charge_state = "none"
	attack_serial += 1
	hit_targets.clear()
	attack_started.emit("normal", combo_index)
	if phase == "startup" and phase_elapsed >= phase_duration:
		_enter_phase("active")

func press_dodge() -> bool:
	if profile == null: return false
	var allowed := phase == "idle" or can_dodge_cancel()
	if not allowed: return false
	if phase != "idle":
		last_cancel_reason = "%s_cancel" % phase
		phase = "idle"; phase_changed.emit(phase)
	holding_attack = false; charge_state = "none"; priming_attack = false
	current_primitive = null
	dodge_motion_seconds = 0.18
	dodge_attack_window = profile.dodge_attack_window_seconds
	return true

func can_dodge_cancel() -> bool:
	if phase == "startup":
		return phase_elapsed <= phase_duration * profile.early_startup_cancel_ratio and combo_index < 3
	if phase == "recovery": return phase_elapsed >= phase_duration * profile.late_recovery_cancel_ratio
	return false

func tick(delta: float) -> void:
	if profile == null: return
	active_just_started = false
	if holding_attack:
		held_seconds += delta
		if priming_attack and held_seconds >= profile.charge_threshold_seconds:
			_promote_priming_to_charge()
	dodge_attack_window = maxf(0.0, dodge_attack_window - delta)
	dodge_motion_seconds = maxf(0.0, dodge_motion_seconds - delta)
	if hitstop_remaining > 0.0:
		hitstop_remaining = maxf(0.0, hitstop_remaining - delta)
		return
	if buffered_input:
		buffer_age += delta
		if buffer_age > profile.input_buffer_seconds: buffered_input = false
	if phase == "idle":
		combo_idle_seconds += delta
		if combo_index > 0 and combo_idle_seconds > profile.combo_window_seconds: combo_index = 0
		return
	phase_elapsed += delta
	if phase_elapsed < phase_duration: return
	if phase == "startup" and priming_attack:
		phase_elapsed = phase_duration
		return
	match phase:
		"startup": _enter_phase("active")
		"active": _enter_phase("recovery")
		"recovery":
			_enter_phase("idle"); combo_idle_seconds = 0.0
			if buffered_input:
				buffered_input = false
				_start_attack("normal")

func register_hit(target_id: int) -> bool:
	if phase != "active" or hit_targets.has(target_id): return false
	hit_targets[target_id] = true
	return true

func begin_hitstop(seconds: float) -> void:
	hitstop_remaining = maxf(hitstop_remaining, seconds)

func current_timing() -> Dictionary:
	return profile.timing_for(attack_kind, combo_index, current_primitive) if profile != null else {}

func phase_ratio() -> float:
	return clampf(phase_elapsed / maxf(0.001, phase_duration), 0.0, 1.0)

func _start_attack(kind: String) -> void:
	if phase != "idle" or profile == null:
		if phase in ["startup", "recovery"]:
			buffered_input = true; buffer_age = 0.0
		return
	attack_kind = kind
	combo_index = combo_index % 3 + 1 if kind == "normal" else 0
	if profile.combo_recipe != null:
		var recipe: Variant = profile.combo_recipe
		current_primitive = recipe.primitive_for_attack(kind, combo_index)
	else:
		current_primitive = null
	attack_serial += 1; hit_targets.clear(); _enter_phase("startup")
	attack_started.emit(kind, combo_index)


func _begin_priming_normal() -> void:
	attack_kind = "normal"
	combo_index = combo_index % 3 + 1
	current_primitive = profile.combo_recipe.primitive_for(combo_index) if profile.combo_recipe != null else null
	priming_attack = true
	hit_targets.clear()
	_enter_phase("startup")


func _promote_priming_to_charge() -> void:
	if not priming_attack or profile == null:
		return
	priming_attack = false
	holding_attack = false
	charge_state = "ready"
	attack_kind = "charge"
	combo_index = 0
	current_primitive = profile.combo_recipe.primitive_for_attack("charge") if profile.combo_recipe != null else null
	attack_serial += 1
	hit_targets.clear()
	_enter_phase("startup")
	attack_started.emit("charge", 0)

func _enter_phase(next_phase: String) -> void:
	phase = next_phase; phase_elapsed = 0.0
	var timing := current_timing()
	match phase:
		"startup": phase_duration = float(timing.get("startup", 0.1))
		"active":
			phase_duration = float(timing.get("active", 0.1)); active_just_started = true
		"recovery": phase_duration = float(timing.get("recovery", 0.2))
		_: phase_duration = 0.0
	phase_changed.emit(phase)
