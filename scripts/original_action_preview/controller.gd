extends RefCounted
## Controls the ORIGINAL-ART training sample only; not an AI weapon compiler.
const TIMELINE := preload("res://scripts/original_action_preview/timeline.gd")
const IDLES := {"sword": "combat/SwordIdle", "gun": "combat/GunAim", "bow": "body/Idle", "fishing": "fishing/Idle", "unarmed": "body/Idle"}
var library: RefCounted
var animation: RefCounted
var equipment := "sword"
var facing := 1.0
var feet := Vector2(360, 580)
var move := Vector2.ZERO
var pace := 0
var crouching := false
var attack_held := false
var fishing_phase := "ready"
var charging := ""
var health := 100
var ammo := 6
var move_during_action := false
var previous: Dictionary = {}
var events: Array[Dictionary] = []
var alternate_run := false
var actual_visits: Dictionary = {}

func _init(source: RefCounted) -> void:
	library = source
	animation = TIMELINE.new(source)

func equip(value: String) -> void:
	if not IDLES.has(value): return
	equipment = value
	charging = ""
	fishing_phase = "ready"
	animation.inspect(IDLES[value])
	previous.clear()
	ammo = 6
	health = 100

func _pressed(input: Dictionary, key: String) -> bool:
	return bool(input.get(key, false)) and not bool(previous.get(key, false))

func _play(names: Array[String], after: String = "", mobile: bool = false, freeze: bool = false) -> void:
	move_during_action = mobile
	animation.play(names, IDLES[equipment] if after.is_empty() else after, freeze)

func _locomotion() -> String:
	var moving := move.length_squared() > 0
	if equipment == "fishing": return "fishing/Idle"
	if equipment == "sword":
		if crouching: return "combat/SwordCrouch"
		if not moving: return "combat/SwordIdle"
		return "combat/SwordSprint" if pace == 2 else (("combat/SwordRunAlt" if alternate_run else "combat/SwordRun") if pace == 1 else "combat/SwordWalk")
	if equipment == "gun":
		if crouching: return "combat/GunCrouch"
		return "combat/GunAim" if not moving else ("combat/GunSprint" if pace == 2 else ("combat/GunRun" if pace == 1 else "combat/GunWalk"))
	if crouching: return "body/Crawl" if moving else "body/Crouch"
	return "body/Idle" if not moving else ("body/Sprint" if pace == 2 else ("body/Run" if pace == 1 else "body/Walk"))

func _attack() -> void:
	match equipment:
		"gun":
			if ammo <= 0: _play(["combat/GunReload"]); return
			var fire := "GunFire"
			if crouching: fire = "GunCrouchFire"
			elif move.length_squared() > 0: fire = "GunSprintFire" if pace == 2 else ("GunRunFire" if pace == 1 else "GunWalkFire")
			_play(["combat/" + fire], _locomotion(), true)
		"sword":
			var slash := "SwordSlash01"
			if crouching: slash = "CrouchSlash"
			elif move.length_squared() > 0: slash = "SwordSprintSlash" if pace == 2 else "SwordRunSlash"
			_play(["combat/" + slash], _locomotion(), move.length_squared() > 0)
		"bow":
			charging = "bow"
			_play(["combat/BowDraw"], "combat/BowAim")
		"fishing":
			if fishing_phase == "cast":
				fishing_phase = "retrieving"
				_play(["fishing/Reel", "fishing/Struggle", "fishing/Catch"])
			else:
				charging = "fishing"
				fishing_phase = "charging"
				_play(["fishing/Prepare"], "fishing/Charge")
		"unarmed": _play(["combat/Punch01", "combat/Punch02", "combat/Punch03"])

