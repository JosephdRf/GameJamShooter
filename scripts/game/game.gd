extends Node3D
## Scène principale : l'arène + les 4 joueurs + leurs zones d'apparition + le
## mode de jeu (défense de zone) + le HUD + le menu pause.
## Au lancement, chaque joueur est placé sur la zone d'apparition (ZoneSpawn,
## enfants de SpawnZones) de son équipe.
## Chaque ordinateur affiche la caméra du joueur qu'il a choisi dans le salon.
## Les joueurs non choisis restent sur place (contrôlés par personne).
## Échap (ui_cancel) quitte le jeu ; P / + (hôte) ouvre le menu pause.
##
## Compte à rebours : l'hôte décompte match_duration secondes (figé pendant la
## pause) et envoie régulièrement le temps restant aux autres ordinateurs, qui
## décomptent de leur côté entre deux envois. À 0, l'hôte termine le combat.
## Fin du combat aussi possible via le bouton de test du menu pause.
## Les scores (par équipe) viennent du mode défense de zone.

## Intervalle (s) entre deux envois du temps restant par l'hôte.
const TIME_SYNC_INTERVAL := 0.5

## Durée d'un combat en secondes (0 = pas de limite, chrono masqué).
@export var match_duration := 60.0

## Temps restant (s). Ne diminue qu'une fois la partie lancée.
var time_left := 0.0
var _running := false
var _ended := false
var _time_sync_cooldown := 0.0

@onready var _arena: Node3D = $Arena
@onready var _players: Node3D = $Players
@onready var _spawn_zones: Node3D = $SpawnZones
@onready var _mode: ZoneDefenseMode = $ZoneDefenseMode
@onready var _hud: CanvasLayer = $MatchHud
@onready var _pause_menu: CanvasLayer = $PauseMenu


func _ready() -> void:
	# La souris est capturée pour que le trackpad pilote la caméra.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_place_players_on_spawn_zones()
	for player: Player in _players.get_children():
		player.camera.face(_arena.global_position) # Au départ, chaque joueur regarde le centre.
	_apply_slots()
	time_left = match_duration
	_hud.set_time_left(time_left if match_duration > 0.0 else -1.0)
	_hud.set_scores(0, 0)
	_mode.scores_changed.connect(func() -> void: _hud.set_scores(_mode.scores[1], _mode.scores[2]))
	NetworkManager.slots_changed.connect(_apply_slots)
	NetworkManager.match_started.connect(_on_match_started)
	_pause_menu.end_match_requested.connect(_end_match)
	NetworkManager.notify_game_ready()


func _process(delta: float) -> void:
	# Ne tourne pas pendant la pause (nœud "pausable") : le chrono est figé.
	_update_capture_bar()
	if not _running:
		return
	time_left = maxf(time_left - delta, 0.0)
	_hud.set_time_left(time_left)
	if not multiplayer.is_server():
		return
	_time_sync_cooldown -= delta
	if _time_sync_cooldown <= 0.0:
		_time_sync_cooldown = TIME_SYNC_INTERVAL
		_sync_time_left.rpc(time_left)
	if time_left <= 0.0:
		_end_match()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()


## Place chaque joueur sur un emplacement de la zone d'apparition de son équipe.
func _place_players_on_spawn_zones() -> void:
	for zone: ZoneSpawn in _spawn_zones.get_children():
		var team_players := _players.get_children().filter(
				func(player: Player) -> bool: return Player.team_of(player.player_id) == zone.team)
		for i in team_players.size():
			team_players[i].set_spawn_position(zone.get_spawn_position(i, team_players.size()))


## Donne à chaque ordinateur l'autorité sur le cube qu'il a choisi (l'hôte garde les autres).
func _apply_slots() -> void:
	if not is_inside_tree(): # Scène en cours de remplacement (retour au salon, fin du combat).
		return
	var my_id := multiplayer.get_unique_id()
	for player: Player in _players.get_children():
		var owner_id := NetworkManager.get_slot_owner(player.player_id)
		player.set_multiplayer_authority(owner_id if owner_id != 0 else 1)
		player.is_local = owner_id == my_id
		player.camera.set_view_active(player.is_local)


func _on_match_started() -> void:
	for player: Player in _players.get_children():
		player.activate()
	_running = match_duration > 0.0
	var players: Array[Player] = []
	players.assign(_players.get_children())
	_mode.start(players)


func _update_capture_bar() -> void:
	var zone := _mode.get_active_zone()
	if zone == null:
		_hud.set_capture(0, 0.0, false)
	else:
		_hud.set_capture(zone.capturing_team, zone.progress / zone.capture_time, zone.contested)


## Hôte -> autres ordinateurs : recale leur chrono sur celui de l'hôte.
@rpc("authority", "unreliable_ordered")
func _sync_time_left(value: float) -> void:
	time_left = value
	_hud.set_time_left(time_left)


func _end_match() -> void:
	if _ended:
		return
	_ended = true
	_running = false
	NetworkManager.end_match(_mode.scores.duplicate())
