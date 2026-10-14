@tool
class_name WaterGauge
extends Control
## Jauge d'eau (MatchHud, écran de chargement), au style des bulles du chrono (Scoreboard) :
## tube translucide au contour bleu, rempli d'eau dont le bord ondule et où remontent
## de petites bulles. Plus claire pendant la recharge. Tout est dessiné dans _draw(), à
## l'échelle de la hauteur de la jauge (REFERENCE_HEIGHT = taille 1).

const TUBE_FILL := Color(0.9, 0.96, 1.0, 0.85)
const TUBE_EDGE := Color(0.36, 0.62, 0.86)
const WATER := Color(0.2, 0.58, 1.0)
const WATER_RECHARGE := Color(0.52, 0.8, 1.0)
const EDGE_WIDTH := 3.0
## Hauteur (px) pour laquelle les épaisseurs et tailles de bulles ci-dessus sont données.
const REFERENCE_HEIGHT := 26.0
## Nombre de bulles dans l'eau (pleine).
const BUBBLES := 9

## Remplissage, de 0 à 1.
@export_range(0.0, 1.0) var ratio := 1.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
@export var recharging := false

var _time := 0.0
## Remplissage affiché : suit `ratio` en douceur.
var _shown := 1.0


func _ready() -> void:
	_shown = ratio


## Remplissage affiché (de 0 à 1) : il rejoint `ratio` en douceur.
func get_shown_ratio() -> float:
	return _shown


func _process(delta: float) -> void:
	_time += delta
	_shown = lerpf(_shown, ratio, 1.0 - exp(-12.0 * delta))
	queue_redraw()


func _draw() -> void:
	var r := size.y / 2.0
	var k := size.y / REFERENCE_HEIGHT
	var edge := EDGE_WIDTH * k
	var tube := _capsule(Rect2(Vector2.ZERO, size), 16)
	draw_colored_polygon(_capsule(Rect2(Vector2.ONE * -edge, size + Vector2.ONE * edge * 2.0), 16), TUBE_EDGE)
	draw_colored_polygon(tube, TUBE_FILL)

	# Eau : rectangle au bord droit ondulé, découpé à la forme du tube.
	var inner := Rect2(Vector2.ONE * 2.0 * k, size - Vector2.ONE * 4.0 * k)
	var level := inner.position.x + inner.size.x * _shown
	var color := WATER_RECHARGE if recharging else WATER
	if _shown > 0.002:
		var water := PackedVector2Array([inner.position, Vector2(inner.position.x, inner.end.y)])
		var steps := 10
		for i in steps + 1:
			var y := inner.end.y - inner.size.y * i / steps
			var wave := sin(y / k * 0.45 + _time * 5.0) * 2.5 * k * minf(_shown * 8.0, 1.0)
			water.append(Vector2(minf(level + wave, inner.end.x), y))
		for part: PackedVector2Array in Geometry2D.intersect_polygons(water, _capsule(inner, 16)):
			draw_colored_polygon(part, color)
		# Bulles qui remontent dans l'eau (positions déterministes, défilent avec le temps).
		for i in BUBBLES:
			var key := float(i) * 12.9898
			var x := inner.position.x + 8.0 * k + fposmod(key * 37.0, inner.size.x - 16.0 * k)
			if x > level - 6.0 * k:
				continue
			var cycle := fposmod(_time * (0.5 + fposmod(key, 0.5)) + fposmod(key * 3.7, 1.0), 1.0)
			var y := lerpf(inner.end.y - 3.0 * k, inner.position.y + 3.0 * k, cycle)
			x += sin(_time * 3.0 + key) * 1.5 * k
			draw_circle(Vector2(x, y), (1.6 + fposmod(key, 1.4)) * k, Color(1, 1, 1, 0.55 * (1.0 - cycle * 0.6)))

	# Reflet sur le haut du tube.
	draw_line(Vector2(r, size.y * 0.24), Vector2(size.x - r, size.y * 0.24), Color(1, 1, 1, 0.55), maxf(2.0, size.y * 0.12), true)


## Contour d'une capsule (rectangle aux bouts ronds) inscrite dans `rect`.
func _capsule(rect: Rect2, segments: int) -> PackedVector2Array:
	var r := rect.size.y / 2.0
	var points := PackedVector2Array()
	var left := Vector2(rect.position.x + r, rect.position.y + r)
	var right := Vector2(rect.end.x - r, rect.position.y + r)
	for i in segments + 1:
		var a := PI / 2.0 + PI * i / segments # De bas en haut, côté gauche.
		points.append(left + Vector2(cos(a), sin(a)) * r)
	for i in segments + 1:
		var a := -PI / 2.0 + PI * i / segments # De haut en bas, côté droit.
		points.append(right + Vector2(cos(a), sin(a)) * r)
	return points
