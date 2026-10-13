@tool
class_name ZoneDefense
extends Node3D
## Zone ronde à capturer (mode défense de zone, cf. ZoneDefenseMode).
##
## Une fois activée, la zone reste `timeout` secondes (décompte en pause tant
## qu'une équipe la capture). Pour la capturer, une équipe doit y rester seule
## `capture_time` secondes :
##   - la zone prend la couleur de l'équipe présente ;
##   - si l'équipe qui capture quitte la zone, la progression repart à 0 ;
##   - si les deux équipes sont dans la zone, la progression est en pause.
## Capturée ou expirée, la zone disparaît et émet `finished`.
##
## Réseau : l'hôte décide (présence, progression, capture) et envoie l'état aux
## autres ordinateurs ; entre deux envois, ceux-ci font avancer la barre seuls.
##
## Position, rayon, points et durées se règlent sur chaque instance, dans la
## scène de jeu (la zone est visible dans l'éditeur, masquée en jeu).

## Émis sur l'hôte : `team` = équipe qui a capturé (1 ou 2), 0 si temps écoulé.
signal finished(team: int)

## Intervalle (s) entre deux envois de l'état par l'hôte.
const SYNC_INTERVAL := 0.1
## Un cube compte comme présent jusqu'à cette hauteur au-dessus de la zone (m).
const MAX_HEIGHT := 3.0
const IDLE_COLOR := Color(1, 0.95, 0.7) # Jaune pâle : visible sur le sol clair.

@export var radius := 3.5:
	set(value):
		radius = value
		_update_shape()
## Hauteur du mur translucide qui entoure la zone (m), pour la voir de loin.
@export var wall_height := 5.0:
	set(value):
		wall_height = value
		_update_shape()
## Points gagnés par l'équipe qui capture la zone.
@export var points := 2
## Durée de vie de la zone une fois activée (s), en pause pendant une capture.
@export var timeout := 20.0
## Temps à passer seul dans la zone pour la capturer (s).
@export var capture_time := 10.0

var active := false
## Équipe en train de capturer (0 = personne).
var capturing_team := 0
## Vrai si les deux équipes sont dans la zone (progression en pause).
var contested := false
## Progression de la capture (s), de 0 à capture_time.
var progress := 0.0
## Temps restant avant disparition (s), figé pendant une capture.
var time_left := 0.0

var _sync_cooldown := 0.0

@onready var _disk: MeshInstance3D = $Disk
@onready var _wall: MeshInstance3D = $Wall
@onready var _ring: MeshInstance3D = $Ring
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	_update_shape()
	if Engine.is_editor_hint():
		_update_visuals()
		return
	_apply_state(false, 0, false, 0.0, 0.0)


## Hôte uniquement : fait apparaître la zone pour tout le monde.
func activate() -> void:
	_sync_state.rpc(true, 0, false, 0.0, timeout)
	_apply_state(true, 0, false, 0.0, timeout)


## Hôte uniquement : fait disparaître la zone pour tout le monde.
func deactivate() -> void:
	_sync_state.rpc(false, 0, false, 0.0, 0.0)
	_apply_state(false, 0, false, 0.0, 0.0)


## Hôte uniquement : à appeler à chaque image physique avec les cubes en jeu.
func update_capture(players: Array[Player], delta: float) -> void:
	if not active:
		return
	var teams := teams_inside(players)
	if teams.is_empty():
		capturing_team = 0
		contested = false
		progress = 0.0
	elif teams.size() == 2:
		contested = true # Pause : l'équipe qui capturait garde sa progression.
	else:
		var team: int = teams[0]
		if team != capturing_team:
			capturing_team = team
			progress = 0.0
		contested = false
		progress += delta

	if capturing_team == 0:
		time_left -= delta
	if capturing_team != 0 and progress >= capture_time:
		var winner := capturing_team
		deactivate()
		finished.emit(winner)
		return
	if time_left <= 0.0:
		deactivate()
		finished.emit(0)
		return

	_sync_cooldown -= delta
	if _sync_cooldown <= 0.0:
		_sync_cooldown = SYNC_INTERVAL
		_sync_progress.rpc(capturing_team, contested, progress, time_left)
	_update_visuals()


## Équipes (1 et/ou 2) ayant au moins un cube dans la zone.
func teams_inside(players: Array[Player]) -> Array[int]:
	var teams: Array[int] = []
	for player in players:
		if not player.is_alive():
			continue
		var offset := player.global_position - global_position
		var inside := Vector2(offset.x, offset.z).length() <= radius and offset.y > -1.0 and offset.y < MAX_HEIGHT
		var team := Player.team_of(player.player_id)
		if inside and not teams.has(team):
			teams.append(team)
	return teams


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Autres ordinateurs : la barre et le décompte avancent entre deux envois de l'hôte.
	if not active or multiplayer.is_server():
		return
	if capturing_team == 0:
		time_left = maxf(time_left - delta, 0.0)
	elif not contested:
		progress = minf(progress + delta, capture_time)


@rpc("authority", "call_remote", "reliable")
func _sync_state(is_active: bool, team: int, is_contested: bool, value: float, remaining: float) -> void:
	_apply_state(is_active, team, is_contested, value, remaining)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_progress(team: int, is_contested: bool, value: float, remaining: float) -> void:
	if active:
		_apply_state(true, team, is_contested, value, remaining)


func _apply_state(is_active: bool, team: int, is_contested: bool, value: float, remaining: float) -> void:
	active = is_active
	capturing_team = team
	contested = is_contested
	progress = value
	time_left = remaining
	visible = active
	_update_visuals()


## La zone s'éclaire de la couleur de l'équipe qui capture.
func _update_visuals() -> void:
	if _disk == null:
		return
	var color := IDLE_COLOR if capturing_team == 0 else Player.TEAM_COLORS[capturing_team - 1]
	var lit := capturing_team != 0
	var disk_material := _disk.material_override as StandardMaterial3D
	disk_material.albedo_color = Color(color, 0.55 if lit else 0.3)
	disk_material.emission = color
	disk_material.emission_energy_multiplier = 1.5 if lit else 0.3
	var wall_material := _wall.material_override as ShaderMaterial
	wall_material.set_shader_parameter(&"color", Color(color, 0.5 if lit else 0.3))
	(_ring.material_override as StandardMaterial3D).albedo_color = color
	_light.light_color = color
	_light.light_energy = 3.0 if lit else 0.0


func _update_shape() -> void:
	if not is_node_ready():
		return
	(_disk.mesh as CylinderMesh).top_radius = radius
	(_disk.mesh as CylinderMesh).bottom_radius = radius
	(_wall.mesh as CylinderMesh).top_radius = radius
	(_wall.mesh as CylinderMesh).bottom_radius = radius
	(_wall.mesh as CylinderMesh).height = wall_height
	_wall.position.y = wall_height / 2.0
	(_wall.material_override as ShaderMaterial).set_shader_parameter(&"height", wall_height)
	(_ring.mesh as TorusMesh).outer_radius = radius
	(_ring.mesh as TorusMesh).inner_radius = radius - 0.2
	_light.omni_range = radius * 2.0
