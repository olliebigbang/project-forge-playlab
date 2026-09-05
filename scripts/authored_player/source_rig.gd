extends RefCounted
## Untouched licensed layers. Fixed full-canvas origin; no alpha recentering,
## generated head, or legacy line arms. Reference Weapon is measurement only.
const ROOT := "res://assets/dead_revolver_player_v1/"
const META := preload("res://scripts/original_sword_preview/sword_library.gd")
const SOURCES := {"body": "Player", "combat": "PlayerCombat", "fishing": "PlayerFishing"}
const FOLDERS := {"body": "", "combat": "Combat/", "fishing": "Fishing/"}
const PARTS := ["LeftLeg", "LeftArm", "Torso", "RightLeg", "Head", "RightArm"]
var metadata: Dictionary = {}
var cache: Dictionary = {}
var errors: Array[String] = []
var donor_cache: Dictionary = {}

func _init() -> void:
	for group: String in SOURCES:
		metadata[group] = META.read_metadata(FileAccess.get_file_as_bytes(ROOT + "Aseprite/" + str(SOURCES[group]) + ".aseprite"), Vector2i.ZERO)

func duration(key: String) -> float:
	var group := key.get_slice("/", 0)
	var tag: Dictionary = metadata[group].tags[key.get_slice("/", 1)]
	var total := 0.0
	for i: int in range(tag.first, tag.last + 1): total += metadata[group].durations[i] / 1000.0
	return total

func sample(key: String, seconds: float, loop: bool = true) -> Dictionary:
	var group := key.get_slice("/", 0)
	var tag: Dictionary = metadata[group].tags[key.get_slice("/", 1)]
	var elapsed := fposmod(seconds, duration(key)) if loop else clampf(seconds, 0, duration(key) - 0.00001)
	var index := 0
	for i: int in range(tag.first, tag.last + 1):
		var dt: float = metadata[group].durations[i] / 1000.0
		if elapsed < dt: break
		elapsed -= dt
		index += 1
	return frame(key, index)

func frame(key: String, index: int) -> Dictionary:
	var cache_key := key + "/" + str(index)
	if cache.has(cache_key): return cache[cache_key]
	var group := key.get_slice("/", 0)
	var name := key.get_slice("/", 1)
	var filename := "%s%02d.png" % [name, index + 1]
	var base := ROOT + "SpritesSeparated/" + str(FOLDERS[group]) + name + "/"
	var result := {"key": key, "index": index, "pivot": Vector2(68, 104) if group == "fishing" else Vector2(48, 84), "parts": {}, "images": {}, "weapon_texture": null, "weapon_pixels": PackedVector2Array(), "weapon_smear": false}
	for part: String in PARTS + ["Weapon"]:
		var path := base + part + "/" + filename
		if not ResourceLoader.exists(path): continue # Some source clips have no weapon or FX layer.
		var texture := load(path) as Texture2D
		var img := texture.get_image()
		result.images[part] = img
		if part in PARTS: result.parts[part] = texture
		elif part == "Weapon":
			result.weapon_texture = texture
			result.weapon_pixels = opaque(img)
			result.weapon_smear = result.weapon_pixels.size() >= 300
	if result.parts.size() != 6: errors.append("Missing authored body layer: " + cache_key)
	result.arm_pixels = {}
	for part: String in ["RightArm", "LeftArm"]: result.arm_pixels[part] = connected_arm_pixels(result.images.get(part))
	# Detached white motion flecks also exist in a few Torso exports. They
	# must not widen the body hull or move the shoulder used for attachments.
	result.body_pixels = connected_arm_pixels(result.images.get("Torso"), true, opaque(result.images.get("Head")))
	result.primary = arm_anchors(result, "RightArm")
	result.support = arm_anchors(result, "LeftArm")
	var core: PackedVector2Array = result.body_pixels.duplicate()
	core.append_array(opaque(result.images.get("Head")))
	result.core_hull = Geometry2D.convex_hull(core)
	cache[cache_key] = result
	return result

static func opaque(img: Image) -> PackedVector2Array:
	var points := PackedVector2Array()
	if img == null: return points
	var bounds := img.get_used_rect()
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if img.get_pixel(x, y).a > 0.5: points.append(Vector2(x, y) + Vector2.ONE * 0.5)
	return points

