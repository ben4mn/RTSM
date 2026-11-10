shader_type canvas_item;

// Fallen figures keep their silhouette but lose colour and light, so they read
// as ground detail and never compete with living units. One shared material.
void fragment() {
	vec4 ink = COLOR;
	float grey = dot(ink.rgb, vec3(0.30, 0.59, 0.11));
	ink.rgb = mix(ink.rgb, vec3(grey), 0.5) * vec3(0.80, 0.76, 0.72);
	ink.a *= 0.92;
	COLOR = ink;
}