func step(dt: float, input: Dictionary) -> void:
	move = (input.get("move", Vector2.ZERO) as Vector2).limit_length()
	pace = 2 if input.get("sprint", false) else (1 if input.get("run", false) else 0)
	crouching = bool(input.get("crouch", false))
	attack_held = bool(input.get("attack", false))
	if not animation.busy() and not is_zero_approx(move.x): facing = signf(move.x)
	if health > 0:
		if _pressed(input, "hit") and input.get("guard", false) and equipment in ["sword", "unarmed"]:
			_play(["combat/GuardImpact"], "combat/Guard")
		elif _pressed(input, "hit"):
			health = maxi(0, health - 25)
			charging = ""
			if health == 0: _play(["body/Die"], "", false, true)
			elif health == 75: _play(["combat/Hit"])
			elif health == 50: _play(["combat/HitUp"])
			else: _play(["body/Knockback"])
		elif _pressed(input, "stun"):
			charging = ""
			_play(["combat/ShockLight", "combat/ShockHeavy", "combat/Stunned"])
		elif not animation.busy():
			if _pressed(input, "dodge"): _play(["body/Roll"], "", true)
			elif _pressed(input, "dash"): _play(["body/DashStart", "body/DashLoop", "body/DashEnd"], "", true)
			elif _pressed(input, "slide"): _play(["body/Slide"], "", true)
			elif _pressed(input, "reload") and equipment == "gun": _play(["combat/GunReload"])
			elif _pressed(input, "quick") and equipment == "sword": _play(["combat/StandingSlash"])
			elif _pressed(input, "secondary"):
				if equipment == "sword": _play(["combat/SwordCombo01", "combat/SwordCombo02", "combat/SwordCombo03", "combat/SwordCombo04"])
				elif equipment == "gun" and ammo > 0: _play(["combat/GunFire2H"])
				elif equipment == "unarmed": _play(["combat/Kick01", "combat/Kick02", "combat/Kick03"])
			elif charging.is_empty() and (_pressed(input, "attack") or (equipment == "gun" and attack_held)):
				_attack()
			elif input.get("guard", false) and equipment in ["sword", "unarmed"]:
				animation.loop("combat/Guard")
			else:
				if charging.is_empty():
					if fishing_phase == "retrieving": fishing_phase = "ready"
					var previous_move: Vector2 = previous.get("move", Vector2.ZERO)
					if equipment == "unarmed" and move.is_zero_approx() and not previous_move.is_zero_approx() and (previous.get("run", false) or previous.get("sprint", false)):
						_play(["body/RunToIdle"])
					else: animation.loop(_locomotion())
		if not charging.is_empty() and not animation.busy() and not attack_held:
			if charging == "bow": _play(["combat/BowFire"])
			else:
				_play(["fishing/Cast"])
				fishing_phase = "cast"
			charging = ""
	# Moving attacks preserve the source facing. Walking backwards is explicit.
	var can_move: bool = health > 0 and charging.is_empty() and (not animation.busy() or move_during_action) and not input.get("guard", false)
	# No authored rod-walk or armed crouch-walk exists: do not slide a static stance.
	if equipment == "fishing" or (crouching and equipment in ["sword", "gun"]) or animation.clip == "combat/GunCrouchFire": can_move = false
	if can_move:
		var speed := 320.0 if pace == 2 else (230.0 if pace == 1 else 135.0)
		if crouching: speed = 65
		if animation.clip.begins_with("body/Dash") or animation.clip in ["body/Roll", "body/Slide"]:
			feet.x += facing * 280 * dt
		else: feet += move * Vector2(speed, speed * 0.45) * dt
		feet.x = clampf(feet.x, 220, 1060)
		feet.y = clampf(feet.y, 488, 604)
	_collect_entries()
	# Use the CURRENT input on the exact recovery boundary, not the input captured
	# at attack start. This prevents a one-frame stale walk/crouch after release.
	if health > 0 and animation.busy() and charging.is_empty():
		animation.next_loop = "combat/Guard" if input.get("guard", false) and equipment in ["sword", "unarmed"] else _locomotion()
	var completed_before: int = animation.completed
	var clip_before: String = animation.clip
	animation.tick(dt)
	_collect_entries()
	if completed_before != animation.completed and clip_before == "combat/GunReload": ammo = 6
	actual_visits[animation.clip] = true
	previous = input.duplicate()

func _collect_entries() -> void:
	for entry: Dictionary in animation.entries:
		actual_visits[entry.clip] = true
		if int(entry.index) == 0:
			var name: String = entry.clip
			if name in ["combat/GunFire", "combat/GunFire2H", "combat/GunWalkFire", "combat/GunRunFire", "combat/GunSprintFire", "combat/GunCrouchFire"]:
				ammo -= 1
				events.append({"type": "shot", "clip": name, "frame": 0, "facing": facing, "feet": feet.snapped(Vector2(4, 4))})
			if name == "combat/BowFire": events.append({"type": "arrow", "clip": name, "frame": 0, "facing": facing, "feet": feet.snapped(Vector2(4, 4))})
			if name in ["body/Roll", "body/Slide", "body/DashStart", "body/Run", "body/Sprint"]:
				var fx := "RollDust" if name == "body/Roll" else ("SlideDust" if name == "body/Slide" else ("DashDust" if name == "body/DashStart" else "RunDustBack"))
				events.append({"type": "fx", "key": "fx/" + fx, "facing": facing, "feet": feet})
	animation.entries.clear()

func inspect(key: String) -> void:
	charging = ""
	fishing_phase = "ready"
	animation.inspect(key)
	events.clear()
	actual_visits[key] = true
