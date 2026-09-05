shader_type canvas_item;
render_mode unshaded;
// Render-time alpha cutout: generated source contains a soft preview halo.
// Keep the original PNG, but never blend that halo into game sprites.
void fragment() {
    // CanvasItem COLOR already includes texture and vertex modulation.
    vec4 source = COLOR;
    if (source.a < 0.94) discard;
    COLOR = vec4(source.rgb, 1.0);
}
