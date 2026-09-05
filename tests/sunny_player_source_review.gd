extends SceneTree
const BASE := "res://assets/dead_revolver_player_v1/"
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const POSES := ["Idle", "Walk", "Run", "Combat/GunAim", "Combat/GunFire2H", "Combat/SwordIdle"]
const PARTS := ["Full", "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]
var output := "res://.tools/sunny-player/source-review"

class Sheet extends Node2D:
	var cells: Array[Dictionary] = []
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1008, 720), Color("26354d"))
		for cell: Dictionary in cells:
			draw_string(FONT, cell.pos + Vector2(4, 15), cell.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
			draw_texture_rect_region(cell.texture, Rect2(cell.pos + Vector2(28, 25), Vector2(80, 88)), Rect2(32, 40, 40, 44))

func _initialize() -> void:
	root.size = Vector2i(1008, 720)
	root.title = "Sunny source component inspection"
	var sheet := Sheet.new()
	sheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var records: Array[Dictionary] = []
	for row: int in POSES.size():
		var pose: String = POSES[row]
		for col: int in PARTS.size():
			var part: String = PARTS[col]
			var path := BASE + ("Sprites/" if part == "Full" else "SpritesSeparated/") + pose + "/" + ("" if part == "Full" else part + "/") + pose.get_file() + "01.png"
			var texture := load(path) as Texture2D
			if texture == null: continue
			var img := texture.get_image()
			sheet.cells.append({"texture": texture, "pos": Vector2(col * 144, row * 120), "label": pose.get_file() + "/" + part})
			var bounds := img.get_used_rect()
			records.append({"pose": pose, "part": part, "bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]})
	root.add_child(sheet)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var f := FileAccess.open(output.path_join("bounds.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(records, "\t"))
	_save.call_deferred()

func _save() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("parts.png"))
	print("SOURCE_REVIEW ", ProjectSettings.globalize_path(output))
	quit()
