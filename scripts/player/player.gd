@tool
class_name Player
extends CharacterBody3D
## Joueur (canard, modèle assets/models/duck_v3.glb, textures dans assets/materials).
## L'équipe (et donc la couleur du réservoir d'eau sur le dos) dépend de `player_id` :
## joueurs 1-2 = équipe bleue, joueurs 3-4 = équipe rouge.
##
## En réseau, l'ordinateur qui a l'autorité sur ce nœud simule le cube et
## diffuse `sync_position` (nœud Sync) ; les autres ordinateurs lissent le
## cube vers cette position.
##
## Vie : `health` (diffusée par l'ordinateur qui a l'autorité). Dégâts via
## take_damage() (depuis n'importe quel ordinateur) ; sans dégâts pendant
## `regen_delay` s, la vie remonte de `regen_rate` PV/s. À 0 PV, le cube
## disparaît `respawn_delay` s puis réapparaît à son point de départ.

## Émis sur tous les ordinateurs quand la vie change / à la mort / à la réapparition.
signal health_changed(health: float)
signal died
signal respawned
## Émis sur tous les ordinateurs quand ce joueur tire (Game crée la bulle).
signal shot(origin: Vector3, direction: Vector3)

## Couleur de chaque équipe (index 0 = équipe 1).
const TEAM_COLORS: Array[Color] = [
	Color("3b82f6"), # Équipe 1 : bleue
	Color("e5484d"), # Équipe 2 : rouge
]
const TEAM_NAMES: Array[String] = ["bleue", "rouge"]
## Calques physiques des murs invisibles des zones d'apparition (ZoneSpawn) :
## calque 3 « spawn_blue » (valeur 4), calque 4 « spawn_red » (valeur 8). Un joueur
## (et ses bulles) est bloqué par la zone d'apparition de l'équipe adverse.
const WORLD_LAYER := 1
const PLAYERS_LAYER := 2
const SPAWN_LAYERS: Array[int] = [4, 8]
## Vitesse de rattrapage des cubes distants (plus élevé = plus réactif, moins lisse).
const REMOTE_SMOOTHING := 25.0
## Au-delà de cet écart, un cube distant est téléporté (ex. réapparition).
## Animations du canard (machine à états du nœud AnimationTree, transitions et fondus
## réglables dans l'éditeur). Le script ne fait que renseigner ses conditions :
## idle à l'arrêt, walk en dessous de RUN_SPEED (m/s), run au-delà ; dashing pendant
## le dash (dash_start → dash), dash_over ensuite (dash → dash_end).
const MOVING_SPEED := 0.3
const RUN_SPEED := 4.0
## Vitesse à laquelle le canard se tourne vers sa direction de déplacement.
const TURN_SPEED := 14.0
## Courbe du dash (fractions de dash_duration) : fin de la montée en vitesse,
## début du ralentissement.
const DASH_RAMP := 0.15
const DASH_SLOWDOWN_START := 0.3
## Portée de la visée (m) : au-delà, on vise un point à cette distance.
const AIM_DISTANCE := 80.0
## Mesh du pistolet dans le modèle (les bulles partent du bout de son canon).
const GUN_MESH := "Gun"
## Matériaux texturés des meshes du modèle. Le réservoir, le tuyau et la ceinture
## partagent la texture « container », à la couleur de l'équipe (index 0 = équipe 1).
const MESH_MATERIALS := {
	&"Duck_body": preload("res://assets/materials/duck_body.tres"),
	&"Gun": preload("res://assets/materials/duck_gun.tres"),
}
const TEAM_COLORED_MESHES: Array[StringName] = [&"Water_Container", &"Tube", &"Belt"]
const TEAM_MATERIALS: Array[Material] = [
	preload("res://assets/materials/duck_container_blue.tres"),
	preload("res://assets/materials/duck_container_red.tres"),
]
const REMOTE_SNAP_DISTANCE := 3.0

@export_range(1, 4) var player_id := 1:
	set(value):
		player_id = value
		_apply_color()

