@tool
class_name ZoneDefense
extends Node3D
## Zone à capturer, ronde ou rectangulaire (mode défense de zone, cf. ZoneDefenseMode).
##
## Une fois activée, la zone reste `timeout` secondes (décompte en pause tant
## qu'une équipe la capture). Pour la capturer, une équipe doit y rester seule
## `capture_time` secondes :
##   - la zone prend la couleur de l'équipe présente ;
##   - si l'équipe qui capture quitte la zone, la progression repart à 0 ;
##     un canard compte comme dedans tant que son corps touche la zone (centre
##     jusqu'à un rayon de capsule hors du bord) ;
##   - si les deux équipes sont dans la zone, la progression est en pause.
## Capturée ou expirée, la zone disparaît et émet `finished`.
##
## Réseau : l'hôte décide (présence, progression, capture) et envoie l'état aux
## autres ordinateurs ; entre deux envois, ceux-ci font avancer la barre seuls.
##
## Colonne de lumière (Beacon) haute de beacon_height, à la couleur de la zone : on
## repère la zone active de loin, au-dessus des murs et des plateformes.
## Position, forme (rayon ou taille), points et durées se règlent sur chaque
## instance, dans la scène de jeu (la zone est visible dans l'éditeur, masquée en jeu).
## Le centre de la zone se place au niveau du sol.

## Émis sur l'hôte : `team` = équipe qui a capturé (1 ou 2), 0 si temps écoulé.
signal finished(team: int)

## Intervalle (s) entre deux envois de l'état par l'hôte.
const SYNC_INTERVAL := 0.1
const IDLE_COLOR := Color(1, 0.95, 0.7) # Jaune pâle : visible sur le sol clair.
## Vitesse de montée des vagues de la colonne de lumière (m/s) : au repos, en capture.
const WAVE_SPEED := 3.0
const WAVE_SPEED_CAPTURING := 7.0
## Couleur de la colonne de lumière quand personne ne capture : jaune doré, franc pour
## ressortir sur les murs clairs.
const BEACON_IDLE_COLOR := Color(1.0, 0.76, 0.05)
## Largeur du liseré au bord de la zone (m).
const RING_WIDTH := 0.2

enum Shape { CIRCLE, RECTANGLE }

@export var shape := Shape.CIRCLE:
	set(value):
		shape = value
		_update_shape()
## Rayon d'une zone ronde (m).
@export var radius := 6.0:
	set(value):
		radius = value
		_update_shape()
## Taille d'une zone rectangulaire (m) : x le long de l'axe X local, y le long de l'axe Z local.
@export var size := Vector2(10.0, 10.0):
	set(value):
		size = value
		_update_shape()
## Hauteur du mur translucide qui entoure la zone (m), pour la voir de loin. Un canard
## compte comme présent tant que son centre est sous le haut du mur (même en sautant).
@export var wall_height := 5.0:
	set(value):
		wall_height = value
		_update_shape()
## Hauteur de la colonne de lumière (m), pour voir la zone de loin.
@export var beacon_height := 30.0:
	set(value):
		beacon_height = value
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
## Position des vagues de la colonne de lumière (m), avancée chaque image.
var _wave_offset := 0.0

@onready var _disk: MeshInstance3D = $Disk
@onready var _wall: MeshInstance3D = $Wall
@onready var _beacon: MeshInstance3D = $Beacon
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
		if not player.is_alive() or player.dummy:
			continue
		var team := Player.team_of(player.player_id)
		if contains(player.global_position, player.get_body_radius()) and not teams.has(team):
			teams.append(team)
	return teams


