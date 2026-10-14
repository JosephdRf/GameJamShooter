// Colonne de lumière d'une zone (ZoneDefense), visible de loin : couleur de l'équipe qui
// capture (jaune sinon), plus dense en bas et sur les bords, qui s'efface vers le haut.
// Couleur semi-transparente (et non additive) : elle reste visible sur les murs clairs.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
// Hauteur de la colonne (m) : le mesh est centré, de -height/2 à +height/2.
uniform float height = 30.0;
// Opacité globale.
uniform float intensity = 0.6;
// Caméra dans la zone (ou à moins de inside_margin m de son bord) : on voit à travers
// (opacité multipliée par inside_min). Forme réglée par ZoneDefense.
uniform bool zone_rect = false;
uniform float zone_radius = 6.0;
uniform vec2 zone_half_size = vec2(5.0);
uniform float inside_margin = 3.0;
uniform float inside_min = 0.12;

// Distance horizontale (m) de la caméra au bord de la zone (négative dedans).
float camera_distance(vec3 camera, vec3 center) {
	vec2 d = camera.xz - center.xz;
	if (zone_rect) {
		vec2 q = abs(d) - zone_half_size;
		return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	}
	return length(d) - zone_radius;
}
// Vagues de lumière qui montent le long de la colonne : position (m, avancée par
// ZoneDefense, plus vite pendant une capture ; sinon scroll_speed), écart entre deux
// vagues (m), et opacité entre deux vagues (0 = vide, 1 = colonne pleine).
uniform float scroll_offset = -1.0;
uniform float scroll_speed = 3.0;
uniform float wave_spacing = 4.5;
uniform float wave_floor = 0.3;

varying float ratio;
varying float side;

void vertex() {
	ratio = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	side = step(abs(NORMAL.y), 0.5); // Pas de dessus / dessous (colonne rectangulaire = boîte).
}

void fragment() {
	// Bords plus lumineux : là où la surface est vue de biais.
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = mix(0.45, 1.0, pow(edge, 1.5));
	float fade = mix(0.25, 1.0, pow(1.0 - ratio, 0.9)) * smoothstep(1.0, 0.85, ratio);
	float y = ratio * height;
	// Chaque vague : front net en haut, traînée qui s'efface vers le bas.
	float offset = scroll_offset >= 0.0 ? scroll_offset : TIME * scroll_speed;
	float phase = fract((y - offset) / wave_spacing);
	float wave = pow(phase, 2.5) * smoothstep(1.0, 0.94, phase);
	float bands = mix(wave_floor, 1.25, wave);
	ALBEDO = mix(color.rgb, vec3(1.0), 0.25 * pow(edge, 3.0));
	ALPHA = clamp(intensity * rim * fade * bands, 0.0, 1.0) * side * mix(inside_min, 1.0, smoothstep(0.0, inside_margin, camera_distance(CAMERA_POSITION_WORLD, NODE_POSITION_WORLD)));
}