@export var move_speed := 6.0
## Élevée = réponse quasi instantanée au stick / aux touches.
@export var acceleration := 90.0
@export var jump_velocity := 8.5
## Multiplicateur de la gravité du projet (plus élevé = saut moins flottant).
@export var gravity_scale := 1.8
@export_group("Dash")
## Vitesse de pointe du dash (m/s).
@export var dash_speed := 22.0
## Durée du dash (s). Courbe de vitesse : montée douce jusqu'à dash_speed
## (DASH_RAMP), plateau, puis ralentissement doux jusqu'à move_speed.
## Distance ≈ 4 m avec les valeurs par défaut.
@export var dash_duration := 0.3
## Temps minimum entre deux dashs (s).
@export var dash_cooldown := 2.0
@export_group("Tir")
## Temps minimum entre deux appuis sur la touche de tir (s).
@export var fire_cooldown := 0.15
## Touche de tir maintenue : une bulle toutes les `auto_fire_interval` s.
@export var auto_fire_interval := 0.2
@export_group("Vie")
@export var max_health := 100.0
## Vie regagnée par seconde (PV/s) quand le joueur ne prend pas de dégâts.
@export var regen_rate := 10.0
## Temps sans dégâts avant que la vie commence à remonter (s).
@export var regen_delay := 2.0
## Temps entre la mort et la réapparition (s).
@export var respawn_delay := 2.0
## En dessous de cette hauteur, le joueur meurt (chute hors de l'arène).
@export var kill_height := -10.0
@export_group("")

## Vrai si ce cube est piloté par les entrées de cet ordinateur.
var is_local := false
## Faux tant que la partie n'a pas commencé : le cube reste figé.
var active := false
## Position diffusée sur le réseau par l'ordinateur qui contrôle ce cube.
var sync_position: Vector3
## Points de vie (0 = mort). Diffusé par le nœud Sync quand il change.
var health := 100.0:
	set(value):
		var was_alive := health > 0.0
		health = value
		health_changed.emit(health)
		if was_alive and health <= 0.0:
			_on_died()
		elif not was_alive and health > 0.0:
			_on_respawned()

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_position: Vector3
## Temps restant du dash en cours (s), 0 si pas de dash.
var _dash_time := 0.0
## Temps restant avant de pouvoir dasher à nouveau (s).
var _dash_cooldown_left := 0.0
var _dash_direction: Vector3
## Vitesse horizontale au moment du dash (point de départ de la courbe).
var _dash_start_speed := 0.0
## Temps restant du dash pour ses animations (condition « dashing »), décompté sur
## tous les ordinateurs (cf. _play_dash).
var _dash_animation_left := 0.0
## Bout du canon (Marker3D créé dans _ready sur le mesh du pistolet) : départ des bulles.
var _muzzle: Marker3D
## Temps écoulé depuis le dernier tir (s).
var _since_last_shot := INF
## Temps restant avant que la vie remonte (s).
var _regen_cooldown_left := 0.0
## Temps restant avant la réapparition, quand le joueur est mort (s).
var _respawn_left := 0.0

## Caméra du joueur : les déplacements sont relatifs à son orientation.
@onready var camera: PlayerCamera = $PlayerCamera
@onready var _model: Node3D = $Model
@onready var _animation_tree: AnimationTree = $AnimationTree
@onready var _animation_playback: AnimationNodeStateMachinePlayback = _animation_tree.get(&"parameters/playback")
@onready var _collision_shape: CollisionShape3D = $CollisionShape
@onready var _sync: MultiplayerSynchronizer = $Sync


## Équipe (1 ou 2) du joueur `id`.
static func team_of(id: int) -> int:
	return 1 if id <= 2 else 2


static func color_of(id: int) -> Color:
	return TEAM_COLORS[team_of(id) - 1]


## Calque de la zone d'apparition adverse de l'équipe `team`.
static func enemy_spawn_layer(team: int) -> int:
	return SPAWN_LAYERS[2 - team]


func _ready() -> void:
	_apply_color()
	if not Engine.is_editor_hint():
		_create_muzzle()
	_spawn_position = global_position
	sync_position = position
	health = max_health


func activate() -> void:
	active = true
	_sync.public_visibility = true


## Fin du combat : le cube s'arrête et ne répond plus aux commandes.
func freeze() -> void:
	active = false
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not active:
		_update_model(Vector3.ZERO, delta)
		return
	var previous_position := position
	if is_multiplayer_authority():
		if is_alive():
			_simulate(delta)
			_regenerate(delta)
		else:
			_respawn_left -= delta
			if _respawn_left <= 0.0:
				respawn()
		sync_position = position
	else:
		_follow_network(delta)
	# Vitesse réelle (aussi pour les canards des autres ordinateurs, qui ne reçoivent que la position).
	_update_model((position - previous_position) / delta, delta)


## Oriente la caméra et le canard vers `point` (sur le plan horizontal).
func face(point: Vector3) -> void:
	camera.face(point)
	_turn_model_towards(Vector3.FORWARD.rotated(Vector3.UP, camera.get_yaw()), 1.0)


## Définit le point d'apparition (et y place le joueur), cf. ZoneSpawn.
func set_spawn_position(point: Vector3) -> void:
	_spawn_position = point
	global_position = point
	sync_position = position
	reset_physics_interpolation()


