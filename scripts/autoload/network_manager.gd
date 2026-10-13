extends Node
## Connexion réseau, choix des joueurs et lancement de la partie.
##
## Modèle "listen server" : l'ordinateur hôte est à la fois serveur et joueur,
## les autres ordinateurs se connectent à son adresse IP (port UDP 7777).
##   - L'hôte fait autorité sur l'attribution des joueurs (`slots`) et le lancement.
##   - Chaque ordinateur fait autorité sur la position de SON cube
##     (cf. Player et son nœud MultiplayerSynchronizer "Sync").
##   - Les joueurs non choisis restent sous l'autorité de l'hôte (cubes immobiles).
##
## Déroulé : host() / join() -> choix des joueurs (move_my_slot) -> start_match()
## -> tous les ordinateurs chargent la scène de jeu -> chacun appelle
## notify_game_ready() -> quand tous sont prêts, match_started est émis partout.
## Pendant la partie, l'hôte seul peut : mettre en pause (set_paused), revenir à
## la sélection d'équipe (return_to_team_select) et terminer le combat (end_match).
## Les changements d'écran sont faits ici pour que tous les ordinateurs suivent.

signal slots_changed
signal connection_succeeded
signal connection_failed(reason: String)
signal match_started
signal pause_changed(paused: bool)

const PORT := 7777
const MAX_PLAYERS := 4
## Au-delà, on abandonne la tentative de connexion (hôte injoignable).
const CONNECT_TIMEOUT := 6.0

## Joueur (1 à 4) -> id réseau de l'ordinateur qui le contrôle (0 = libre).
var slots := {}
## Joueur (1 à 4) -> vrai si l'ordinateur a validé ce choix (bouton A).
var locked := {}
## Message affiché par l'écran hôte/IP au retour d'une partie interrompue.
var last_error := ""
## Scores de la dernière partie (équipe 1 ou 2 -> points), lus par l'écran de fin.
var final_scores := {}

var _ready_peers := {}
var _match_begun := false
var _in_game := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Reçoit les ordres de l'hôte même en pause.
	_reset_session()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


#region API publique

func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer is ENetMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Refuse (ERR_ALREADY_EXISTS) si une partie est déjà hébergée sur le réseau local.
func host() -> Error:
	if not LanDiscovery.get_hosts().is_empty():
		return ERR_ALREADY_EXISTS
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_reset_session()
	_assign_free_slot(1)
	_broadcast_slots()
	return OK


