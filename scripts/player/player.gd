@tool
class_name Player
extends CharacterBody3D
## Joueur contrôlable (cube). La couleur dépend de `player_id`.

const PLAYER_COLORS: Array[Color] = [
	Color("e5484d"), # Joueur 1 : rouge
	Color("f5c400"), # Joueur 2 : jaune
	Color("3b82f6"), # Joueur 3 : bleu
	Color("30a46c"), # Joueur 4 : vert
]

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

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_position: Vector3

## Caméra du joueur : les déplacements sont relatifs à son orientation.
@onready var camera: PlayerCamera = $PlayerCamera
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_apply_color()
	_spawn_position = global_position


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta

	if Input.is_action_just_pressed(_action(&"jump")) and is_on_floor():
		velocity.y = jump_velocity

	var input := Input.get_vector(_action(&"left"), _action(&"right"), _action(&"up"), _action(&"down"))
	var direction := Vector3(input.x, 0.0, input.y)
	if camera:
		direction = direction.rotated(Vector3.UP, camera.get_yaw())
	var target := direction * move_speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

	move_and_slide()

	if global_position.y < kill_height:
		respawn()


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _action(action_name: StringName) -> StringName:
	return InputManager.action(player_id, action_name)


func _apply_color() -> void:
	if _mesh == null: # Setter appelé avant que le nœud soit prêt.
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = PLAYER_COLORS[player_id - 1]
	_mesh.material_override = material
