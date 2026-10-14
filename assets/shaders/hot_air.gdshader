// Air chaud (HairDryer) : paroi de cylindre / cône qui fait onduler ce qu'il y a derrière
// (texture de l'écran déformée par un bruit qui monte), légèrement blanchie, avec des
// filets plus clairs. S'efface en bas, en haut et sur les bords vus de face.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 tint : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform float tint_strength = 0.1;
// Déformation de l'image derrière (fraction de l'écran).
uniform float distortion = 0.015;
// Vitesse de montée du bruit (tours de texture par seconde).
uniform float speed = 0.8;
// Demi-hauteur du cylindre (m), pour situer le pixel entre le bas (0) et le haut (1).
uniform float half_height = 5.0;

varying float height_fraction;

void vertex() {
	height_fraction = clamp((VERTEX.y + half_height) / (2.0 * half_height), 0.0, 1.0);
}

void fragment() {
	vec2 uv = vec2(UV.x * 3.0, height_fraction * 1.5 - TIME * speed);
	float n1 = texture(noise_tex, uv).r;
	float n2 = texture(noise_tex, uv * vec2(1.7, 0.6) + vec2(0.37, -TIME * speed * 0.4)).r;
	// Apparaît au-dessus du bas, disparaît vers le haut, et sur les bords de la colonne (paroi
	// vue de profil) : un volume d'air flou plutôt qu'un tube au contour net.
	float fade = smoothstep(0.0, 0.08, height_fraction) * (1.0 - smoothstep(0.45, 1.0, height_fraction));
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	fade *= smoothstep(0.1, 0.75, facing);
	vec2 offset = (vec2(n1, n2) - 0.5) * distortion * fade;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;
	// Filets : bandes claires étirées vers le haut dans le bruit.
	float streak = smoothstep(0.62, 0.8, texture(noise_tex, vec2(UV.x * 6.0, height_fraction * 0.35 - TIME * speed * 1.3)).r);
	vec3 color = mix(behind, tint.rgb, tint_strength * fade * (0.5 + n1));
	color += mix(tint.rgb, vec3(1.0), 0.5) * streak * tint_strength * 1.5 * fade;
	ALBEDO = color;
	ALPHA = clamp(fade * 1.5, 0.0, 1.0);
}
