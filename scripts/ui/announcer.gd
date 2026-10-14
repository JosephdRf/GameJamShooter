extends CanvasLayer
## Messages de match en gros en haut de l'écran (instancié dans scenes/game/game.tscn) :
## « Attention… », « C'est parti ! », prise de zone, « Prolongation ! », « Terminé ! ».
## Game décide quand ils s'affichent et combien de temps ; ce script ne fait qu'afficher.
## Textes, couleurs et effet d'apparition / disparition : dans l'inspecteur.
##
## Style façon Splatoon : lettres blanches très épaisses (Titan One), ombre portée nette
## à la couleur de l'équipe. Le texte est dessiné dans un SubViewport (Viewport) puis
## affiché par Display, dont le shader (announce_fx) ajoute flou de mouvement,
## inclinaison, éclat blanc et passage au gris. Flash : éclair blanc plein écran.
## Un nouveau message remplace aussitôt le précédent.

enum Effect {
	SPLAT, ## Surgit en rebondissant ; s'efface en s'étirant, flou et gris (Splatoon).
	SLIDE, ## Arrive de la droite à toute vitesse, penché, et repart à gauche (traînée floue).
	STAMP, ## Tombe de très gros sur l'écran (éclair, secousse) ; rétrécit en s'effaçant.
	FLASH, ## Éclair blanc, le texte clignote blanc puis prend ses couleurs ; s'efface en blanc.
	JELLY, ## Gélatine : s'écrase et rebondit ; s'aplatit pour disparaître.
}

@export var effect := Effect.SPLAT
@export var ready_text := "Attention…"
@export var go_text := "C'est parti !"
@export var ally_capture_text := "Ton équipe a pris la zone !"
@export var enemy_capture_text := "L'adversaire a pris la zone !"
@export var finish_text := "Terminé !"
@export var overtime_text := "Prolongation !"
## Couleur de l'ombre pour les messages neutres (début, fin).
@export var neutral_color := Color("1f9d8b")
## Couleur de l'ombre de « Prolongation ! ».
@export var overtime_color := Color("e8892b")
## Taille du texte des messages longs (prise de zone).
@export var long_message_font_size := 140

var _tween: Tween
var _default_font_size := 0

@onready var _flash: ColorRect = %Flash
@onready var _viewport: SubViewport = %Viewport
@onready var _message: Label = %Message
@onready var _display: TextureRect = %Display
@onready var _fx: ShaderMaterial = _display.material


func _ready() -> void:
	_default_font_size = _message.get_theme_font_size(&"font_size")
	_display.texture = _viewport.get_texture()
	_display.visible = false
	_display.resized.connect(func() -> void: _display.pivot_offset = _display.size / 2.0)
	_display.pivot_offset = _display.size / 2.0


func show_ready(duration: float) -> void:
	play(ready_text, duration, neutral_color)


func show_go(duration: float) -> void:
	play(go_text, duration, neutral_color)


## `ally` : vrai si c'est l'équipe du joueur de cet ordinateur.
func show_capture(ally: bool, team_color: Color, duration: float) -> void:
	play(ally_capture_text if ally else enemy_capture_text, duration, team_color, long_message_font_size)


func show_overtime(duration: float) -> void:
	play(overtime_text, duration, overtime_color)


func show_finish(duration: float) -> void:
	play(finish_text, duration, neutral_color)


## Affiche `text` pendant `duration` secondes (apparition et disparition comprises), avec
## une ombre de couleur `color`, et l'effet `with_effect` (-1 = celui de l'inspecteur).
func play(text: String, duration: float, color: Color, font_size := 0, with_effect := -1) -> void:
	if _tween:
		_tween.kill()
	_message.text = text
	_message.add_theme_font_size_override(&"font_size", font_size if font_size > 0 else _default_font_size)
	_message.add_theme_color_override(&"font_shadow_color", color)
	_message.add_theme_color_override(&"font_outline_color", color.darkened(0.45))
	_reset()
	var chosen: Effect = effect if with_effect < 0 else with_effect as Effect
	_tween = create_tween()
	var enter_time := _enter(chosen)
	var exit_time := _exit_duration(chosen)
	_tween.chain().tween_interval(maxf(duration - enter_time - exit_time, 0.0))
	_exit(chosen)
	_tween.chain().tween_callback(_display.hide)


func _reset() -> void:
	_display.visible = true
	_display.scale = Vector2.ONE
	_display.position.x = 0.0
	_display.position.y = _display.get_parent_area_size().y * _display.anchor_top
	_display.rotation = 0.0
	for parameter: StringName in [&"blur", &"trail", &"skew", &"flash", &"gray"]:
		_fx.set_shader_parameter(parameter, 0.0)
	_fx.set_shader_parameter(&"trail_side", 1.0)
	_fx.set_shader_parameter(&"alpha", 0.0)
	_flash.color.a = 0.0


