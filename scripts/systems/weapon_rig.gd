class_name WeaponRig
extends Node2D

var sprite: Sprite2D
var grip_primary: Marker2D
var grip_secondary: Marker2D
var muzzle: Marker2D
var tip: Marker2D
var spin_pivot: Marker2D
var effects: Node2D
var debug_overlay: Node2D

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	add_child(sprite)
	grip_primary = _marker("GripPrimary")
	grip_secondary = _marker("GripSecondary")
	muzzle = _marker("Muzzle")
	tip = _marker("Tip")
	spin_pivot = _marker("SpinPivot")
	effects = Node2D.new()
	effects.name = "Effects"
	add_child(effects)
	debug_overlay = Node2D.new()
	debug_overlay.name = "DebugOverlay"
	add_child(debug_overlay)

func mount_asset(asset: WeaponVisualAsset) -> void:
	if sprite == null:
		_ready()
	sprite.texture = asset.texture
	sprite.centered = false
	grip_primary.position = asset.grip_primary
	grip_secondary.position = asset.grip_secondary
	muzzle.position = asset.muzzle
	tip.position = asset.tip
	spin_pivot.position = asset.spin_pivot
	position = -asset.grip_primary

func _marker(marker_name: String) -> Marker2D:
	var marker := Marker2D.new()
	marker.name = marker_name
	add_child(marker)
	return marker

