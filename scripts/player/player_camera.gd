class_name PlayerCamera
extends Node3D
## Caméra 3e personne, enfant d'un Player.
## Seule la caméra du cube contrôlé par cet ordinateur est affichée et réagit
## aux entrées : joystick droit (actions look_*) et souris / trackpad.
##
## Hiérarchie : PlayerCamera (lacet / yaw) > Pitch (tangage) > SpringArm > Camera
## Cadrage façon Splatoon : pivot 1,44 m au-dessus du centre du canard (au-dessus
## de sa tête), bras de 4 m presque horizontal (-2°) : le canard est en bas au
## centre de l'écran, le viseur (centre de l'écran, sauf aide à la visée : cf.
## AimAssist) juste au-dessus de lui.
## Au repos, le viseur vise donc au loin à hauteur de tête : les bulles portent
## (incliné vers le bas, il viserait le sol et les bulles s'y écraseraient).
## Le SpringArm rapproche la caméra si un mur se trouve entre elle et le joueur.
## Visée (action aim maintenue : L2 / ZL, clic gauche) : la caméra avance le long
## de son bras et resserre son champ ; le viseur reste au centre de l'écran (aide
## à la visée coupée, cf. AimAssist) et vise le même point qu'avant le zoom.

## Vitesse de rotation en radians par seconde (stick poussé à fond).
@export var look_sensitivity := 4.0
## Radians par pixel de déplacement de la souris / du trackpad.
@export var mouse_sensitivity := 0.004
## Inclinaison verticale de la caméra (°) : limite basse (vers le sol) et haute (vers le plafond).
@export_range(-89.0, 0.0) var min_pitch_degrees := -75.0
@export_range(0.0, 89.0) var max_pitch_degrees := 60.0
@export var invert_y := false
## Visée : champ de vision (°) et longueur du bras (m), au lieu de ceux de la scène.
@export var aim_fov := 55.0
@export var aim_arm_length := 2.5
## Vitesse du zoom (plus élevé = plus rapide).
@export var aim_zoom_speed := 14.0

## Hauteur d'écran de référence des décalages en pixels (comme le viseur).
const REFERENCE_HEIGHT := 1080.0

## Décalage du viseur par rapport au centre de l'écran (px, à 1080 px de haut),
## réglé par AimAssist. La caméra, elle, ne bouge pas.
var aim_offset := Vector2.ZERO
## Vrai tant que le joueur local (vivant, en jeu) maintient l'action aim.
var aiming := false

var _zoom := 0.0 # 0 = normal, 1 = visée.
var _base_fov: float
var _base_arm_length: float

@onready var _player: Player = get_parent()
@onready var _pitch: Node3D = $Pitch
@onready var _spring_arm: SpringArm3D = $Pitch/SpringArm
@onready var _camera: Camera3D = $Pitch/SpringArm/Camera


func _ready() -> void:
	_spring_arm.add_excluded_object(_player.get_rid())
	_base_fov = _camera.fov
	_base_arm_length = _spring_arm.spring_length


func _process(delta: float) -> void:
	aiming = _player.is_local and _player.active and _player.is_alive() and Input.is_action_pressed(&"aim")
	var target_zoom := 1.0 if aiming else 0.0
	if _zoom == target_zoom:
		return
	_zoom = lerpf(_zoom, target_zoom, 1.0 - exp(-aim_zoom_speed * delta))
	if absf(_zoom - target_zoom) < 0.001:
		_zoom = target_zoom
	# La caméra avance dans l'axe de son bras : le centre de l'écran vise toujours le même point.
	_camera.fov = lerpf(_base_fov, aim_fov, _zoom)
	_spring_arm.spring_length = lerpf(_base_arm_length, aim_arm_length, _zoom)


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