## Ajoute l'apparition au tween ; renvoie sa durée (s).
func _enter(chosen: Effect) -> float:
	var t := _tween
	match chosen:
		Effect.SPLAT:
			_display.scale = Vector2.ONE * 0.4
			t.tween_property(_display, ^"scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.parallel().tween_method(_set_fx.bind(&"alpha"), 0.0, 1.0, 0.06)
			t.parallel().tween_method(_set_fx.bind(&"flash"), 1.0, 0.0, 0.25)
			return 0.28
		Effect.SLIDE:
			var width := _display.size.x
			_display.position.x = width
			_fx.set_shader_parameter(&"trail", 1.0)
			_fx.set_shader_parameter(&"trail_side", 1.0)
			_fx.set_shader_parameter(&"alpha", 1.0)
			t.tween_property(_display, ^"position:x", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.parallel().tween_method(_set_fx.bind(&"blur"), 0.25, 0.0, 0.26).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.parallel().tween_method(_set_fx.bind(&"skew"), -2.5, 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			return 0.4
		Effect.STAMP:
			_display.scale = Vector2.ONE * 3.0
			t.tween_property(_display, ^"scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.parallel().tween_method(_set_fx.bind(&"alpha"), 0.0, 1.0, 0.1)
			t.parallel().tween_method(_set_fx.bind(&"blur"), 0.04, 0.0, 0.14)
			# Impact : éclair et secousse qui s'amortit.
			t.chain().tween_property(_flash, ^"color:a", 0.55, 0.02)
			t.chain().tween_property(_flash, ^"color:a", 0.0, 0.25)
			var base_y := _display.position.y
			var shake := create_tween()
			shake.tween_interval(0.14)
			for offset: float in [16.0, -12.0, 8.0, -5.0, 2.0, 0.0]:
				shake.tween_property(_display, ^"position:y", base_y + offset, 0.035)
			return 0.41
		Effect.FLASH:
			_flash.color.a = 0.8
			create_tween().tween_property(_flash, ^"color:a", 0.0, 0.35)
			_set_fx(1.0, &"alpha")
			_set_fx(1.0, &"flash")
			for alpha: float in [0.15, 1.0, 0.15, 1.0]:
				t.tween_interval(0.06)
				t.tween_callback(_set_fx.bind(alpha, &"alpha"))
			t.tween_method(_set_fx.bind(&"flash"), 1.0, 0.0, 0.2)
			return 0.24 + 0.2
		_: # JELLY
			_display.scale = Vector2(1.5, 0.2)
			t.tween_method(_set_fx.bind(&"alpha"), 0.0, 1.0, 0.05)
			for target: Vector2 in [Vector2(0.75, 1.3), Vector2(1.15, 0.85), Vector2(0.95, 1.06), Vector2.ONE]:
				t.chain().tween_property(_display, ^"scale", target, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			return 0.05 + 0.36


func _exit_duration(chosen: Effect) -> float:
	match chosen:
		Effect.SPLAT:
			return 0.32
		Effect.SLIDE:
			return 0.26
		Effect.STAMP:
			return 0.2
		Effect.FLASH:
			return 0.25
		_:
			return 0.2


## Ajoute la disparition à la suite du tween.
func _exit(chosen: Effect) -> void:
	var t := _tween
	var time := _exit_duration(chosen)
	match chosen:
		Effect.SPLAT:
			# Comme Splatoon : le texte s'étire en largeur, s'aplatit, devient flou et gris.
			t.chain().tween_property(_display, ^"scale", Vector2(1.6, 0.8), time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.parallel().tween_method(_set_fx.bind(&"blur"), 0.0, 0.1, time).set_ease(Tween.EASE_IN)
			t.parallel().tween_method(_set_fx.bind(&"gray"), 0.0, 1.0, time * 0.6)
			t.parallel().tween_method(_set_fx.bind(&"alpha"), 1.0, 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		Effect.SLIDE:
			t.chain().tween_callback(_set_fx.bind(-1.0, &"trail_side"))
			t.tween_property(_display, ^"position:x", -_display.size.x, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			t.parallel().tween_method(_set_fx.bind(&"blur"), 0.0, 0.25, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			t.parallel().tween_method(_set_fx.bind(&"skew"), 0.0, 2.5, time)
		Effect.STAMP:
			t.chain().tween_property(_display, ^"scale", Vector2.ONE * 0.5, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			t.parallel().tween_method(_set_fx.bind(&"alpha"), 1.0, 0.0, time).set_ease(Tween.EASE_IN)
		Effect.FLASH:
			t.chain().tween_method(_set_fx.bind(&"flash"), 0.0, 1.0, time * 0.5)
			t.parallel().tween_property(_display, ^"scale", Vector2.ONE * 1.12, time)
			t.parallel().tween_method(_set_fx.bind(&"alpha"), 1.0, 0.0, time).set_ease(Tween.EASE_IN)
		_:
			t.chain().tween_property(_display, ^"scale", Vector2(1.35, 0.0), time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			t.parallel().tween_method(_set_fx.bind(&"alpha"), 1.0, 0.0, time).set_ease(Tween.EASE_IN)


func _set_fx(value: float, parameter: StringName) -> void:
	_fx.set_shader_parameter(parameter, value)
