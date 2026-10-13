extends Node
## Crée les actions d'entrée au démarrage.
##
## Chaque ordinateur contrôle UN seul cube (celui choisi dans le lobby), avec
## le clavier/trackpad OU n'importe quelle manette branchée :
##   move_left/right/up/down : Z/Q/S/D (ou flèches) / joystick gauche
##   look_left/right/up/down : joystick droit (la souris est gérée par PlayerCamera)
##   jump                    : Espace / bouton du bas (B sur Switch Pro)
##   dash                    : K / bouton de gauche (Y sur Switch Pro, Carré sur PlayStation)
##   shoot                   : T / gâchettes (ZL et ZR sur Switch Pro, L2 et R2 sur PlayStation)
##   start                   : bouton Start (+ sur Switch Pro)
##   pause (en jeu, hôte)    : P / bouton Start (+ sur Switch Pro)
##   ui_accept (menus)       : Entrée / Espace / A sur Switch Pro (bouton de droite)
##   menu_back (menus)       : Retour arrière / B sur Switch Pro (bouton du bas)
##   menu_left/menu_right    : comme move_left/right, mais avec une zone morte
##                             plus large pour naviguer dans les menus
##
## Les touches sont *physiques* : Z/Q/S/D en AZERTY = W/A/S/D en QWERTY.
##
## Manettes qui envoient de fausses valeurs (vu avec une Switch Pro sous macOS :
## stick gauche annoncé poussé et ZR enfoncée sans que personne n'y touche) :
##   - les sticks d'une manette ne comptent qu'une fois vus au repos (centrés) ;
##   - une gâchette ne compte qu'une fois vue relâchée.
## Sinon le cube avancerait tout seul. Les boutons, eux, marchent toujours.

const STICK_DEADZONE := 0.15
## Sticks considérés « au repos » sous cette valeur, sur chaque axe.
const STICK_CENTERED := 0.2
const STICK_AXES: Array[JoyAxis] = [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
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
## Gâchettes (axes de 0 à 1) qui déclenchent `shoot` ; seuils d'appui / de relâchement.
const SHOOT_TRIGGERS: Array[JoyAxis] = [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
const TRIGGER_PRESSED := 0.6
const TRIGGER_RELEASED := 0.3

## (manette, gâchette) -> enfoncée ? Absente tant que la gâchette n'a jamais été vue
## relâchée : une gâchette coincée (ou mal lue, vu sur une Switch Pro sous macOS)
## est ignorée au lieu de bloquer le tir.
var _trigger_down := {}
## Associations [action, axe, sens] des sticks, ajoutées à l'InputMap manette par
## manette (dans _trust_sticks) une fois ses sticks vus au repos.
var _stick_bindings: Array[Array] = []
## Manettes dont les sticks sont pris en compte.
var _trusted_sticks := {}
## Manette -> instant de connexion (ms). Ses sticks ne sont vérifiés qu'après
## STICK_CHECK_DELAY, le temps que les vraies valeurs des axes arrivent.
var _connected_at := {}
const STICK_CHECK_DELAY := 500


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

	# Gâchettes : gérées à part dans _input() (voir _trigger_down), pas dans l'InputMap.
	_add_action(&"shoot")
	_add_key(&"shoot", KEY_T)

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

	# Actions de menu intégrées à Godot (ui_left…) : leurs sticks passent aussi par le filtre.
	for action_name: StringName in [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		for event in InputMap.action_get_events(action_name):
			if event is InputEventJoypadMotion:
				InputMap.action_erase_event(action_name, event)
				_add_joy_axis(action_name, event.axis, event.axis_value)

	process_mode = Node.PROCESS_MODE_ALWAYS # Vérifie les sticks même en pause.
	for device in Input.get_connected_joypads():
		_connected_at[device] = Time.get_ticks_msec()
	# Émis aussi au démarrage pour les manettes déjà branchées.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Chaque appui sur une gâchette = un tir (« shoot » appuyé puis relâché aussitôt).
func _input(event: InputEvent) -> void:
	var motion := event as InputEventJoypadMotion
	if motion == null or not SHOOT_TRIGGERS.has(motion.axis):
		return
	var trigger := Vector2i(motion.device, motion.axis)
	if motion.axis_value < TRIGGER_RELEASED:
		_trigger_down[trigger] = false
	elif motion.axis_value > TRIGGER_PRESSED and _trigger_down.get(trigger) == false:
		_trigger_down[trigger] = true
		_tap(&"shoot")


func _tap(action_name: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	Input.parse_input_event(event)
	# Relâché après deux images physiques : le joueur (qui lit l'entrée en physique) voit l'appui.
	await get_tree().physics_frame
	await get_tree().physics_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func _add_action(action_name: StringName, deadzone := 0.5) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name, deadzone)


func _add_key(action_name: StringName, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.device = -1 # Tous les claviers.
	InputMap.action_add_event(action_name, event)


## Stick : pas ajouté tout de suite à l'InputMap (voir _trust_sticks).
func _add_joy_axis(action_name: StringName, axis: JoyAxis, value: float) -> void:
	_stick_bindings.append([action_name, axis, value])


func _process(_delta: float) -> void:
	for device: int in _connected_at:
		if not _trusted_sticks.has(device) and Time.get_ticks_msec() - _connected_at[device] > STICK_CHECK_DELAY \
				and _sticks_centered(device):
			_trust_sticks(device)


func _sticks_centered(device: int) -> bool:
	for axis in STICK_AXES:
		if absf(Input.get_joy_axis(device, axis)) > STICK_CENTERED:
			return false
	return true


## Les sticks de `device` pilotent désormais les actions.
func _trust_sticks(device: int) -> void:
	_trusted_sticks[device] = true
	for binding in _stick_bindings:
		var event := InputEventJoypadMotion.new()
		event.device = device
		event.axis = binding[1]
		event.axis_value = binding[2]
		InputMap.action_add_event(binding[0], event)


func _forget_sticks(device: int) -> void:
	_trusted_sticks.erase(device)
	for binding in _stick_bindings:
		for event in InputMap.action_get_events(binding[0]):
			if event is InputEventJoypadMotion and event.device == device:
				InputMap.action_erase_event(binding[0], event)
		Input.action_release(binding[0])


func _add_joy_button(action_name: StringName, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = -1 # Toutes les manettes.
	event.button_index = button
	InputMap.action_add_event(action_name, event)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		print("Manette %d connectée (%s)" % [device, Input.get_joy_name(device)])
		_connected_at[device] = Time.get_ticks_msec()
	else:
		print("Manette %d déconnectée" % device)
		_connected_at.erase(device)
		_forget_sticks(device)
		for trigger: Vector2i in _trigger_down.keys():
			if trigger.x == device:
				_trigger_down.erase(trigger)
