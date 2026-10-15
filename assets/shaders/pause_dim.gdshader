// Fond du menu pause : l'image du jeu figé, grisée (presque en noir et blanc) et assombrie,
// avec une légère teinte bleue comme les menus.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Part de gris (0 = couleurs d'origine, 1 = noir et blanc), luminosité, teinte.
uniform float desaturation = 0.85;
uniform float brightness = 0.5;
uniform vec4 tint : source_color = vec4(0.75, 0.85, 1.0, 1.0);

void fragment() {
	vec3 color = textureLod(screen_texture, SCREEN_UV, 1.5).rgb;
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(color, vec3(gray), desaturation) * brightness * tint.rgb, 1.0);
}
