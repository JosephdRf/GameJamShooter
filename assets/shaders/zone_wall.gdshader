// Mur d'une zone (ZoneDefense) : couleur unie, opaque en bas, transparent en haut.
// Les faces horizontales (dessus / dessous du mur rectangulaire, une boîte) sont masquées.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.3);
// Hauteur du mur (m) : le mesh est centré, de -height/2 à +height/2.
uniform float height = 5.0;

// Caméra dans la zone (ou à moins de inside_margin m de son bord) : on voit à travers
// (opacité multipliée par inside_min). Forme réglée par ZoneDefense.
uniform bool zone_rect = false;
uniform float zone_radius = 6.0;
uniform vec2 zone_half_size = vec2(5.0);
uniform float inside_margin = 3.0;
uniform float inside_min = 0.4;

// Distance horizontale (m) de la caméra au bord de la zone (négative dedans).
float camera_distance(vec3 camera, vec3 center) {
	vec2 d = camera.xz - center.xz;
	if (zone_rect) {
		vec2 q = abs(d) - zone_half_size;
		return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	}
	return length(d) - zone_radius;
}

varying float ratio;
varying float side;

void vertex() {
	ratio = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	side = step(abs(NORMAL.y), 0.5);
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a * (1.0 - ratio) * side * mix(inside_min, 1.0, smoothstep(0.0, inside_margin, camera_distance(CAMERA_POSITION_WORLD, NODE_POSITION_WORLD)));
}
