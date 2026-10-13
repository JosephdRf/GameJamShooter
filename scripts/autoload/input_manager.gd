extends Node
## Crée les actions d'entrée au démarrage.
##
## Chaque ordinateur contrôle UN seul cube (celui choisi dans le lobby), avec
## le clavier/trackpad OU n'importe quelle manette branchée :
##   move_left/right/up/down : Z/Q/S/D (ou flèches) / joystick gauche
##   look_left/right/up/down : joystick droit (la souris est gérée par PlayerCamera)
##   jump                    : Espace / bouton du bas (B sur Switch Pro)
##   dash                    : K / bouton de gauche (Y sur Switch Pro, Carré sur PlayStation)
##   start                   : bouton Start (+ sur Switch Pro)
##   pause (en jeu, hôte)    : P / bouton Start (+ sur Switch Pro)
##   ui_accept (menus)       : Entrée / Espace / A sur Switch Pro (bouton de droite)
##   menu_back (menus)       : Retour arrière / B sur Switch Pro (bouton du bas)
##   menu_left/menu_right    : comme move_left/right, mais avec une zone morte
##                             plus large pour naviguer dans les menus
##
## Les touches sont *physiques* : Z/Q/S/D en AZERTY = W/A/S/D en QWERTY.

const STICK_DEADZONE := 0.15
const MENU_DEADZONE := 0.5

## Godot utilise une disposition *positionnelle* (style Xbox) pour les boutons :
## JOY_BUTTON_A = bouton du BAS, soit le bouton "B" d'une manette Switch Pro
## (et A sur Xbox, Croix sur PlayStation). Cf. doc de JoyButton.
const JUMP_BUTTON := JOY_BUTTON_A
## Bouton de GAUCHE : Y sur Switch Pro, Carré sur PlayStation, X sur Xbox.
const DASH_BUTTON := JOY_BUTTON_X
## Bouton "A" d'une manette Switch Pro (bouton de DROITE) pour valider dans les menus.
const CONFIRM_BUTTON := JOY_BUTTON_B
## Bouton "B" d'une manette Switch Pro (bouton du BAS) pour revenir en arrière.
const BACK_BUTTON := JOY_BUTTON_A


func _ready() -> void:
	var axes := {
		&"move_left": [JOY_AXIS_LEFT_X, -1.0, [KEY_A, KEY_LEFT]],
		&"move_right": [JOY_AXIS_LEFT_X, 1.0, [KEY_D, KEY_RIGHT]],
		&"move_up": [JOY_AXIS_LEFT_Y, -1.0, [KEY_W, KEY_UP]],
		&"move_down": [JOY_AXIS_LEFT_Y, 1.0, [KEY_S, KEY_DOWN]],
		&"look_left": [JOY_AXIS_RIGHT_X, -1.0, []],
		&"look_right": [JOY_AXIS_RIGHT_X, 1.0, []],
		&"look_up": [JOY_AXIS_RIGHT_Y, -1.0, []],
		&"look_down": [JOY_AXIS_RIGHT_Y, 1.0, []],
	}
	for action_name: StringName in axes:
		_add_action(action_name, STICK_DEADZONE)
		_add_joy_axis(action_name, axes[action_name][0], axes[action_name][1])
		for keycode: Key in axes[action_name][2]:
			_add_key(action_name, keycode)

	_add_action(&"menu_left", MENU_DEADZONE)
	_add_joy_axis(&"menu_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_button(&"menu_left", JOY_BUTTON_DPAD_LEFT)
	_add_key(&"menu_left", KEY_A)
	_add_key(&"menu_left", KEY_LEFT)

	_add_action(&"menu_right", MENU_DEADZONE)
	_add_joy_axis(&"menu_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_button(&"menu_right", JOY_BUTTON_DPAD_RIGHT)
	_add_key(&"menu_right", KEY_D)
	_add_key(&"menu_right", KEY_RIGHT)

	_add_action(&"jump")
	_add_joy_button(&"jump", JUMP_BUTTON)
	_add_key(&"jump", KEY_SPACE)

	_add_action(&"dash")
	_add_joy_button(&"dash", DASH_BUTTON)
	_add_key(&"dash", KEY_K)

	_add_action(&"start")
	_add_joy_button(&"start", JOY_BUTTON_START)

	_add_action(&"pause")
	_add_joy_button(&"pause", JOY_BUTTON_START)
	_add_key(&"pause", KEY_P)

	# ui_accept existe déjà (Entrée, Espace) : on y ajoute le A de la manette.
	_add_joy_button(&"ui_accept", CONFIRM_BUTTON)

	_add_action(&"menu_back")
	_add_joy_button(&"menu_back", BACK_BUTTON)
	_add_key(&"menu_back", KEY_BACKSPACE)

	# Émis aussi au démarrage pour les manettes déjà branchées.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _add_action(action_name: StringName, deadzone := 0.5) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name, deadzone)


func _add_key(action_name: StringName, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.device = -1 # Tous les claviers.
	InputMap.action_add_event(action_name, event)


func _add_joy_axis(action_name: StringName, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = -1 # Toutes les manettes.
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action_name, event)


func _add_joy_button(action_name: StringName, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = -1 # Toutes les manettes.
	event.button_index = button
	InputMap.action_add_event(action_name, event)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		print("Manette %d connectée (%s)" % [device, Input.get_joy_name(device)])
	else:
		print("Manette %d déconnectée" % device)
