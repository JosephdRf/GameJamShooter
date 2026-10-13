extends CanvasLayer
## Menu pause, instancié dans la scène de jeu (fonctionne même partie figée).
##
## Seul l'hôte peut mettre en pause (P ou +) : la partie est figée sur tous les
## ordinateurs. Chez l'hôte : Reprendre (ou P / + / B / Échap) et Quitter, qui
## ramène tout le monde à la sélection d'équipe. Chez les autres : un simple
## message d'attente (Échap quitte le jeu, comme en partie).

@onready var _message: Label = %Message
@onready var _buttons: Control = %Buttons
@onready var _resume_button: Button = %ResumeButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	visible = false
	_resume_button.pressed.connect(NetworkManager.set_paused.bind(false))
	_quit_button.pressed.connect(NetworkManager.return_to_team_select)
	NetworkManager.pause_changed.connect(_on_pause_changed)


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
	_message.text = "" if is_host else "L'hôte a mis la partie en pause…"
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if is_host:
			_resume_button.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
