shader_type canvas_item;

// Re-map only the existing painted materials. UV, geometry and texture alpha
// remain untouched: ResourceNode's original canopy picking mask stays exact.
uniform vec4 source_a : source_color;
uniform vec4 source_b : source_color;
uniform vec4 source_c : source_color;
uniform vec4 source_d : source_color;
uniform vec4 paint_a : source_color;
uniform vec4 paint_b : source_color;
uniform vec4 paint_c : source_color;
uniform vec4 paint_d : source_color;
varying vec4 item_tint;

void vertex() {
	// Keep inherited fog/visibility and depletion fade, including alpha.
	item_tint = COLOR;
}

float material_weight(vec3 sample_color, vec3 reference) {
	vec3 difference = sample_color - reference;
	return 1.0 / max(dot(difference, difference), 0.00001);
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	vec4 weights = vec4(
		material_weight(original.rgb, source_a.rgb),
		material_weight(original.rgb, source_b.rgb),
		material_weight(original.rgb, source_c.rgb),
		material_weight(original.rgb, source_d.rgb)
	);
	weights /= dot(weights, vec4(1.0));
	vec3 painted = paint_a.rgb * weights.x + paint_b.rgb * weights.y
		+ paint_c.rgb * weights.z + paint_d.rgb * weights.w;
	COLOR = vec4(painted, original.a) * item_tint;
}
