shader_type canvas_item;

// Construction keeps a faint final silhouette for identification, while the
// completed portion rises from the actual artwork's footing to its roof.
uniform float construction_progress : hint_range(0.0, 1.0) = 0.0;
uniform float ink_top = 0.0;
uniform float ink_bottom = 1.0;

void fragment() {
	vec4 ink = COLOR;
	float cutoff = mix(ink_bottom, ink_top, construction_progress);
	float built = smoothstep(cutoff - 0.012, cutoff + 0.012, UV.y);
	ink.a *= mix(0.18, 1.0, built);
	COLOR = ink;
}
