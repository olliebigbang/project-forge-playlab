extends SceneTree

const BLUEPRINT := preload("res://scripts/data/weapon_blueprint.gd")
const SEMANTIC_RESOLVER := preload("res://scripts/systems/semantic_anchor_resolver.gd")

const TARGETS_PATH := "res://tools/comfyui/anchor_calibration/test_cases/calibration_targets.json"
const REPORT_JSON_PATH := "res://tools/comfyui/anchor_calibration/reports/evaluation.json"
const REPORT_MD_PATH := "res://tools/comfyui/anchor_calibration/reports/SPIKE1_REPORT.md"
const OUTPUT_ROOT := "res://tools/comfyui/anchor_calibration/output"
const REQUIRED_SAVED_FIELDS: Array[String] = [
	"auto_anchors",
	"corrected_anchors",
	"anchor_source",
	"confidence",
	"required_anchor_types",
]
const ADJUSTABLE_TOLERANCE_PX := 9.0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_evaluate")

func _evaluate() -> void:
	var targets := _read_json(TARGETS_PATH)
	if targets.is_empty():
		_fail("calibration target file is missing or invalid")
		_finish({})
		return
	var runs: Array = targets.get("runs", [])
	if runs.size() != 11:
		_fail("expected 11 existing successful sprites, found %d" % runs.size())
	var seen: Dictionary = {}
	var spike0_hashes: Dictionary = {}
	for value: Variant in runs:
		var entry := value as Dictionary
		var key := _entry_key(entry)
		if seen.has(key):
			_fail("duplicate corpus entry: %s" % key)
		seen[key] = true
		var legacy_path := str(entry.get("sprite_path", "")).get_base_dir().path_join("anchors.json")
		if FileAccess.file_exists(legacy_path):
			spike0_hashes[legacy_path] = FileAccess.get_md5(legacy_path)

	var per_run: Array[Dictionary] = []
	var adjustable_correct := 0
	var adjustable_total := 0
	var auto_usable_count := 0
	var final_usable_count := 0
	var flipped_count := 0
	for value: Variant in runs:
		var entry := value as Dictionary
		var result := _evaluate_run(entry)
		per_run.append(result)
		adjustable_correct += int(result.get("auto_adjustable_correct", 0))
		adjustable_total += int(result.get("auto_adjustable_total", 0))
		auto_usable_count += 1 if bool(result.get("auto_usable", false)) else 0
		final_usable_count += 1 if bool(result.get("final_usable", false)) else 0
		flipped_count += 1 if bool(result.get("training_flip_x", false)) else 0

	for legacy_path: String in spike0_hashes.keys():
		if FileAccess.get_md5(legacy_path) != str(spike0_hashes[legacy_path]):
			_fail("Spike 0 anchor file changed: %s" % legacy_path)
	var report := {
		"schema_version": 1,
		"spike": "Forge Semantic Anchor Calibration Spike 1",
		"source_sprite_count": runs.size(),
		"source_policy": {
			"existing_spike0_sprites_only": true,
			"comfyui_started": false,
			"spike0_anchor_files_unchanged": failures.filter(func(reason: String) -> bool: return reason.begins_with("Spike 0 anchor file changed")).is_empty(),
		},
		"metric_definition": {
			"auto_adjustable_anchor_accuracy": "GripPrimary plus EffectOrigin/StrikePoint within %.1f px of manual visual-review point" % ADJUSTABLE_TOLERANCE_PX,
			"auto_usable": "all adjustable anchors accurate, derived anchors geometrically valid, and reviewer confirms the sprite has usable semantics",
			"final_usable": "the fixed visual-review points pass through the same set_manual_anchor/recompute/save path, derived anchors and copied asset validate, and the reviewer confirms usable semantics",
			"ui_flow_scope": "A separate deterministic UI event test covers outside-press rejection, GripPrimary click-drag, step confirmation, EffectOrigin click, completion, and auto-confidence restoration. The 11-run percentage is a corpus calibration result, not 11 recorded GUI sessions.",
		},
		"auto_adjustable_anchor_accuracy": _ratio(adjustable_correct, adjustable_total),
		"auto_usable_rate": _ratio(auto_usable_count, runs.size()),
		"final_usable_after_calibration_rate": _ratio(final_usable_count, runs.size()),
		"orientation_normalized_count": flipped_count,
		"results": per_run,
		"failures": failures.duplicate(),
	}
	_write_text_atomic(REPORT_JSON_PATH, JSON.stringify(report, "  ") + "\n")
	_write_text_atomic(REPORT_MD_PATH, _build_markdown(report))
	_finish(report)

