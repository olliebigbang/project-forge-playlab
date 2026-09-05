extends SceneTree
## Deterministic GPU capture of the meta-progression UI. This is a layout
## review, not a substitute for the normal-input expedition playtest.

const UI := preload("res://scripts/sunny_expedition/session.gd")
const META := preload("res://scripts/sunny_expedition/meta_progression.gd")
const RULES := preload("res://scripts/sunny_expedition/rules.gd")

var evidence := ""
var files: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	for key: String in ["ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY"]:
		OS.unset_environment(key)
	evidence = "res://.tools/sunny-meta-progression/%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(evidence)
	OS.set_environment("FORGE_WEAPON_LIBRARY_ROOT", evidence.path_join("isolated-library"))
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var ui := UI.new()
	ui.include_user_library = false
	root.add_child(ui)
	await process_frame
	ui.set_process(false)
	ui.arena.audio_enabled = false
	var advanced := {"schema": META.SCHEMA, "insight": 4, "completed_runs": 2, "mastered_families": ["broad_impact"]}
	ui.meta_progression = advanced.duplicate(true)
	ui.campaign["meta_progression"] = advanced.duplicate(true)
	ui._refresh_ui()
	await capture("01-hub-meta.png")
	ui.select_weapon(0)
	ui.start_story_run(14)
	await capture("02-story-route-choice.png")
	ui.choose_story_route("ridge")
	await capture("03-story-briefing.png")
	ui.return_to_forge()
	ui.start_trial_run(14)
	await capture("04-trial-briefing-meta.png")
	ui.begin_chapter()
	ui.arena.set_process(false)
	ui.arena.enemies.clear()
	ui.arena.spawn_tells.clear()
	ui.arena.seal_progress = RULES.SEAL_SECONDS
	ui.arena.player_position = ui.arena.seal_position
	ui.arena._objective_completion_allowed()
	await capture("05-upgrade-with-reroll.png")
	if ui.flow != "upgrade" or ui.pending_upgrade_choices.size() != 3:
		failures.append("upgrade dialog did not open")
	if ui.upgrade_reroll_button == null or not ui.upgrade_reroll_button.visible or ui.upgrade_reroll_button.disabled:
		failures.append("earned reroll is not visibly actionable")
	if not ui.dialog_body.text.contains("【进阶】"):
		failures.append("advanced pool is not visibly disclosed")
	var rerolled: Dictionary = ui.reroll_upgrade_choices()
	if not bool(rerolled.get("ok", false)):
		failures.append("visible reroll did not execute")
	await capture("06-rerolled-offer.png")
	ui.choose_upgrade(0)
	# Use a first-clear account for the result capture so the longest unlock line
	# is also layout-reviewed. Earlier captures already cover the advanced state.
	ui.meta_progression = META.empty()
	ui.campaign["meta_progression"] = ui.meta_progression.duplicate(true)
	ui._chapter_finished({"elapsed_seconds": 95.0, "defeated": 8, "damage_taken": 66.0, "upgrade_rerolls_used": 1})
	await capture("07-result-meta-reward.png")
	if ui.flow != "result" or not ui.dialog_body.text.contains("见闻 +") or not ui.dialog_body.text.contains("当前"):
		failures.append("result does not visibly explain meta reward")
	var report := {
		"real_gpu": true,
		"automatic_capture": true,
		"synthetic_layout_state": true,
		"normal_input_playtest": false,
		"online_calls": 0,
		"viewport": [1280, 720],
		"files": files,
		"failures": failures,
		"meta_after": ui.meta_progression,
		"rerolls_used": ui.arena.upgrade_rerolls_used,
	}
	var file := FileAccess.open(evidence.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("SUNNY_META_PROGRESSION_EVIDENCE ", ProjectSettings.globalize_path(evidence))
	ui.free()
	quit(0 if failures.is_empty() else 1)


func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := evidence.path_join(name)
	if root.get_texture().get_image().save_png(path) != OK:
		failures.append("capture failed: " + name)
	else:
		files.append(ProjectSettings.globalize_path(path))
