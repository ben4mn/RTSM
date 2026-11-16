shader_type canvas_item;
render_mode unshaded;

// The edge of the world: the playable diamond ends in a sandy bank, a
// lapping foam line and a sea that deepens and dims into the night-teal
// clear colour. Drawn as one static ring mesh around the field (MapRim), in
// the same palette as the lakes so "water = impassable" reads at a glance.
// The fog veil above it continues the edge's fog state over the sea.
uniform sampler2D rim_noise : filter_linear, repeat_enable;
uniform vec2 map_origin = vec2(0.0);
uniform vec4 map_inverse = vec4(1.0, 0.0, 0.0, 1.0);
uniform float map_tiles = 88.0;
uniform float motion = 1.0;
uniform vec3 night = vec3(0.094, 0.165, 0.188);
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 rel = world_position - map_origin;
	vec2 tile = vec2(dot(rel, map_inverse.xy), dot(rel, map_inverse.zw));
	// Tiles outside the field, along the worse axis: < 0 inside, 0 on the edge.
	vec2 low = -0.5 - tile;
	vec2 high = tile - (map_tiles - 0.5);
	float out_d = max(max(low.x, low.y), max(high.x, high.y));

	vec2 ground = world_position * vec2(1.0, 2.0);
	float t = TIME * motion;
	vec2 grain = texture(rim_noise, ground / 900.0).rg;
	vec2 swell_noise = texture(rim_noise, ground / 2600.0 + vec2(0.31, 0.77)).rg;
	// The waterline wanders a little seaward only, so the bank never eats a
	// playable tile and a unit standing on the last tile stays on land.
	float d = out_d - (grain.r - 0.5) * 0.30 - 0.06;

	if (d < 0.0) {
		// The last half tile of land: a sandy bank darkening toward the water.
		float bank = smoothstep(-0.55, -0.02, d + (grain.g - 0.5) * 0.22);
		vec3 sand = mix(vec3(0.812, 0.769, 0.588), vec3(0.655, 0.635, 0.490), smoothstep(0.35, 0.95, bank));
		sand *= 0.95 + 0.10 * grain.g;
		COLOR = vec4(sand, bank * 0.92);
	} else {
		vec2 swell = ground * vec2(1.0, 2.4);
		float ripple_a = texture(rim_noise, swell / 150.0 + vec2(t * 0.020, t * 0.008)).r;
		float ripple_b = texture(rim_noise, swell / 400.0 + vec2(0.5 - t * 0.016, 0.2 + t * 0.006)).g;
		float depth = smoothstep(0.05, 2.6, d);
		vec3 water = mix(vec3(0.482, 0.690, 0.659), vec3(0.290, 0.478, 0.541), depth);
		// Open sea: darker and a little cooler, broken by slow swells.
		water = mix(water, vec3(0.200, 0.345, 0.400), smoothstep(2.0, 6.0, d + (swell_noise.r - 0.5) * 1.6));
		float calm = 1.0 - smoothstep(3.0, 9.0, d);
		water += (ripple_a + ripple_b - 1.0) * vec3(0.030, 0.036, 0.034) * (0.4 + 0.6 * calm);
		float glint = smoothstep(0.40, 0.56, ripple_a * ripple_b);
		water += vec3(0.105, 0.115, 0.095) * glint * (0.25 + 0.75 * calm);
		// Wet sand just under the surface, then a foam line lapping the bank.
		water = mix(water, vec3(0.560, 0.590, 0.500), (1.0 - smoothstep(0.0, 0.16, d)) * 0.55);
		float lap = 0.05 * sin(t * 0.85 + grain.g * 19.0);
		float foam = smoothstep(0.03 + lap, 0.09 + lap, d) * (1.0 - smoothstep(0.13 + lap, 0.26 + lap, d));
		water = mix(water, vec3(0.91, 0.93, 0.87), foam * (0.45 + 0.4 * ripple_b));
		// A soft second line of surf further out keeps the coast alive.
		float surf = smoothstep(0.55, 0.62, d + (swell_noise.g - 0.5) * 0.3) * (1.0 - smoothstep(0.66, 0.80, d + (swell_noise.g - 0.5) * 0.3));
		water = mix(water, vec3(0.80, 0.86, 0.82), surf * 0.18 * (0.5 + ripple_a));
		// The world ends in the dusk, the same colour as the empty canvas.
		float dusk = smoothstep(4.5, 12.0, d + (swell_noise.r - 0.5) * 2.0);
		COLOR = vec4(mix(water, night, dusk), 1.0);
	}
}
