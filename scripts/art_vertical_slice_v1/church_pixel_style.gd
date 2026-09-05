class_name ChurchPixelStyle
extends RefCounted

# An opt-in rendering contract, not an object or combat recipe. Purple shadows,
# warm ramps and blue highlights sampled from the licensed Church source sheets;
# ivory/green material extensions keep arbitrary object identities recognisable.
const ID := "church_v1"
const VERSION := "church-pixel-v1.0"
const SUNNY_ID := "sunny_v1"
const SUNNY_VERSION := "sunny-pixel-v1.0"
const SUNNY_PALETTE := ["20383b", "314b45", "42645a", "648a63", "77be78", "b3d785", "f9e5b1", "e5c080", "bf8c4c", "8d573c", "59362e", "333e50", "50647c", "819baa", "b6cad1", "edf3e9", "3d778c", "48a7b0", "83d9cd", "bf6547", "e58d57", "f2bc76", "943f4b", "d26365", "37432b", "627337", "a4ad4b", "d8d281", "8c7587", "baa3a6", "efcfb7", "1b292d"]
const MAX_COLORS := 24
const PALETTE_HEX := [
	"1b0f2b", "161633", "32224c", "40295d", "603c83", "6c4a77", "8f6a9b", "b287c0", "c49eca",
	"331a19", "521e2f", "5e253c", "793d4e", "a4493e", "b15c51", "c56336", "e1924d", "d0a46d",
	"453c3c", "585651", "888c78", "a99d91", "ccc2ad", "eee0c0", "fff1d6",
	"bf0000", "e93100", "e95200", "ff9000", "ffc812", "ffeb0f", "d50964", "9c0565",
	"164f8c", "1664c5", "00b9ff", "00fff0", "315851", "4d7862", "78a46b", "b0c581",
	"1f1e47", "2d2c56", "3a3968", "41406f", "e28066", "a37e50", "79390a",
]

static func version(style_id: String) -> String:
	return SUNNY_VERSION if style_id == SUNNY_ID else (VERSION if style_id == ID else "")

static func contract(style_id: String) -> Dictionary:
	if style_id == SUNNY_ID:
		return {"id": SUNNY_ID, "version": SUNNY_VERSION, "prompt": "Fit a cheerful Sunny side-view pixel-art action game: warm sandy highlights, mint/teal and leaf-green accents, blue-grey metal and brown wood, crisp dark green-grey outlines. Broad clean pixel clusters, at most 24 flat opaque colors, no antialiasing, dithering, bloom, grain or painted texture. A small held object beside a roughly 40-pixel-tall character, not an oversized inventory illustration. Strict side view, transparent background, exactly one object. Keep its identity, real structural parts and recognizable material/accent colors; never turn a modern item into a fantasy weapon. Continuous readable thin/flexible parts. Upper-left daylight. Style changes appearance only, never object structure or mechanics."}
	if style_id != ID:
		return {}
	return {
		"id": ID, "version": VERSION,
		"prompt": "Fit a GothicVania Church side-view pixel-art game: restrained purple-blue shadows, warm ochre/ivory highlights, clear dark outlines and broad deliberate pixel clusters. A small held object beside a roughly 40-pixel-tall source character, never an inventory illustration with excessive micro-detail. Use at most 24 flat opaque colors; no antialiasing, gradients, dithering, bloom or painterly texture. Strict side view, one object only, transparent background. Preserve the described object's identity, distinctive material/accent colors and every declared structural part; do not medievalise a modern object, replace it with a fantasy weapon, or change its mechanics. For flexible/thin parts keep continuous readable strands. Lighting is upper-left; silhouette readability is more important than tiny detail.",
	}

static func palette(style_id: String = ID) -> Array[Color]:
	var colors: Array[Color] = []
	for hex: String in (SUNNY_PALETTE if style_id == SUNNY_ID else PALETTE_HEX):
		colors.append(Color.html(hex))
	return colors

