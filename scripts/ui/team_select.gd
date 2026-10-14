extends Control
## Sélection d'équipe (maquette : assets/ui/team_select/maquette.png) : deux serviettes,
## bleue (joueurs 1-2) et rouge (joueurs 3-4), avec un bouton par joueur.
##
## Chaque ordinateur choisit son joueur avec le joystick gauche ou ← →, ou en cliquant
## sur un joueur libre. Un joueur déjà pris par un autre ordinateur est grisé et sauté.
## A (ou Entrée, ou un clic sur son propre joueur) valide le choix et place le curseur
## sur « Lancer » ; B (ou Retour arrière) annule la validation. L'hôte lance la partie
## avec Start ou la bulle « Lancer ». Échap / bulle « Quitter » -> écran hôte/IP.
## Les boutons grossissent au survol (et au focus clavier / manette) ; le joueur choisi
## par cet ordinateur reste un peu plus gros.
## Nécessite une session réseau (sinon retour à l'écran hôte/IP).

## Échelle d'un bouton survolé, et du joueur choisi par cet ordinateur.
const HOVER_SCALE := 1.12
const MINE_SCALE := 1.05
## Vitesse de l'animation d'échelle (plus élevé = plus rapide).
const SCALE_SPEED := 14.0
## Teinte d'un joueur pris par un autre ordinateur.
const TAKEN_MODULATE := Color(0.5, 0.52, 0.58)

## Bouton -> vrai tant que la souris le survole.
var _hovered := {}

@onready var _info: Label = %Info
@onready var _players: Array[TextureButton] = [%Player1, %Player2, %Player3, %Player4]
@onready var _leave_button: TextureButton = %LeaveButton
@onready var _start_button: TextureButton = %StartButton


func _ready() -> void:
	if not NetworkManager.is_online():
		set_process(false)
		_leave.call_deferred()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(Music.MENU)
	%AcceptHint/Label.text = "Sélectionner  (Entrée)"
	%BackHint/Label.text = "Annuler  (Retour arrière)"
	for i in _players.size():
		_players[i].pressed.connect(_on_player_pressed.bind(i + 1))
	for button: BaseButton in _players + [_start_button, _leave_button]:
		button.mouse_entered.connect(func() -> void: _hovered[button] = true)
		button.mouse_exited.connect(func() -> void: _hovered[button] = false)
	_leave_button.pressed.connect(_leave)
	_start_button.pressed.connect(NetworkManager.start_match)
	_start_button.visible = multiplayer.is_server()
	NetworkManager.slots_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if not NetworkManager.is_my_slot_locked():
		if Input.is_action_just_pressed(&"menu_left"):
			UiSounds.play_click()
			NetworkManager.move_my_slot(-1)
		if Input.is_action_just_pressed(&"menu_right"):
			UiSounds.play_click()
			NetworkManager.move_my_slot(1)
	if multiplayer.is_server() and Input.is_action_just_pressed(&"start"):
		UiSounds.play_confirm()
		NetworkManager.start_match()
	_animate_scales(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Les boutons qui ont le focus consomment ui_accept avant d'arriver ici.
	if event.is_action_pressed(&"ui_accept") and not NetworkManager.is_my_slot_locked():
		get_viewport().set_input_as_handled()
		_set_locked(true)
	elif event.is_action_pressed(&"menu_back") and NetworkManager.is_my_slot_locked():
		get_viewport().set_input_as_handled()
		_set_locked(false)
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()


## Clic sur un joueur : le choisir s'il est libre, valider (ou annuler) si c'est le sien.
## (Le son de validation est joué par UiSounds, branché sur tous les boutons.)
func _on_player_pressed(player_id: int) -> void:
	if NetworkManager.get_my_slot() == player_id:
		NetworkManager.set_my_slot_locked(not NetworkManager.is_my_slot_locked())
	elif not NetworkManager.is_my_slot_locked():
		NetworkManager.choose_slot(player_id)


func _set_locked(value: bool) -> void:
	if value:
		UiSounds.play_confirm()
	else:
		UiSounds.play_click()
	NetworkManager.set_my_slot_locked(value)
	if value and multiplayer.is_server():
		_start_button.grab_focus()
	else:
		get_viewport().gui_release_focus() # ← → servent à choisir le joueur, pas à naviguer.


func _leave() -> void:
	NetworkManager.leave()
	get_tree().change_scene_to_file(Screens.CONNECT)


## Grossit en douceur les boutons survolés / avec le focus, et le joueur choisi.
func _animate_scales(delta: float) -> void:
	var my_slot := NetworkManager.get_my_slot()
	for button: BaseButton in _players + [_start_button, _leave_button]:
		var target := 1.0
		if _hovered.get(button, false) or button.has_focus():
			target = HOVER_SCALE
		elif button in _players and _players.find(button) + 1 == my_slot:
			target = MINE_SCALE
		var weight := 1.0 - exp(-SCALE_SPEED * delta)
		button.scale = button.scale.lerp(Vector2.ONE * target, weight)


func _refresh() -> void:
	var my_id := multiplayer.get_unique_id()
	for i in _players.size():
		var player_id := i + 1
		var owner_id: int = NetworkManager.slots.get(player_id, 0)
		var is_locked: bool = NetworkManager.locked.get(player_id, false)
		var state: Label = _players[i].get_node(^"State")
		if owner_id == my_id:
			_players[i].modulate = Color.WHITE
			state.text = "Toi  ✔ prêt" if is_locked else "Toi"
		elif owner_id == 0:
			_players[i].modulate = Color.WHITE
			state.text = ""
		else:
			_players[i].modulate = TAKEN_MODULATE
			state.text = ("Pris par l'hôte" if owner_id == 1 else "Pris") + ("  ✔ prêt" if is_locked else "")

	var count := NetworkManager.get_connected_count()
	if multiplayer.is_server():
		var addresses := NetworkManager.get_local_ipv4_addresses()
		var ip_text := "  ou  ".join(addresses) if not addresses.is_empty() else "introuvable (es-tu connecté à un réseau ?)"
		_info.text = "Tu héberges la partie. Les autres ordinateurs doivent rejoindre l'IP : %s\nOrdinateurs connectés : %d / %d" % [ip_text, count, NetworkManager.MAX_PLAYERS]
	else:
		_info.text = "Connecté à l'hôte  ·  Ordinateurs connectés : %d / %d\nEn attente que l'hôte lance la partie…" % [count, NetworkManager.MAX_PLAYERS]
