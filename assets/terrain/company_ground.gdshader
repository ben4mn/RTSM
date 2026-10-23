shader_type canvas_item;
render_mode unshaded;

// Two shared static materials. World-space detail crosses tile boundaries,
// keeps transparent edges exact, and never reads undiscovered map state.
uniform bool water_surface = false;
varying vec2 field_position;
varying vec4 field_tint;

void vertex() {
	field_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	field_tint = COLOR;
}

float field_hash(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float field_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 part = fract(point);
	part = part * part * (3.0 - 2.0 * part);
	return mix(mix(field_hash(cell), field_hash(cell + vec2(1.0, 0.0)), part.x),
		mix(field_hash(cell + vec2(0.0, 1.0)), field_hash(cell + vec2(1.0, 1.0)), part.x), part.y);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 ground = field_position * vec2(1.0, 1.7);
	float broad = field_noise(ground / 190.0) - 0.5;
	float detail = field_noise(ground / 37.0) - 0.5;
	vec3 surface = source.rgb;
	if (water_surface) {
		// Broken, horizontal glints read as water without glitter or movement.
		float wave = sin(field_position.y * 0.39 + sin(field_position.x * 0.028) * 1.3);
		float glint = smoothstep(0.86, 1.0, wave) * smoothstep(0.0, 0.42, detail);
		surface += vec3(0.026, 0.043, 0.045) * broad + vec3(0.027, 0.037, 0.030) * glint;
	} else {
		// Low contrast warm/cool meadow patches, not a per-tile checkerboard.
		surface += vec3(0.035, 0.038, 0.027) * broad + vec3(0.011, 0.015, 0.009) * detail;
	}
	COLOR = vec4(surface, source.a) * field_tint;
}
