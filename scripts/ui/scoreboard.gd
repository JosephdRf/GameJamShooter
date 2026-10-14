@tool
class_name Scoreboard
extends Control
## Chrono et scores en haut de l'écran (dans MatchHud) : score bleu | chrono | score rouge,
## dessinés sur des formes reliées entre elles, au style choisi (`style`).
##
## - Chiffres en Titan One (comme les annonces), à largeur fixe : ils ne bougent pas en
##   changeant.
## - Dernières LAST_SECONDS secondes : chiffres jaunes ; à chaque seconde ils deviennent
##   blancs et grossissent un instant (comme Splatoon).
## - Prolongation : le chrono (0:00) clignote.
## - Quand un score augmente, sa forme et son chiffre gonflent ensemble (même facteur,
##   même centre : le chiffre reste dans la forme), puis reviennent en rebondissant.
## - Les formes « respirent » légèrement.
## Tout est dessiné dans _draw() : pas de nœuds enfants.

enum Style {
	BUBBLES, ## Nuage de bulles de savon translucides ; scores dans deux grosses bulles.
	INK, ## Tache d'encre noire avec des gouttes (Splatoon) ; scores en taches colorées.
	FOAM, ## Mousse de bain blanche et dense ; scores en mousse colorée.
}

## Secondes restantes à partir desquelles les chiffres passent au jaune et battent.
const LAST_SECONDS := 20
const YELLOW := Color(1.0, 0.86, 0.1)
const NAVY := Color(0.07, 0.2, 0.36)
const TEAM_COLORS: Array[Color] = [Color(0.231, 0.51, 0.965), Color(0.898, 0.282, 0.302)]

@export var style := Style.BUBBLES:
	set(value):
		style = value
		_build_shapes()
		queue_redraw()
@export var font: Font = preload("res://assets/fonts/titan_one/TitanOne-Regular.ttf")
@export var timer_font_size := 46
@export var score_font_size := 44
## Largeur maximale (px) du chiffre d'un score : au-delà (10 et plus), il est écrit plus
## petit pour tenir dans sa forme.
@export var score_max_width := 56.0
## Aperçu dans l'éditeur.
@export var preview_seconds := 95.0:
	set(value):
		preview_seconds = value
		_time_left = value
		queue_redraw()

var _time_left := 95.0
var _time_visible := true
var _overtime := false
var _scores: Array[int] = [0, 0]
## Grossissement maximal d'un score qui augmente (forme et chiffre).
const SCORE_POP_SCALE := 0.3

## Grossissement en cours (0..1, retombe à 0) : chrono, score bleu, score rouge.
var _pops: Array[float] = [0.0, 0.0, 0.0]
var _last_whole := -1
## Formes : groupe -> liste de [centre, rayon, phase] (cercles qui composent la forme).
var _shapes := {}
var _time := 0.0


func _ready() -> void:
	_build_shapes()


func _process(delta: float) -> void:
	_time += delta
	for i in _pops.size():
		_pops[i] = maxf(_pops[i] - delta * 3.2, 0.0)
	queue_redraw()


## Temps restant (s) ; négatif = chrono masqué.
func set_time_left(seconds: float) -> void:
	_time_visible = seconds >= 0.0
	_time_left = maxf(seconds, 0.0)
	var whole := ceili(_time_left)
	if whole != _last_whole and _last_whole != -1 and whole < LAST_SECONDS and whole > 0:
		_pops[0] = 1.0
	_last_whole = whole


func set_overtime(enabled: bool) -> void:
	_overtime = enabled


## `team` : 0 = bleu, 1 = rouge.
func set_score(team: int, value: int) -> void:
	if value > _scores[team]:
		_pops[1 + team] = 1.0
	_scores[team] = value


func _center() -> Vector2:
	return Vector2(size.x / 2.0, size.y / 2.0)


func _score_offset() -> float:
	return 132.0 if style == Style.BUBBLES else (158.0 if style == Style.INK else 150.0)


# --- Formes ---------------------------------------------------------------------

func _build_shapes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + style
	_shapes.clear()
	var c := Vector2.ZERO # Coordonnées relatives au centre du chrono.
	var side := _score_offset()
	match style:
		Style.BUBBLES:
			_shapes["timer"] = _cloud(rng, c, Vector2(72, 29), 12, 17.0, 29.0, 2)
			for t in 2:
				var at := Vector2(-side if t == 0 else side, 6)
				_shapes["score%d" % t] = [[at, 40.0, rng.randf() * TAU], [at + Vector2(-30 if t == 0 else 30, -26), 13.0, rng.randf() * TAU], [at + Vector2(-36 if t == 0 else 36, 22), 9.0, rng.randf() * TAU]]
		Style.INK:
			_shapes["timer"] = _splat(rng, c, Vector2(86, 36), 26, 7)
			for t in 2:
				_shapes["score%d" % t] = _splat(rng, Vector2(-side if t == 0 else side, 4), Vector2(36, 30), 14, 3)
		Style.FOAM:
			_shapes["timer"] = _cloud(rng, c, Vector2(90, 32), 22, 13.0, 24.0, 6)
			for t in 2:
				_shapes["score%d" % t] = _cloud(rng, Vector2(-side if t == 0 else side, 4), Vector2(34, 26), 12, 11.0, 20.0, 2)


