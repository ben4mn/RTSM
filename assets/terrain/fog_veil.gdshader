shader_type canvas_item;
render_mode unshaded;

// One quad over the whole field. Unexplored ground is a soft bank of dark
// cloud with feathered, wandering edges; remembered ground is cooled and
// dimmed; ground in sight only receives faint drifting cloud shadows.
// fog_state is an 88x88 texture (red = in sight, green = explored) that
// FogVeil eases over time, so vision never pops.
uniform sampler2D fog_state : filter_linear, repeat_disable;
uniform sampler2D veil_noise : filter_linear, repeat_enable;
uniform vec2 map_origin = vec2(0.0);
uniform vec4 map_inverse = vec4(1.0, 0.0, 0.0, 1.0);
uniform float map_tiles = 88.0;
uniform float motion = 1.0;
uniform float shadow_strength = 0.11;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 ground = world_position * vec2(1.0, 2.0);
	float t = TIME * motion;
	vec2 drift = texture(veil_noise, ground / 1700.0 + vec2(t * 0.0035, t * 0.0015)).rg;
	float billow = drift.r;
	float wisp = drift.g;

	vec2 rel = world_position - map_origin;
	vec2 tile = vec2(dot(rel, map_inverse.xy), dot(rel, map_inverse.zw));
	// Beyond the field edge the fog continues the state of the nearest edge
	// tile (the state texture clamps), so a known coast shows its sea and an
	// unknown one stays under cloud. The last playable tile is never fogged
	// by the edge itself; the sea fades back into cloud a few tiles out.
	vec2 inset = min(tile + 0.5, map_tiles - 0.5 - tile);
	float beyond = -min(inset.x, inset.y);
	// Out over the sea the bank's edges wander more, so the clamped state
	// does not draw ruler-straight fog bands off the coast.
	vec2 warp = vec2(wisp - 0.5, billow - 0.5) * (1.1 + clamp(beyond, 0.0, 8.0) * 0.7);
	vec2 state = texture(fog_state, (tile + 0.5 + warp) / map_tiles).rg;
	float inside = 1.0 - smoothstep(4.0, 10.0, beyond + (wisp - 0.5) * 2.4);
	float explored = state.g * inside;
	float seen = state.r * (1.0 - smoothstep(1.5, 6.0, beyond + (wisp - 0.5) * 1.4));

	float cloud_alpha = 1.0 - smoothstep(0.22, 0.72, explored);
	float body = smoothstep(0.25, 0.75, billow * 0.6 + wisp * 0.4);
	vec3 cloud = mix(vec3(0.098, 0.153, 0.169), vec3(0.176, 0.243, 0.251), body);
	// A paler lip where the bank thins, like lit cloud edges on an old chart.
	float lip = smoothstep(0.02, 0.30, explored) * (0.55 + 0.45 * wisp);
	cloud = mix(cloud, vec3(0.345, 0.404, 0.384), lip * 0.55);

	float memory_alpha = (1.0 - smoothstep(0.18, 0.82, seen)) * 0.44;
	float shade = texture(veil_noise, ground / 4300.0 + vec2(0.63 + t * 0.0042, 0.41 + t * 0.0019)).r;
	float shadow_alpha = smoothstep(0.50, 0.72, shade) * shadow_strength;
	float under = memory_alpha + (1.0 - memory_alpha) * shadow_alpha;
	vec3 under_color = vec3(0.090, 0.137, 0.184);

	float alpha = cloud_alpha + (1.0 - cloud_alpha) * under;
	vec3 color = (cloud * cloud_alpha + under_color * under * (1.0 - cloud_alpha)) / max(alpha, 0.001);
	COLOR = vec4(color, alpha);
}