func _evaluate_run(entry: Dictionary) -> Dictionary:
	var key := _entry_key(entry)
	var sprite_path := str(entry.get("sprite_path", ""))
	if not FileAccess.file_exists(sprite_path):
		_fail("sprite missing: %s" % sprite_path)
		return {"run": key, "error": "SPRITE_MISSING"}
	var image := Image.load_from_file(ProjectSettings.globalize_path(sprite_path))
	if image == null or image.get_size() != Vector2i(96, 96):
		_fail("sprite must be readable 96x96 PNG: %s" % sprite_path)
		return {"run": key, "error": "INVALID_SPRITE"}
	var original_pixels := image.get_data()
	var blueprint := BLUEPRINT.new() as WeaponBlueprint
	blueprint.id = "semantic_eval_%s" % key.replace("/", "_")
	blueprint.display_name = "Semantic anchor calibration sample"
	blueprint.behavior_family = str(entry.get("behavior_family", "sustained_ranged"))
	blueprint.grip_profile = str(entry.get("grip_profile", "rear_grip"))
	blueprint.validate_and_repair()
	var calibration = SEMANTIC_RESOLVER.resolve(image, blueprint)
	if calibration == null:
		_fail("semantic resolver rejected sprite: %s" % key)
		return {"run": key, "error": "RESOLVER_REJECTED"}
	calibration.case_id = str(entry.get("case_id", ""))
	calibration.run_id = str(entry.get("run_id", ""))
	calibration.source_sprite = sprite_path

	var declared_required := _string_array(entry.get("required_anchor_types", []))
	if not _same_string_set(calibration.required_anchor_types, declared_required):
		_fail("required anchor declaration mismatch: %s" % key)
	var manual_points := _point_dictionary(entry.get("manual_points", {}))
	var auto_point_results: Dictionary = {}
	var auto_adjustable_correct := 0
	for anchor_type: String in manual_points.keys():
		var auto_point: Vector2 = calibration.auto_anchors.get(anchor_type, Vector2(-999, -999))
		var expected: Vector2 = manual_points[anchor_type]
		var distance := auto_point.distance_to(expected)
		var accurate := distance <= ADJUSTABLE_TOLERANCE_PX
		auto_point_results[anchor_type] = {
			"auto": _point_array(auto_point),
			"manual_reference": _point_array(expected),
			"distance_px": snappedf(distance, 0.01),
			"accurate": accurate,
		}
		auto_adjustable_correct += 1 if accurate else 0
	var auto_derived := _derived_checks(calibration, image, entry, false)
	var reviewer_usable := bool(entry.get("reviewer_usable_after_calibration", true))
	var auto_usable := auto_adjustable_correct == manual_points.size() and bool(auto_derived.get("passed", false)) and reviewer_usable

	var point_confidence: Dictionary = entry.get("point_confidence", {})
	for anchor_type: String in manual_points.keys():
		calibration.set_manual_anchor(anchor_type, manual_points[anchor_type], float(point_confidence.get(anchor_type, 0.95)))
	SEMANTIC_RESOLVER.recompute_derived(calibration, image)
	var final_derived := _derived_checks(calibration, image, entry, true)
	var asset: WeaponVisualAsset = calibration.build_asset_copy()
	var action_type := "EffectOrigin" if calibration.required_anchor_types.has("EffectOrigin") else "StrikePoint"
	var final_geometry: bool = calibration.validation_errors().is_empty()
	final_geometry = final_geometry and SEMANTIC_RESOLVER.is_on_or_near_alpha(image, calibration.anchor_point("GripPrimary"), 4)
	final_geometry = final_geometry and SEMANTIC_RESOLVER.is_on_or_near_alpha(image, calibration.anchor_point(action_type), 8)
	final_geometry = final_geometry and bool(final_derived.get("passed", false))
	final_geometry = final_geometry and asset != null and asset.canvas_size == Vector2i(96, 96)
	if asset != null:
		var action_training: Vector2 = calibration.training_anchor_point(action_type)
		final_geometry = final_geometry and action_training.x >= calibration.training_anchor_point("GripPrimary").x
	final_geometry = final_geometry and image.get_data() == original_pixels
	var final_usable: bool = final_geometry and reviewer_usable

	var output_path := "%s/%s/%s/semantic_anchors.json" % [OUTPUT_ROOT, calibration.case_id, calibration.run_id]
	var save_error: Error = calibration.save_json(output_path)
	if save_error != OK:
		_fail("calibration sidecar save failed for %s: %s" % [key, error_string(save_error)])
		final_usable = false
	else:
		_validate_saved_sidecar(output_path, calibration.required_anchor_types, key)

	return {
		"run": key,
		"sprite_path": sprite_path,
		"required_anchor_types": calibration.required_anchor_types.duplicate(),
		"auto_point_results": auto_point_results,
		"auto_adjustable_correct": auto_adjustable_correct,
		"auto_adjustable_total": manual_points.size(),
		"auto_derived": auto_derived,
		"auto_usable": auto_usable,
		"corrected_anchors": calibration.to_dict().get("corrected_anchors", {}),
		"final_derived": final_derived,
		"final_geometry_pass": final_geometry,
		"reviewer_usable_after_calibration": reviewer_usable,
		"final_usable": final_usable,
		"training_flip_x": bool(calibration.training_transform.get("flip_x", false)),
		"output_sidecar": output_path,
		"limitations": entry.get("limitations", []),
	}

