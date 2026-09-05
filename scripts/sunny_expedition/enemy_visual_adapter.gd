class_name SunnyEnemyVisualAdapter
extends RefCounted

## Presentation-only adapter for the licensed Sunny enemy sheets.
## Combat delivery still comes from the compiled enemy attack. This adapter
## chooses a clip, keeps commit -> active frames continuous, and separates
## visible attack effects from the body Alpha used by weapon contact.


static func route_for(spec: Dictionary, delivery: String, moving: bool, hurt: bool = false) -> Dictionary:
	var routes := spec.get("routes", {}) as Dictionary
	if hurt and routes.has("hurt"):
		return (routes.get("hurt", {}) as Dictionary).duplicate(true)
	if not delivery.is_empty() and routes.has(delivery):
		return (routes.get(delivery, {}) as Dictionary).duplicate(true)
	if moving and routes.has("move"):
		return (routes.get("move", {}) as Dictionary).duplicate(true)
	return (routes.get("idle", {}) as Dictionary).duplicate(true)


static func phase_frame(route: Dictionary, phase: String, phase_progress: float, stage_elapsed: float) -> int:
	var frame_count := maxi(1, int(route.get("frame_count", 1)))
	var sequence: Array = route.get("%s_frames" % phase, []) as Array
	if sequence.is_empty():
		sequence = route.get("idle_frames", []) as Array
	if sequence.is_empty():
		for index: int in range(frame_count):
			sequence.append(index)
	if phase in ["telegraph", "commit", "active", "recovery"]:
		var sample_index := mini(sequence.size() - 1, floori(clampf(phase_progress, 0.0, 1.0) * float(sequence.size())))
		return clampi(int(sequence[sample_index]), 0, frame_count - 1)
	var speed := maxf(0.01, float(route.get("speed", 6.0)))
	return clampi(int(sequence[posmod(floori(stage_elapsed * speed), sequence.size())]), 0, frame_count - 1)


static func commit_active_progress(attack: Dictionary, phase: String, phase_elapsed: float) -> float:
	var timeline := attack.get("timeline", {}) as Dictionary
	var commit_seconds := maxf(0.0, float(timeline.get("commit_seconds", 0.0)))
	var active_seconds := maxf(0.0, float(timeline.get("active_seconds", 0.0)))
	var total := commit_seconds + active_seconds
	if total <= 0.0001:
		return 1.0
	if phase == "commit":
		return clampf(phase_elapsed / total, 0.0, 1.0)
	if phase == "active":
		return clampf((commit_seconds + phase_elapsed) / total, 0.0, 1.0)
	return 0.0 if phase == "telegraph" else 1.0


static func continuity_is_valid(route: Dictionary) -> bool:
	var commit_frames: Array = route.get("commit_frames", []) as Array
	var active_frames: Array = route.get("active_frames", []) as Array
	if commit_frames.is_empty() or active_frames.is_empty():
		return true
	var commit_end := int(commit_frames.back())
	var active_start := int(active_frames.front())
	return active_start >= commit_end and active_start <= commit_end + 1


## Modifier presentation is derived from the compiled anonymous family, never
## from the enemy name.  The arena uses this one contract for tint, silhouette
## attachments, labels and warning accents so the skin cannot disagree with the
## live echo / residue / barrier runtime.
static func modifier_family(snapshot: Dictionary) -> String:
	var contract := snapshot.get("modifier_contract", {}) as Dictionary
	var families := contract.get("families", []) as Array
	for family: String in ["barrier", "residue", "echo"]:
		if family in families:
			return family
	return ""


