// Anneau au sol autour d'un canard (Player._create_zone_ring) : cercle à la couleur de son équipe
// et, sur son bord, une flèche dorée qui pointe vers la zone à défendre (arrow_angle).
// Dessiné sur un plan horizontal : UV (0,0)-(1,1) couvre le carré du cercle.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.23, 0.51, 0.96, 1.0);
uniform vec4 arrow_color : source_color = vec4(1.0, 0.85, 0.2, 1.0);
// Direction de la zone dans le plan (radians, 0 = +X, PI/2 = +Z) et opacité de la flèche.
uniform float arrow_angle = 0.0;
uniform float arrow_alpha = 0.0;
// Anneau : rayon (fraction du demi-côté) et épaisseur.
uniform float ring_radius = 0.56;
uniform float ring_width = 0.055;

float band(float d, float half_width) {
	return 1.0 - smoothstep(half_width - 0.012, half_width + 0.012, abs(d));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	// Anneau : trait de la couleur de l'équipe, liseré sombre, léger voile à l'intérieur.
	float ring = band(r - ring_radius, ring_width * 0.5);
	float outline = band(r - ring_radius, ring_width * 0.5 + 0.025) - ring;
	float inner = (1.0 - smoothstep(ring_radius - 0.04, ring_radius, r)) * 0.12;
	vec3 col = color.rgb;
	float alpha = ring * 0.9 + inner;
	col = mix(col, color.rgb * 0.45, clamp(outline / max(alpha + outline, 0.001), 0.0, 1.0));
	alpha += outline * 0.75;

	// Flèche (triangle pointe vers l'extérieur) posée sur l'anneau, tournée vers la zone.
	float c = cos(-arrow_angle);
	float s = sin(-arrow_angle);
	vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y); // Repère de la flèche : pointe vers +x.
	float tip = 0.95;
	float base = ring_radius + 0.03;
	float t = clamp((q.x - base) / (tip - base), 0.0, 1.0);
	float half_w = mix(0.2, 0.0, t);
	float inside = step(base, q.x) * step(q.x, tip) * step(abs(q.y), half_w);
	float edge = step(base - 0.045, q.x) * step(q.x, tip + 0.05) * step(abs(q.y), mix(0.27, 0.0, clamp((q.x - base + 0.045) / (tip - base + 0.095), 0.0, 1.0)));
	float a_out = (edge - inside) * arrow_alpha;
	float a_in = inside * arrow_alpha;
	col = mix(col, vec3(0.42, 0.24, 0.0), a_out);
	col = mix(col, arrow_color.rgb, a_in);
	alpha = max(alpha, max(a_in, a_out * 0.9));

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
