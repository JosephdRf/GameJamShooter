// Passe en gris assombri tout ce qui est affiché en dessous (écran de mort).
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// 1 = luminosité d'origine, plus bas = plus sombre.
uniform float brightness : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(gray * brightness), 1.0);
}
