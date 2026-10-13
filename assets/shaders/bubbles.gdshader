// Bulles autour d'une ellipse dégagée au centre de l'écran (écrans de dégâts,
// scenes/ui/damage/). Trois couches de bulles de tailles différentes, qui se
// superposent. Les bulles restent en place et tournent un peu sur elles-mêmes ;
// quand `amount` baisse, elles rétrécissent jusqu'à disparaître (d'abord celles
// proches du centre). Tailles en fraction de la hauteur de l'écran.
shader_type canvas_item;

// Niveau d'apparition des bulles : 0 = aucune, 1 = toutes à leur taille
// (piloté par scripts/ui/damage_overlay.gd selon la vie).
uniform float amount : hint_range(0.0, 1.0) = 1.0;
// Part de l'écran couverte, depuis le bord de l'ellipse : 0 = rien,
// 1 = jusqu'au centre. Les coins sont toujours plus couverts que les côtés.
uniform float band : hint_range(0.0, 1.0) = 0.15;
// Taille des plus petites et des plus grosses bulles (diamètre max).
uniform float size_min : hint_range(0.01, 0.5) = 0.04;
uniform float size_max : hint_range(0.01, 0.5) = 0.09;
// Proportion de bulles présentes dans la zone couverte.
uniform float density : hint_range(0.0, 1.0) = 0.8;
// Amplitude (radians) et vitesse du balancement des reflets.
uniform float wobble = 0.5;
uniform float wobble_speed = 1.2;
// Change la disposition des bulles (un nombre différent par écran).
uniform float seed = 1.0;
uniform vec4 tint : source_color = vec4(0.88, 0.96, 1.0, 1.0);
// Voile laiteux dans la zone couverte (0 = aucun).
uniform float veil : hint_range(0.0, 1.0) = 0.25;

const int LAYERS = 3;
// Durée relative de la croissance d'une bulle (sur l'échelle de `amount`).
const float GROW = 0.35;

float hash(vec2 p, float salt) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.31 + salt * 7.13) * 43758.5453);
}

// Distance « elliptique » au centre : 0 au centre, 1 au milieu des bords, ~1,4 dans les coins.
float ellipse(vec2 screen_pos, vec2 size) {
	return length((screen_pos / size - 0.5) * 2.0);
}

vec2 rotate(vec2 v, float angle) {
	return vec2(v.x * cos(angle) - v.y * sin(angle), v.x * sin(angle) + v.y * cos(angle));
}

// Opacité d'une couche de bulles (une bulle au plus par case de la grille).
// Pour casser l'effet de quadrillage, la grille est inclinée (angle différent
// pour chaque couche) et chaque rangée est décalée au hasard.
float bubble_layer(vec2 pos, vec2 size, float cell_size, float layer) {
	float angle = 0.6 + layer * 1.1 + seed;
	vec2 grid = rotate(pos, angle) / cell_size + layer * 0.37;
	float shift = hash(vec2(floor(grid.y), 7.0), layer + 6.5);
	grid.x += shift;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float size_rand = hash(cell, layer + 0.5);
	float max_radius = mix(0.15, 0.48, size_rand * size_rand); // Surtout des petites bulles.
	vec2 center = 0.5 + (vec2(hash(cell, layer + 1.5), hash(cell, layer + 2.5)) - 0.5) * (1.0 - 2.0 * max_radius);

	// Plus la bulle est loin du centre, plus elle a de chances d'exister.
	vec2 center_in_grid = cell + center - vec2(shift, 0.0) - layer * 0.37;
	vec2 center_on_screen = rotate(center_in_grid * cell_size, -angle);
	float e = ellipse(center_on_screen, size);
	float chance = density * smoothstep(1.0 - band, 1.0 - band * 0.6, e);
	if (chance <= 0.0 || hash(cell, layer + 3.5) >= chance) {
		return 0.0;
	}
	// Moment d'apparition : les bulles du bord d'abord, celles vers le centre ensuite.
	float inner = clamp((1.0 - e) / max(band, 0.001), 0.0, 1.0);
	float appear_at = mix(hash(cell, layer + 4.5), inner, 0.6) * (1.0 - GROW);
	float growth = clamp((amount - appear_at) / GROW, 0.0, 1.0);
	float radius = max_radius * growth * (2.0 - growth); // Ralentit en fin de croissance.
	if (radius <= 0.0) {
		return 0.0;
	}
	vec2 offset = local - center;
	float q = length(offset) / radius;
	if (q >= 1.0) {
		return 0.0;
	}
	float rim = smoothstep(0.72, 0.92, q) * (1.0 - smoothstep(0.94, 1.0, q));
	// Reflets qui se balancent : la bulle semble tourner un peu.
	float tilt = sin(TIME * wobble_speed + hash(cell, layer + 5.5) * 6.28) * wobble;
	vec2 spin = rotate(offset / radius, tilt);
	float shine = 1.0 - smoothstep(0.12, 0.24, length(spin + vec2(0.35)));
	float glint = 1.0 - smoothstep(0.04, 0.09, length(spin - vec2(0.3, 0.42)));
	return max(max(rim * 0.9, 0.2), max(shine * 0.95, glint * 0.7));
}

void fragment() {
	vec2 screen = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 size = vec2(screen.x / screen.y, 1.0);
	vec2 pos = SCREEN_UV * size;
	float e = ellipse(pos, size);
	float alpha = 0.0;
	// Au centre de l'ellipse, aucune bulle ne peut arriver : rien à calculer (performances).
	if (e >= 1.0 - band - size_max) {
		// Superposition des couches : a + b - a×b.
		for (int i = 0; i < LAYERS; i++) {
			float layer = float(i);
			float cell_size = mix(size_min, size_max, layer / float(LAYERS - 1));
			float a = bubble_layer(pos, size, cell_size, layer);
			alpha = alpha + a - alpha * a;
		}
		float mist = amount * veil * smoothstep(1.0 - band, 1.0 + band * 0.3, e);
		alpha = alpha + mist - alpha * mist;
	}
	COLOR = vec4(tint.rgb, alpha * tint.a);
}
