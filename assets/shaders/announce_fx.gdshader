// Effets des messages de match (Announcer), appliqués à l'image du texte (SubViewport) :
// flou de mouvement horizontal, inclinaison, éclat blanc et passage au gris.
shader_type canvas_item;

// Longueur du flou horizontal (en fraction de la largeur de l'image).
uniform float blur = 0.0;
// 0 = flou des deux côtés, 1 = traînée d'un seul côté (derrière le texte qui file).
uniform float trail = 0.0;
// Sens de la traînée : 1 = vers la droite, -1 = vers la gauche.
uniform float trail_side = 1.0;
// Inclinaison (italique) : décalage horizontal du haut par rapport au bas.
uniform float skew = 0.0;
// 1 = texte tout blanc (ombre comprise).
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 1 = texte gris et pâle (comme quand un message de Splatoon s'efface).
uniform float gray : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

const int SAMPLES = 16;

void fragment() {
	vec2 uv = UV;
	uv.x += skew * (0.5 - uv.y) * 0.1;
	vec4 sum = vec4(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		float offset = mix(t - 0.5, t * trail_side, trail) * blur;
		vec4 c = texture(TEXTURE, uv + vec2(offset, 0.0));
		sum += vec4(c.rgb * c.a, c.a);
	}
	sum /= float(SAMPLES);
	vec3 rgb = sum.a > 0.0 ? sum.rgb / sum.a : vec3(0.0);
	float luminance = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(mix(luminance, 1.0, 0.45)), gray);
	rgb = mix(rgb, vec3(1.0), flash);
	COLOR = vec4(rgb, sum.a * alpha * (1.0 - 0.35 * gray));
}
