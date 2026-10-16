class_name ZoneDefenseMode
extends Node3D
## Mode défense de zone : les zones (ZoneDefense) sont les enfants de ce nœud.
##
## Une seule zone est active à la fois. Au début du combat, aucune : la première,
## tirée au hasard, apparaît first_zone_delay secondes après « C'est parti ! ». Une zone
## reste jusqu'à sa capture (pas de limite de temps, cf. ZoneDefense.timeout) ; capturer une
## zone rapporte ses `points` à l'équipe, puis une autre zone, forcément différente, apparaît
## next_zone_delay secondes plus tard (« Une nouvelle zone est apparue ! »).
## Équipe menée de comeback_gap points ou plus : la zone suivante a comeback_weight fois plus
## de chances d'apparaître de son côté (ZoneDefense.side) que chacune des autres. Sinon, pas de
## répétition : une zone ne revient pas avant que NO_REPEAT_SPAN - 1 autres soient passées (jamais
## deux fois la même sur NO_REPEAT_SPAN zones de suite), s'il y a assez de zones.
## Pour ajouter / déplacer / régler les zones : modifier les instances
## ZoneDefense sous ce nœud dans scenes/game/game.tscn.
##
## Réseau : l'hôte choisit les zones et tient les scores, puis les envoie aux
## autres ordinateurs.

signal scores_changed
## Émis sur tous les ordinateurs quand une équipe (1 ou 2) capture la zone.
signal zone_captured(team: int)
## Émis sur tous les ordinateurs quand une zone apparaît : la première de la partie, celle qui
## suit une capture (après next_zone_delay) ou celle qui remplace une zone expirée.
signal new_zone_appeared

## Hors rattrapage, pas deux fois la même zone sur ce nombre de zones consécutives.
const NO_REPEAT_SPAN := 5

## Délai (s) entre « C'est parti ! » et l'apparition de la première zone (figé pendant la pause).
@export var first_zone_delay := 5.0
## Délai (s) entre la capture d'une zone et l'apparition de la suivante (figé pendant la pause).
@export var next_zone_delay := 5.0

## Points rapportés par une élimination (cf. add_kill).
@export var kill_points := 1
## Écart de points à partir duquel la zone suivante apparaît plus souvent du côté de l'équipe
## menée, et combien de fois plus (une zone de son côté compte pour `comeback_weight` tirages).
@export var comeback_gap := 10
@export var comeback_weight := 3.0

## Équipe (1 ou 2) -> points.
var scores := {1: 0, 2: 0}

var _zones: Array[ZoneDefense] = []
var _players: Array[Player] = []
var _active_index := -1
## Dernières zones activées (indices), de la plus ancienne à la plus récente.
var _history: Array[int] = []


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


## Hôte uniquement : un joueur de l'équipe `team` (1 ou 2) a éliminé un adversaire.
func add_kill(team: int) -> void:
	scores[team] += kill_points
	_sync_scores.rpc(scores)


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
	_history.append(index)
	if _history.size() > NO_REPEAT_SPAN:
		_history.pop_front()
	_zones[index].activate()


func _on_zone_finished(team: int) -> void:
	var previous := _active_index
	if team == 0: # Zone expirée (timeout > 0) : la suivante tout de suite.
		_announce_new_zone.rpc()
		_activate(_pick_next_zone(previous))
		return
	scores[team] += _zones[previous].points
	_sync_scores.rpc(scores)
	_announce_capture.rpc(team)
	_active_index = -1
	await get_tree().create_timer(next_zone_delay, false).timeout
	# Partie finie entre-temps (mode figé) : pas de zone.
	if not is_inside_tree() or not can_process():
		return
	# Tirée maintenant : avec l'écart de points d'après les éliminations de l'attente.
	_activate(_pick_next_zone(previous))
	_announce_new_zone.rpc()


## Prochaine zone : au hasard parmi les autres (la même s'il n'y en a qu'une). Équipe menée de
## comeback_gap points ou plus : celles de son côté comptent comeback_weight fois. Sinon, aucune
## des NO_REPEAT_SPAN - 1 dernières (si toutes y sont, seulement pas la précédente).
func _pick_next_zone(previous: int) -> int:
	if _zones.size() <= 1:
		return previous
	var trailing := 0
	if scores[2] - scores[1] >= comeback_gap:
		trailing = 1
	elif scores[1] - scores[2] >= comeback_gap:
		trailing = 2
	var recent: Array[int] = [previous]
	if trailing == 0 and _zones.size() >= NO_REPEAT_SPAN:
		recent = _history.slice(-(NO_REPEAT_SPAN - 1))
	var weights := PackedFloat32Array()
	for i in _zones.size():
		var weight := 0.0 if i in recent else 1.0
		if trailing != 0 and _zones[i].side == trailing:
			weight *= comeback_weight
		weights.append(weight)
	return RandomNumberGenerator.new().rand_weighted(weights)


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
