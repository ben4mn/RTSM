shader_type canvas_item;

// Brief white impact flash. One shared material: every struck unit batches.
uniform float strength : hint_range(0.0, 1.0) = 0.82;

void fragment() {
	vec4 ink = COLOR;
	ink.rgb = mix(ink.rgb, vec3(1.0, 0.99, 0.94), strength);
	COLOR = ink;
}
