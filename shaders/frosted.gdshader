shader_type canvas_item;
// 毛玻璃：取螢幕紋理做多次取樣模糊，再疊一層帶白的霧。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float blur_lod : hint_range(0.0, 6.0) = 3.2;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tint : source_color = vec4(0.1, 0.08, 0.08, 1.0);
uniform float frost : hint_range(0.0, 1.0) = 0.12;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE * pow(2.0, blur_lod) * 0.6;
	vec3 c = vec3(0.0);
	// 9 點取樣 + mipmap LOD，便宜但夠糊
	c += textureLod(screen_tex, uv, blur_lod).rgb * 0.28;
	c += textureLod(screen_tex, uv + vec2( px.x, 0.0), blur_lod).rgb * 0.09;
	c += textureLod(screen_tex, uv + vec2(-px.x, 0.0), blur_lod).rgb * 0.09;
	c += textureLod(screen_tex, uv + vec2(0.0,  px.y), blur_lod).rgb * 0.09;
	c += textureLod(screen_tex, uv + vec2(0.0, -px.y), blur_lod).rgb * 0.09;
	c += textureLod(screen_tex, uv + vec2( px.x,  px.y), blur_lod).rgb * 0.09;
	c += textureLod(screen_tex, uv + vec2(-px.x,  px.y), blur_lod).rgb * 0.09;
	c += textureLod(screen_tex, uv + vec2( px.x, -px.y), blur_lod).rgb * 0.09;
	c += textureLod(screen_tex, uv + vec2(-px.x, -px.y), blur_lod).rgb * 0.09;
	// 霧感：往白提一點，再疊色
	c = mix(c, vec3(1.0), frost);
	c = mix(c, tint.rgb, tint_strength);
	COLOR = vec4(c, 1.0);
}
