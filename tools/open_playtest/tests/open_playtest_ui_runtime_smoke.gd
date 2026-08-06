extends SceneTree

const OPEN_PLAYTEST_UI := preload("res://tools/open_playtest/godot/open_playtest.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var screen_root := Control.new()
	root.add_child(screen_root)
	var open_playtest_ui := OPEN_PLAYTEST_UI.new()
	open_playtest_ui.set("screen_root", screen_root)
	open_playtest_ui.call("_show_heavy_melee_entry_prompt")
	var dialog: ConfirmationDialog = null
	for child: Node in screen_root.get_children():
		if child is ConfirmationDialog:
			dialog = child as ConfirmationDialog
			break
	if dialog == null:
		_fail("HEAVY_MELEE_CONFIRMATION_DIALOG_NOT_CREATED")
		return
	if dialog.ok_button_text != "进入近战手感测试" or dialog.cancel_button_text != "稍后":
		_fail("HEAVY_MELEE_CONFIRMATION_ACTIONS_INVALID")
		return
	print("OPEN_PLAYTEST_UI_RUNTIME_SMOKE=PASS")
	open_playtest_ui.free()
	screen_root.free()
	quit(0)


func _fail(reason: String) -> void:
	printerr("OPEN_PLAYTEST_UI_RUNTIME_SMOKE=FAIL REASON=%s" % reason)
	quit(2)
