@tool
class_name BubbleBar
extends Control
## Barre de progression en rangée de bulles (écran de préparation du combat) : les bulles,
## vides au départ (contour pâle), se gonflent l'une après l'autre à la couleur `color`
## quand la progression les atteint (la bulle en cours grossit avec elle), avec un petit
## rebond et un reflet. Tout est dessiné dans _draw(), à l'échelle de la hauteur.

const EMPTY_FILL := Color(1, 1, 1, 0.06)
const EMPTY_EDGE := Color(1, 1, 1, 0.22)
## Rebond d'une bulle qui vient de se remplir : durée (s) et amplitude (fraction du rayon).
const POP_TIME := 0.25
const POP_SCALE := 0.35

## Progression, de 0 à 1.
@export_range(0.0, 1.0) var ratio := 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
@export var color := Color(0.231, 0.51, 0.965)
@export_range(4, 30) var count := 12

var _time := 0.0
## Instant (s) où chaque bulle s'est remplie (-1 = pas encore), pour son rebond.
var _filled_at: Array[float] = []


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Fraction (0 à 1) de la progression affichée : bulles pleines + bulle en cours.
func get_shown_ratio() -> float:
	return ratio


func _draw() -> void:
	if _filled_at.size() != count:
		_filled_at.resize(count)
		_filled_at.fill(-1.0)
	var r := size.y / 2.0
	var step := (size.x - 2.0 * r) / maxf(count - 1, 1)
	var edge := maxf(2.0, r * 0.12)
	var dark := color.darkened(0.45)
	for i in count:
		var center := Vector2(r + step * i, r + sin(_time * 3.0 + i * 0.7) * r * 0.06)
		draw_circle(center, r * 0.92, EMPTY_FILL)
		draw_arc(center, r * 0.92, 0.0, TAU, 32, EMPTY_EDGE, edge * 0.6, true)
		# Part de cette bulle dans la progression (0 = vide, 1 = pleine).
		var fill := clampf(ratio * count - i, 0.0, 1.0)
		if fill <= 0.0:
			_filled_at[i] = -1.0
			continue
		if fill >= 1.0 and _filled_at[i] < 0.0:
			_filled_at[i] = _time
		var pop := 0.0
		if _filled_at[i] >= 0.0:
			var t := (_time - _filled_at[i]) / POP_TIME
			pop = sin(clampf(t, 0.0, 1.0) * PI) * POP_SCALE
		var radius := r * (0.35 + 0.57 * sqrt(fill)) * (1.0 + pop)
		draw_circle(center, radius, color)
		draw_arc(center, radius, 0.0, TAU, 32, dark, edge, true)
		# Reflet en haut à gauche.
		draw_circle(center + Vector2(-0.35, -0.38) * radius, radius * 0.24, Color(1, 1, 1, 0.75))
		draw_circle(center + Vector2(0.18, -0.52) * radius, radius * 0.09, Color(1, 1, 1, 0.6))
