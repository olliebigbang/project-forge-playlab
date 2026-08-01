class_name MockWeaponImageGenerator
extends WeaponImageGenerator

const RENDERER := preload("res://scripts/systems/procedural_weapon_renderer.gd")
const RESOLVER := preload("res://scripts/systems/anchor_resolver.gd")

func generate(blueprint: WeaponBlueprint, _sketch_image: Image = null, geometry: Dictionary = {}) -> Dictionary:
	var image: Image = RENDERER.build_image(blueprint, geometry)
	if image == null or image.is_empty():
		return {"ok": false, "error": "LOCAL_PIXEL_GENERATION_FAILED"}
	var asset: WeaponVisualAsset = RESOLVER.resolve(image, blueprint)
	if asset == null:
		return {"ok": false, "error": "ALPHA_ANCHOR_RESOLUTION_FAILED"}
	var asset_dir := "user://playlab/assets/%s" % blueprint.id.validate_filename()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(asset_dir))
	image.save_png(asset_dir + "/original_generated.png")
	image.save_png(asset_dir + "/processed_sprite.png")
	return {"ok": true, "asset": asset, "source": "LOCAL PROCEDURAL PIXEL GENERATOR"}

