class_name PlayerCamera
extends Node3D
## Caméra 3e personne, enfant d'un Player.
## Seule la caméra du cube contrôlé par cet ordinateur est affichée et réagit
## aux entrées : joystick droit (actions look_*) et souris / trackpad.
##
## Hiérarchie : PlayerCamera (lacet / yaw) > Pitch (tangage) > SpringArm > Camera
## Cadrage façon Splatoon : pivot 1,15 m au-dessus du centre du canard (au-dessus
## de sa tête), bras de 3,2 m presque horizontal (-2°) : le canard est en bas au
## centre de l'écran, le viseur (centre de l'écran, sauf aide à la visée : cf.
## AimAssist) juste au-dessus de lui.
## Au repos, le viseur vise donc au loin à hauteur de tête : les bulles portent
## (incliné vers le bas, il viserait le sol et les bulles s'y écraseraient).
## Le SpringArm rapproche la caméra si un mur se trouve entre elle et le joueur.

## Vitesse de rotation en radians par seconde (stick poussé à fond).
@export var look_sensitivity := 4.0
## Radians par pixel de déplacement de la souris / du trackpad.
@export var mouse_sensitivity := 0.004
@export_range(-89.0, 0.0) var min_pitch_degrees := -70.0
@export_range(0.0, 89.0) var max_pitch_degrees := 45.0
@export var invert_y := false

## Hauteur d'écran de référence des décalages en pixels (comme le viseur).
const REFERENCE_HEIGHT := 1080.0

## Décalage du viseur par rapport au centre de l'écran (px, à 1080 px de haut),
## réglé par AimAssist. La caméra, elle, ne bouge pas.
var aim_offset := Vector2.ZERO

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


## Rayon de visée : part de la caméra et passe par le viseur (centre de l'écran
## décalé de aim_offset).
func get_aim_ray() -> Array[Vector3]:
	var rect := get_viewport().get_visible_rect()
	var point := rect.get_center() + aim_offset * rect.size.y / REFERENCE_HEIGHT
	return [_camera.project_ray_origin(point), _camera.project_ray_normal(point)]


## Position de `world_point` à l'écran, en décalage depuis le centre (px, à 1080 px
## de haut) ; null s'il est derrière la caméra.
func screen_offset_of(world_point: Vector3) -> Variant:
	if _camera.is_position_behind(world_point):
		return null
	var rect := get_viewport().get_visible_rect()
	return (_camera.unproject_position(world_point) - rect.get_center()) * REFERENCE_HEIGHT / rect.size.y


## Rotation horizontale de la caméra, utilisée pour orienter les déplacements du joueur.
func get_yaw() -> float:
	return global_rotation.y

