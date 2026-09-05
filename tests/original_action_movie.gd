extends SceneTree
const SESSION := preload("res://scenes/original_action_preview.tscn")

class Replay extends Node:
	var scene: Node2D
	var elapsed := 0.0
	var stage := -1
	var step_count := 0
	func _physics_process(delta: float) -> void:
		var current := mini(6, int(elapsed / 4))
		var local := fmod(elapsed, 4)
		if current != stage:
			stage = current
			step_count = 0
			scene.equip([0, 0, 1, 1, 1, 3, 4][stage])
			scene.actor.feet = Vector2(360, 580)
			scene.actor.facing = 1
			scene.target_feet = Vector2(864, 580)
			scene.hits = 0
			scene.auto_crouch = stage != 2
			if stage == 0: scene.actor.feet.x = 720
			if stage == 5: scene.actor.feet.x = 560
		var input: Dictionary = {}
		match stage:
			0: input = {"secondary": step_count == 0 or step_count == 145}
			1: input = {"move": Vector2.RIGHT if local < 2.8 else Vector2.LEFT, "run": true, "attack": step_count % 48 == 0}
			2: input = {"attack": local < 2.5}
			3: input = {"attack": local < 2.5}
			4: input = {"move": Vector2.RIGHT if local < 2 else Vector2.LEFT, "run": true, "attack": true}
			5: input = {"attack": local < 0.8 or (local >= 1.4 and local < 1.5)}
			6:
				if local < 1.7: input = {"attack": step_count == 0}
				elif local < 2.8: input = {"dodge": step_count == 103}
				else: input = {"guard": true, "hit": step_count == 190}
		# The session itself stays on the production path; only input is scripted.
		scene.advance(delta, input)
		elapsed += delta
		step_count += 1
		if elapsed >= 28:
			print("ORIGINAL_ACTION_MOVIE replay_seconds=", elapsed, " input=scripted source=offline")
			get_tree().quit()

func _initialize() -> void: _start.call_deferred()

func _start() -> void:
	var scene := SESSION.instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	var replay := Replay.new()
	replay.scene = scene
	root.add_child(replay)
