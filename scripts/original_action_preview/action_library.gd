extends RefCounted
## Authored art catalog. These are animation names, NOT object-name combat rules.
const METADATA := preload("res://scripts/original_sword_preview/sword_library.gd")
const ROOT := "res://assets/dead_revolver_player_v1/"
const SOURCES := {"body": "Player", "combat": "PlayerCombat", "fishing": "PlayerFishing", "fx": "Effects", "weapon": "Weapons"}
const FOLDERS := {"body": "", "combat": "Combat/", "fishing": "Fishing/", "fx": "FX/", "weapon": "Weapons/"}
const EXCLUDED_PREFIXES := ["Ladder", "Climb", "Ledge", "Monkey", "Wall"]
const CONDITIONAL := ["Jump", "JumpRise", "JumpMid", "JumpFall", "Land", "FrontFlip", "Spin", "LookUp", "InteractionPull", "Push", "Pull", "PushIdle", "SwordJump", "SwordJumpRise", "SwordJumpMid", "SwordJumpFall", "AirSlash", "AirSlashUp", "AirSlashDown", "GroundSlam", "ThrowUnderarm", "ThrowOverarm"]
const CONTEXT_BODY := ["Idle", "Walk", "Run", "Sprint", "RunToIdle", "Crouch", "Crawl", "Roll", "DashStart", "DashLoop", "DashEnd", "Slide", "Knockback", "Die"]
const CONTEXT_FX := ["RunDustBack", "DashDust", "RollDust", "SlideDust"]
const ALIASES := {"SwordSlash01": "挥剑", "SwordCombo01": "连击一", "SwordCombo02": "连击二", "SwordCombo03": "连击三", "SwordCombo04": "连击四", "GunCrouchFire": "蹲射", "GunWalkFire": "边走边射", "GunRunFire": "边跑边射", "GunSprintFire": "冲刺射击", "SwordRunSlash": "跑动挥剑", "SwordSprintSlash": "冲刺挥剑", "CrouchSlash": "蹲斩", "GunReload": "换弹", "GuardImpact": "格挡受击", "Prepare": "抛竿准备", "Charge": "抛竿蓄力", "Cast": "抛竿", "Reel": "收线", "Struggle": "拉扯", "Catch": "提竿", "Knockback": "击退", "Die": "倒地"}
var clips: Dictionary = {}
var catalog: Array[Dictionary] = []
var errors: Array[String] = []
var hashes: Dictionary = {}

func _init() -> void:
	for group: String in SOURCES:
		var source := ROOT + "Aseprite/" + str(SOURCES[group]) + ".aseprite"
		var metadata := METADATA.read_metadata(FileAccess.get_file_as_bytes(source), Vector2i.ZERO)
		if metadata.is_empty():
			errors.append("Invalid source metadata: " + source)
			continue
		hashes[group] = FileAccess.get_sha256(source)
		for tag_name: String in metadata.tags:
			var key := group + "/" + tag_name
			var excluded := EXCLUDED_PREFIXES.any(func(prefix: String) -> bool: return tag_name.begins_with(prefix))
			var status := "排除：攀爬关卡专用" if excluded else ("条件动作：只供演示，尚无对应关卡交互" if tag_name in CONDITIONAL else "动作库已接入")
			var contextual := (group == "body" and tag_name in CONTEXT_BODY) or (group == "combat" and tag_name not in CONDITIONAL) or group == "fishing" or (group == "fx" and tag_name in CONTEXT_FX) or (group == "weapon" and tag_name in ["Bullet", "Arrow"])
			if not excluded:
				if contextual: status = "按键 / 状态联动已接入" if group not in ["fx", "weapon"] else "事件配套素材已接入"
				elif tag_name not in CONDITIONAL: status = "检查菜单可播放，未接对应玩法事件"
			catalog.append({"key": key, "status": status, "excluded": excluded, "contextual": contextual and not excluded})
			if excluded: continue
			var tag: Dictionary = metadata.tags[tag_name]
			if int(tag.direction) != 0:
				errors.append("Unsupported source direction: " + key)
				continue
			var frames: Array[Dictionary] = []
			for index: int in range(int(tag.first), int(tag.last) + 1):
				var name := "%s%02d.png" % [tag_name, index - int(tag.first) + 1]
				var path := ROOT + "Sprites/" + str(FOLDERS[group]) + tag_name + "/" + name
				if not ResourceLoader.exists(path):
					errors.append("Missing source PNG: " + path)
					continue
				var texture := load(path) as Texture2D
				if texture == null or texture.get_size() != Vector2(metadata.canvas):
					errors.append("Invalid canvas: " + path)
					continue
				var frame := {"texture": texture, "image": texture.get_image(), "duration_ms": int(metadata.durations[index]), "source_frame": index, "path": path}
				# Source fishing canvas adds 20 px above and 20 px before the feet.
				# Fixed pivot comes from the authored Idle feet, not per-frame recentering.
				frame.pivot = Vector2(68, 104) if group == "fishing" else Vector2(48, 84)
				if group == "combat" and tag_name.begins_with("Gun"):
					var weapon_path := ROOT + "SpritesSeparated/Combat/" + tag_name + "/Weapon/" + name
					if ResourceLoader.exists(weapon_path):
						var weapon := (load(weapon_path) as Texture2D).get_image()
						var bounds := weapon.get_used_rect()
						if bounds.has_area(): frame.muzzle = Vector2(bounds.end.x, bounds.position.y + bounds.size.y * 0.5)
				frames.append(frame)
			clips[key] = frames

func frame(key: String, index: int = 0) -> Dictionary:
	return clips[key][index]

func total_ms(key: String) -> int:
	var total := 0
	for item: Dictionary in clips[key]: total += int(item.duration_ms)
	return total

func label(key: String) -> String:
	var name := key.get_slice("/", 1)
	return str(ALIASES.get(name, name))

func playable_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: String in clips:
		if key.get_slice("/", 0) in ["body", "combat", "fishing"]: keys.append(key)
	return keys
