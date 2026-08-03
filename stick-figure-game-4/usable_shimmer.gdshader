shader_type canvas_item;

uniform float time = 0.0;
uniform float strength = 0.85;
uniform vec3 gold_color = vec3(1.0, 0.9, 0.35);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float band = fract(UV.x * 0.7 + UV.y * 0.25 - time * 0.7);
	float shine = smoothstep(0.25, 0.5, band) * (1.0 - smoothstep(0.5, 0.75, band));
	// Stronger base gold tint so it reads on pixel art
	c.rgb = mix(c.rgb, c.rgb * gold_color * 1.25, 0.45 * c.a);
	c.rgb += gold_color * shine * strength * c.a;
	COLOR = c;
}