func _derived_checks(calibration: RefCounted, image: Image, entry: Dictionary, corrected: bool) -> Dictionary:
	var passed := true
	var details: Dictionary = {}
	var anchors: Dictionary = calibration.corrected_anchors if corrected else calibration.auto_anchors
	if calibration.required_anchor_types.has("GripSecondary"):
		var primary: Vector2 = calibration.anchor_point("GripPrimary") if corrected else anchors.get("GripPrimary", Vector2.ZERO)
		var secondary: Vector2 = calibration.anchor_point("GripSecondary") if corrected else anchors.get("GripSecondary", Vector2.ZERO)
		var distance := primary.distance_to(secondary)
		var on_alpha := SEMANTIC_RESOLVER.is_on_or_near_alpha(image, secondary, 2)
		var secondary_pass := on_alpha and distance >= 6.0 and distance <= 30.0
		details["GripSecondary"] = {
			"point": _point_array(secondary),
			"distance_from_primary": snappedf(distance, 0.01),
			"on_alpha": on_alpha,
			"passed": secondary_pass,
		}
		passed = passed and secondary_pass
	if calibration.required_anchor_types.has("SpinPivot"):
		var pivot: Vector2 = calibration.anchor_point("SpinPivot") if corrected else anchors.get("SpinPivot", Vector2.ZERO)
		var expected := SEMANTIC_RESOLVER.alpha_centroid(image)
		var reviewer_reference: Dictionary = entry.get("reviewer_reference", {})
		if reviewer_reference.has("spin_pivot_alpha_centroid_exact"):
			expected = _pair_to_point(reviewer_reference["spin_pivot_alpha_centroid_exact"])
		var distance := pivot.distance_to(expected)
		var pivot_pass := distance <= 0.05
		details["SpinPivot"] = {
			"point": _point_array(pivot),
			"alpha_centroid": _point_array(expected),
			"distance_px": snappedf(distance, 0.001),
			"passed": pivot_pass,
		}
		passed = passed and pivot_pass
	return {"passed": passed, "details": details}

