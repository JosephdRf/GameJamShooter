class_name RisingBubbles
extends Control
## Bulles décoratives qui montent doucement sur les écrans de menu (placées juste au-dessus du
## fond, derrière textes et boutons ; ne captent pas la souris). Quelques bulles de tailles,
## vitesses et ondulations aléatoires, très transparentes ; elles apparaissent en bas, s'effacent
## en haut, puis repartent d'en bas ailleurs. Tailles et vitesses à l'échelle de la hauteur de
## l'écran (données pour REFERENCE_HEIGHT px).

const REFERENCE_HEIGHT := 1080.0
## Nombre de bulles à l'écran.
@export var count := 14
## Rayon (px) et vitesse de montée (px/s) : mini et maxi.
@export var radius_range := Vector2(8.0, 42.0)
@export var speed_range := Vector2(28.0, 70.0)
## Opacité du contour (le reste suit).
@export var opacity := 0.55

var _bubbles: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for i in count:
		# Réparties sur toute la hauteur dès le départ : l'écran n'est pas vide en arrivant.
		_bubbles.append(_new_bubble(randf()))


func _process(delta: float) -> void:
	_time += delta
	var k := size.y / REFERENCE_HEIGHT
	for b in _bubbles:
		b.y -= b.speed * k * delta / maxf(size.y, 1.0)
		if b.y < -0.05:
			b.merge(_new_bubble(1.05), true)
	queue_redraw()


## Bulle à la hauteur `y` (fraction de la hauteur de l'écran, 0 = en haut).
func _new_bubble(y: float) -> Dictionary:
	var t := randf()
	return {
		"x": randf(), "y": y,
		"radius": lerpf(radius_range.x, radius_range.y, t * t), # Plus de petites que de grosses.
		"speed": randf_range(speed_range.x, speed_range.y),
		"wobble": randf_range(6.0, 18.0), "wobble_speed": randf_range(0.6, 1.4), "phase": randf() * TAU,
	}


func _draw() -> void:
	var k := size.y / REFERENCE_HEIGHT
	for b in _bubbles:
		var r: float = b.radius * k
		var center := Vector2(b.x * size.x + sin(_time * b.wobble_speed + b.phase) * b.wobble * k, b.y * size.y)
		# Apparition en bas, effacement dans le haut de l'écran.
		var fade := clampf((1.05 - b.y) / 0.12, 0.0, 1.0) * clampf((b.y + 0.05) / 0.3, 0.0, 1.0)
		if fade <= 0.0:
			continue
		var alpha := opacity * fade
		draw_circle(center, r, Color(1, 1, 1, alpha * 0.18))
		draw_arc(center, r, 0.0, TAU, 32, Color(1, 1, 1, alpha), maxf(1.5, r * 0.09), true)
		# Reflet en haut à gauche.
		draw_arc(center, r * 0.68, deg_to_rad(200.0), deg_to_rad(250.0), 8, Color(1, 1, 1, alpha * 1.6), maxf(1.5, r * 0.12), true)
