extends Node3D
## Scène principale : l'arène + les 4 joueurs + leurs zones d'apparition + le
## mode de jeu (défense de zone) + le HUD + le menu pause.
## Au lancement, chaque joueur est placé sur la zone d'apparition (ZoneSpawn,
## enfants de SpawnZones) de son équipe.
## La vie du joueur local s'affiche via DamageOverlay (bulles) et DeathScreen.
## Tirs : chaque bulle tirée (signal Player.shot) est créée sous Projectiles et
## se supprime d'elle-même en éclatant.
## Test (version de développement) : l'action debug_damage (H) inflige 10 dégâts à son propre cube.
## Debug mode (action debug_mode : Ctrl + D), désactivé au lancement : affiche les
## PV du joueur local (DebugHealth) et le rectangle de l'aide à la visée.
## Chaque ordinateur affiche la caméra du joueur qu'il a choisi dans le salon.
## Les joueurs non choisis restent sur place (contrôlés par personne).
## Échap (ui_cancel) quitte le jeu ; P / + (hôte) ouvre le menu pause.
##
## Compte à rebours : l'hôte décompte match_duration secondes (figé pendant la
## pause) et envoie régulièrement le temps restant aux autres ordinateurs, qui
## décomptent de leur côté entre deux envois. À 0, l'hôte termine le combat.
## Les scores (par équipe) viennent du mode défense de zone.
##
## Messages (Announcer) : au lancement « Attention… » (joueurs figés) pendant
## ready_duration, puis « C'est parti ! » : les joueurs bougent, le chrono et
## les zones démarrent. À chaque prise de zone : « Ton équipe / L'adversaire a
## pris la zone clé ! ». À la fin : « Terminé ! » pendant finish_duration,
## joueurs et bulles figés, puis écran de fin.

## Intervalle (s) entre deux envois du temps restant par l'hôte.
const TIME_SYNC_INTERVAL := 0.5
const PROJECTILE_SCENE := preload("res://scenes/game/bubble_projectile.tscn")
const CAPTURE_PROJECTILE_SCENE := preload("res://scenes/game/capture_bubble.tscn")
## Dégâts infligés par l'action de test debug_damage.
const DEBUG_DAMAGE := 10.0

## Durée d'un combat en secondes (0 = pas de limite, chrono masqué).
@export var match_duration := 60.0
## Durée de « Attention… » (joueurs figés), puis de « C'est parti ! » (s).
@export var ready_duration := 2.0
@export var go_duration := 2.0
## Durée de « Ton équipe / L'adversaire a pris la zone clé ! » (s).
@export var capture_message_duration := 2.5
## Durée de « Terminé ! » avant l'écran de fin (s).
@export var finish_duration := 1.5

## Temps restant (s). Ne diminue qu'une fois la partie lancée.
var time_left := 0.0
var _running := false
var _ended := false
var _time_sync_cooldown := 0.0
var _debug_mode := false

@onready var _arena: Node3D = $Arena
@onready var _players: Node3D = $Players
@onready var _spawn_zones: Node3D = $SpawnZones
@onready var _projectiles: Node3D = $Projectiles
@onready var _mode: ZoneDefenseMode = $ZoneDefenseMode
@onready var _hud: CanvasLayer = $MatchHud
@onready var _damage_overlay: CanvasLayer = $DamageOverlay
@onready var _death_screen: CanvasLayer = $DeathScreen
@onready var _announcer: CanvasLayer = $Announcer
@onready var _crosshair: CanvasLayer = $Crosshair
@onready var _debug_layer: CanvasLayer = $DebugHealth
@onready var _debug_health: Label = $DebugHealth/Label


