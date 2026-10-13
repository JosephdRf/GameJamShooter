extends Control
## Sélection d'équipe : 4 cartes (joueurs 1-2 = équipe bleue, 3-4 = équipe rouge).
##
## Chaque ordinateur déplace son choix avec le joystick gauche ou ← →. Un joueur
## déjà pris par un autre ordinateur est grisé et sauté.
## A (ou Entrée) valide le choix et place le curseur sur "Lancer la partie" ;
## B (ou Retour arrière) annule la validation. L'hôte lance la partie avec Start
## ou le bouton. Échap / "Quitter le salon" -> écran hôte/IP.
## Nécessite une session réseau (sinon retour à l'écran hôte/IP).

const CARD_SIZE := Vector2(210, 250)
const TAKEN_COLOR := Color(0.24, 0.25, 0.28)

var _cards: Array[PanelContainer] = []
var _card_titles: Array[Label] = []
var _card_states: Array[Label] = []

@onready var _info: Label = %Info
@onready var _hint: Label = %Hint
@onready var _team_slots: Array[HBoxContainer] = [
	$Margin/Layout/Teams/Team1/Slots,
	$Margin/Layout/Teams/Team2/Slots,
]
@onready var _leave_button: Button = %LeaveButton
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	if not NetworkManager.is_online():
		set_process(false)
		_leave.call_deferred()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_cards()
	_leave_button.pressed.connect(_leave)
	_start_button.pressed.connect(NetworkManager.start_match)
	_start_button.visible = multiplayer.is_server()
	NetworkManager.slots_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if not NetworkManager.is_my_slot_locked():
		if Input.is_action_just_pressed(&"menu_left"):
			NetworkManager.move_my_slot(-1)
		if Input.is_action_just_pressed(&"menu_right"):
			NetworkManager.move_my_slot(1)
	if multiplayer.is_server() and Input.is_action_just_pressed(&"start"):
		NetworkManager.start_match()


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


func _set_locked(value: bool) -> void:
	NetworkManager.set_my_slot_locked(value)
	if value and multiplayer.is_server():
		_start_button.grab_focus()
	else:
		get_viewport().gui_release_focus() # ← → servent à choisir le joueur, pas à naviguer.


func _leave() -> void:
	NetworkManager.leave()
	get_tree().change_scene_to_file(Screens.CONNECT)


func _build_cards() -> void:
	for player_id in range(1, NetworkManager.MAX_PLAYERS + 1):
		var card := PanelContainer.new()
		card.custom_minimum_size = CARD_SIZE
		card.add_theme_stylebox_override(&"panel", StyleBoxFlat.new())

		var content := VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override(&"separation", 12)
		card.add_child(content)

		var title := Label.new()
		title.text = "Joueur %d" % player_id
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override(&"font_size", 30)
		content.add_child(title)

		var state := Label.new()
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(state)

		_team_slots[Player.team_of(player_id) - 1].add_child(card)
		_cards.append(card)
		_card_titles.append(title)
		_card_states.append(state)


func _refresh() -> void:
	var my_id := multiplayer.get_unique_id()
	for i in _cards.size():
		var player_id := i + 1
		var owner_id: int = NetworkManager.slots.get(player_id, 0)
		var color := Player.color_of(player_id)
		var style := _cards[i].get_theme_stylebox(&"panel") as StyleBoxFlat
		style.set_corner_radius_all(16)
		style.set_border_width_all(0)
		var text_color := Color.WHITE

		var is_locked: bool = NetworkManager.locked.get(player_id, false)
		if owner_id == my_id:
			style.bg_color = color
			style.set_border_width_all(6)
			style.border_color = Color.WHITE
			_card_states[i].text = "✔  TOI  ·  prêt" if is_locked else "◀   TOI   ▶"
		elif owner_id == 0:
			style.bg_color = color.darkened(0.6)
			text_color = Color(1, 1, 1, 0.75)
			_card_states[i].text = "Libre"
		else:
			style.bg_color = TAKEN_COLOR
			text_color = Color(0.55, 0.56, 0.6)
			_card_states[i].text = ("Pris par l'hôte" if owner_id == 1 else "Pris") + ("  ·  prêt" if is_locked else "")

		_card_titles[i].add_theme_color_override(&"font_color", text_color)
		_card_states[i].add_theme_color_override(&"font_color", text_color)

	if NetworkManager.is_my_slot_locked():
		_hint.text = "B (ou Retour arrière) pour changer de joueur  ·  Échap pour quitter le salon"
	else:
		_hint.text = "Joystick gauche ou ← → pour choisir  ·  A (ou Entrée) pour valider  ·  Échap pour quitter le salon"

	var count := NetworkManager.get_connected_count()
	if multiplayer.is_server():
		var addresses := NetworkManager.get_local_ipv4_addresses()
		var ip_text := "  ou  ".join(addresses) if not addresses.is_empty() else "introuvable (es-tu connecté à un réseau ?)"
		_info.text = "Tu héberges la partie. Les autres ordinateurs doivent rejoindre l'IP :  %s\nOrdinateurs connectés : %d / %d" % [ip_text, count, NetworkManager.MAX_PLAYERS]
	else:
		_info.text = "Connecté à l'hôte  ·  Ordinateurs connectés : %d / %d\nEn attente que l'hôte lance la partie…" % [count, NetworkManager.MAX_PLAYERS]
