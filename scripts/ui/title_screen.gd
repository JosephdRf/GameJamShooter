extends Control
## Écran d'accueil : nom du jeu (qui flotte doucement) + bouton Démarrer jaune
## (-> écran hôte/IP), qui grossit au survol / au focus comme sur les autres écrans.
## Démarrer : clic, Entrée, A ou Start (+). Échap quitte le jeu.
## Nom du jeu tiré au sort une fois par lancement (titre et barre de la fenêtre) :
## ALT_NAME une fois sur dix (ALT_NAME_CHANCE), le nom du projet sinon.

## Échelle du bouton survolé ou sélectionné, et vitesse de l'animation d'échelle.
const HOVER_SCALE := 1.08
const SCALE_SPEED := 14.0
## Flottement du titre : amplitude (px) et période (s).
const TITLE_FLOAT := 8.0
const TITLE_PERIOD := 3.0
const ALT_NAME := "Fuck My Life"
const ALT_NAME_CHANCE := 0.1

## Nom tiré à ce lancement (vide tant que l'écran d'accueil n'a pas été affiché).
static var _launch_name := ""

var _hovered := false
var _time := 0.0
## Position de repos du titre (il flotte autour).
var _title_y := 0.0

@onready var _title: Label = %Title
@onready var _start_button: TextureButton = %StartButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(Music.MENU)
	_start_button.pressed.connect(_start)
	_start_button.mouse_entered.connect(func() -> void: _hovered = true)
	_start_button.mouse_exited.connect(func() -> void: _hovered = false)
	_start_button.grab_focus()
	_title_y = _title.position.y
	if _launch_name.is_empty():
		_launch_name = ALT_NAME if randf() < ALT_NAME_CHANCE else _title.text
	_title.text = _launch_name
	get_window().title = _launch_name


func _process(delta: float) -> void:
	_time += delta
	_title.position.y = _title_y + sin(_time * TAU / TITLE_PERIOD) * TITLE_FLOAT
	_title.rotation = sin(_time * TAU / (TITLE_PERIOD * 1.7)) * 0.015
	var target := HOVER_SCALE if _hovered or _start_button.has_focus() else 1.0
	_start_button.scale = _start_button.scale.lerp(Vector2.ONE * target, 1.0 - exp(-SCALE_SPEED * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"start"):
		get_viewport().set_input_as_handled()
		UiSounds.play_confirm() # Le bouton, lui, a son propre son (UiSounds).
		_start()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


func _start() -> void:
	get_tree().change_scene_to_file(Screens.CONNECT)