## Vrai si un corps de rayon `margin` centré en `point` touche la zone.
func contains(point: Vector3, margin := 0.0) -> bool:
	var offset := global_transform.affine_inverse() * point
	if offset.y <= -1.0 or offset.y >= wall_height:
		return false
	if shape == Shape.RECTANGLE:
		return absf(offset.x) <= size.x / 2.0 + margin and absf(offset.z) <= size.y / 2.0 + margin
	return Vector2(offset.x, offset.z).length() <= radius + margin


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if active:
		_wave_offset += (WAVE_SPEED_CAPTURING if capturing_team != 0 else WAVE_SPEED) * delta
		(_beacon.material_override as ShaderMaterial).set_shader_parameter(&"scroll_offset", fmod(_wave_offset, 900.0)) # 900 = 200 écarts de vagues : pas de saut.
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
	disk_material.albedo_color = Color(color, 0.32 if lit else 0.3)
	disk_material.emission = color
	disk_material.emission_energy_multiplier = 0.7 if lit else 0.3
	var wall_material := _wall.material_override as ShaderMaterial
	wall_material.set_shader_parameter(&"color", Color(color, 0.38 if lit else 0.3))
	(_ring.material_override as StandardMaterial3D).albedo_color = color
	var beacon_material := _beacon.material_override as ShaderMaterial
	beacon_material.set_shader_parameter(&"color", color if lit else BEACON_IDLE_COLOR)
	beacon_material.set_shader_parameter(&"intensity", 0.6)
	_light.light_color = color
	_light.light_energy = 0.6 if lit else 0.0


func _update_shape() -> void:
	if not is_node_ready():
		return
	var light_range := radius
	if shape == Shape.RECTANGLE:
		var floor_mesh := BoxMesh.new()
		floor_mesh.size = Vector3(size.x, 0.04, size.y)
		_disk.mesh = floor_mesh
		# Mur : boîte sans dessus ni dessous (le shader masque les faces horizontales).
		var wall := BoxMesh.new()
		wall.size = Vector3(size.x, wall_height, size.y)
		_wall.mesh = wall
		_ring.mesh = _rectangle_ring()
		var beacon := BoxMesh.new()
		beacon.size = Vector3(size.x, beacon_height, size.y)
		_beacon.mesh = beacon
		light_range = size.length() / 2.0
	else:
		_disk.mesh = _cylinder(radius, 0.04, true)
		_wall.mesh = _cylinder(radius, wall_height, false)
		_beacon.mesh = _cylinder(radius, beacon_height, false)
		var ring := TorusMesh.new()
		ring.outer_radius = radius
		ring.inner_radius = radius - RING_WIDTH
		ring.rings = 64
		ring.ring_segments = 8
		_ring.mesh = ring
	_wall.position.y = wall_height / 2.0
	# Forme de la zone pour les shaders (transparents quand la caméra est dedans).
	for material: ShaderMaterial in [_wall.material_override, _beacon.material_override]:
		material.set_shader_parameter(&"zone_rect", shape == Shape.RECTANGLE)
		material.set_shader_parameter(&"zone_radius", radius)
		material.set_shader_parameter(&"zone_half_size", size / 2.0)
	_beacon.position.y = beacon_height / 2.0
	(_beacon.material_override as ShaderMaterial).set_shader_parameter(&"height", beacon_height)
	(_wall.material_override as ShaderMaterial).set_shader_parameter(&"height", wall_height)
	_light.omni_range = light_range * 2.0


func _cylinder(cylinder_radius: float, height: float, caps: bool) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = cylinder_radius
	mesh.bottom_radius = cylinder_radius
	mesh.height = height
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.cap_top = caps
	mesh.cap_bottom = caps
	return mesh


## Liseré d'une zone rectangulaire : 4 baguettes le long des bords (même épaisseur que le
## tore d'une zone ronde, aplati par l'échelle du nœud Ring).
func _rectangle_ring() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size / 2.0 - Vector2.ONE * RING_WIDTH / 2.0
	for side: Array in [
		[Vector3(size.x, RING_WIDTH, RING_WIDTH), Vector3(0, 0, half.y)],
		[Vector3(size.x, RING_WIDTH, RING_WIDTH), Vector3(0, 0, -half.y)],
		[Vector3(RING_WIDTH, RING_WIDTH, size.y), Vector3(half.x, 0, 0)],
		[Vector3(RING_WIDTH, RING_WIDTH, size.y), Vector3(-half.x, 0, 0)],
	]:
		var bar := BoxMesh.new()
		bar.size = side[0]
		tool.append_from(bar, 0, Transform3D(Basis(), side[1]))
	return tool.commit()
