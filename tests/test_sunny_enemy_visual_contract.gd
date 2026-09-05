extends SceneTree

const ARENA := preload("res://scripts/sunny_expedition/arena.gd")
const ADAPTER := preload("res://scripts/sunny_expedition/enemy_visual_adapter.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var arena := ARENA.new()
	root.add_child(arena)
	await process_frame
	var expected_deliveries := {
		"spring_hopper": ["contact", "marked_impact"],
		"spore_raider": ["rush", "projectile"],
		"wind_wisp": ["contact", "marked_impact"],
		"thorn_guardian": ["contact", "projectile"],
	}
	for blueprint_id: String in expected_deliveries:
		var spec: Dictionary = arena._enemy_visual_spec(blueprint_id)
		_check(not spec.is_empty(), "%s visual spec exists" % blueprint_id)
		for delivery: String in expected_deliveries[blueprint_id]:
			var route := ADAPTER.route_for(spec, delivery, false)
			_check(not route.is_empty(), "%s %s route exists" % [blueprint_id, delivery])
			_check(ADAPTER.continuity_is_valid(route), "%s %s commit-active frames do not restart" % [blueprint_id, delivery])
			var commit_end := ADAPTER.phase_frame(route, "commit", 1.0, 0.0)
			var active_start := ADAPTER.phase_frame(route, "active", 0.0, 0.0)
			_check(active_start >= commit_end and active_start <= commit_end + 1, "%s %s active starts at commit continuation" % [blueprint_id, delivery])
	var thorn_contact := ADAPTER.route_for(arena._enemy_visual_spec("thorn_guardian"), "contact", false)
	var thorn_projectile := ADAPTER.route_for(arena._enemy_visual_spec("thorn_guardian"), "projectile", false)
	_check(str((thorn_contact.texture as Texture2D).resource_path).ends_with("thorn_guardian_hurt.png"), "thorn close contact uses non-shooting lunge sheet")
	_check(str((thorn_projectile.texture as Texture2D).resource_path).ends_with("thorn_guardian_shoot.png"), "thorn projectile uses shooting sheet")
	var wisp_cast := ADAPTER.route_for(arena._enemy_visual_spec("wind_wisp"), "marked_impact", false)
	_check(bool(wisp_cast.get("readable_cast", false)), "wisp marked impact declares readable cast lift")
	_check((wisp_cast.get("anchors", {}) as Dictionary).has("cast"), "wisp cast anchor is data driven")
	var labels := {}
	var markers := {}
	for family: String in ["echo", "residue", "barrier"]:
		var snapshot := {"modifier_contract": {"families": [family]}}
		_check(ADAPTER.modifier_family(snapshot) == family, "%s modifier skin reads the anonymous runtime family" % family)
		var skin := ADAPTER.modifier_skin(family)
		_check(not skin.is_empty() and not str(skin.get("label", "")).is_empty(), "%s modifier skin has a readable label" % family)
		labels[str(skin.label)] = true
		markers[str(skin.silhouette_marker)] = true
	_check(labels.size() == 3 and markers.size() == 3, "echo residue and barrier use three distinct labels and silhouette markers")
	_check(ADAPTER.modifier_family({"modifier_contract": {"families": []}}).is_empty(), "ordinary enemies do not gain an elite skin")
	_test_effect_alpha(arena, "spore_raider", "projectile", 7, "spore bubbles")
	_test_effect_alpha(arena, "thorn_guardian", "projectile", 5, "thorn seed")
	var spore_route := ADAPTER.route_for(arena._enemy_visual_spec("spore_raider"), "projectile", false)
	_check((spore_route.get("anchors", {}) as Dictionary).has("launch"), "spore launch anchor is data driven")
	_check((thorn_projectile.get("anchors", {}) as Dictionary).has("launch"), "thorn launch anchor is data driven")
	var anchor_sample := {"anchors": thorn_projectile.anchors, "root": Vector2(300, 400), "pivot": Vector2(30, 45), "zoom": 3.0, "draw_facing": 1.0}
	var left_anchor := ADAPTER.world_anchor(anchor_sample, "launch")
	anchor_sample["draw_facing"] = -1.0
	var right_anchor := ADAPTER.world_anchor(anchor_sample, "launch")
	_check(is_equal_approx(left_anchor.distance_to(Vector2(300, 400)), right_anchor.distance_to(Vector2(300, 400))), "launch anchor mirrors without changing reach")
	arena.free()
	if failures.is_empty():
		print("SUNNY_ENEMY_VISUAL_CONTRACT_TEST: PASS (%d checks)" % checks)
		print("Tests finished: passed=%d failed=0" % checks)
		quit(0)
	else:
		for failure: String in failures:
			printerr("SUNNY_ENEMY_VISUAL_CONTRACT_TEST: FAIL: ", failure)
		print("Tests finished: passed=%d failed=%d" % [checks - failures.size(), failures.size()])
		quit(1)


func _test_effect_alpha(arena: Node, blueprint_id: String, delivery: String, frame: int, label: String) -> void:
	var route := ADAPTER.route_for(arena._enemy_visual_spec(blueprint_id), delivery, false)
	var texture := route.texture as Texture2D
	var frame_size: Vector2i = route.frame_size
	var source := Rect2i(frame * frame_size.x, 0, frame_size.x, frame_size.y)
	var layers := ADAPTER.alpha_layers(texture.get_image(), source, route.get("collision", {}) as Dictionary)
	_check((layers.body_points as PackedVector2Array).size() > 0, "%s keeps body Alpha" % label)
	_check((layers.effect_points as PackedVector2Array).size() > 0, "%s separates visible effect pixels" % label)
	var effect_point: Vector2 = (layers.effect_points as PackedVector2Array)[0]
	var pixel := Vector2i(floori(effect_point.x), floori(effect_point.y))
	var index := pixel.y * frame_size.x + pixel.x
	_check((layers.visual_alpha as PackedByteArray)[index] != 0, "%s remains visible" % label)
	_check((layers.body_alpha as PackedByteArray)[index] == 0, "%s cannot count as enemy body contact" % label)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
