extends RefCounted
## Apply to all reusable pages, not just the combat HUD. No copied UI logic.
static func box(fill: Color, border: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill; result.border_color = border
	result.set_border_width_all(2)
	result.set_content_margin_all(8)
	return result

static func apply(node: Node) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", Color("20383b"))
		node.text = node.text.replace("此阵眼", "此路标")
	if node is Panel or node is PanelContainer:
		node.add_theme_stylebox_override("panel", box(Color("f9e5b1"), Color("648a63")))
	if node is Button:
		for state: String in ["normal", "hover", "focus", "pressed", "disabled"]:
			node.add_theme_stylebox_override(state, box(Color("77be78") if state == "pressed" else (Color("b3d785") if state == "hover" else (Color("d5d0b0") if state == "disabled" else Color("f9e5b1"))), Color("42645a")))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: node.add_theme_color_override(state, Color("20383b"))
		node.add_theme_color_override("font_disabled_color", Color("819079"))
	if node is TextEdit:
		node.add_theme_color_override("font_color", Color("20383b"))
		node.add_theme_color_override("font_placeholder_color", Color("648a63"))
		node.add_theme_color_override("caret_color", Color("20383b"))
		for state: String in ["normal", "focus"]: node.add_theme_stylebox_override(state, box(Color("edf3e9"), Color("648a63")))
	if node is ColorRect: node.color = Color("e5c080") if node.color.a > 0.9 else Color(0.12, 0.25, 0.23, 0.72)
	for child: Node in node.get_children(): apply(child)