## Nuage : cercles le long d'une ellipse (demi-axes `half`) + cercles de remplissage au centre.
func _cloud(rng: RandomNumberGenerator, center: Vector2, half: Vector2, count: int, r_min: float, r_max: float, fill: int) -> Array:
	var circles := []
	for i in count:
		var angle := TAU * i / count + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(r_min, r_max)
		circles.append([center + Vector2(cos(angle) * half.x, sin(angle) * half.y), r, rng.randf() * TAU])
	for i in fill:
		var x := lerpf(-half.x * 0.55, half.x * 0.55, (i + 0.5) / fill)
		circles.append([center + Vector2(x, rng.randf_range(-4, 4)), half.y + 8.0, rng.randf() * TAU])
	return circles


## Tache d'encre : cœur + lobes irréguliers + gouttes détachées.
func _splat(rng: RandomNumberGenerator, center: Vector2, half: Vector2, lobes: int, drops: int) -> Array:
	var circles := []
	for i in 3:
		circles.append([center + Vector2(lerpf(-half.x * 0.5, half.x * 0.5, i / 2.0), 0), half.y + 6.0, rng.randf() * TAU])
	for i in lobes:
		var angle := TAU * i / lobes + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(6.0, 15.0)
		var reach := rng.randf_range(0.95, 1.18)
		circles.append([center + Vector2(cos(angle) * half.x * reach, sin(angle) * half.y * reach), r, rng.randf() * TAU])
	for i in drops:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(1.3, 1.55)
		circles.append([center + Vector2(cos(angle) * half.x * dist, sin(angle) * half.y * dist), rng.randf_range(3.5, 7.0), rng.randf() * TAU])
	return circles


func _breath(circle: Array, amount: float) -> float:
	return circle[1] * (1.0 + amount * sin(_time * 1.6 + circle[2]))


# --- Dessin ---------------------------------------------------------------------

func _draw() -> void:
	if Engine.is_editor_hint() and _shapes.is_empty():
		_build_shapes()
	var c := _center()
	var timer_scale := 1.0 + 0.08 * _pops[0]
	var side := _score_offset()
	for t in 2:
		var pivot := Vector2(-side if t == 0 else side, 6 if style == Style.BUBBLES else 4)
		var score_scale := _score_scale(t)
		_draw_group(_shapes["score%d" % t], c, score_scale, _score_fill(t), _score_edge(t), pivot)
	if _time_visible:
		_draw_group(_shapes["timer"], c, timer_scale, _timer_fill(), _timer_edge())
		_draw_timer_text(c)
	for t in 2:
		var at := c + Vector2(-side if t == 0 else side, 6 if style == Style.BUBBLES else 4)
		var pop := _pops[1 + t]
		var text_color := Color.WHITE
		var outline := TEAM_COLORS[t].darkened(0.45)
		if style == Style.FOAM:
			text_color = TEAM_COLORS[t].darkened(0.15)
			outline = Color.WHITE
		var text := str(_scores[t])
		var font_size := score_font_size
		var width := _text_width(text, font_size)
		if width > score_max_width:
			font_size = floori(font_size * score_max_width / width)
		_draw_text(text, at, font_size, _score_scale(t), text_color.lerp(Color.WHITE, pop * 0.8), outline, 8)


## Échelle commune de la forme et du chiffre d'un score (gonflement quand il augmente).
func _score_scale(team: int) -> float:
	return 1.0 + SCORE_POP_SCALE * _ease_pop(_pops[1 + team])


