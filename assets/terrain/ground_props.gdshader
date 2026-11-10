shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// Every ground prop on the field is one MultiMesh draw. INSTANCE_CUSTOM:
// x = atlas cell, y = wind sway in mesh pixels, z = phase, w = 1 for a
// butterfly (flutters around its anchor instead of swaying).
uniform float motion = 1.0;
uniform vec2 atlas_cells = vec2(8.0, 4.0);
const float ROOT_V = 0.875;

void vertex() {
	float cell = floor(INSTANCE_CUSTOM.x + 0.5);
	float t = TIME * motion;
	float phase = INSTANCE_CUSTOM.z;
	if (INSTANCE_CUSTOM.w > 0.5) {
		float flap = 0.30 + 0.70 * abs(sin(t * 11.0 + phase));
		VERTEX.x *= mix(1.0, flap, motion);
		VERTEX += vec2(sin(t * 0.55 + phase) * 17.0 + sin(t * 1.9 + phase * 2.3) * 4.0,
			sin(t * 0.83 + phase * 1.7) * 7.0 + sin(t * 2.6 + phase) * 2.0 - 9.0);
	} else {
		float lean = sin(t * 1.35 + phase) + 0.45 * sin(t * 2.9 + phase * 1.7);
		VERTEX.x += lean * motion * INSTANCE_CUSTOM.y * (ROOT_V - UV.y) / ROOT_V;
	}
	UV = (vec2(mod(cell, atlas_cells.x), floor(cell / atlas_cells.x)) + UV) / atlas_cells;
}

void fragment() {
	// The atlas is premultiplied by WorldDressing; tint alpha is always one.
	COLOR = texture(TEXTURE, UV) * COLOR;
}