static func arm_anchors(frame_data: Dictionary, part: String) -> Dictionary:
	var points: PackedVector2Array = frame_data.arm_pixels[part]
	var torso: Image = frame_data.images.get("Torso")
	if points.is_empty() or torso == null:
		var center := Vector2(torso.get_used_rect().get_center()) if torso != null else Vector2(48, 62)
		return {"shoulder": center, "hand": center + Vector2(6, 0), "elbow": center + Vector2(3, 3), "reach": 9.0}
	var torso_rect := Rect2()
	var first := true
	for p: Vector2 in frame_data.body_pixels:
		if first: torso_rect = Rect2(p, Vector2.ONE); first = false
		else: torso_rect = torso_rect.expand(p)
	var shoulder_guess := Vector2(torso_rect.position.x + torso_rect.size.x * 0.5, torso_rect.position.y + 3.0)
	var shoulder := points[0]
	for point: Vector2 in points:
		if point.distance_squared_to(shoulder_guess) < shoulder.distance_squared_to(shoulder_guess): shoulder = point
	var weapon_points := opaque(frame_data.images.get("Weapon"))
	var hand := points[0]
	var best := -INF
	for point: Vector2 in points:
		var distance := point.distance_to(shoulder)
		# Prefer distal arm pixels adjacent to the reference grip; never infer
		# an AI object's identity from these authored art names.
		var nearest := INF
		for wp: Vector2 in weapon_points: nearest = minf(nearest, point.distance_squared_to(wp))
		var score := distance if weapon_points.is_empty() else distance - sqrt(nearest) * 2.0
		if score > best: best = score; hand = point
	var direction := (hand - shoulder).normalized()
	var midpoint := shoulder.lerp(hand, 0.5)
	var sum := Vector2.ZERO
	var count := 0
	for point: Vector2 in points:
		if absf((point - midpoint).dot(direction)) < 1.6:
			sum += point; count += 1
	var elbow := sum / count if count > 0 else midpoint
	# Deeply folded authored arms are V-shaped, not a strip along the direct
	# shoulder/hand chord. The old midpoint estimate missed their actual elbow,
	# shortened both bones and swung the leftover pixels above the head.
	var furthest := 0.0
	var bend_side := 1.0
	for point: Vector2 in points:
		var signed_distance := direction.cross(point - shoulder)
		if absf(signed_distance) > furthest:
			furthest = absf(signed_distance); bend_side = signf(signed_distance)
	if furthest > 3.25:
		var extremity := Vector2.ZERO
		var extremity_count := 0
		for point: Vector2 in points:
			if direction.cross(point - shoulder) * bend_side >= furthest * 0.80:
				extremity += point; extremity_count += 1
		if extremity_count > 0: elbow = extremity / extremity_count
	# A straight source arm still has two bones; leave a small anatomical bend
	# when retargeting a rifle's much wider grip spacing.
	if absf((elbow - shoulder).cross(direction)) < 1.0: elbow += Vector2(-direction.y, direction.x) * 1.5
	return {"shoulder": shoulder, "hand": hand, "elbow": elbow, "reach": shoulder.distance_to(elbow) + elbow.distance_to(hand)}

func full_arm_frame(body: Dictionary) -> Dictionary:
	var cache_key := str([body.key, body.index])
	if donor_cache.has(cache_key): return donor_cache[cache_key]
	if _usable_arm(body, "RightArm"):
		donor_cache[cache_key] = body
		return body
	# Some active source frames bake a large speed smear into RightArm. It is
	# not anatomy, even when it is one connected component. Keep that frame's
	# entire body, but retarget a clear original limb from the closest frame.
	var donor := body
	var part := "LeftArm"
	if not _usable_arm(body, part):
		var group := str(body.key).get_slice("/", 0)
		var tag: Dictionary = metadata[group].tags[str(body.key).get_slice("/", 1)]
		var count := int(tag.last) - int(tag.first) + 1
		var found := false
		for distance: int in range(1, count):
			for index: int in [int(body.index) - distance, int(body.index) + distance]:
				if index < 0 or index >= count: continue
				var candidate := frame(body.key, index)
				for arm: String in ["RightArm", "LeftArm"]:
					if _usable_arm(candidate, arm): donor = candidate; part = arm; found = true; break
				if found: break
			if found: break
		if not found: return body
	var out := body.duplicate(true)
	out.primary = (donor.primary if part == "RightArm" else donor.support).duplicate(true)
	out.pivot = Vector2(body.pivot) + Vector2(out.primary.shoulder) - Vector2(body.primary.shoulder)
	out.parts.RightArm = donor.parts[part]
	out.images.RightArm = donor.images[part]
	out.arm_pixels.RightArm = donor.arm_pixels[part]
	donor_cache[cache_key] = out
	return out

