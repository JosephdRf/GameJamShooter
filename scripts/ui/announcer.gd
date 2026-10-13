extends CanvasLayer
## Messages de match en gros au centre de l'écran (instancié dans
## scenes/game/game.tscn) : « Attention… », « C'est parti ! », prise de zone,
## « Terminé ! ». Game décide quand ils s'affichent et combien de temps ; ce
## script ne fait qu'afficher. Textes et couleurs : dans l'inspecteur.
##
## Animation : le message arrive en grossissant légèrement (rebond), reste,
## puis s'efface. Un nouveau message remplace aussitôt le précédent.

@export var ready_text := "Attention…"
@export var go_text := "C'est parti !"
@export var ally_capture_text := "Ton équipe a pris la zone clé !"
@export var enemy_capture_text := "L'adversaire a pris la zone clé !"
@export var finish_text := "Terminé !"
## Couleur du contour pour les messages neutres (début, fin).
@export var neutral_color := Color("1f9d8b")
## Taille du texte des messages longs (prise de zone).
@export var long_message_font_size := 64

## Durées des animations d'entrée et de sortie (s).
const APPEAR_DURATION := 0.25
const FADE_DURATION := 0.2

var _tween: Tween
var _default_font_size := 0

@onready var _message: Label = %Message


func _ready() -> void:
	_default_font_size = _message.get_theme_font_size(&"font_size")
	_message.visible = false


func show_ready(duration: float) -> void:
	_announce(ready_text, duration, neutral_color)


func show_go(duration: float) -> void:
	_announce(go_text, duration, neutral_color)


## `ally` : vrai si c'est l'équipe du joueur de cet ordinateur.
func show_capture(ally: bool, team_color: Color, duration: float) -> void:
	_announce(ally_capture_text if ally else enemy_capture_text, duration, team_color, long_message_font_size)


func show_finish(duration: float) -> void:
	_announce(finish_text, duration, neutral_color)


func _announce(text: String, duration: float, color: Color, font_size := 0) -> void:
	if _tween:
		_tween.kill()
	_message.text = text
	_message.add_theme_font_size_override(&"font_size", font_size if font_size > 0 else _default_font_size)
	_message.add_theme_color_override(&"font_outline_color", color)
	_message.add_theme_color_override(&"font_shadow_color", color.darkened(0.35))
	_message.visible = true
	_message.modulate.a = 0.0
	_message.pivot_offset = _message.size / 2.0
	_message.scale = Vector2.ONE * 1.5
	_tween = create_tween()
	_tween.set_parallel()
	_tween.tween_property(_message, ^"scale", Vector2.ONE, APPEAR_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_message, ^"modulate:a", 1.0, APPEAR_DURATION * 0.6)
	_tween.chain().tween_interval(maxf(duration - APPEAR_DURATION - FADE_DURATION, 0.0))
	_tween.chain().tween_property(_message, ^"modulate:a", 0.0, FADE_DURATION)
	_tween.chain().tween_callback(_message.hide)