func _validate_saved_sidecar(path: String, required: Array[String], key: String) -> void:
	var saved := _read_json(path)
	for field: String in REQUIRED_SAVED_FIELDS:
		if not saved.has(field):
			_fail("saved sidecar missing %s for %s" % [field, key])
	var corrected: Dictionary = saved.get("corrected_anchors", {})
	for anchor_type: String in required:
		if not corrected.has(anchor_type):
			_fail("saved sidecar missing corrected %s for %s" % [anchor_type, key])

func _build_markdown(report: Dictionary) -> String:
	var auto_accuracy: Dictionary = report.get("auto_adjustable_anchor_accuracy", {})
	var auto_usable: Dictionary = report.get("auto_usable_rate", {})
	var final_usable: Dictionary = report.get("final_usable_after_calibration_rate", {})
	var lines: Array[String] = [
		"# Forge Semantic Anchor Calibration Spike 1",
		"",
		"> 独立训练区验证；仅使用 Spike 0 已有的 11 张透明 Sprite。未启动 ComfyUI，未生成新图，未接入房间或正式战斗。",
		"",
		"## 结论",
		"",
		"- 自动可调锚点准确率：**%d/%d（%.1f%%）**。" % [auto_accuracy.get("passed", 0), auto_accuracy.get("total", 0), auto_accuracy.get("percent", 0.0)],
		"- 完全自动可用率：**%d/%d（%.1f%%）**。" % [auto_usable.get("passed", 0), auto_usable.get("total", 0), auto_usable.get("percent", 0.0)],
		"- 固定人工复核点经两步校准接口后最终可用率：**%d/%d（%.1f%%）**。" % [final_usable.get("passed", 0), final_usable.get("total", 0), final_usable.get("percent", 0.0)],
		"- 左向素材被派生资产水平归一化：**%d** 张；原始 Sprite 未改写。" % int(report.get("orientation_normalized_count", 0)),
		"",
		"准确率按 96×96 图上 `GripPrimary` 与 `EffectOrigin/StrikePoint` 距人工视觉复核点不超过 %.1f px 计算；派生的 `GripSecondary` 与 `SpinPivot` 单独做 Alpha 几何检查。11 张的校准后比例来自固定复核坐标通过同一校准/保存接口的批量验证，不冒充 11 次录制的 GUI 会话；点击、拖动、分步确认与画布外起拖拒绝由独立自动 UI 事件测试覆盖。" % ADJUSTABLE_TOLERANCE_PX,
		"",
		"## 逐张结果",
		"",
		"| Sprite | 行为所需锚点 | 自动点 | 自动可用 | 校准后可用 | 训练派生翻转 |",
		"|---|---|---:|:---:|:---:|:---:|",
	]
	for value: Variant in report.get("results", []):
		var result := value as Dictionary
		lines.append("| %s | %s | %d/%d | %s | %s | %s |" % [
			str(result.get("run", "")),
			", ".join(result.get("required_anchor_types", [])),
			int(result.get("auto_adjustable_correct", 0)),
			int(result.get("auto_adjustable_total", 0)),
			"✓" if bool(result.get("auto_usable", false)) else "—",
			"✓" if bool(result.get("final_usable", false)) else "—",
			"✓" if bool(result.get("training_flip_x", false)) else "—",
		])
	lines.append_array([
		"",
		"## 失败层与边界",
		"",
		"- `case_d/seed_41003_s45` 即使完成两点校准，仍没有可信的可见发射/力量出口，因此按视觉语义复核判为不可用；不以继续调参或伪造枪口掩盖。",
		"- `GripSecondary` 仅在双手行为声明下，按主握点朝 Alpha 质心方向搜索实体区域；玩家不需要逐件设置。",
		"- `SpinPivot` 仅在回旋行为声明下使用二值 Alpha 质心；不要求玩家点击。",
		"- `StrikePoint` 与 `SpinPivot` 在此 Spike 中由 Forge 覆盖层验证；现有战斗规则未被修改，因此本报告不声称它们已成为新的玩法机制。",
		"- 运行时只向既有 `GameplayArena.start_stage(\"training\", ...)` 交付复制出的校准资产；默认 Mock、房间一/二和 V2 均保持原状。",
		"",
		"## 视觉证据",
		"",
		"- `calibration_ui.png`：步骤 1、旧自动建议灰圈、Forge 握持夹具与作用符文。",
		"- `calibration_step2.png`：家具 Sprite 的步骤 2 `EffectOrigin` 人工校准。",
		"- `two_hand_strike.png`：双手行为的主/副握持夹具与 `StrikePoint`；副握点为 Alpha 派生。",
		"- `returning_spin.png`：回旋行为的 `GripPrimary`、Alpha 质心 `SpinPivot` 与 `StrikePoint`。",
		"- `training_zone.png`：校准资产、夹具和作用符文仅在既有训练区挂载。",
		"- `test_run.txt`：Godot 解析、25 项回归/UI 事件测试及 11-Sprite 评估的可追溯输出。",
		"",
		"## 产物",
		"",
		"每张 Sprite 的独立 sidecar 位于 `tools/comfyui/anchor_calibration/output/<case_id>/<run_id>/semantic_anchors.json`，包含 `auto_anchors`、完整 `corrected_anchors`、`anchor_source`、`confidence` 与 `required_anchor_types`。",
		"",
	])
	return "\n".join(lines)

