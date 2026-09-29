shader_type sky;

// Maps a flat sunset painting onto the sky dome. The painting's horizon row sits at
// horizon_v; the front half of the dome shows the whole image with the sun straight
// ahead (-Z), the back half mirrors it so there is no visible seam.
uniform sampler2D sky_tex : source_color, filter_linear, repeat_disable;
uniform float horizon_v = 0.85;
uniform float brightness = 1.0;
uniform vec3 ground_color : source_color = vec3(0.22, 0.12, 0.14);

void sky() {
	vec3 d = normalize(EYEDIR);
	float elev = asin(clamp(d.y, -1.0, 1.0));
	float u = 0.5 + atan(d.x, -d.z) / PI;
	if (u > 1.0) {
		u = 2.0 - u;
	} else if (u < 0.0) {
		u = -u;
	}
	float t = clamp(elev / (PI * 0.5 * 0.6), 0.0, 1.0);
	float v = mix(horizon_v, 0.02, t);
	vec3 c = texture(sky_tex, vec2(u, v)).rgb;
	if (elev < 0.0) {
		c = mix(c, ground_color, clamp(-elev * 8.0, 0.0, 1.0));
	}
	COLOR = c * brightness;
}
