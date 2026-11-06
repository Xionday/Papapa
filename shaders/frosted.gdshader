shader_type canvas_item;
// 毛玻璃：不用 mipmap（Web/GLES3 的螢幕紋理不一定有 mip），改用固定半徑的多點取樣模糊。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float radius_px : hint_range(0.0, 40.0) = 14.0;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.2;
uniform vec4 tint : source_color = vec4(0.1, 0.08, 0.08, 1.0);
uniform float frost : hint_range(0.0, 1.0) = 0.06;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, uv).rgb * 2.0;
	float wsum = 2.0;
	// 兩圈各 8 點，內圈半徑 0.5r、外圈 r
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398; // 45°
		vec2 d = vec2(cos(a), sin(a));
		c += texture(screen_tex, uv + d * px * radius_px * 0.5).rgb;
		c += texture(screen_tex, uv + d * px * radius_px).rgb * 0.7;
		wsum += 1.7;
	}
	c /= wsum;
	c = mix(c, vec3(1.0), frost);
	c = mix(c, tint.rgb, tint_strength);
	COLOR = vec4(c, 1.0);
}
