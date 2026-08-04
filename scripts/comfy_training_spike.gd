extends Node2D

const GAMEPLAY_ARENA := preload("res://scripts/systems/gameplay_arena.gd")
const MOCK_PROVIDER := preload("res://scripts/services/mock_forge_visual_provider.gd")
const LOCAL_PROVIDER := preload("res://scripts/services/local_comfy_forge_visual_provider.gd")
const MODE_MOCK := "MOCK"
const MODE_LOCAL_COMFYUI := "LOCAL_COMFYUI"

var arena: GameplayArena
var provider
var blueprint: WeaponBlueprint
var status_label: Label
var mode := MODE_MOCK
var capture_path := ""
var capture_frames := -1
var started_training := false
var last_provider_status := ""

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("07111f"))
	blueprint = WeaponBlueprint.fixed_blueprint("gatling")
	_parse_arguments()
	arena = GAMEPLAY_ARENA.new() as GameplayArena
	add_child(arena)
	arena.visible = false
	_build_overlay()
	if mode == MODE_LOCAL_COMFYUI:
		_start_local()
	else:
		_start_mock()

func _process(_delta: float) -> void:
	if not started_training and provider != null:
		var result: Dictionary = provider.poll()
		var provider_status := str(result.get("status", "idle"))
		if provider_status != last_provider_status:
			last_provider_status = provider_status
			print("SPIKE_PROVIDER_STATUS=%s REASON=%s" % [provider_status, str(result.get("failure_reason", ""))])
		match provider_status:
			"running":
				status_label.text = "LOCAL_COMFYUI：正在生成并进行透明 Alpha 校验…"
			"success":
				_start_training(result.get("asset") as WeaponVisualAsset, str(result.get("output_directory", "")))
			"failed":
				status_label.text = "LOCAL_COMFYUI 失败：%s\n玩家输入仍保留。按 M 明确切换到 Mock。" % str(result.get("failure_reason", "UNKNOWN"))
	if capture_frames >= 0:
		capture_frames -= 1
		if capture_frames == 0:
			var image := get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
			var capture_error := image.save_png(capture_path)
			print("SPIKE_CAPTURE=%s ERROR=%d SIZE=%s" % [capture_path, capture_error, image.get_size()])
			get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M and not started_training:
		if provider != null:
			provider.cancel_current()
		mode = MODE_MOCK
		_start_mock()

func _start_local() -> void:
	var local_provider = LOCAL_PROVIDER.new()
	provider = local_provider
	var config_result: Dictionary = local_provider.configure(_argument_value("--comfy-config=", "res://tools/comfyui/config/forge_comfy_config.local.json"))
	if not bool(config_result.get("ok", false)):
		status_label.text = "LOCAL_COMFYUI 配置错误：%s\n按 M 明确切换到 Mock。" % str(config_result.get("error", "UNKNOWN"))
		return
	var result_directory := _argument_value("--comfy-result=", "")
	if not result_directory.is_empty():
		var result: Dictionary = local_provider.load_atomic_result(result_directory, blueprint)
		if str(result.get("status", "")) == "success":
			_start_training(result.get("asset") as WeaponVisualAsset, result_directory)
		else:
			status_label.text = "LOCAL_COMFYUI 结果加载失败：%s" % str(result.get("failure_reason", "UNKNOWN"))
		return
	var health: Dictionary = local_provider.health_check()
	if not bool(health.get("ok", false)):
		status_label.text = "LOCAL_COMFYUI 不可用：%s\n按 M 明确切换到 Mock。" % str(health.get("error", "HEALTH_CHECK_FAILED"))
		return
	var prompt := _argument_value("--prompt=", "一把冒蓝火、会连续射击的重型多管物件。")
	var sketch_png := PackedByteArray()
	var sketch_path := _argument_value("--sketch=", "")
	if not sketch_path.is_empty() and FileAccess.file_exists(sketch_path):
		sketch_png = FileAccess.get_file_as_bytes(sketch_path)
	local_provider.request_visual(blueprint, prompt, sketch_png, 0.45)
	status_label.text = "LOCAL_COMFYUI：请求已提交（120 秒超时）"

func _start_mock() -> void:
	provider = MOCK_PROVIDER.new()
	provider.request_visual(blueprint, "", PackedByteArray())
	status_label.text = "MOCK：本地程序化视觉"

func _start_training(asset: WeaponVisualAsset, output_directory: String) -> void:
	if asset == null:
		status_label.text = "视觉资源为空，训练区未启动。"
		return
	started_training = true
	arena.visible = true
	arena.debug_anchors = true
	arena.start_stage("training", blueprint, asset)
	var display_directory := output_directory.replace("\\", "/")
	var output_marker := "tools/comfyui/output/"
	var marker_index := display_directory.find(output_marker)
	if marker_index >= 0:
		display_directory = display_directory.substr(marker_index)
	status_label.text = "%s｜仅训练区｜96×96 Alpha 已验证\n%s" % [mode, display_directory]
	if not capture_path.is_empty():
		capture_frames = 24

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.07, 0.12, 0.92)
	panel.position = Vector2(18, 14)
	panel.size = Vector2(1244, 88)
	layer.add_child(panel)
	var title := Label.new()
	title.text = "FORGE OBJECT SPRITE GENERATION SPIKE 0"
	title.position = Vector2(20, 8)
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	status_label = Label.new()
	status_label.position = Vector2(20, 41)
	status_label.size = Vector2(1200, 44)
	status_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(status_label)

func _parse_arguments() -> void:
	mode = _argument_value("--visual-provider=", MODE_MOCK).to_upper()
	if mode not in [MODE_MOCK, MODE_LOCAL_COMFYUI]:
		mode = MODE_MOCK
	capture_path = _argument_value("--capture-path=", "")

func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
