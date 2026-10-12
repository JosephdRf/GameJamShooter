extends Node
## Crée les actions d'entrée de chaque joueur au démarrage.
##
## Pour chaque joueur N (1 à 4), les actions suivantes sont créées :
##   pN_left, pN_right, pN_up, pN_down, pN_jump        (déplacement / saut)
##   pN_look_left, pN_look_right, pN_look_up, pN_look_down   (caméra)
##
## Attribution des périphériques :
##   - Clavier + souris/trackpad -> joueur 1 :
##     Z/Q/S/D (ou flèches) = déplacement, Espace = saut, souris/trackpad = caméra
##     (touches *physiques* : Z/Q/S/D en AZERTY = W/A/S/D en QWERTY)
##   - Manette d'index K (0, 1, 2, 3) -> joueur K + 1 :
##     joystick gauche = déplacement, joystick droit = caméra, B = saut

const MAX_PLAYERS := 4
const KEYBOARD_PLAYER := 1
const STICK_DEADZONE := 0.15

## Godot utilise une disposition *positionnelle* (style Xbox) pour les boutons :
## JOY_BUTTON_A = bouton du BAS, soit le bouton "B" d'une manette Switch Pro
## (et A sur Xbox, Croix sur PlayStation). Cf. doc de JoyButton.
const JUMP_BUTTON := JOY_BUTTON_A


func _ready() -> void:
	for player_id in range(1, MAX_PLAYERS + 1):
		_setup_player_actions(player_id)
	# Émis aussi au démarrage pour les manettes déjà branchées.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


static func action(player_id: int, action_name: StringName) -> StringName:
	return StringName("p%d_%s" % [player_id, action_name])


func _setup_player_actions(player_id: int) -> void:
	var device := player_id - 1

	var bindings := {
		&"left": [JOY_AXIS_LEFT_X, -1.0, [KEY_A, KEY_LEFT]],
		&"right": [JOY_AXIS_LEFT_X, 1.0, [KEY_D, KEY_RIGHT]],
		&"up": [JOY_AXIS_LEFT_Y, -1.0, [KEY_W, KEY_UP]],
		&"down": [JOY_AXIS_LEFT_Y, 1.0, [KEY_S, KEY_DOWN]],
		# Caméra : au clavier, elle se contrôle à la souris (voir PlayerCamera).
		&"look_left": [JOY_AXIS_RIGHT_X, -1.0, []],
		&"look_right": [JOY_AXIS_RIGHT_X, 1.0, []],
		&"look_up": [JOY_AXIS_RIGHT_Y, -1.0, []],
		&"look_down": [JOY_AXIS_RIGHT_Y, 1.0, []],
	}
	for action_name in bindings:
		var name := action(player_id, action_name)
		_add_action(name, STICK_DEADZONE)
		var axis: int = bindings[action_name][0]
		var axis_value: float = bindings[action_name][1]
		_add_joy_axis(name, device, axis, axis_value)
		if player_id == KEYBOARD_PLAYER:
			for keycode: Key in bindings[action_name][2]:
				_add_key(name, keycode)

	var jump := action(player_id, &"jump")
	_add_action(jump)
	_add_joy_button(jump, device, JUMP_BUTTON)
	if player_id == KEYBOARD_PLAYER:
		_add_key(jump, KEY_SPACE)


func _add_action(name: StringName, deadzone := 0.5) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, deadzone)


func _add_key(name: StringName, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.device = -1 # Tous les claviers.
	InputMap.action_add_event(name, event)


func _add_joy_axis(name: StringName, device: int, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(name, event)


func _add_joy_button(name: StringName, device: int, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	InputMap.action_add_event(name, event)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_log_joypad(device, connected)


func _log_joypad(device: int, connected: bool) -> void:
	if connected:
		print("Manette %d connectée (%s) -> joueur %d" % [device, Input.get_joy_name(device), device + 1])
	else:
		print("Manette %d déconnectée" % device)
