extends SceneTree
const RIG := preload("res://scripts/authored_player/source_rig.gd")
func _initialize() -> void:
	var rig := RIG.new()
	for key: String in ["combat/SwordCombo03", "combat/StandingSlash", "combat/SwordSlash01", "combat/SwordIdle", "combat/GunAim", "body/Idle"]:
		var tag: Dictionary = rig.metadata[key.get_slice("/", 0)].tags[key.get_slice("/", 1)]
		for i: int in range(mini(2, int(tag.last) - int(tag.first) + 1)):
			var frame := rig.frame(key, i)
			var out := {"key":key,"frame":i,"primary":frame.primary,"support":frame.support}
			for part: String in frame.images: out[part] = frame.images[part].get_used_rect()
			print(JSON.stringify(out))
	quit()
