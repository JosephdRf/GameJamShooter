extends Control
## Écran d'accueil : nom du jeu + bouton Démarrer (-> écran hôte/IP).
## Démarrer : clic, Entrée, A ou Start (+). Échap quitte le jeu.

@onready var _start_button: Button = %StartButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_start_button.pressed.connect(_start)
	_start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"start"):
		get_viewport().set_input_as_handled()
		_start()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


func _start() -> void:
	get_tree().change_scene_to_file(Screens.CONNECT)