static func _usable_arm(data: Dictionary, part: String) -> bool:
	var pixels: PackedVector2Array = data.arm_pixels[part]
	var a: Dictionary = data.primary if part == "RightArm" else data.support
	if pixels.size() < 20 or float(a.reach) < 10: return false
	for p: Vector2 in pixels:
		var upper := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a.shoulder, a.elbow))
		var lower := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a.elbow, a.hand))
		if minf(upper, lower) > 5.0: return false
	return true

static func world(point: Vector2, frame_data: Dictionary, feet: Vector2, face: float, scale: float) -> Vector2:
	var local := (point - Vector2(frame_data.pivot)) * scale
	return feet + Vector2(local.x * face, local.y)

func draw_part(canvas: Node2D, frame_data: Dictionary, part: String, feet: Vector2, face: float, scale: float, tint: Color = Color.WHITE) -> void:
	if not frame_data.parts.has(part): return
	canvas.draw_set_transform(feet.round(), 0, Vector2(face * scale, scale))
	if part in ["LeftArm", "RightArm", "Torso"]:
		var img: Image = frame_data.images[part]
		var pixels: PackedVector2Array = frame_data.body_pixels if part == "Torso" else frame_data.arm_pixels[part]
		for point: Vector2 in pixels:
			canvas.draw_rect(Rect2(point - Vector2.ONE * 0.5 - Vector2(frame_data.pivot), Vector2.ONE), img.get_pixelv(Vector2i(point)) * tint)
	else: canvas.draw_texture(frame_data.parts[part], -Vector2(frame_data.pivot), tint)
	canvas.draw_set_transform(Vector2.ZERO)

func draw_raw_part(canvas: Node2D, frame_data: Dictionary, part: String, feet: Vector2, face: float, scale: float, tint: Color = Color.WHITE) -> void:
	if not frame_data.parts.has(part): return
	canvas.draw_set_transform(feet.round(), 0, Vector2(face * scale, scale))
	canvas.draw_texture(frame_data.parts[part], -Vector2(frame_data.pivot), tint)
	canvas.draw_set_transform(Vector2.ZERO)

func draw_weapon_smear(canvas: Node2D, frame_data: Dictionary, feet: Vector2, face: float, scale: float) -> bool:
	if not bool(frame_data.get("weapon_smear", false)): return false
	var texture := frame_data.get("weapon_texture") as Texture2D
	if texture == null: return false
	canvas.draw_set_transform(feet.round(), 0, Vector2(face * scale, scale))
	canvas.draw_texture(texture, -Vector2(frame_data.pivot), Color(1, 1, 1, 0.72))
	canvas.draw_set_transform(Vector2.ZERO)
	return true

func draw_arm(canvas: Node2D, frame_data: Dictionary, part: String, feet: Vector2, face: float, scale: float, target: Vector2, tint: Color) -> Dictionary:
	var anchors: Dictionary = frame_data.primary if part == "RightArm" else frame_data.support
	var shoulder := world(anchors.shoulder, frame_data, feet, face, scale)
	var original := world(anchors.hand, frame_data, feet, face, scale)
	if target.distance_to(original) <= 0.01:
		draw_part(canvas, frame_data, part, feet, face, scale, tint)
	else:
		# Retarget ONLY the original arm pixels using two bones. Keep bone
		# lengths and transverse thickness; do not stretch a line into an arm.
		var source_delta := original - shoulder
		var target_delta := target - shoulder
		var source_elbow := world(anchors.elbow, frame_data, feet, face, scale)
		var upper := shoulder.distance_to(source_elbow)
		var lower := original.distance_to(source_elbow)
		var distance := clampf(target_delta.length(), absf(upper - lower) + 0.01, upper + lower - 0.01)
		var along := (upper * upper - lower * lower + distance * distance) / (2 * distance)
		var normal := Vector2(-target_delta.normalized().y, target_delta.normalized().x)
		var bend := signf(source_delta.cross(source_elbow - shoulder))
		if is_zero_approx(bend): bend = face
		var target_elbow := shoulder + target_delta.normalized() * along + normal * sqrt(maxf(0, upper * upper - along * along)) * bend
		var img: Image = frame_data.images[part]
		for point: Vector2 in frame_data.arm_pixels[part]:
			# Shared corner mapping produces a watertight pixel mesh. Forward
			# stamping isolated squares leaves cracks around a bent elbow.
			var polygon := PackedVector2Array()
			for corner: Vector2 in [Vector2(-0.5,-0.5), Vector2(0.5,-0.5), Vector2(0.5,0.5), Vector2(-0.5,0.5)]:
				var source_point := world(point + corner, frame_data, feet, face, scale)
				var du := source_point.distance_to(Geometry2D.get_closest_point_to_segment(source_point, shoulder, source_elbow))
				var dl := source_point.distance_to(Geometry2D.get_closest_point_to_segment(source_point, source_elbow, original))
				var weight := pow(dl + 0.01, 4) / (pow(du + 0.01, 4) + pow(dl + 0.01, 4))
				var top := _bone_point(source_point, shoulder, source_elbow, shoulder, target_elbow)
				var low := _bone_point(source_point, source_elbow, original, target_elbow, target)
				polygon.append(low.lerp(top, weight).round())
			for indices: Array in [[0, 1, 2], [0, 2, 3]]:
				var triangle := PackedVector2Array([polygon[indices[0]], polygon[indices[1]], polygon[indices[2]]])
				if absf((triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])) > 0.1:
					canvas.draw_colored_polygon(triangle, img.get_pixelv(Vector2i(point)) * tint)
	return {"shoulder": shoulder, "source_hand": original, "hand": target, "displacement": target.distance_to(original)}

