extends RefCounted
## Main-arena adapter for the same orthogonal recipe used by the mechanism lab.
## It never selects a move by object identity. Geometry stays with the arena's
## pixel renderer; this object owns the one authoritative clock and primitive.

const AFFORDANCE := preload("res://scripts/combat_feel/object_affordance_profile.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const CONTROLLER := preload("res://scripts/combat_feel/melee_combat_controller.gd")
const AXES := preload("res://scripts/combat_feel/mechanism_axis_resolver.gd")
const GROUND_DEPTH_PROJECTION := 0.30
const GROUND_MIN_LONGITUDINAL_SCALE := 0.26

var profile: Resource
var affordance: Resource
var controller: RefCounted = CONTROLLER.new()
var error := ""
var root_applied := 0.0
var root_serial := -1
var button_held := false
var latched_open := false
var latch_serial := -1
var sustained_seconds := 0.0
var pulse_seconds := 0.0

func configure(blueprint: WeaponBlueprint, asset: WeaponVisualAsset) -> bool:
	error = ""
	profile = null
	controller.configure(null)
	if blueprint == null or asset == null or blueprint.behavior_family != "heavy_melee":
		return false
	affordance = AFFORDANCE.new()
	# Production entries have already passed AI + silhouette validation. Copy
	# every declared axis, not the lossy legacy weight/family summary.
	for key: String in AXES.REQUIRED_AXES:
		if blueprint.affordance.has(key): affordance.set(key, blueprint.affordance[key])
	for key: String in AXES.REQUIRED_FLAGS:
		if blueprint.affordance.has(key): affordance.set(key, blueprint.affordance[key])
	affordance.confidence = float(blueprint.affordance.get("confidence", 0.0))
	affordance.evidence_parts = PackedStringArray(blueprint.affordance.get("evidence_parts", []))
	var errors: Array[String] = affordance.validation_errors()
	if not errors.is_empty():
		error = ",".join(errors)
		return false
	var compiled: Variant = COMPILER.new().compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
	if not compiled is Resource:
		error = str(compiled)
		return false
	profile = compiled
	controller.configure(profile)
	root_applied = 0.0
	root_serial = -1
	button_held = false
	latched_open = false
	latch_serial = -1
	sustained_seconds = 0.0
	pulse_seconds = 0.0
	return true

func input_attack(pressed: bool, held: bool) -> void:
	button_held = held
	if pressed: controller.press_attack()
	if not held: controller.release_attack()

func tick(delta: float) -> void:
	var p: Variant = primitive()
	if p != null and controller.attack_kind == "charge" and str(p.activation_mode) == "charge_release" and button_held and controller.phase == "startup":
		# A charged release is genuinely waiting for the button, not a timer-only
		# imitation of holding. The normal tap remains immediately usable.
		controller.phase_elapsed = minf(controller.phase_duration, controller.phase_elapsed + delta)
		return
	if p != null and active() and float(p.state_extent_ratio) > 0.0:
		if str(p.activation_mode) == "toggle" and latch_serial != controller.attack_serial:
			latched_open = not latched_open
			latch_serial = controller.attack_serial
		if str(p.activation_mode) == "continuous_hold" and button_held and sustained_seconds < 2.0:
			sustained_seconds += delta
			pulse_seconds += delta
			controller.phase_elapsed = minf(controller.phase_elapsed, controller.phase_duration * 0.65)
			if pulse_seconds >= 0.24:
				controller.hit_targets.clear()
				pulse_seconds = 0.0
	else:
		sustained_seconds = 0.0
		pulse_seconds = 0.0
	controller.tick(delta)

func primitive() -> Variant:
	return controller.current_primitive

func active() -> bool:
	return profile != null and controller.phase == "active"

func busy() -> bool:
	return profile != null and controller.phase != "idle"

func motion_ratio() -> float:
	match controller.phase:
		"startup": return controller.phase_ratio() * 0.30
		"active": return 0.30 + controller.phase_ratio() * 0.52
		"recovery": return 0.82 + controller.phase_ratio() * 0.18
	return 0.0

func state_power() -> float:
	var p: Variant = primitive()
	if latched_open: return 1.0
	if p == null or not busy(): return 0.0
	var extent := float(p.state_extent_ratio)
	match controller.phase:
		"startup": return extent * smoothstep(0.3, 1.0, controller.phase_ratio())
		"active": return extent
		"recovery": return extent * (1.0 - smoothstep(0.0, 1.0, controller.phase_ratio()))
	return 0.0

func pose(facing: float) -> Dictionary:
	var p: Variant = primitive()
	if p == null or not busy():
		return {
			"angle": 0.0,
			"offset": Vector2.ZERO,
			"trajectory_plane": "screen_arc",
			"path_angle": 0.0,
			"longitudinal_scale": 1.0,
			"depth_layer": 0.0,
		}
	var phase_ratio: float = controller.phase_ratio()
	var lag := clampf(float(p.trajectory_lag_ratio) * 0.22, 0.0, 0.30)
	var strike := smoothstep(0.0, 1.0, clampf((phase_ratio - lag) / (1.0 - lag), 0.0, 1.0))
	var angle := 0.0
	var extension := 0.0
	var local_offset := Vector2.ZERO
	match controller.phase:
		"startup":
			angle = lerpf(0.0, float(p.start_angle), smoothstep(0.0, 1.0, phase_ratio))
			local_offset = Vector2(p.local_start_offset) * phase_ratio
		"active":
			angle = lerpf(float(p.start_angle), float(p.end_angle), strike)
			extension = sin(strike * PI) * float(p.extension_pixels)
			local_offset = Vector2(p.local_start_offset).lerp(Vector2(p.local_end_offset), strike)
		"recovery":
			angle = lerpf(float(p.end_angle), 0.0, smoothstep(0.0, 1.0, phase_ratio))
			angle += sin(phase_ratio * PI) * float(p.follow_through_radians)
			local_offset = Vector2(p.local_end_offset) * (1.0 - phase_ratio)
	# Keep arms anatomically attached. Reach beyond this comes from the object
	# or its deployed structure, never an invisible longer collision sector.
	local_offset += Vector2(extension, 0.0)
	local_offset = local_offset.limit_length(30.0)
	var trajectory_plane := str(p.trajectory_plane)
	var projection := _trajectory_projection(angle, trajectory_plane, facing)
	return {
		"angle": float(projection.angle),
		"offset": Vector2(local_offset.x * facing, local_offset.y),
		"trajectory_plane": trajectory_plane,
		"path_angle": angle,
		"longitudinal_scale": float(projection.longitudinal_scale),
		"depth_layer": float(projection.depth_layer),
	}


func _trajectory_projection(path_angle: float, trajectory_plane: String, facing: float) -> Dictionary:
	if trajectory_plane not in ["ground_sweep", "ground_orbit"]:
		return {
			"angle": path_angle * facing,
			"longitudinal_scale": 1.0,
			"depth_layer": 0.0,
		}
	# Project a yaw rotation on the walk plane into the side-view camera. The
	# long axis becomes short while pointing toward/away from the camera instead
	# of becoming a full-length vertical pole. The sign is also the draw layer:
	# negative is behind the torso and positive is in front.
	var projected := Vector2(cos(path_angle), sin(path_angle) * GROUND_DEPTH_PROJECTION)
	var longitudinal_scale := maxf(GROUND_MIN_LONGITUDINAL_SCALE, projected.length())
	var projected_angle := projected.angle()
	return {
		"angle": projected_angle * facing,
		"longitudinal_scale": longitudinal_scale,
		"depth_layer": sin(path_angle),
	}

func movement_ratio() -> float:
	var p: Variant = primitive()
	if not busy() or p == null: return 1.0
	var allowed := float(p.movement_allowed_ratio)
	if controller.phase == "recovery": allowed = lerpf(allowed, 1.0, controller.phase_ratio())
	return allowed

func root_step() -> float:
	var p: Variant = primitive()
	if not busy() or p == null or controller.priming_attack: return 0.0
	if root_serial != controller.attack_serial:
		root_serial = controller.attack_serial
		root_applied = 0.0
	var active_fraction := lerpf(0.92, 0.60, clampf(float(p.inertia_ratio), 0.0, 1.0))
	var ratio := 0.0
	if controller.phase == "active": ratio = active_fraction * smoothstep(0.0, 1.0, controller.phase_ratio())
	if controller.phase == "recovery": ratio = active_fraction + (1.0 - active_fraction) * smoothstep(0.0, 1.0, controller.phase_ratio())
	var target := float(p.root_motion_distance) * ratio
	var step := maxf(0.0, target - root_applied)
	root_applied = maxf(root_applied, target)
	return step

func reach() -> float:
	if profile == null: return 0.0
	var p: Variant = primitive()
	var timing: Dictionary = controller.current_timing()
	return float(profile.reach_pixels) * float(timing.get("reach_scale", 1.0)) * (float(p.hitbox_length_multiplier) if p != null else 1.0)

func evidence() -> Dictionary:
	var p: Variant = primitive()
	return {
		"phase": controller.phase, "phase_elapsed": controller.phase_elapsed,
		"combo": controller.combo_index, "kind": controller.attack_kind,
		"serial": controller.attack_serial, "timing": controller.current_timing(),
		"primitive": p.to_dict() if p != null else {},
		"movement_ratio": movement_ratio(), "reach": reach(), "state_power": state_power(),
	}
