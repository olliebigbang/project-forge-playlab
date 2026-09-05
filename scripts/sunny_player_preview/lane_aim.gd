extends RefCounted
## Side-view characters retain ground depth. Height correction is not a
## licence to aim into a different lane, turn around, or enlarge hitboxes.
const LANE_HALF_WIDTH := 30.0
const MAX_ANGLE := deg_to_rad(62.0)
const MAX_DISTANCE := 1000.0

static func select_target(player: Vector2, facing: float, enemies: Array[Dictionary], previous_id: String = "") -> Dictionary:
	var selected: Dictionary = {}
	var best := INF
	for enemy: Dictionary in enemies:
		if float(enemy.get("hp", 0.0)) <= 0.0: continue
		var relative := Vector2(enemy.pos) - player
		if relative.x * facing < 22.0 or relative.x * facing > MAX_DISTANCE: continue
		if absf(relative.y) > LANE_HALF_WIDTH: continue
		var score := absf(relative.x) + absf(relative.y) * 2.0
		if str(enemy.get("id", "")) == previous_id: score -= 30.0
		if score < best:
			best = score
			selected = enemy
	return selected

static func angle_to_target(muzzle: Vector2, target: Vector2, facing: float) -> float:
	var delta := target - muzzle
	return clampf(atan2(delta.y, maxf(8.0, delta.x * facing)), -MAX_ANGLE, MAX_ANGLE) * facing
