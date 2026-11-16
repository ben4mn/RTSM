shader_type canvas_item;

// A destroyed building sinks into its own footing: the artwork slides down and
// everything that passes below the ground line is cut away.
uniform float sink : hint_range(0.0, 1.0) = 0.0;
uniform float ink_top = 0.0;
uniform float ink_bottom = 1.0;

void fragment() {
	float shift = sink * (ink_bottom - ink_top);
	vec2 source = vec2(UV.x, UV.y - shift);
	vec4 ink = texture(TEXTURE, source);
	// Never sample the neighbouring atlas cell above this building.
	ink.a *= step(ink_top, source.y);
	// A ragged, dusty edge where the walls meet the ground.
	float edge = smoothstep(ink_bottom - 0.004, ink_bottom - 0.03, UV.y);
	ink.a *= mix(1.0, edge, step(0.001, sink));
	ink.rgb *= mix(1.0, 0.70, sink);
	COLOR = ink;
}
