shader_type canvas_item;

// Canopies lean a pixel or two in a slow shared breeze. The sprite shears
// around its root line so trunks stay planted; phase comes from where the
// plant stands, so a grove ripples instead of nodding in unison.
uniform float motion = 1.0;
uniform float strength = 2.4;
uniform float root_v = 0.84;

void vertex() {
	vec2 anchor = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	float t = TIME * motion;
	float phase = anchor.x * 0.011 + anchor.y * 0.019;
	float lean = sin(t * 1.05 + phase) + 0.4 * sin(t * 2.3 + phase * 1.6);
	VERTEX.x += lean * motion * strength * (root_v - UV.y) / root_v;
}