static func _bone_point(point: Vector2, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var old_dir := (b - a).normalized()
	var new_dir := (d - c).normalized()
	return c + new_dir * (point - a).dot(old_dir) + Vector2(-new_dir.y, new_dir.x) * (point - a).dot(Vector2(-old_dir.y, old_dir.x))

func draw_underarm(canvas: Node2D, frame_data: Dictionary, feet: Vector2, face: float, scale: float, tint: Color) -> void:
	# Separated exports omit torso pixels occluded by the original near arm.
	# Either source arm can contain neck/chest overlap in overhead poses.
	# Restore BOTH inside the head+torso core, not only the cut-out torso hull.
	# These are original pixels, never a newly drawn neck or spare full arm.
	var hull: PackedVector2Array = frame_data.core_hull
	if hull.size() < 3: return
	for part: String in ["LeftArm", "RightArm"]:
		var img: Image = frame_data.images[part]
		for point: Vector2 in frame_data.arm_pixels[part]:
			if Geometry2D.is_point_in_polygon(point, hull):
				var position := world(point, frame_data, feet, face, scale)
				canvas.draw_rect(Rect2(position - Vector2.ONE * scale * 0.5, Vector2.ONE * scale), img.get_pixelv(Vector2i(point)) * tint)

static func connected_arm_pixels(img: Image, largest_only: bool = false, attached_to: PackedVector2Array = PackedVector2Array()) -> PackedVector2Array:
	# Some exported arm layers include detached 1–4 px motion flecks formerly
	# hidden by the source sword/FX. They are not anatomy or attachment anchors.
	# Cull only tiny disconnected components at DRAW time; source files stay exact.
	var all := opaque(img)
	var remaining := {}
	for point: Vector2 in all: remaining[Vector2i(point)] = true
	var components: Array[PackedVector2Array] = []
	while not remaining.is_empty():
		var seed: Vector2i = remaining.keys()[0]
		var queue: Array[Vector2i] = [seed]
		var component := PackedVector2Array()
		remaining.erase(seed)
		var cursor := 0
		while cursor < queue.size():
			var point := queue[cursor]; cursor += 1
			component.append(Vector2(point) + Vector2.ONE * 0.5)
			for y: int in range(-1, 2):
				for x: int in range(-1, 2):
					var next := point + Vector2i(x, y)
					if remaining.has(next): remaining.erase(next); queue.append(next)
		components.append(component)
	var largest := 0
	for points: PackedVector2Array in components: largest = maxi(largest, points.size())
	var clean := PackedVector2Array()
	var body_neighbors := attached_to.duplicate()
	if largest_only:
		for points: PackedVector2Array in components:
			if points.size() == largest: body_neighbors.append_array(points)
	for points: PackedVector2Array in components:
		var keep := points.size() == largest or (not largest_only and points.size() > 4)
		if largest_only and not keep:
			# A source neck/chest island can be disconnected from Torso because
			# the head/arm sits between. Preserve islands adjacent to real anatomy.
			for point: Vector2 in points:
				for neighbor: Vector2 in body_neighbors:
					if point.distance_squared_to(neighbor) <= 9: keep = true; break
				if keep: break
		if keep: clean.append_array(points)
	return clean