func _ready() -> void:
	# La souris est capturée pour que le trackpad pilote la caméra.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Music.stop()
	_place_players_on_spawn_zones()
	for player: Player in _players.get_children():
		player.face(_arena.global_position) # Au départ, chaque joueur regarde le centre.
		player.health_changed.connect(_on_player_health_changed.bind(player))
		player.died.connect(_on_player_died.bind(player))
		player.respawned.connect(_on_player_respawned.bind(player))
		player.shot.connect(_on_player_shot.bind(player))
	_apply_slots()
	_debug_layer.visible = _debug_mode
	time_left = match_duration
	_hud.set_time_left(time_left if match_duration > 0.0 else -1.0)
	_hud.set_scores(0, 0)
	_mode.scores_changed.connect(func() -> void: _hud.set_scores(_mode.scores[1], _mode.scores[2]))
	_mode.zone_captured.connect(_on_zone_captured)
	NetworkManager.slots_changed.connect(_apply_slots)
	NetworkManager.match_started.connect(_on_match_started)
	NetworkManager.notify_game_ready()


func _process(delta: float) -> void:
	# Ne tourne pas pendant la pause (nœud "pausable") : le chrono est figé.
	_update_capture_bar()
	_update_crosshair()
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
	elif event.is_action_pressed(&"debug_mode"):
		_debug_mode = not _debug_mode
		_debug_layer.visible = _debug_mode
	elif OS.is_debug_build() and event.is_action_pressed(&"debug_damage"):
		for player: Player in _players.get_children():
			if player.is_local and player.active:
				player.take_damage(DEBUG_DAMAGE)


func _on_player_health_changed(health: float, player: Player) -> void:
	if player.is_local:
		_damage_overlay.set_health_ratio(health / player.max_health)
		_debug_health.text = "PV : %d" % ceili(health)


## Sur tous les ordinateurs ; seule la bulle de l'ordinateur du tireur inflige des dégâts.
func _on_player_shot(origin: Vector3, direction: Vector3, capture: bool, player: Player) -> void:
	var bubble: BubbleProjectile = (CAPTURE_PROJECTILE_SCENE if capture else PROJECTILE_SCENE).instantiate()
	_projectiles.add_child(bubble)
	bubble.launch(player, origin, direction, player.is_multiplayer_authority())


func _on_player_died(player: Player) -> void:
	if player.is_local:
		_death_screen.show_death()


func _on_player_respawned(player: Player) -> void:
	if player.is_local:
		_death_screen.hide_death()


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


## Sur tous les ordinateurs, au même moment (à la latence près).
func _on_match_started() -> void:
	_announcer.show_ready(ready_duration)
	await get_tree().create_timer(ready_duration, false).timeout # Figé pendant la pause.
	if not is_inside_tree() or _ended:
		return
	_announcer.show_go(go_duration)
	for player: Player in _players.get_children():
		player.activate()
	_running = match_duration > 0.0
	var players: Array[Player] = []
	players.assign(_players.get_children())
	_mode.start(players)


func _on_zone_captured(team: int) -> void:
	var local_team := 0
	for player: Player in _players.get_children():
		if player.is_local:
			local_team = Player.team_of(player.player_id)
	_announcer.show_capture(team == local_team, Player.TEAM_COLORS[team - 1], capture_message_duration)


func _update_crosshair() -> void:
	for player: Player in _players.get_children():
		if player.is_local:
			_crosshair.visible = player.is_alive() and not _ended
			_crosshair.set_on_target(_crosshair.visible and player.is_aiming_at_enemy())
			_crosshair.set_aim(player.camera.aim_offset,
					player.aim_assist.box_size if _debug_mode and player.aim_assist.is_active() else Vector2.ZERO)
			return
	_crosshair.visible = false


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


## Hôte uniquement, quand le chrono arrive à 0.
func _end_match() -> void:
	if _ended:
		return
	_finish_match.rpc(_mode.scores.duplicate())


## Sur tous les ordinateurs : « Terminé ! », tout se fige, puis l'hôte passe à l'écran de fin.
@rpc("authority", "call_local", "reliable")
func _finish_match(scores: Dictionary) -> void:
	_ended = true
	_running = false
	for player: Player in _players.get_children():
		player.freeze()
	_projectiles.process_mode = Node.PROCESS_MODE_DISABLED
	_mode.process_mode = Node.PROCESS_MODE_DISABLED # Plus de capture ni de points.
	_announcer.show_finish(finish_duration)
	if not multiplayer.is_server():
		return
	await get_tree().create_timer(finish_duration, false).timeout
	if is_inside_tree():
		NetworkManager.end_match(scores)
