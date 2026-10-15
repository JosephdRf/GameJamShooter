class_name InputBadge
extends Control
## Pastille d'une touche ou d'un bouton dans les fiches de l'écran de préparation du combat :
##   - KEY : touche de clavier ou bouton de souris (touche claire en relief, texte dedans) ;
##   - FACE : bouton de façade d'une manette (rond, lettre ou symbole PlayStation) ;
##   - SHOULDER : gâchette ou bouton de tranche (pilule sombre, ZR, R2, RB…).
## Taille calculée d'après le texte (`label`) et la hauteur `badge_height`.

enum Kind { KEY, FACE, SHOULDER }
## Symboles PlayStation dessinés (la police n'a pas ces caractères).
enum Symbol { NONE, SQUARE }

const FONT := preload("res://assets/fonts/titan_one/TitanOne-Regular.ttf")
const KEY_FILL := Color(0.97, 0.98, 1.0)
const KEY_EDGE := Color(0.07, 0.25, 0.45)
const SHOULDER_FILL := Color(0.16, 0.19, 0.24)
const PS_SQUARE_COLOR := Color(0.93, 0.47, 0.71)

var kind := Kind.KEY
var label := ""
var symbol := Symbol.NONE
## Couleur de la lettre (bouton de façade).
var letter_color := Color.WHITE
var badge_height := 40.0


func setup(badge_kind: Kind, text: String, color := Color.WHITE, badge_symbol := Symbol.NONE) -> InputBadge:
	kind = badge_kind
	label = text
	letter_color = color
	symbol = badge_symbol
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_minimum_size()
	queue_redraw()
	return self


func _font_size() -> int:
	return roundi(badge_height * (0.5 if kind == Kind.FACE else 0.42))


func _get_minimum_size() -> Vector2:
	if kind == Kind.FACE:
		return Vector2(badge_height, badge_height)
	var text_width := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x
	return Vector2(maxf(text_width + badge_height * 0.7, badge_height * 1.3), badge_height)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var font_size := _font_size()
	match kind:
		Kind.KEY:
			# Touche en relief : bord inférieur plus épais.
			var box := StyleBoxFlat.new()
			box.bg_color = KEY_FILL
			box.border_color = KEY_EDGE
			box.set_border_width_all(3)
			box.border_width_bottom = 6
			box.set_corner_radius_all(9)
			draw_style_box(box, rect)
			_draw_label(KEY_EDGE, font_size, -1.5)
		Kind.SHOULDER:
			var box := StyleBoxFlat.new()
			box.bg_color = SHOULDER_FILL
			box.border_color = SHOULDER_FILL.lightened(0.35)
			box.set_border_width_all(2)
			box.set_corner_radius_all(roundi(size.y / 2.0))
			box.corner_radius_bottom_left = 8
			box.corner_radius_bottom_right = 8
			draw_style_box(box, rect)
			_draw_label(Color.WHITE, font_size, 0.0)
		Kind.FACE:
			var center := size / 2.0
			var r := size.y / 2.0
			draw_circle(center, r, SHOULDER_FILL)
			draw_arc(center, r - 1.0, 0.0, TAU, 32, SHOULDER_FILL.lightened(0.35), 2.0, true)
			if symbol == Symbol.SQUARE:
				var side := r * 0.85
				draw_rect(Rect2(center - Vector2.ONE * side / 2.0, Vector2.ONE * side), PS_SQUARE_COLOR, false, 3.0)
			else:
				_draw_label(letter_color, font_size, 0.0)


func _draw_label(color: Color, font_size: int, lift: float) -> void:
	var text_size := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := (size.y - text_size.y) / 2.0 + FONT.get_ascent(font_size) + lift
	draw_string(FONT, Vector2((size.x - text_size.x) / 2.0, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