func is_alive() -> bool:
	return health > 0.0


## Inflige `amount` PV de dégâts. Appelable depuis n'importe quel ordinateur :
## les dégâts sont appliqués par celui qui a l'autorité sur ce cube.
func take_damage(amount: float) -> void:
	if is_multiplayer_authority():
		_apply_damage(amount)
	else:
		_apply_damage.rpc_id(get_multiplayer_authority(), amount)


## Réapparition au point de départ, avec toute sa vie.
func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_dash_time = 0.0
	_regen_cooldown_left = 0.0
	health = max_health
	reset_physics_interpolation()


func _simulate(delta: float) -> void:
	var input := Vector2.ZERO
	if is_local:
		input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if Input.is_action_just_pressed(&"jump") and is_on_floor():
			velocity.y = jump_velocity
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera.get_yaw())

	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	if is_local and Input.is_action_just_pressed(&"dash") and is_on_floor() and _dash_cooldown_left == 0.0:
		_start_dash(direction)

	# Petite marge : sans elle, 12 pas de 1/60 s font 0,19999… < 0,2 s (arrondis) et le tir prend une image de retard.
	_since_last_shot += delta + 0.0001
	# Nouvel appui : tir dès fire_cooldown écoulé ; touche maintenue : toutes les auto_fire_interval.
	var pressed := Input.is_action_just_pressed(&"shoot") and _since_last_shot >= fire_cooldown
	var held := Input.is_action_pressed(&"shoot") and _since_last_shot >= auto_fire_interval
	if is_local and (pressed or held):
		_since_last_shot = 0.0
		# Tout droit devant la caméra (à l'horizontale), depuis le centre du cube.
		var target := aim()
		# La bulle vise avec sa surface : son centre s'arrête à un rayon de la surface
		# visée, sinon son bas frôlerait le sol (ou le mur) et elle éclaterait avant.
		var aim_point: Vector3 = target.point + target.normal * BubbleProjectile.RADIUS
		_turn_model_towards(aim_point - global_position, 1.0) # D'abord tourner le canard : le canon pointe vers la cible.
		var origin := _muzzle.global_position if _muzzle else global_position
		var shot_direction := (aim_point - origin).normalized()
		# Cible trop proche (derrière le canon) : on tire simplement dans l'axe de la caméra.
		if shot_direction.dot(camera.get_aim_ray()[1]) < 0.5:
			shot_direction = camera.get_aim_ray()[1]
		_shoot.rpc(origin, shot_direction)

	if not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta
	if _dash_time > 0.0:
		# Dash : vitesse horizontale selon la courbe (la gravité s'applique si on quitte le sol).
		_dash_time = maxf(_dash_time - delta, 0.0)
		var speed := _dash_speed_at(1.0 - _dash_time / dash_duration)
		velocity.x = _dash_direction.x * speed
		velocity.z = _dash_direction.z * speed
	else:
		var target := direction * move_speed
		velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

	move_and_slide()

	if global_position.y < kill_height:
		_apply_damage(health)


func _regenerate(delta: float) -> void:
	_regen_cooldown_left = maxf(_regen_cooldown_left - delta, 0.0)
	if _regen_cooldown_left == 0.0 and health < max_health:
		health = minf(health + regen_rate * delta, max_health)


## Sur tous les ordinateurs (appelé par celui qui contrôle ce cube).
@rpc("authority", "call_local", "reliable")
func _shoot(origin: Vector3, direction: Vector3) -> void:
	_turn_model_towards(direction, 1.0) # Le canard se tourne d'un coup vers son tir.
	shot.emit(origin, direction)


## Sur tous les ordinateurs (appelé par celui qui contrôle ce cube) : lance les
## animations du dash.
@rpc("authority", "call_local", "reliable")
func _play_dash() -> void:
	_dash_animation_left = dash_duration