func _ratio(passed: int, total: int) -> Dictionary:
	return {
		"passed": passed,
		"total": total,
		"percent": snappedf(float(passed) * 100.0 / float(maxi(1, total)), 0.1),
	}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}

func _write_text_atomic(path: String, content: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		_fail("cannot create report directory: %s" % error_string(error))
		return
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_fail("cannot write report: %s" % path)
		return
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	var promote_error := DirAccess.rename_absolute(temporary, absolute)
	if promote_error != OK:
		_fail("cannot promote report: %s" % error_string(promote_error))

func _point_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for key: String in (value as Dictionary).keys():
		result[key] = _pair_to_point((value as Dictionary)[key])
	return result

func _pair_to_point(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO

func _point_array(point: Vector2) -> Array[float]:
	return [snappedf(point.x, 0.001), snappedf(point.y, 0.001)]

func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(str(item))
	return result

func _same_string_set(first: Array[String], second: Array[String]) -> bool:
	if first.size() != second.size():
		return false
	for item: String in first:
		if not second.has(item):
			return false
	return true

func _entry_key(entry: Dictionary) -> String:
	return "%s/%s" % [entry.get("case_id", ""), entry.get("run_id", "")]

func _fail(reason: String) -> void:
	failures.append(reason)
	printerr("SPIKE1_FAIL | %s" % reason)

func _finish(report: Dictionary) -> void:
	if not report.is_empty():
		var auto_accuracy: Dictionary = report.get("auto_adjustable_anchor_accuracy", {})
		var auto_usable: Dictionary = report.get("auto_usable_rate", {})
		var final_usable: Dictionary = report.get("final_usable_after_calibration_rate", {})
		print("SPIKE1_AUTO_ANCHORS=%d/%d (%.1f%%)" % [auto_accuracy.get("passed", 0), auto_accuracy.get("total", 0), auto_accuracy.get("percent", 0.0)])
		print("SPIKE1_AUTO_USABLE=%d/%d (%.1f%%)" % [auto_usable.get("passed", 0), auto_usable.get("total", 0), auto_usable.get("percent", 0.0)])
		print("SPIKE1_FINAL_USABLE=%d/%d (%.1f%%)" % [final_usable.get("passed", 0), final_usable.get("total", 0), final_usable.get("percent", 0.0)])
	print("SPIKE1_RESULT=%s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
