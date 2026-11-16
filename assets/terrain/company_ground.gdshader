shader_type canvas_item;
render_mode unshaded;

// Two shared materials paint the whole field in world space, so colour never
// follows the diamond grid. WorldDressing binds a small per-tile data texture
// (water, forest floor, trodden ground, depth) and one tileable noise texture;
// the tile atlas only supplies the exact alpha silhouette. Nothing here reads
// undiscovered map state beyond what the opaque fog veil already hides.
uniform bool water_surface = false;
uniform bool dressed = false;
uniform sampler2D ground_data : filter_linear, repeat_disable;
uniform sampler2D ground_noise : filter_linear, repeat_enable;
uniform vec2 map_origin = vec2(0.0);
uniform vec4 map_inverse = vec4(1.0, 0.0, 0.0, 1.0);
uniform float map_tiles = 88.0;
uniform float motion = 1.0;
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
	vec3 surface = source.rgb;
	if (!dressed) {
		// Standalone tiles (fixtures, previews) keep the quiet original surface.
		vec2 ground = field_position * vec2(1.0, 1.7);
		float broad = field_noise(ground / 190.0) - 0.5;
		float detail = field_noise(ground / 37.0) - 0.5;
		if (water_surface) {
			float wave = sin(field_position.y * 0.39 + sin(field_position.x * 0.028) * 1.3);
			float glint = smoothstep(0.86, 1.0, wave) * smoothstep(0.0, 0.42, detail);
			surface += vec3(0.026, 0.043, 0.045) * broad + vec3(0.027, 0.037, 0.030) * glint;
		} else {
			surface += vec3(0.035, 0.038, 0.027) * broad + vec3(0.011, 0.015, 0.009) * detail;
		}
	} else {
		// Undo the isometric squash so patches are round on the ground plane.
		vec2 ground = field_position * vec2(1.0, 2.0);
		// Two lookups give four scales: red is broad, green a finer pitch.
		vec2 wide = texture(ground_noise, ground / 3100.0).rg;
		vec2 close = texture(ground_noise, ground / 210.0 + vec2(0.71, 0.53)).rg;
		float broad = wide.r;
		float patch = wide.g;
		float grain = close.r;
		float blade = close.g;

		vec2 rel = field_position - map_origin;
		vec2 tile = vec2(dot(rel, map_inverse.xy), dot(rel, map_inverse.zw));
		vec2 warp = vec2(grain - 0.5, blade - 0.5) * 0.42;
		vec4 data = texture(ground_data, (tile + 0.5 + warp) / map_tiles);

		// Meadow: lush hollows, a mid green, and straw-dry rises.
		float climate = broad * 0.62 + patch * 0.38;
		vec3 lush = vec3(0.478, 0.612, 0.384);
		vec3 mid = vec3(0.580, 0.675, 0.447);
		vec3 dry = vec3(0.702, 0.706, 0.482);
		vec3 grass = mix(lush, mid, smoothstep(0.30, 0.52, climate));
		grass = mix(grass, dry, smoothstep(0.56, 0.76, climate));
		grass *= 0.955 + 0.09 * grain;
		grass += (blade - 0.5) * 0.032;

		// Shaded, mossy floor under the trees.
		float canopy = smoothstep(0.12, 0.70, data.g + (grain - 0.5) * 0.28);
		grass = mix(grass, grass * vec3(0.70, 0.79, 0.74) + vec3(0.012, 0.018, 0.02), canopy);

		// Trodden ground: ragged, grain-broken soil around towns, camps and tracks.
		float worn = smoothstep(0.34, 0.66, data.b + (grain - 0.5) * 0.34 + (blade - 0.5) * 0.14);
		vec3 soil = vec3(0.694, 0.624, 0.463) * (0.93 + 0.14 * blade);
		vec3 land = mix(grass, soil, worn * 0.86);

		// Shore: dry sand, a darker wet lip, a lapping foam line, shallows, depth.
		float t = TIME * motion;
		float shore = data.r + (blade - 0.5) * 0.07;
		float sand = smoothstep(0.10, 0.34, shore);
		vec3 beach = mix(vec3(0.812, 0.769, 0.588), vec3(0.655, 0.635, 0.490), smoothstep(0.36, 0.50, shore));
		land = mix(land, beach, sand);

		surface = land;
		if (shore > 0.47) {
			// Short horizontal dashes that drift against each other read as
			// wind on water; they stay small so a lake never looks blotchy.
			vec2 swell = ground * vec2(1.0, 2.4);
			float ripple_a = texture(ground_noise, swell / 150.0 + vec2(t * 0.020, t * 0.008)).r;
			float ripple_b = texture(ground_noise, swell / 400.0 + vec2(0.5 - t * 0.016, 0.2 + t * 0.006)).g;
			float depth = smoothstep(0.5, 1.0, shore) * 0.45 + data.a * 0.55;
			vec3 water = mix(vec3(0.482, 0.690, 0.659), vec3(0.290, 0.478, 0.541), smoothstep(0.18, 0.92, depth));
			water += (ripple_a + ripple_b - 1.0) * vec3(0.030, 0.036, 0.034);
			float glint = smoothstep(0.40, 0.56, ripple_a * ripple_b);
			water += vec3(0.105, 0.115, 0.095) * glint;
			float lap = 0.028 * sin(t * 0.85 + patch * 19.0);
			float foam = smoothstep(0.498 + lap, 0.525 + lap, shore) * (1.0 - smoothstep(0.545 + lap, 0.61 + lap, shore));
			water = mix(water, vec3(0.91, 0.93, 0.87), foam * (0.45 + 0.4 * ripple_b));
			surface = mix(land, water, smoothstep(0.488, 0.512, shore));
		}
	}
	COLOR = vec4(surface, source.a) * field_tint;
}