func join(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_reset_session()
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(_on_connect_timeout.bind(peer))
	return OK


func leave() -> void:
	_close_peer()
	_reset_session()


## Id réseau de l'ordinateur qui contrôle `player_id` (0 = personne).
func get_slot_owner(player_id: int) -> int:
	if not is_online():
		# Scène de jeu lancée directement (F6) : on contrôle le joueur 1.
		return multiplayer.get_unique_id() if player_id == 1 else 0
	return slots.get(player_id, 0)


## Joueur (1 à 4) choisi par cet ordinateur, 0 si aucun.
func get_my_slot() -> int:
	return _slot_of(multiplayer.get_unique_id())


func get_connected_count() -> int:
	return multiplayer.get_peers().size() + 1


func is_my_slot_locked() -> bool:
	return locked.get(get_my_slot(), false)


## Valide (ou annule) le choix de joueur de cet ordinateur.
func set_my_slot_locked(value: bool) -> void:
	if multiplayer.is_server():
		_set_locked(1, value)
	else:
		_request_lock.rpc_id(1, value)


## Déplace le choix de cet ordinateur vers le joueur libre suivant (-1 gauche, +1 droite).
func move_my_slot(direction: int) -> void:
	if multiplayer.is_server():
		_move_slot(1, direction)
	else:
		_request_move_slot.rpc_id(1, direction)


## Hôte uniquement : lance la partie pour tous les ordinateurs connectés.
func start_match() -> void:
	if not multiplayer.is_server() or _in_game:
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	_load_game.rpc()


## Hôte uniquement : met en pause (ou reprend) la partie sur tous les ordinateurs.
func set_paused(value: bool) -> void:
	if multiplayer.is_server():
		_set_paused.rpc(value)


## Hôte uniquement : tous les ordinateurs reviennent à la sélection d'équipe.
func return_to_team_select() -> void:
	if multiplayer.is_server():
		_load_team_select.rpc()


## Hôte uniquement : fin du combat, tous les ordinateurs affichent l'écran de fin.
func end_match(scores: Dictionary) -> void:
	if multiplayer.is_server():
		_end_match.rpc(scores)


## Appelé par la scène de jeu une fois chargée.
func notify_game_ready() -> void:
	if not is_online():
		match_started.emit()
	elif multiplayer.is_server():
		_set_peer_ready(1)
	else:
		_peer_ready.rpc_id(1)


## Adresses IPv4 de cet ordinateur, celles d'un réseau local en premier.
static func get_local_ipv4_addresses() -> PackedStringArray:
	var preferred := PackedStringArray()
	var others := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") != 3 or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		# 172.20.10.x = partage de connexion iPhone ; 192.168.x.x / 10.x.x.x = box, routeur.
		if address.begins_with("172.20.10.") or address.begins_with("192.168.") or address.begins_with("10."):
			preferred.append(address)
		else:
			others.append(address)
	preferred.append_array(others)
	return preferred

#endregion


#region RPC

@rpc("any_peer", "reliable")
func _request_move_slot(direction: int) -> void:
	if multiplayer.is_server():
		_move_slot(multiplayer.get_remote_sender_id(), direction)


@rpc("any_peer", "reliable")
func _request_lock(value: bool) -> void:
	if multiplayer.is_server():
		_set_locked(multiplayer.get_remote_sender_id(), value)


@rpc("authority", "call_local", "reliable")
func _sync_slots(new_slots: Dictionary, new_locked: Dictionary) -> void:
	slots = new_slots
	locked = new_locked
	slots_changed.emit()


@rpc("authority", "call_local", "reliable")
func _load_game() -> void:
	_in_game = true
	get_tree().change_scene_to_file(Screens.GAME)


@rpc("any_peer", "reliable")
func _peer_ready() -> void:
	if multiplayer.is_server():
		_set_peer_ready(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _begin_match() -> void:
	match_started.emit()


@rpc("authority", "call_local", "reliable")
func _set_paused(value: bool) -> void:
	get_tree().paused = value
	pause_changed.emit(value)


@rpc("authority", "call_local", "reliable")
func _load_team_select() -> void:
	_leave_game()
	get_tree().change_scene_to_file(Screens.TEAM_SELECT)


@rpc("authority", "call_local", "reliable")
func _end_match(scores: Dictionary) -> void:
	final_scores = scores
	_leave_game()
	get_tree().change_scene_to_file(Screens.END)

#endregion


#region Logique côté hôte

func _move_slot(peer_id: int, direction: int) -> void:
	var current := _slot_of(peer_id)
	if current == 0 or locked[current]:
		return
	var target := current + direction
	while target >= 1 and target <= MAX_PLAYERS:
		if slots[target] == 0:
			slots[current] = 0
			slots[target] = peer_id
			_broadcast_slots()
			return
		target += direction


func _set_locked(peer_id: int, value: bool) -> void:
	var player_id := _slot_of(peer_id)
	if player_id != 0:
		locked[player_id] = value
		_broadcast_slots()


func _assign_free_slot(peer_id: int) -> void:
	for player_id in range(1, MAX_PLAYERS + 1):
		if slots[player_id] == 0:
			slots[player_id] = peer_id
			return


func _broadcast_slots() -> void:
	_sync_slots.rpc(slots, locked)


func _set_peer_ready(peer_id: int) -> void:
	_ready_peers[peer_id] = true
	_try_begin_match()


func _try_begin_match() -> void:
	if _match_begun:
		return
	for peer_id in [1] + Array(multiplayer.get_peers()):
		if not _ready_peers.has(peer_id):
			return
	_match_begun = true
	_begin_match.rpc()

#endregion


func _slot_of(peer_id: int) -> int:
	for player_id: int in slots:
		if slots[player_id] == peer_id:
			return player_id
	return 0


func _reset_session() -> void:
	slots = {}
	locked = {}
	for player_id in range(1, MAX_PLAYERS + 1):
		slots[player_id] = 0
		locked[player_id] = false
	_ready_peers.clear()
	_match_begun = false
	_in_game = false


## Sortie de la scène de jeu : on rouvre le salon (nouveaux ordinateurs acceptés,
## choix des joueurs à valider de nouveau).
func _leave_game() -> void:
	get_tree().paused = false
	_in_game = false
	_ready_peers.clear()
	_match_begun = false
	if multiplayer.is_server() and is_online():
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = false
		for player_id: int in locked:
			locked[player_id] = false
		_broadcast_slots()


func _close_peer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func _return_to_connect_screen(reason: String) -> void:
	_close_peer()
	_reset_session()
	get_tree().paused = false
	last_error = reason
	get_tree().change_scene_to_file(Screens.CONNECT)


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_assign_free_slot(peer_id)
		_broadcast_slots()


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_id := _slot_of(peer_id)
	if player_id != 0:
		slots[player_id] = 0
		locked[player_id] = false
	_ready_peers.erase(peer_id)
	_broadcast_slots()
	if _in_game:
		_try_begin_match() # Ne pas bloquer le lancement si un ordinateur part pendant le chargement.


func _on_connected_to_server() -> void:
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	_close_peer()
	connection_failed.emit("Impossible de joindre l'hôte.")


func _on_connect_timeout(peer: ENetMultiplayerPeer) -> void:
	if multiplayer.multiplayer_peer == peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		_close_peer()
		connection_failed.emit("L'hôte ne répond pas : vérifie l'IP et que vous êtes sur le même réseau.")


func _on_server_disconnected() -> void:
	_return_to_connect_screen("L'hôte a quitté la partie.")
