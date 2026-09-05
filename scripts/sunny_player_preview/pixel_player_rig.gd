extends RefCounted
## Licensed motion frames drive a modular generated adventurer exterior.
## No whole-body sprite or independently swinging arm under the held arms.
const ROOT := "res://assets/dead_revolver_player_v1/SpritesSeparated/"
const ATLAS := preload("res://assets/sunny_player_v2/adventurer_atlas.png")
const HEAD_REGION := Rect2(152, 40, 328, 308)
const TORSO_REGION := Rect2(668, 122, 280, 344)
const UPPER_REGION := Rect2(1230, 122, 128, 340)
const FORE_REGION := Rect2(258, 618, 86, 252)
const FIST_REGION := Rect2(705, 697, 143, 124)
const HEAD_SIZE := Vector2(44, 46)
# Real attachment locations in the generated parts, not their bounding-box
# centres. Both neck locations lie on opaque skin inside the collar opening.
const HEAD_NECK := Vector2(282, 340)
const TORSO_NECK := Vector2(812, 148)
const PRIMARY_SHOULDER := Vector2(716, 200)
const SUPPORT_SHOULDER := Vector2(902, 199)
const TORSO_SIZE := Vector2(44, 64)
const PALM_TO_WRIST := Vector2(-5, 0)
const SCALE := 4.0
const PIVOT := Vector2(48, 84)
const SOURCE_SHOULDER := Vector2(46, 56)
const SOURCE_ELBOW := Vector2(53, 59)
const SOURCE_HAND := Vector2(60, 59)
const UPPER_LENGTH := 7.6157731059 * SCALE
const LOWER_LENGTH := 7.0 * SCALE
const MAX_REACH := UPPER_LENGTH + LOWER_LENGTH - 1.0
const MIN_REACH := absf(UPPER_LENGTH - LOWER_LENGTH) + 1.0
const OUTLINE := Color("283e49")
const PART_COLORS := {"Head": Color("f4c897"), "Torso": Color("65bca4"), "RightLeg": Color("527083"), "LeftLeg": Color("46627a"), "LeftArm": Color("d0a374")}
var poses: Dictionary = {}

func _init() -> void:
	for pose: String in ["Idle", "Combat/GunWalk", "Combat/GunRun"]:
		var frames: Array[Dictionary] = []
		for index: int in range(7 if pose == "Idle" else 8):
			var name := "%s%02d.png" % [pose.get_file(), index + 1]
			var frame: Dictionary = {"name": name, "parts": {}, "bounds": {}}
			for part: String in ["Head", "Torso", "LeftLeg", "RightLeg", "LeftArm"]:
				var texture := load(ROOT + pose + "/" + part + "/" + name) as Texture2D
				var img := texture.get_image()
				frame.parts[part] = texture
				frame.bounds[part] = img.get_used_rect()
				if part == "Torso":
					var bounds := img.get_used_rect()
					frame["shoulder"] = Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.position.y + 4)
			# The new head must follow the new torso's neck, not the independent
			# head trajectory or silhouette of the original mannequin animation.
			frame["head_bounds"] = Rect2(head_rect(frame).position / SCALE + PIVOT, HEAD_SIZE / SCALE)
			frames.append(frame)
		poses[pose] = frames

func torso_rect(frame: Dictionary) -> Rect2:
	var center := (Vector2(frame.shoulder) - PIVOT) * SCALE
	return Rect2(center + Vector2(-22, -8), TORSO_SIZE)

func neck_local(frame: Dictionary) -> Vector2:
	return torso_rect(frame).position + (TORSO_NECK - TORSO_REGION.position) / TORSO_REGION.size * TORSO_SIZE

func head_rect(frame: Dictionary) -> Rect2:
	return Rect2(neck_local(frame) - (HEAD_NECK - HEAD_REGION.position) / HEAD_REGION.size * HEAD_SIZE, HEAD_SIZE)

static func wrist_offset(facing: float, grip_angle: float) -> Vector2:
	return Vector2(PALM_TO_WRIST.x * facing, PALM_TO_WRIST.y).rotated(grip_angle)

static func constrain_grip(desired: Vector2, primary_shoulder: Vector2, support_shoulder: Vector2, secondary_delta: Vector2, two_hands: bool, facing: float, grip_angle: float) -> Vector2:
	var offset := wrist_offset(facing, grip_angle)
	return constrain_hand(desired + offset, primary_shoulder, support_shoulder, secondary_delta, two_hands) - offset

func sample(clock: float, moving: bool, dodging: bool) -> Dictionary:
	var pose := "Combat/GunRun" if dodging else ("Combat/GunWalk" if moving else "Idle")
	var frames: Array = poses[pose]
	var index := int(clock * (12.0 if dodging else 8.0)) % frames.size()
	var frame: Dictionary = frames[index].duplicate()
	frame["pose"] = pose
	frame["index"] = index
	return frame

func shoulders(frame: Dictionary, feet: Vector2, facing: float) -> Dictionary:
	var torso := torso_rect(frame)
	var primary := torso.position + (PRIMARY_SHOULDER - TORSO_REGION.position) / TORSO_REGION.size * torso.size
	var support := torso.position + (SUPPORT_SHOULDER - TORSO_REGION.position) / TORSO_REGION.size * torso.size
	return {"primary": feet + Vector2(primary.x * facing, primary.y), "support": feet + Vector2(support.x * facing, support.y)}