static func modifier_skin(family: String) -> Dictionary:
	match family:
		"barrier":
			return {
				"label": "护盾精英",
				"broken_label": "护盾已破",
				"tint": Color("c7f3ee"),
				"accent": Color("67e8f9"),
				"dark": Color("176b78"),
				"silhouette_marker": "crystal_plates",
			}
		"residue":
			return {
				"label": "残留精英",
				"tint": Color("e6f4aa"),
				"accent": Color("a3e635"),
				"dark": Color("4d7c0f"),
				"silhouette_marker": "spore_satchels",
			}
		"echo":
			return {
				"label": "回声精英",
				"tint": Color("eadcff"),
				"accent": Color("d8b4fe"),
				"dark": Color("7e22ce"),
				"silhouette_marker": "afterimage_motes",
			}
	return {}


static func alpha_layers(image: Image, source: Rect2i, policy: Dictionary = {}) -> Dictionary:
	var size := source.size
	var visual_alpha := PackedByteArray()
	visual_alpha.resize(size.x * size.y)
	var opaque := PackedVector2Array()
	for y: int in range(size.y):
		for x: int in range(size.x):
			if image.get_pixelv(source.position + Vector2i(x, y)).a <= 0.5:
				continue
			visual_alpha[y * size.x + x] = 1
			opaque.append(Vector2(x + 0.5, y + 0.5))
	var body_alpha := visual_alpha.duplicate()
	var mode := str(policy.get("mode", "all_alpha"))
	if mode == "clip_rect":
		var body_rect: Rect2i = policy.get("rect", Rect2i(Vector2i.ZERO, size))
		for y: int in range(size.y):
			for x: int in range(size.x):
				if not body_rect.has_point(Vector2i(x, y)):
					body_alpha[y * size.x + x] = 0
	elif mode == "largest_component":
		body_alpha = _largest_component_mask(visual_alpha, size)
	var body_points := PackedVector2Array()
	var effect_points := PackedVector2Array()
	for y: int in range(size.y):
		for x: int in range(size.x):
			var mask_index := y * size.x + x
			if body_alpha[mask_index] != 0:
				body_points.append(Vector2(x + 0.5, y + 0.5))
			elif visual_alpha[mask_index] != 0:
				effect_points.append(Vector2(x + 0.5, y + 0.5))
	return {
		"visual_alpha": visual_alpha,
		"body_alpha": body_alpha,
		"opaque_points": opaque,
		"body_points": body_points,
		"effect_points": effect_points,
	}


static func world_anchor(sample: Dictionary, anchor_name: String) -> Vector2:
	var anchors := sample.get("anchors", {}) as Dictionary
	if not anchors.has(anchor_name):
		return Vector2(sample.get("root", Vector2.ZERO))
	var local := Vector2(anchors[anchor_name]) - Vector2(sample.get("pivot", Vector2.ZERO))
	local.x *= float(sample.get("draw_facing", 1.0))
	return Vector2(sample.get("root", Vector2.ZERO)) + local * float(sample.get("zoom", 1.0))


static func _largest_component_mask(alpha: PackedByteArray, size: Vector2i) -> PackedByteArray:
	var visited := PackedByteArray()
	visited.resize(alpha.size())
	var best: Array[Vector2i] = []
	for y: int in range(size.y):
		for x: int in range(size.x):
			var start_index := y * size.x + x
			if alpha[start_index] == 0 or visited[start_index] != 0:
				continue
			var component: Array[Vector2i] = []
			var pending: Array[Vector2i] = [Vector2i(x, y)]
			visited[start_index] = 1
			while not pending.is_empty():
				var point: Vector2i = pending.pop_back()
				component.append(point)
				for neighbour: Vector2i in [point + Vector2i.LEFT, point + Vector2i.RIGHT, point + Vector2i.UP, point + Vector2i.DOWN]:
					if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= size.x or neighbour.y >= size.y:
						continue
					var neighbour_index := neighbour.y * size.x + neighbour.x
					if alpha[neighbour_index] == 0 or visited[neighbour_index] != 0:
						continue
					visited[neighbour_index] = 1
					pending.append(neighbour)
			if component.size() > best.size():
				best = component
	var result := PackedByteArray()
	result.resize(alpha.size())
	for point: Vector2i in best:
		result[point.y * size.x + point.x] = 1
	return result
