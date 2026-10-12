@tool
class_name Player
extends CharacterBody3D
## Joueur (cube). La couleur et l'équipe dépendent de `player_id`.
##
## En réseau, l'ordinateur qui a l'autorité sur ce nœud simule le cube et
## diffuse `sync_position` (nœud Sync) ; les autres ordinateurs lissent le
## cube vers cette position.

const PLAYER_COLORS: Array[Color] = [
	Color("e5484d"), # Joueur 1 : rouge
	Color("f5c400"), # Joueur 2 : jaune
	Color("3b82f6"), # Joueur 3 : bleu
	Color("30a46c"), # Joueur 4 : vert
]
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
## En dessous de cette hauteur, le joueur réapparaît à sa position de départ.
@export var kill_height := -10.0

## Vrai si ce cube est piloté par les entrées de cet ordinateur.
var is_local := false
## Faux tant que la partie n'a pas commencé : le cube reste figé.
var active := false
## Position diffusée sur le réseau par l'ordinateur qui contrôle ce cube.
var sync_position: Vector3

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_position: Vector3

## Caméra du joueur : les déplacements sont relatifs à son orientation.
@onready var camera: PlayerCamera = $PlayerCamera
@onready var _mesh: MeshInstance3D = $Mesh
@onready var _sync: MultiplayerSynchronizer = $Sync


static func team_of(id: int) -> int:
	return 1 if id <= 2 else 2


func _ready() -> void:
	_apply_color()
	_spawn_position = global_position
	sync_position = position


func activate() -> void:
	active = true
	_sync.public_visibility = true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not active:
		return
	if is_multiplayer_authority():
		_simulate(delta)
		sync_position = position
	else:
		_follow_network(delta)


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _simulate(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta

	var input := Vector2.ZERO
	if is_local:
		input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if Input.is_action_just_pressed(&"jump") and is_on_floor():
			velocity.y = jump_velocity

	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera.get_yaw())
	var target := direction * move_speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

	move_and_slide()

	if global_position.y < kill_height:
		respawn()


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
	material.albedo_color = PLAYER_COLORS[player_id - 1]
	_mesh.material_override = material