static func joint(shoulder: Vector2, hand: Vector2, facing: float) -> Vector2:
	var delta := hand - shoulder
	var distance := clampf(delta.length(), absf(UPPER_LENGTH - LOWER_LENGTH) + 0.1, MAX_REACH)
	var direction := delta.normalized() if delta.length() > 0.01 else Vector2(facing, 0)
	var along := (UPPER_LENGTH * UPPER_LENGTH - LOWER_LENGTH * LOWER_LENGTH + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, UPPER_LENGTH * UPPER_LENGTH - along * along))
	return shoulder + direction * along + Vector2(-direction.y, direction.x) * height * facing

static func constrain_hand(desired: Vector2, primary_shoulder: Vector2, support_shoulder: Vector2, secondary_delta: Vector2, two_hands: bool) -> Vector2:
	var result := desired
	# Project into the intersection of both arm-reach discs. The weapon remains
	# rigid between its real grips; never clamp the supporting hand off its grip.
	for index: int in range(32 if two_hands else 1):
		result = primary_shoulder + _reachable_delta(result - primary_shoulder)
		if two_hands:
			var center := support_shoulder - secondary_delta
			result = center + _reachable_delta(result - center)
	return result

static func _reachable_delta(delta: Vector2) -> Vector2:
	if delta.length() < 0.001: return Vector2(MIN_REACH, 0)
	return delta.normalized() * clampf(delta.length(), MIN_REACH, MAX_REACH)

func draw_body(canvas: Node2D, frame: Dictionary, feet: Vector2, facing: float, resting_arm: bool) -> void:
	if resting_arm:
		# The unused far arm belongs to the OTHER shoulder, not the same
		# shoulder as the gun arm. Draw it behind the torso.
		var shoulder: Vector2 = shoulders(frame, feet, facing).support
		var hand := shoulder + Vector2(-4 * facing, 49)
		var rest_angle := PI / 2 * facing
		var pose := draw_arm(canvas, shoulder, hand, facing, true, rest_angle)
		draw_fist(canvas, pose.elbow, hand, facing, true, rest_angle)
	for part: String in ["LeftLeg", "RightLeg", "Torso", "Head"]: draw_part(canvas, frame, part, feet, facing)

func draw_part(canvas: Node2D, frame: Dictionary, part: String, feet: Vector2, facing: float) -> void:
	if part == "Head" or part == "Torso":
		canvas.draw_set_transform(feet.snapped(Vector2(2, 2)), 0, Vector2(facing, 1))
		var target: Rect2
		if part == "Head":
			target = head_rect(frame)
		else:
			target = torso_rect(frame)
		canvas.draw_texture_rect_region(ATLAS, target, HEAD_REGION if part == "Head" else TORSO_REGION)
		canvas.draw_set_transform(Vector2.ZERO)
		return
	canvas.draw_set_transform(feet.round(), 0, Vector2(facing * SCALE, SCALE))
	var texture: Texture2D = frame.parts[part]
	for shift: Vector2 in [Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0, -0.5), Vector2(0, 0.5)]:
		canvas.draw_texture(texture, -PIVOT + shift, OUTLINE)
	if part in ["LeftLeg", "RightLeg"]:
		# Retain every authored walking silhouette; a separate boot material
		# follows each frame's foot rather than a static screen-space stripe.
		var boot_y := float(frame.bounds[part].end.y) - 4.0
		canvas.draw_texture_rect_region(texture, Rect2(-PIVOT, Vector2(96, boot_y)), Rect2(0, 0, 96, boot_y), Color("536b7c") if part == "RightLeg" else Color("445b70"))
		canvas.draw_texture_rect_region(texture, Rect2(Vector2(0, boot_y) - PIVOT, Vector2(96, 84 - boot_y)), Rect2(0, boot_y, 96, 84 - boot_y), Color("b38457"))
	else: canvas.draw_texture(texture, -PIVOT, PART_COLORS[part])
	canvas.draw_set_transform(Vector2.ZERO)

func draw_arm(canvas: Node2D, shoulder: Vector2, hand: Vector2, facing: float, rear: bool, grip_angle: float = 0.0) -> Dictionary:
	var wrist := hand + wrist_offset(facing, grip_angle)
	var elbow := joint(shoulder, wrist, facing)
	var tone := Color("bec4c7") if rear else Color.WHITE
	_draw_limb(canvas, UPPER_REGION, shoulder, elbow, 16, facing, tone)
	_draw_limb(canvas, FORE_REGION, elbow, wrist, 14, facing, tone)
	return {"shoulder": shoulder, "elbow": elbow, "wrist": wrist, "hand": hand, "grip_angle": grip_angle, "upper_length": shoulder.distance_to(elbow), "lower_length": elbow.distance_to(wrist)}

func draw_fist(canvas: Node2D, _elbow: Vector2, hand: Vector2, facing: float, rear: bool, grip_angle: float = 0.0) -> void:
	# The closed fingers wrap the object, not the forearm's arbitrary heading.
	canvas.draw_set_transform(hand.snapped(Vector2(2, 2)), grip_angle, Vector2(facing, 1))
	canvas.draw_texture_rect_region(ATLAS, Rect2(-6, -6, 12, 12), FIST_REGION, Color("bec4c7") if rear else Color.WHITE)
	canvas.draw_set_transform(Vector2.ZERO)

func _draw_limb(canvas: Node2D, region: Rect2, start: Vector2, finish: Vector2, width: float, facing: float, tone: Color) -> void:
	canvas.draw_set_transform(start.snapped(Vector2(2, 2)), (finish - start).angle() - PI / 2, Vector2(facing, 1))
	canvas.draw_texture_rect_region(ATLAS, Rect2(-width / 2, -2, width, start.distance_to(finish) + 4), region, tone)
	canvas.draw_set_transform(Vector2.ZERO)
