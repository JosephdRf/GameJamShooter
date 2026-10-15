extends CanvasLayer
## Menu pause, instancié dans la scène de jeu (fonctionne même partie figée), au style des
## autres menus : le jeu figé reste visible derrière, grisé et assombri (shader pause_dim),
## avec des bulles qui montent, le titre « Pause » qui flotte, le bouton jaune « Reprendre »
## et la bulle « Quitter » (ils grossissent au survol et au focus clavier / manette).
##
## Seul l'hôte peut mettre en pause (P ou +) : la partie est figée sur tous les
## ordinateurs. Chez l'hôte : Reprendre (ou P / + / B / Échap) et Quitter, qui
## ramène tout le monde à la sélection d'équipe. Chez les autres : un simple
## message d'attente (Échap quitte le jeu, comme en partie).

const BUTTON_HOVER_SCALE := 1.06
const BUBBLE_HOVER_SCALE := 1.12
const SCALE_SPEED := 14.0
## Flottement du titre : amplitude (px) et période (s).
const TITLE_FLOAT := 8.0
const TITLE_PERIOD := 3.0

@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _buttons: Control = %Buttons
@onready var _resume_button: TextureButton = %ResumeButton
@onready var _quit_button: TextureButton = %QuitButton

var _hovered := {}
var _time := 0.0
var _title_y := 0.0


func _ready() -> void:
	visible = false
	_title_y = _title.position.y
	_resume_button.pressed.connect(NetworkManager.set_paused.bind(false))
	_quit_button.pressed.connect(NetworkManager.return_to_team_select)
	for button: BaseButton in [_resume_button, _quit_button]:
		button.mouse_entered.connect(func() -> void: _hovered[button] = true)
		button.mouse_exited.connect(func() -> void: _hovered[button] = false)
	NetworkManager.pause_changed.connect(_on_pause_changed)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_title.position.y = _title_y + sin(_time * TAU / TITLE_PERIOD) * TITLE_FLOAT
	_title.rotation = sin(_time * TAU / (TITLE_PERIOD * 1.7)) * 0.015
	# La souris l'emporte sur le focus : seul le bouton survolé grossit.
	var mouse_over_any: bool = _hovered.values().has(true)
	for button: TextureButton in [_resume_button, _quit_button]:
		var target := 1.0
		if _hovered.get(button, false) or (button.has_focus() and not mouse_over_any):
			target = BUBBLE_HOVER_SCALE if button == _quit_button else BUTTON_HOVER_SCALE
		button.scale = button.scale.lerp(Vector2.ONE * target, 1.0 - exp(-SCALE_SPEED * delta))


func _unhandled_input(event: InputEvent) -> void:
	if not multiplayer.is_server():
		if visible and event.is_action_pressed(&"ui_cancel"):
			get_tree().quit()
		return
	var resume_pressed := visible and (event.is_action_pressed(&"menu_back") or event.is_action_pressed(&"ui_cancel"))
	if event.is_action_pressed(&"pause") or resume_pressed:
		get_viewport().set_input_as_handled()
		NetworkManager.set_paused(not visible)


func _on_pause_changed(paused: bool) -> void:
	visible = paused
	var is_host := multiplayer.is_server()
	_buttons.visible = is_host
	_message.visible = not is_host
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_hovered.clear()
		if is_host:
			_resume_button.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
