class_name ZoneDefenseMode
extends Node3D
## Mode défense de zone : les zones (ZoneDefense) sont les enfants de ce nœud.
##
## Une seule zone est active à la fois. Au début du combat, aucune : la première,
## tirée au hasard, apparaît first_zone_delay secondes après « C'est parti ! ». Ensuite
## il y en a toujours une : quand elle disparaît (capturée ou temps écoulé), une autre
## zone, forcément différente, apparaît. Capturer une zone rapporte ses `points` à
## l'équipe.
## Pour ajouter / déplacer / régler les zones : modifier les instances
## ZoneDefense sous ce nœud dans scenes/game/game.tscn.
##
## Réseau : l'hôte choisit les zones et tient les scores, puis les envoie aux
## autres ordinateurs.

signal scores_changed
## Émis sur tous les ordinateurs quand une équipe (1 ou 2) capture la zone.
signal zone_captured(team: int)
## Émis sur tous les ordinateurs quand une zone apparaît sans avoir été gagnée : la
## première de la partie, ou celle qui remplace une zone expirée (temps écoulé).
signal new_zone_appeared

## Délai (s) entre « C'est parti ! » et l'apparition de la première zone (figé pendant la pause).
@export var first_zone_delay := 5.0

## Équipe (1 ou 2) -> points.
var scores := {1: 0, 2: 0}

var _zones: Array[ZoneDefense] = []
var _players: Array[Player] = []
var _active_index := -1


func _ready() -> void:
	for child in get_children():
		if child is ZoneDefense:
			_zones.append(child)
			child.finished.connect(_on_zone_finished)


## Hôte uniquement : lance le mode avec les cubes en jeu.
func start(players: Array[Player]) -> void:
	_players = players
	if not multiplayer.is_server() or _zones.is_empty():
		return
	await get_tree().create_timer(first_zone_delay, false).timeout
	# Partie finie entre-temps (mode figé) : pas de zone.
	if not is_inside_tree() or not can_process():
		return
	_activate(randi() % _zones.size())
	_announce_new_zone.rpc()


## Zone actuellement active (null si aucune).
func get_active_zone() -> ZoneDefense:
	for zone in _zones:
		if zone.active:
			return zone
	return null


## Vrai si une équipe est en train de capturer la zone active (même contestée).
func is_capture_in_progress() -> bool:
	var zone := get_active_zone()
	return zone != null and zone.capturing_team != 0


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and _active_index != -1:
		_zones[_active_index].update_capture(_players, delta)


func _activate(index: int) -> void:
	_active_index = index
	_zones[index].activate()


func _on_zone_finished(team: int) -> void:
	if team != 0:
		scores[team] += _zones[_active_index].points
		_sync_scores.rpc(scores)
		_announce_capture.rpc(team)
	else:
		_announce_new_zone.rpc()
	# Prochaine zone : au hasard parmi les autres (la même s'il n'y en a qu'une).
	var next := _active_index
	if _zones.size() > 1:
		next = randi() % (_zones.size() - 1)
		if next >= _active_index:
			next += 1
	_activate(next)


@rpc("authority", "call_local", "reliable")
func _announce_capture(team: int) -> void:
	zone_captured.emit(team)


@rpc("authority", "call_local", "reliable")
func _announce_new_zone() -> void:
	new_zone_appeared.emit()


@rpc("authority", "call_local", "reliable")
func _sync_scores(new_scores: Dictionary) -> void:
	scores = new_scores
	scores_changed.emit()