## Ce que vise le joueur (centre de l'écran) : { point, normal, collider (ou null) }.
## Le rayon part de la hauteur du canard (pas de la caméra) pour ignorer ce qui
## se trouve entre la caméra et lui.
func aim() -> Dictionary:
	var ray := camera.get_aim_ray()
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	origin += direction * maxf((global_position - origin).dot(direction), 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * AIM_DISTANCE,
			WORLD_LAYER | PLAYERS_LAYER | enemy_spawn_layer(team_of(player_id)), [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"point": origin + direction * AIM_DISTANCE, "normal": Vector3.ZERO, "collider": null}
	return {"point": hit.position, "normal": hit.normal, "collider": hit.collider}


## Vrai si le viseur est sur un adversaire vivant.
func is_aiming_at_enemy() -> bool:
	var target := aim().collider as Player
	return target != null and target.is_alive() and team_of(target.player_id) != team_of(player_id)


## Crée un repère au bout du canon : extrémité du mesh du pistolet, côté avant du canard.
func _create_muzzle() -> void:
	var gun := _model.find_child(GUN_MESH, true, false) as MeshInstance3D
	if gun == null:
		return
	var box := gun.get_aabb()
	var half := box.get_longest_axis() * box.get_longest_axis_size() / 2.0
	var end_a := box.get_center() + half
	var end_b := box.get_center() - half
	var forward := _model.global_basis.z # Le canard regarde vers +Z.
	_muzzle = Marker3D.new()
	_muzzle.name = &"Muzzle"
	gun.add_child(_muzzle)
	_muzzle.position = end_a if (gun.to_global(end_a) - gun.to_global(end_b)).dot(forward) > 0.0 else end_b


## Animation et orientation du canard selon sa vitesse (et le dash en cours).
func _update_model(velocity_now: Vector3, delta: float) -> void:
	var horizontal := Vector3(velocity_now.x, 0.0, velocity_now.z)
	var speed := horizontal.length()
	var moving := speed > MOVING_SPEED and is_alive()
	if moving:
		_turn_model_towards(horizontal, 1.0 - exp(-TURN_SPEED * delta))
	_dash_animation_left = maxf(_dash_animation_left - delta, 0.0)
	var dashing := _dash_animation_left > 0.0
	_animation_tree.set(&"parameters/conditions/dashing", dashing)
	_animation_tree.set(&"parameters/conditions/dash_over", not dashing)
	_animation_tree.set(&"parameters/conditions/idle", not moving)
	_animation_tree.set(&"parameters/conditions/walk", moving and speed <= RUN_SPEED)
	_animation_tree.set(&"parameters/conditions/run", moving and speed > RUN_SPEED)


## Le modèle regarde vers +Z : on l'aligne sur `direction` (weight = 1 : d'un coup).
func _turn_model_towards(direction: Vector3, weight: float) -> void:
	if Vector2(direction.x, direction.z).is_zero_approx():
		return
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(direction.x, direction.z), weight)


@rpc("any_peer", "call_remote", "reliable")
func _apply_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0:
		return
	_regen_cooldown_left = regen_delay
	health = maxf(health - amount, 0.0)


## Sur tous les ordinateurs : le cube mort disparaît et ne bloque plus personne.
func _on_died() -> void:
	_respawn_left = respawn_delay
	_model.visible = false
	_collision_shape.set_deferred(&"disabled", true)
	died.emit()


func _on_respawned() -> void:
	_dash_animation_left = 0.0
	_animation_playback.start(&"idle") # Repart de l'arrêt, pas de l'animation au moment de la mort.
	_model.visible = true
	_collision_shape.set_deferred(&"disabled", false)
	respawned.emit()


## Vitesse du dash à l'instant `t` (0 = début, 1 = fin).
func _dash_speed_at(t: float) -> float:
	var cruise := lerpf(dash_speed, move_speed, smoothstep(DASH_SLOWDOWN_START, 1.0, t))
	return lerpf(_dash_start_speed, cruise, smoothstep(0.0, DASH_RAMP, t))


## Dash (au sol uniquement) dans la direction du joystick, ou devant la caméra s'il est au repos.
func _start_dash(direction: Vector3) -> void:
	if direction.is_zero_approx():
		direction = Vector3.FORWARD.rotated(Vector3.UP, camera.get_yaw())
	_dash_direction = direction.normalized()
	_dash_start_speed = Vector2(velocity.x, velocity.z).length()
	_dash_time = dash_duration
	_dash_cooldown_left = dash_cooldown
	_play_dash.rpc()


func _follow_network(delta: float) -> void:
	if position.distance_to(sync_position) > REMOTE_SNAP_DISTANCE:
		position = sync_position
		reset_physics_interpolation()
	else:
		position = position.lerp(sync_position, 1.0 - exp(-REMOTE_SMOOTHING * delta))


func _apply_color() -> void:
	collision_mask = WORLD_LAYER | PLAYERS_LAYER | enemy_spawn_layer(team_of(player_id))
	if _model == null: # Setter appelé avant que le nœud soit prêt.
		return
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mesh.name in TEAM_COLORED_MESHES:
			mesh.material_override = TEAM_MATERIALS[team_of(player_id) - 1]
		else:
			mesh.material_override = MESH_MATERIALS.get(mesh.name)
