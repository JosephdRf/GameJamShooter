extends Control
## Écran hôte/IP : héberger la partie, ou rejoindre l'hôte avec son IP.
##   - Héberger -> sélection d'équipe.
##   - Rejoindre -> connexion réussie ? oui : sélection d'équipe ; non : message ici.
## Un seul hôte par réseau : si LanDiscovery détecte déjà une partie, "Héberger"
## est désactivé et l'IP de l'hôte est pré-remplie.
## Échap : annule la connexion en cours, sinon revient à l'écran d'accueil.

const SETTINGS_PATH := "user://settings.cfg"

const INSTRUCTIONS := """[font_size=26][b]Avant de lancer une partie[/b][/font_size]

[b]1. Même réseau.[/b] Tous les ordinateurs sur le même Wi-Fi : le plus simple est le [b]partage de connexion du téléphone[/b] de l'hôte (eduroam et les Wi-Fi d'école bloquent souvent les connexions entre ordinateurs).

[b]2. Un seul hôte.[/b] Un ordinateur clique sur [b]Héberger[/b] : son adresse IP s'affiche. Sur Mac, accepter la demande « connexions entrantes » si elle apparaît. Une fois la partie détectée sur le réseau, les autres ne peuvent plus héberger.

[b]3. Les autres rejoignent.[/b] Ils saisissent l'IP de l'hôte (pré-remplie si la partie est détectée) et cliquent sur [b]Rejoindre[/b].

[b]4. Choix des équipes.[/b] Chacun choisit son cube, valide, puis l'hôte lance la partie."""

var _connecting := false

@onready var _instructions: RichTextLabel = %Instructions
@onready var _host_button: Button = %HostButton
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _join_button: Button = %JoinButton
@onready var _discovered: Label = %Discovered
@onready var _status: Label = %Status
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(Music.MENU)
	_instructions.text = INSTRUCTIONS
	_address_edit.text = _load_last_address()

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_address_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_back_button.pressed.connect(_back)

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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _connecting:
			NetworkManager.leave()
			_connecting = false
			_status.text = "Connexion annulée."
			_refresh()
			_join_button.grab_focus()
		else:
			_back()


func _refresh() -> void:
	var hosts := LanDiscovery.get_hosts()
	var host_taken := not hosts.is_empty()
	_host_button.disabled = _connecting or host_taken
	_host_button.text = "Partie déjà hébergée" if host_taken else "Héberger la partie"
	_join_button.disabled = _connecting
	_address_edit.editable = not _connecting
	if host_taken:
		_discovered.text = "Partie détectée sur %s : rejoins-la." % hosts[0]
		# Pré-remplit l'IP, sauf si le joueur est en train d'en saisir une autre.
		if not _connecting and not _address_edit.has_focus():
			_address_edit.text = hosts[0]
		if _host_button.has_focus():
			_join_button.grab_focus()
	else:
		_discovered.text = ""


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
	_status.text = "Connexion à %s… (Échap pour annuler)" % address
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
