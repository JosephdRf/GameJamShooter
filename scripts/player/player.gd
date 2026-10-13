@tool
class_name Player
extends CharacterBody3D
## Joueur (cube). L'équipe (et donc la couleur) dépend de `player_id` :
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
## Vitesse de rattrapage des cubes distants (plus élevé = plus réactif, moins lisse).
const REMOTE_SMOOTHING := 25.0
## Au-delà de cet écart, un cube distant est téléporté (ex. réapparition).
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
## Vitesse horizontale pendant le dash (m/s).
@export var dash_speed := 24.0
## Durée du dash (s) : distance parcourue ≈ dash_speed × dash_duration.
@export var dash_duration := 0.18
## Temps minimum entre deux dashs (s).
@export var dash_cooldown := 2.0
@export_group("Tir")
## Temps minimum entre deux tirs (s).
@export var fire_cooldown := 0.25
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
var _dash_velocity: Vector3
## Temps restant avant de pouvoir tirer à nouveau (s).
var _fire_cooldown_left := 0.0
## Temps restant avant que la vie remonte (s).
var _regen_cooldown_left := 0.0
## Temps restant avant la réapparition, quand le joueur est mort (s).
var _respawn_left := 0.0

## Caméra du joueur : les déplacements sont relatifs à son orientation.
@onready var camera: PlayerCamera = $PlayerCamera
@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collision_shape: CollisionShape3D = $CollisionShape
@onready var _sync: MultiplayerSynchronizer = $Sync


## Équipe (1 ou 2) du joueur `id`.
static func team_of(id: int) -> int:
	return 1 if id <= 2 else 2


static func color_of(id: int) -> Color:
	return TEAM_COLORS[team_of(id) - 1]


func _ready() -> void:
	_apply_color()
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
	if Engine.is_editor_hint() or not active:
		return
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

	_fire_cooldown_left = maxf(_fire_cooldown_left - delta, 0.0)
	if is_local and Input.is_action_just_pressed(&"shoot") and _fire_cooldown_left == 0.0:
		_fire_cooldown_left = fire_cooldown
		# Tout droit devant la caméra (à l'horizontale), depuis le centre du cube.
		_shoot.rpc(global_position, Vector3.FORWARD.rotated(Vector3.UP, camera.get_yaw()))

	if not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta
	if _dash_time > 0.0:
		# Dash : vitesse horizontale fixe (la gravité s'applique si on quitte le sol).
		_dash_time -= delta
		velocity.x = _dash_velocity.x
		velocity.z = _dash_velocity.z
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
	shot.emit(origin, direction)


@rpc("any_peer", "call_remote", "reliable")
func _apply_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0:
		return
	_regen_cooldown_left = regen_delay
	health = maxf(health - amount, 0.0)


## Sur tous les ordinateurs : le cube mort disparaît et ne bloque plus personne.
func _on_died() -> void:
	_respawn_left = respawn_delay
	_mesh.visible = false
	_collision_shape.set_deferred(&"disabled", true)
	died.emit()


func _on_respawned() -> void:
	_mesh.visible = true
	_collision_shape.set_deferred(&"disabled", false)
	respawned.emit()


## Dash (au sol uniquement) dans la direction du joystick, ou devant la caméra s'il est au repos.
func _start_dash(direction: Vector3) -> void:
	if direction.is_zero_approx():
		direction = Vector3.FORWARD.rotated(Vector3.UP, camera.get_yaw())
	_dash_velocity = direction.normalized() * dash_speed
	_dash_time = dash_duration
	_dash_cooldown_left = dash_cooldown


func _follow_network(delta: float) -> void:
	if position.distance_to(sync_position) > REMOTE_SNAP_DISTANCE:
		position = sync_position
		reset_physics_interpolation()
	else:
		position = position.lerp(sync_position, 1.0 - exp(-REMOTE_SMOOTHING * delta))


func _apply_color() -> void:
	if _mesh == null: # Setter appelé avant que le nœud soit prêt.
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color_of(player_id)
	_mesh.material_override = material
