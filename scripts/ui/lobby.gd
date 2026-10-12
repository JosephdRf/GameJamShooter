extends Control
## Écran de démarrage : héberger / rejoindre une partie, puis choisir son joueur.
##
## Écran "Home"   : consignes + boutons Héberger / Rejoindre.
## Écran "Select" : 4 cartes (joueurs 1-2 = équipe 1, 3-4 = équipe 2). Chaque
## ordinateur déplace son choix avec le joystick gauche ou ← →. Un joueur déjà
## pris par un autre ordinateur est grisé et sauté.
## A (ou Entrée) valide le choix et place le curseur sur "Lancer la partie" ;
## B (ou Retour arrière) annule la validation. Start lance la partie (hôte).

const SETTINGS_PATH := "user://settings.cfg"
const CARD_SIZE := Vector2(210, 250)
const TAKEN_COLOR := Color(0.24, 0.25, 0.28)

const INSTRUCTIONS := """[font_size=26][b]Avant de lancer une partie[/b][/font_size]

[b]1. Même réseau.[/b] Tous les ordinateurs sur le même Wi-Fi : le plus simple est le [b]partage de connexion du téléphone[/b] de l'hôte (eduroam et les Wi-Fi d'école bloquent souvent les connexions entre ordinateurs).

[b]2. Un seul hôte.[/b] Un ordinateur clique sur [b]Héberger[/b] : son adresse IP s'affiche. Sur Mac, accepter la demande « connexions entrantes » si elle apparaît.

[b]3. Les autres rejoignent.[/b] Ils saisissent l'IP de l'hôte et cliquent sur [b]Rejoindre[/b].

[b]4. Choix des joueurs.[/b] Chacun choisit son cube avec le joystick gauche (ou ← →) et valide avec [b]A[/b] (ou Entrée). Équipe 1 : [color=#e5484d]rouge[/color] et [color=#f5c400]jaune[/color]  ·  Équipe 2 : [color=#3b82f6]bleu[/color] et [color=#30a46c]vert[/color].

[b]5. C'est parti.[/b] L'hôte appuie sur [b]Start[/b] (bouton +) ou valide « Lancer la partie ». Les joueurs non choisis restent immobiles."""

var _cards: Array[PanelContainer] = []
var _card_titles: Array[Label] = []
var _card_states: Array[Label] = []
var _connecting := false

@onready var _home: Control = $Margin/Layout/Home
@onready var _select: Control = $Margin/Layout/Select
@onready var _instructions: RichTextLabel = $Margin/Layout/Home/Instructions
@onready var _host_button: Button = $Margin/Layout/Home/Actions/HostButton
@onready var _address_edit: LineEdit = $Margin/Layout/Home/Actions/AddressEdit
@onready var _join_button: Button = $Margin/Layout/Home/Actions/JoinButton
@onready var _status: Label = $Margin/Layout/Home/Actions/Status
@onready var _quit_button: Button = $Margin/Layout/Home/Actions/QuitButton
@onready var _info: Label = $Margin/Layout/Select/Info
@onready var _hint: Label = $Margin/Layout/Select/Hint
@onready var _team_slots: Array[HBoxContainer] = [
	$Margin/Layout/Select/Teams/Team1/Slots,
	$Margin/Layout/Select/Teams/Team2/Slots,
]
@onready var _leave_button: Button = $Margin/Layout/Select/Buttons/LeaveButton
@onready var _start_button: Button = $Margin/Layout/Select/Buttons/StartButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_instructions.text = INSTRUCTIONS
	_build_cards()

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_quit_button.pressed.connect(get_tree().quit)
	_leave_button.pressed.connect(_leave)
	_start_button.pressed.connect(NetworkManager.start_match)

	NetworkManager.slots_changed.connect(_refresh_select)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	_address_edit.text = _load_last_address()
	_show_home(NetworkManager.last_error)
	NetworkManager.last_error = ""


func _process(_delta: float) -> void:
	if not _select.visible:
		return
	if not NetworkManager.is_my_slot_locked():
		if Input.is_action_just_pressed(&"menu_left"):
			NetworkManager.move_my_slot(-1)
		if Input.is_action_just_pressed(&"menu_right"):
			NetworkManager.move_my_slot(1)
	if multiplayer.is_server() and Input.is_action_just_pressed(&"start"):
		NetworkManager.start_match()


func _unhandled_input(event: InputEvent) -> void:
	# Les boutons qui ont le focus consomment ui_accept avant d'arriver ici.
	if _select.visible and event.is_action_pressed(&"ui_accept") and not NetworkManager.is_my_slot_locked():
		get_viewport().set_input_as_handled()
		_set_locked(true)
	elif _select.visible and event.is_action_pressed(&"menu_back") and NetworkManager.is_my_slot_locked():
		get_viewport().set_input_as_handled()
		_set_locked(false)
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _select.visible or _connecting:
			_leave()
		else:
			get_tree().quit()


func _set_locked(value: bool) -> void:
	NetworkManager.set_my_slot_locked(value)
	if value and multiplayer.is_server():
		_start_button.grab_focus()
	else:
		get_viewport().gui_release_focus() # ← → servent à choisir le joueur, pas à naviguer.


func _show_home(status := "") -> void:
	_connecting = false
	_home.visible = true
	_select.visible = false
	_set_home_enabled(true)
	_status.text = status
	_host_button.grab_focus()


func _show_select() -> void:
	_connecting = false
	_home.visible = false
	_select.visible = true
	get_viewport().gui_release_focus() # ← → servent à choisir le joueur, pas à naviguer.
	_start_button.visible = multiplayer.is_server()
	_refresh_select()


func _leave() -> void:
	NetworkManager.leave()
	_show_home()


func _set_home_enabled(enabled: bool) -> void:
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled
	_address_edit.editable = enabled


func _on_host_pressed() -> void:
	var err := NetworkManager.host()
	if err != OK:
		_status.text = "Impossible d'héberger (port %d déjà utilisé ?) — erreur %d" % [NetworkManager.PORT, err]
		return
	_show_select()


func _on_join_pressed() -> void:
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		_status.text = "Saisis l'adresse IP affichée sur l'ordinateur de l'hôte."
		_address_edit.grab_focus()
		return
	var err := NetworkManager.join(address)
	if err != OK:
		_status.text = "Adresse invalide : %s" % address
		return
	_save_last_address(address)
	_connecting = true
	_set_home_enabled(false)
	_status.text = "Connexion à %s… (Échap pour annuler)" % address


func _on_connection_succeeded() -> void:
	_show_select()


func _on_connection_failed(reason: String) -> void:
	_show_home(reason)


#region Cartes de choix des joueurs

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


func _refresh_select() -> void:
	if not _select.visible:
		return
	var my_id := multiplayer.get_unique_id()
	for i in _cards.size():
		var player_id := i + 1
		var owner_id: int = NetworkManager.slots.get(player_id, 0)
		var color := Player.PLAYER_COLORS[i]
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

#endregion


func _load_last_address() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return ""
	return config.get_value("network", "last_address", "")


func _save_last_address(address: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("network", "last_address", address)
	config.save(SETTINGS_PATH)
