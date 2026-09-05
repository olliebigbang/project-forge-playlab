extends SceneTree
const AXES := preload("res://scripts/combat_feel/ranged_mechanism_axis_resolver.gd")
const FIT := preload("res://scripts/combat_feel/weapon_player_fit_compiler.gd")
const INTERPRETER := preload("res://scripts/services/open_identity_interpreter.gd")
var passed := 0
var failed := 0
func check(label: String, value: bool) -> void:
	if value: passed += 1
	else: failed += 1; printerr("FAIL | ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var axes: Dictionary = {"layout": "conventional_rifle", "firearm_family": "submachine_gun", "stock_structure": "none", "support_mode": "two_hand_free", "feed_position": "ahead_of_grip", "magazine_shape": "curved", "barrel_length": "short", "upper_profile": "top_rail"}
	var errors := AXES._combination_errors(axes)
	check("stockless free two-hand layout valid", errors.is_empty())
	axes.support_mode = "two_hand_shouldered"; errors = AXES._combination_errors(axes)
	check("no fabricated shoulder stock", "AI_RANGED_STRUCTURE_CONFLICT:CONVENTIONAL" in errors)
	var bp := WeaponBlueprint.new(); bp.affordance = {"weapon_domain": "handheld_firearm", "support_mode": "two_hand_free"}
	var asset := WeaponVisualAsset.new(); asset.opaque_bounds = Rect2i(0,0,82,30); asset.grip_primary = Vector2(20,20); asset.grip_secondary = Vector2(40,20)
	check("free two-hand requires actual supporting hand", FIT.compile(bp, asset).support_required)
	print("STOCKLESS_SUPPORT passed=%d failed=%d" % [passed, failed]); quit(0 if failed == 0 else 1)
