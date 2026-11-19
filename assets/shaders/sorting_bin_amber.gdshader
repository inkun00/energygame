shader_type spatial;

uniform sampler2D enamel : source_color, filter_linear_mipmap_anisotropic;

void fragment() {
	vec3 paint = texture(enamel, UV).rgb;
	float teal = smoothstep(0.015, 0.085, min(paint.g, paint.b) - paint.r);
	vec3 amber = vec3(paint.g * 1.55, paint.g * 0.77, paint.g * 0.23);
	ALBEDO = mix(paint, amber, teal);
	ROUGHNESS = 0.86;
	METALLIC = 0.08;
}
