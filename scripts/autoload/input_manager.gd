extends Node
## Les actions d'entrée sont définies dans Projet › Paramètres du projet › Contrôles
## (clavier et manettes, à modifier là-bas). Le code n'utilise que celles-ci :
##   move_left/right/up/down : se déplacer (Z/Q/S/D ou flèches / stick gauche)
##   look_left/right/up/down : tourner la caméra (stick droit ; la souris est gérée par PlayerCamera)
##   jump                    : sauter (Espace / bouton du bas)
##   dash                    : dash (Maj / bouton de gauche)
##   shoot                   : tirer, maintenu = en continu (clic gauche, T / gâchette droite)
##   water_cannon            : canon à eau (clic droit / gâchette ou bouton haut gauche)
##   aim                     : viser, maintenu = zoom sans aide à la visée (clic gauche / gâchette gauche)
##   pause                   : menu pause en jeu, hôte (P / Start)
##   start                   : lancer depuis l'accueil et le choix des équipes (Start)
##   menu_left/right/up/down : choisir son joueur (Z/Q/S/D ou flèches / croix, stick gauche)
##   menu_back               : annuler son choix (Retour arrière / bouton du bas)
##   ui_accept (de Godot)    : valider (Entrée, Espace / bouton de droite)
##   ui_cancel (de Godot)    : quitter le jeu (Échap)
##   debug_damage            : version de développement, 10 dégâts à son canard (H)
##   debug_mode              : afficher / masquer le debug mode : PV, rectangle de l'aide à la visée (Ctrl + D)
##
## Les touches sont *physiques* : Z/Q/S/D en AZERTY = W/A/S/D en QWERTY.
## Les boutons de manette sont repérés par leur *position* (noms Xbox dans Godot) :
##   bouton du bas    (Joypad Button 0) = B sur Switch Pro, Croix sur PlayStation
##   bouton de droite (Joypad Button 1) = A sur Switch Pro, Rond sur PlayStation
##   bouton de gauche (Joypad Button 2) = Y sur Switch Pro, Carré sur PlayStation
##   gâchettes (axes 4 et 5)            = ZL / ZR sur Switch Pro, L2 / R2 sur PlayStation
##   Start (Joypad Button 6)            = + sur Switch Pro, Options sur PlayStation
##
## Ce script ne crée aucune action : il filtre les axes (sticks et gâchettes) des
## manettes qui envoient de fausses valeurs (vu avec une Switch Pro sous macOS : stick
## gauche annoncé poussé et ZR enfoncée sans que personne n'y touche). Un axe d'une
## manette ne compte qu'une fois vu au repos, sinon le canard avancerait ou tirerait
## tout seul. Les boutons, eux, marchent toujours.

## Axe considéré « au repos » sous cette valeur (stick centré, gâchette relâchée).
const AXIS_REST := 0.2

## Famille de l'appareil utilisé en dernier, pour afficher les bonnes touches (cf. ButtonPrompt).
enum DeviceType { KEYBOARD, PLAYSTATION, NINTENDO, XBOX }

## Émis quand le joueur passe du clavier à une manette (ou d'une manette à une autre famille).
signal device_type_changed

var device_type := DeviceType.KEYBOARD
## Délai après la connexion d'une manette avant de regarder ses axes (ms) : le temps
## que leurs vraies valeurs arrivent.
const AXIS_CHECK_DELAY := 500

## Axes de manette des actions (tous appareils), retirés de l'InputMap au démarrage :
## [action, InputEventJoypadMotion]. Remis manette par manette (dans _trust_axis).
var _axis_bindings: Array[Array] = []
## Axes utilisés par au moins une action.
var _axes: Array[JoyAxis] = []
## Manette -> { axe: true } pour ses axes déjà pris en compte.
var _trusted_axes := {}
## Manette -> instant de connexion (ms).
var _connected_at := {}


func _ready() -> void:
	for action_name in InputMap.get_actions():
		for event in InputMap.action_get_events(action_name):
			var motion := event as InputEventJoypadMotion
			if motion and motion.device == -1:
				InputMap.action_erase_event(action_name, motion)
				_axis_bindings.append([action_name, motion])
				if motion.axis not in _axes:
					_axes.append(motion.axis)
	process_mode = Node.PROCESS_MODE_ALWAYS # Vérifie les axes même en pause.
	for device in Input.get_connected_joypads():
		_connected_at[device] = Time.get_ticks_msec()
	# Émis aussi au démarrage pour les manettes déjà branchées.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Repère l'appareil utilisé : clavier / souris, ou manette (axe déjà jugé fiable).
func _input(event: InputEvent) -> void:
	var type := -1
	if event is InputEventKey or event is InputEventMouseButton:
		type = DeviceType.KEYBOARD
	elif event is InputEventJoypadButton and event.pressed:
		type = joypad_type(event.device)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5 \
			and _trusted_axes.get(event.device, {}).has(event.axis):
		type = joypad_type(event.device)
	if type != -1 and type != device_type:
		device_type = type as DeviceType
		device_type_changed.emit()


## Famille de la manette `device`, d'après son nom (Xbox par défaut).
static func joypad_type(device: int) -> DeviceType:
	var joy_name := Input.get_joy_name(device).to_lower()
	for word in ["nintendo", "switch", "joy-con", "pro controller"]:
		if word in joy_name:
			return DeviceType.NINTENDO
	for word in ["playstation", "dualsense", "dualshock", "sony", "ps3", "ps4", "ps5"]:
		if word in joy_name:
			return DeviceType.PLAYSTATION
	return DeviceType.XBOX


func _process(_delta: float) -> void:
	for device: int in _connected_at:
		if Time.get_ticks_msec() - _connected_at[device] < AXIS_CHECK_DELAY:
			continue
		var trusted: Dictionary = _trusted_axes.get_or_add(device, {})
		for axis in _axes:
			if not trusted.has(axis) and absf(Input.get_joy_axis(device, axis)) < AXIS_REST:
				_trust_axis(device, axis)


## L'axe `axis` de la manette `device` pilote désormais ses actions.
func _trust_axis(device: int, axis: JoyAxis) -> void:
	_trusted_axes[device][axis] = true
	for binding in _axis_bindings:
		var motion: InputEventJoypadMotion = binding[1]
		if motion.axis == axis:
			var event := motion.duplicate() as InputEventJoypadMotion
			event.device = device
			InputMap.action_add_event(binding[0], event)


func _forget_axes(device: int) -> void:
	_trusted_axes.erase(device)
	for binding in _axis_bindings:
		for event in InputMap.action_get_events(binding[0]):
			if event is InputEventJoypadMotion and event.device == device:
				InputMap.action_erase_event(binding[0], event)
		Input.action_release(binding[0]) # Ex. gâchette tenue au moment de la déconnexion.


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		print("Manette %d connectée (%s)" % [device, Input.get_joy_name(device)])
		_connected_at[device] = Time.get_ticks_msec()
	else:
		print("Manette %d déconnectée" % device)
		_connected_at.erase(device)
		_forget_axes(device)
