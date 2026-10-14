// Mur d'une zone (ZoneDefense) : couleur unie, opaque en bas, transparent en haut.
// Les faces horizontales (dessus / dessous du mur rectangulaire, une boîte) sont masquées.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.3);
// Hauteur du mur (m) : le mesh est centré, de -height/2 à +height/2.
uniform float height = 5.0;

varying float ratio;
varying float side;

void vertex() {
	ratio = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	side = step(abs(NORMAL.y), 0.5);
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a * (1.0 - ratio) * side;
}
