// Sol d'une zone (ZoneDefense) : teinte transparente à la couleur de la zone et, pendant une
// capture, un disque (un rectangle pour une zone rectangulaire) de la couleur de l'équipe qui
// part du centre et atteint le bord au moment de la capture. Son aire grandit à vitesse
// constante (rayon = racine de `progress`) : à mi-capture, la moitié du sol est couverte.
// Liseré clair sur le bord qui avance. Zone disputée (`contested`) : rayures blanches qui
// défilent sur le disque.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
// Couleur du disque : celle de l'équipe qui capture (gardée pendant qu'il se résorbe,
// quand l'équipe est sortie).
uniform vec4 fill_color : source_color = vec4(0.23, 0.51, 0.96, 1.0);
// Opacité du sol hors du disque, et du disque.
uniform float base_alpha = 0.3;
uniform float lit_alpha = 0.6;
// Forme de la zone (réglée par ZoneDefense).
uniform bool zone_rect = false;
uniform float zone_radius = 6.0;
uniform vec2 zone_half_size = vec2(5.0);
// Capture : progression affichée (0 à 1), vrai si une équipe capture, vrai si disputée.
uniform float progress = 0.0;
uniform bool capturing = false;
uniform bool contested = false;
// Largeur du liseré au bord du disque (m).
uniform float rim_width = 0.18;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos.xz;
	// Distance normalisée au centre (0 au centre, 1 au bord) et taille d'un mètre dans cette unité.
	float d;
	float meter;
	if (zone_rect) {
		vec2 q = abs(p) / zone_half_size;
		d = max(q.x, q.y);
		meter = q.x > q.y ? 1.0 / zone_half_size.x : 1.0 / zone_half_size.y;
	} else {
		d = length(p) / zone_radius;
		meter = 1.0 / zone_radius;
	}
	vec3 rgb = color.rgb;
	float alpha = base_alpha;
	float reach = sqrt(clamp(progress, 0.0, 1.0)); // Aire proportionnelle à la progression.
	if (progress > 0.0001 && d <= reach) {
		rgb = fill_color.rgb;
		alpha = lit_alpha;
		if (contested) {
			float stripe = step(0.5, fract((p.x + p.y) * 0.45 - TIME * 0.8));
			rgb = mix(rgb, vec3(1.0), stripe * 0.55);
		}
		// Liseré clair sur le bord du disque.
		float rim = 1.0 - smoothstep(rim_width * meter * 0.4, rim_width * meter, reach - d);
		rgb = mix(rgb, mix(fill_color.rgb, vec3(1.0), 0.6), rim);
		alpha = mix(alpha, 0.95, rim);
	}
	ALBEDO = rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