static func normalize(source: Image, style_id: String) -> Dictionary:
	if style_id.is_empty():
		return {"ok": true, "image": source, "report": {"applied": false}}
	if contract(style_id).is_empty():
		return {"ok": false, "error": "ART_STYLE_UNKNOWN"}
	if source == null or source.is_empty() or source.get_size() != Vector2i(96, 96):
		return {"ok": false, "error": "ART_STYLE_CANVAS_INVALID"}
	var output := source.duplicate() as Image
	output.convert(Image.FORMAT_RGBA8)
	var colors := palette(style_id)
	var mapped := PackedInt32Array()
	mapped.resize(96 * 96)
	mapped.fill(-1)
	var counts := {}
	var opaque := 0
	# Preserve the exact provider-normalised Alpha mask: recolour, never inflate
	# a handle, erase a strand, invent a silhouette or move an anchor.
	for y: int in range(96):
		for x: int in range(96):
			var color := output.get_pixel(x, y)
			if color.a > 0.0 and color.a < 1.0:
				return {"ok": false, "error": "ART_STYLE_SOFT_ALPHA"}
			if color.a == 0.0:
				output.set_pixel(x, y, Color.TRANSPARENT)
				continue
			opaque += 1
			var index := _nearest(color, colors)
			mapped[y * 96 + x] = index
			counts[index] = int(counts.get(index, 0)) + 1
	if opaque == 0:
		return {"ok": false, "error": "ART_STYLE_EMPTY_SILHOUETTE"}
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool: return int(counts[a]) > int(counts[b]) if counts[a] != counts[b] else a < b)
	var selected: Array[Color] = []
	for index: int in ranked.slice(0, MAX_COLORS):
		selected.append(colors[index])
	for y: int in range(96):
		for x: int in range(96):
			var index := mapped[y * 96 + x]
			if index >= 0:
				output.set_pixel(x, y, selected[_nearest(colors[index], selected)])
	var report := inspect(output, style_id)
	report["alpha_preserved"] = true
	report["source_opaque_pixels"] = opaque
	report["normalization"] = "palette_only_before_anchors_and_mechanism_compile"
	return {"ok": bool(report.ok), "image": output, "report": report, "error": report.get("error", "")}

static func inspect(source: Image, style_id: String) -> Dictionary:
	if contract(style_id).is_empty() or source == null or source.get_size() != Vector2i(96, 96):
		return {"ok": false, "error": "ART_STYLE_INPUT_INVALID"}
	var allowed := {}
	for color: Color in palette(style_id): allowed[color.to_rgba32()] = true
	var unique := {}
	var opaque := 0
	for y: int in range(96):
		for x: int in range(96):
			var color := source.get_pixel(x, y)
			if color.a == 0.0: continue
			if color.a != 1.0: return {"ok": false, "error": "ART_STYLE_SOFT_ALPHA"}
			if not allowed.has(color.to_rgba32()): return {"ok": false, "error": "ART_STYLE_PALETTE_MISMATCH"}
			unique[color.to_rgba32()] = true
			opaque += 1
	if opaque == 0 or unique.size() > MAX_COLORS:
		return {"ok": false, "error": "ART_STYLE_COLOR_BUDGET_OR_EMPTY"}
	return {"ok": true, "applied": true, "id": style_id, "version": version(style_id), "opaque_pixels": opaque, "color_count": unique.size(), "max_colors": MAX_COLORS, "hard_alpha": true, "aesthetic_review": "not_automated", "conditioning": "text_contract_and_local_palette_not_image_reference"}

static func _nearest(color: Color, colors: Array[Color]) -> int:
	var best := 0
	var distance := INF
	for index: int in range(colors.size()):
		var other := colors[index]
		# Luma-weighted RGB: a fixed, deterministic art mapping, not AI evidence.
		var current := 0.30 * pow(color.r - other.r, 2) + 0.59 * pow(color.g - other.g, 2) + 0.11 * pow(color.b - other.b, 2)
		if current < distance:
			distance = current
			best = index
	return best
