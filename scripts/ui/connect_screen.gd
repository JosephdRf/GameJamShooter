extends Control
## Écran hôte/IP, au style de la sélection d'équipe : serviette bleue « Héberger »,
## serviette rouge avec l'IP de l'hôte et « Rejoindre », bulle « Quitter ».
##   - Héberger -> sélection d'équipe.
##   - Rejoindre -> connexion réussie ? oui : sélection d'équipe ; non : message ici.
## Un seul hôte par réseau : si LanDiscovery détecte déjà une partie, "Héberger"
## est grisé et l'IP de l'hôte est pré-remplie.
## Les boutons grossissent au survol (et au focus clavier / manette).
## Échap, B / Retour arrière (hors saisie de l'IP) ou « Quitter » : annule la connexion
## en cours, sinon revient à l'écran d'accueil.

const SETTINGS_PATH := "user://settings.cfg"
## Échelle d'un bouton serviette survolé, et de la bulle « Quitter » survolée.
const BUTTON_HOVER_SCALE := 1.06
const BUBBLE_HOVER_SCALE := 1.12
## Vitesse de l'animation d'échelle (plus élevé = plus rapide).
const SCALE_SPEED := 14.0
## Teinte d'un bouton désactivé.
const DISABLED_MODULATE := Color(0.5, 0.52, 0.58)
const NETWORK_TIP := "Tous les ordinateurs doivent être sur le même partage de connexion"

var _connecting := false
## Bouton -> vrai tant que la souris le survole.
var _hovered := {}

@onready var _info: Label = %Info
@onready var _host_button: TextureButton = %HostButton
@onready var _host_text: Label = $Layout/Towel1/HostButton/Text
@onready var _host_hint: Label = %HostHint
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _join_button: TextureButton = %JoinButton
@onready var _status: Label = %Status
@onready var _leave_button: TextureButton = %LeaveButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(Music.MENU)
	_address_edit.text = _load_last_address()

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_leave_button.pressed.connect(_cancel_or_back)
	for button: BaseButton in [_host_button, _join_button, _leave_button]:
		button.mouse_entered.connect(func() -> void: _hovered[button] = true)
		button.mouse_exited.connect(func() -> void: _hovered[button] = false)

	NetworkManager.connection_succeeded.connect(_go_to_team_select)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	LanDiscovery.hosts_changed.connect(_refresh)
	LanDiscovery.start_listening()

	# Message laissé par une partie interrompue (ex. l'hôte est parti).
	_status.text = NetworkManager.last_error
	NetworkManager.last_error = ""
	_host_button.grab_focus()
	_refresh()


func _exit_tree() -> void:
	LanDiscovery.stop_listening()


func _process(delta: float) -> void:
	# La souris l'emporte sur le focus : seul le bouton survolé grossit.
	var mouse_over_any: bool = _hovered.values().has(true)
	for button: BaseButton in [_host_button, _join_button, _leave_button]:
		var target := 1.0
		if not button.disabled and (_hovered.get(button, false) or (button.has_focus() and not mouse_over_any)):
			target = BUBBLE_HOVER_SCALE if button == _leave_button else BUTTON_HOVER_SCALE
		button.scale = button.scale.lerp(Vector2.ONE * target, 1.0 - exp(-SCALE_SPEED * delta))


func _unhandled_input(event: InputEvent) -> void:
	# Retour arrière dans le champ IP efface un caractère : le champ le consomme avant d'arriver ici.
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"menu_back"):
		get_viewport().set_input_as_handled()
		_cancel_or_back()


func _cancel_or_back() -> void:
	if not _connecting:
		_back()
		return
	NetworkManager.leave()
	_connecting = false
	_status.text = "Connexion annulée."
	_refresh()
	_join_button.grab_focus()


func _refresh() -> void:
	var hosts := LanDiscovery.get_hosts()
	var host_taken := not hosts.is_empty()
	_host_button.disabled = _connecting or host_taken
	_host_button.modulate = DISABLED_MODULATE if _host_button.disabled else Color.WHITE
	_host_text.text = "Déjà hébergée" if host_taken else "Héberger"
	_host_text.add_theme_font_size_override(&"font_size", 36 if host_taken else 44)
	_host_hint.text = "Une partie existe déjà\nsur ce réseau" if host_taken else "Crée la partie\nsur cet ordinateur"
	_join_button.disabled = _connecting
	_join_button.modulate = DISABLED_MODULATE if _join_button.disabled else Color.WHITE
	_address_edit.editable = not _connecting
	if host_taken:
		_info.text = "Partie détectée sur %s : rejoins-la." % hosts[0]
		# Pré-remplit l'IP, sauf si le joueur est en train d'en saisir une autre.
		if not _connecting and not _address_edit.has_focus():
			_address_edit.text = hosts[0]
		if _host_button.has_focus():
			_join_button.grab_focus()
	else:
		_info.text = NETWORK_TIP


func _on_host_pressed() -> void:
	var err := NetworkManager.host()
	match err:
		OK:
			_go_to_team_select()
		ERR_ALREADY_EXISTS:
			_status.text = "Une partie est déjà hébergée sur ce réseau : rejoins-la."
		_:
			_status.text = "Impossible d'héberger (port %d déjà utilisé ?) — erreur %d" % [NetworkManager.PORT, err]


func _on_join_pressed() -> void:
	if _connecting:
		return
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		_status.text = "Saisis l'adresse IP affichée sur l'ordinateur de l'hôte."
		_address_edit.grab_focus()
		return
	if NetworkManager.join(address) != OK:
		_status.text = "Adresse invalide : %s" % address
		return
	_save_last_address(address)
	_connecting = true
	_status.text = "Connexion à %s… (Retour pour annuler)" % address
	_refresh()


func _on_connection_failed(reason: String) -> void:
	_connecting = false
	_status.text = reason
	_refresh()
	_join_button.grab_focus()


func _go_to_team_select() -> void:
	get_tree().change_scene_to_file(Screens.TEAM_SELECT)


func _back() -> void:
	get_tree().change_scene_to_file(Screens.TITLE)


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