## Forme : contour de l'union des cercles (cercles du contour plus gros, dessinés d'abord),
## puis remplissage, puis reflets. Agrandie de `scale_factor` autour de `pivot` (relatif à
## `origin`).
func _draw_group(circles: Array, origin: Vector2, scale_factor: float, fill: Color, edge: Color, pivot := Vector2.ZERO) -> void:
	# Le centre de chaque cercle s'écarte du pivot du même facteur que son rayon.
	origin += pivot * (1.0 - scale_factor)
	var breath := 0.035 if style != Style.INK else 0.02
	var edge_width := 3.5 if style == Style.BUBBLES else (0.0 if style == Style.INK else 3.0)
	if edge_width > 0.0:
		for circle: Array in circles:
			draw_circle(origin + circle[0] * scale_factor, _breath(circle, breath) * scale_factor + edge_width, edge)
	if style == Style.FOAM:
		# Ombre douce sous la mousse, pour le relief.
		for circle: Array in circles:
			draw_circle(origin + circle[0] * scale_factor + Vector2(0, 4), _breath(circle, breath) * scale_factor, fill.darkened(0.12))
	for circle: Array in circles:
		draw_circle(origin + circle[0] * scale_factor, _breath(circle, breath) * scale_factor, fill)
	if style == Style.BUBBLES:
		# Reflets de bulle : petit arc clair en haut à gauche de chaque grosse bulle.
		for circle: Array in circles:
			var r: float = _breath(circle, breath) * scale_factor
			if r < 12.0:
				continue
			var p: Vector2 = origin + circle[0] * scale_factor
			draw_arc(p, r * 0.72, PI * 1.08, PI * 1.42, 10, Color(1, 1, 1, 0.85), maxf(2.0, r * 0.12), true)
	elif style == Style.INK:
		# Brillance de l'encre : un trait clair sur le haut du cœur.
		var core: Array = circles[1]
		draw_arc(origin + core[0] * scale_factor, core[1] * 0.78 * scale_factor, PI * 1.15, PI * 1.45, 12, Color(fill.lightened(0.5), 0.55), 3.0, true)


func _timer_fill() -> Color:
	match style:
		Style.BUBBLES:
			return Color(0.9, 0.96, 1.0, 0.9)
		Style.INK:
			return Color(0.05, 0.05, 0.07)
		_:
			return Color(0.98, 0.99, 1.0)


func _timer_edge() -> Color:
	return Color(0.36, 0.62, 0.86) if style == Style.BUBBLES else Color(0.72, 0.8, 0.88)


func _score_fill(team: int) -> Color:
	match style:
		Style.BUBBLES:
			return Color(TEAM_COLORS[team].lightened(0.15), 0.88)
		Style.INK:
			return TEAM_COLORS[team]
		_:
			return TEAM_COLORS[team].lerp(Color.WHITE, 0.72)


func _score_edge(team: int) -> Color:
	return TEAM_COLORS[team].darkened(0.25) if style == Style.BUBBLES else TEAM_COLORS[team].lerp(Color.WHITE, 0.4)


func _draw_timer_text(c: Vector2) -> void:
	var whole := ceili(_time_left)
	var text := "%d:%02d" % [whole / 60, whole % 60]
	var last := whole <= LAST_SECONDS and _time_visible
	var base := Color.WHITE if style == Style.INK else NAVY
	var outline := Color(0, 0, 0, 0) if style == Style.INK else Color.WHITE
	if last or _overtime:
		base = YELLOW
		outline = Color(0.05, 0.05, 0.07) if style != Style.INK else Color(0, 0, 0, 0)
	var pop := _pops[0]
	var color := base.lerp(Color.WHITE, pop)
	if _overtime:
		color.a = 0.25 + 0.75 * (0.5 + 0.5 * cos(_time * TAU / 0.6))
	_draw_text(text, c + Vector2(0, 2), timer_font_size, 1.0 + 0.35 * _ease_pop(pop), color, outline, 10)


func _ease_pop(pop: float) -> float:
	return pop * pop * (3.0 - 2.0 * pop)


## Largeur de `text` avec des chiffres à largeur fixe (comme _draw_text).
func _text_width(text: String, font_size: int) -> float:
	var digit_w := 0.0
	for d in "0123456789":
		digit_w = maxf(digit_w, font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var total := 0.0
	for ch in text:
		total += digit_w if ch.is_valid_int() else font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return total


## Texte centré sur `at`, chiffres à largeur fixe, agrandi de `scale_factor` autour de son centre.
func _draw_text(text: String, at: Vector2, font_size: int, scale_factor: float, color: Color, outline: Color, outline_size: int) -> void:
	var digit_w := 0.0
	for d in "0123456789":
		digit_w = maxf(digit_w, font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var widths := []
	var total := 0.0
	for ch in text:
		var w := digit_w if ch.is_valid_int() else font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widths.append(w)
		total += w
	var ascent := font.get_ascent(font_size)
	var height := ascent + font.get_descent(font_size)
	draw_set_transform(at, 0.0, Vector2.ONE * scale_factor)
	var x := -total / 2.0
	for i in text.length():
		var ch := text[i]
		var w: float = widths[i]
		var glyph_w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2(x + (w - glyph_w) / 2.0, ascent - height / 2.0)
		if outline.a > 0.0:
			draw_string_outline(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline)
		draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += w
	draw_set_transform(Vector2.ZERO)
