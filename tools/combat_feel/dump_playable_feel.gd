extends SceneTree

## Print what each playable asset actually compiles to, at the numbers the player receives.
##
## A human played three single-variable pairs and could not tell them apart. Before changing
## any design that is worth checking rather than assuming: an asset that reaches the compiler
## by the legacy path never gets a contact_resolution or a grip_topology at all, so it would
## carry the enum defaults and the comparison would have been between two identical things.
##
## Usage:
##     godot --headless --path <repo> --script res://tools/combat_feel/dump_playable_feel.gd

const LOADER := preload("res://scripts/combat_feel/combat_feel_asset_loader.gd")
const COMPILER := preload("res://scripts/combat_feel/melee_motion_compiler.gd")
const FEEDBACK := preload("res://scripts/combat_feel/impact_feedback_profile.gd")

# (label, how the runner reaches it, loader call, argument)
const ASSETS: Array = [
	["frying_pan", "-MotionGrammarAsset frying_pan", "motion_grammar", "frying_pan"],
	["old_mop", "-MotionGrammarAsset old_mop", "motion_grammar", "old_mop"],
	["shotgun_melee", "-MotionGrammarAsset shotgun_melee", "motion_grammar", "shotgun_melee"],
	["frying_pan (recipe)", "-RecipeAsset frying_pan", "recipe", "frying_pan"],
	["old_mop (recipe)", "-RecipeAsset old_mop", "recipe", "old_mop"],
	["giant_wooden_spoon", "-Weapon giant_wooden_spoon", "frozen", "giant_wooden_spoon"],
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=".repeat(78))
	print("What the player actually receives")
	print("=".repeat(78))
	for entry: Array in ASSETS:
		_report(str(entry[0]), str(entry[1]), str(entry[2]), str(entry[3]))
	quit(0)


func _report(label: String, how: String, kind: String, asset_id: String) -> void:
	var loader: Variant = LOADER.new()
	var loaded: Dictionary
	match kind:
		"motion_grammar": loaded = loader.load_motion_grammar_asset(asset_id)
		"recipe": loaded = loader.load_recipe_asset(asset_id)
		_: loaded = loader.load_frozen_live(asset_id)
	print("\n--- %s   (%s)" % [label, how])
	if not bool(loaded.get("ok", false)):
		print("    LOAD FAILED: %s" % str(loaded.get("error", "?")))
		return
	var affordance: Variant = loaded.get("affordance_profile")
	var asset: Variant = loaded.get("asset")
	if affordance == null:
		print("    no affordance profile -> LEGACY compile path")
		print("    contact_resolution and grip_topology are never assigned; both keep their")
		print("    enum defaults, so this asset carries no axis at all.")
		return
	var compiled: Variant = COMPILER.new().compile(affordance, asset.anchors_dict(), asset.opaque_bounds)
	if compiled is String:
		print("    COMPILE REFUSED: %s" % compiled)
		return
	var hit: Variant = FEEDBACK.for_attack(compiled, "normal", 1, compiled.combo_recipe.primitive_for(1))
	print("    tempo=%s  resolution=%s  grip=%s" % [
		compiled.tempo, compiled.contact_resolution, compiled.grip_topology])
	print("    hitstop=%.4fs  knockback=%.1f  recoil=%.1fdeg  sound=%s" % [
		hit.hitstop_seconds, hit.knockback_strength, hit.recoil_degrees, hit.sound_profile])
	print("    deflect=%.1fdeg  player_move=%+.1fpx" % [
		hit.weapon_deflect_degrees,
		float(hit.player_advance_pixels) - float(hit.player_pushback_pixels)])
