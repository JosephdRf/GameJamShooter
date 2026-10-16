@tool
class_name DashGauge
extends Control
## Jauge du dash (MatchHud, en bas à droite), au style de la jauge d'eau (WaterGauge) : bulle
## translucide au contour bleu, qui se remplit d'eau (bord ondulé) pendant que le dash se
## recharge, plus claire tant qu'il n'est pas prêt. Prêt : pleine, d'un bleu vif, avec deux
## chevrons blancs ; à l'instant où il redevient prêt, elle gonfle (« pop ») avec un éclat blanc.
## Tout est dessiné dans _draw(), à l'échelle de la taille de la jauge (REFERENCE_SIZE = 1).

const BUBBLE_FILL := Color(0.9, 0.96, 1.0, 0.85)
const BUBBLE_EDGE := Color(0.36, 0.62, 0.86)
const READY := Color(0.2, 0.58, 1.0)
const RECHARGING := Color(0.62, 0.84, 1.0)
const CHEVRON := Color(1, 1, 1)
const CHEVRON_RECHARGING := Color(1, 1, 1, 0.45)
const EDGE_WIDTH := 3.0
## Diamètre (px) pour lequel les épaisseurs ci-dessus sont données.
const REFERENCE_SIZE := 64.0
## « Pop » quand le dash redevient prêt : grossissement et durée (s).
const POP_SCALE := 1.25
const POP_DURATION := 0.35

## Recharge, de 0 (dash juste utilisé) à 1 (prêt).
@export_range(0.0, 1.0) var ratio := 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if value >= 1.0 and ratio < 1.0 and is_inside_tree():
			_pop()
		ratio = value
		queue_redraw()

var _time := 0.0
## Remplissage affiché : suit `ratio` en douceur (mais tombe d'un coup au dash).
var _shown := 1.0
## Éclat blanc du « pop » (de 1 à 0).
var _flash := 0.0
var _pop_tween: Tween


func _ready() -> void:
	_shown = ratio
	resized.connect(func() -> void: pivot_offset = size / 2.0)
	pivot_offset = size / 2.0


func _process(delta: float) -> void:
	_time += delta
	_shown = ratio if ratio < _shown else lerpf(_shown, ratio, 1.0 - exp(-14.0 * delta))
	queue_redraw()


func _pop() -> void:
	if _pop_tween:
		_pop_tween.kill()
	scale = Vector2.ONE * POP_SCALE
	_flash = 1.0
	_pop_tween = create_tween().set_parallel()
	_pop_tween.tween_property(self, ^"scale", Vector2.ONE, POP_DURATION) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(self, ^"_flash", 0.0, POP_DURATION)


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0
	var k := radius * 2.0 / REFERENCE_SIZE
	var edge := EDGE_WIDTH * k
	draw_circle(center, radius + edge, BUBBLE_EDGE)
	draw_circle(center, radius, BUBBLE_FILL)

	# Eau qui monte : bas du disque intérieur, bord du haut ondulé.
	var inner := radius - 2.0 * k
	var ready := _shown >= 0.999
	var color := READY if ready else RECHARGING
	if _shown > 0.002:
		var level := center.y + inner - inner * 2.0 * _shown
		var water := PackedVector2Array()
		var steps := 12
		for i in steps + 1:
			var x := center.x - inner + inner * 2.0 * i / steps
			var wave := 0.0 if ready else sin(x / k * 0.35 + _time * 5.0) * 2.0 * k
			water.append(Vector2(x, level + wave))
		water.append(Vector2(center.x + inner, center.y + inner + 1.0))
		water.append(Vector2(center.x - inner, center.y + inner + 1.0))
		for part: PackedVector2Array in Geometry2D.intersect_polygons(water, _circle(center, inner, 32)):
			draw_colored_polygon(part, color)

	# Deux chevrons (≫) : le dash.
	var chevron_color := CHEVRON if ready else CHEVRON_RECHARGING
	var h := radius * 0.42
	var w := radius * 0.28
	for offset: float in [-radius * 0.2, radius * 0.18]:
		var tip := center + Vector2(offset + w * 0.5, 0.0)
		var points := PackedVector2Array([tip + Vector2(-w, -h), tip, tip + Vector2(-w, h)])
		draw_polyline(points, Color(0.1, 0.38, 0.72, chevron_color.a), 7.0 * k, true)
		draw_polyline(points, chevron_color, 4.0 * k, true)

	# Reflet en haut à gauche, et éclat blanc du « pop ».
	draw_arc(center, radius * 0.72, PI * 1.1, PI * 1.45, 12, Color(1, 1, 1, 0.6), maxf(2.0, 3.0 * k), true)
	if _flash > 0.0:
		draw_circle(center, radius + edge, Color(1, 1, 1, 0.7 * _flash))


func _circle(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		points.append(center + Vector2.from_angle(TAU * i / segments) * radius)
	return points
