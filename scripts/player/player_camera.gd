class_name PlayerCamera
extends Node3D
## Caméra 3e personne, enfant d'un Player.
## Seule la caméra du cube contrôlé par cet ordinateur est affichée et réagit
## aux entrées : joystick droit (actions look_*) et souris / trackpad.
##
## Hiérarchie : PlayerCamera (lacet / yaw) > Pitch (tangage) > SpringArm > Camera
## Le SpringArm rapproche la caméra si un mur se trouve entre elle et le joueur.

## Vitesse de rotation en radians par seconde (stick poussé à fond).
@export var look_sensitivity := 4.0
## Radians par pixel de déplacement de la souris / du trackpad.
@export var mouse_sensitivity := 0.004
@export_range(-89.0, 0.0) var min_pitch_degrees := -70.0
@export_range(0.0, 89.0) var max_pitch_degrees := 30.0
@export var invert_y := false

@onready var _player: Player = get_parent()
@onready var _pitch: Node3D = $Pitch
@onready var _spring_arm: SpringArm3D = $Pitch/SpringArm
@onready var _camera: Camera3D = $Pitch/SpringArm/Camera


func _ready() -> void:
	_spring_arm.add_excluded_object(_player.get_rid())


func _physics_process(delta: float) -> void:
	if not _player.is_local:
		return
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	_rotate_view(look * look_sensitivity * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _player.is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_view(event.screen_relative * mouse_sensitivity)


## `amount.x` > 0 tourne vers la droite, `amount.y` > 0 regarde vers le bas.
func _rotate_view(amount: Vector2) -> void:
	if invert_y:
		amount.y = -amount.y
	rotation.y -= amount.x
	_pitch.rotation.x = clampf(
		_pitch.rotation.x - amount.y,
		deg_to_rad(min_pitch_degrees),
		deg_to_rad(max_pitch_degrees),
	)


## Affiche (ou non) le jeu depuis cette caméra.
func set_view_active(view_active: bool) -> void:
	_camera.current = view_active


## Oriente la caméra pour regarder dans la direction de `point` (sur le plan horizontal).
func face(point: Vector3) -> void:
	var direction := point - global_position
	if Vector2(direction.x, direction.z).is_zero_approx():
		return
	global_rotation.y = atan2(-direction.x, -direction.z)


## Rotation horizontale de la caméra, utilisée pour orienter les déplacements du joueur.
func get_yaw() -> float:
	return global_rotation.y

