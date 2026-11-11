shader_type canvas_item;
render_mode unshaded;

uniform vec4 body_color : source_color = vec4(0.20, 0.36, 0.35, 1.0);
uniform vec4 edge_color : source_color = vec4(0.98, 0.93, 0.78, 1.0);
// Fallback when the echo carries no per-instance edge (modulate red = 1).
uniform float edge_pixels = 6.0;

// The edge width rides in the echo's self_modulate red channel (pixels / 16),
// so every echo of an owner shares one material and the echoes batch.
varying float edge_from_modulate;

void vertex() {
	edge_from_modulate = COLOR.r < 0.999 ? COLOR.r * 16.0 : edge_pixels;
}

void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	vec2 step_uv = TEXTURE_PIXEL_SIZE * edge_from_modulate;
	float inside = min(texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a, texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a);
	inside = min(inside, texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a);
	inside = min(inside, texture(TEXTURE, UV - vec2(0.0, step_uv.y)).a);
	float edge = clamp((alpha - inside) * 2.0, 0.0, 1.0);
	// Interior-only edge: no new geometry or target/selection footprint.
	COLOR = vec4(mix(body_color.rgb, edge_color.rgb, edge), alpha * mix(0.22, 0.92, edge));
}
