class_name AimAssist
extends Node
## Aide à la visée du joueur local (enfant d'un Player). Si un adversaire visible
## entre dans le rectangle `box_size` autour du centre de l'écran, le viseur glisse
## vers lui sans bouger la caméra (PlayerCamera.aim_offset), en restant dans le
## rectangle ; les bulles partent vers le viseur. Sans cible, il revient au centre.
## Coupée pendant la visée (PlayerCamera.aiming) : le viseur revient au centre.

@export var enabled := true
## Taille du rectangle autour du centre de l'écran (px, à 1080 px de haut).
@export var box_size := Vector2(200, 150)
## Vitesse à laquelle le viseur rejoint la cible (plus élevé = plus rapide).
@export var follow_speed := 12.0
## Au-delà de cette distance (m), un adversaire n'attire pas le viseur.
## Le rectangle s'affiche en debug mode (Ctrl + D, cf. Game).
@export var max_distance := 30.0

@onready var _player: Player = get_parent()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _player.is_local:
		return
	var camera := _player.camera
	var target := _find_target_offset() if is_active() and _player.is_alive() else Vector2.ZERO
	camera.aim_offset = camera.aim_offset.lerp(target, 1.0 - exp(-follow_speed * delta))


## Vrai si l'aide agit : activée, et le joueur ne vise pas.
func is_active() -> bool:
	return enabled and not _player.camera.aiming


## Décalage à l'écran (px, à 1080 px de haut) de l'adversaire visible le plus proche
## du centre parmi ceux qui sont dans le rectangle, Vector2.ZERO s'il n'y en a pas.
func _find_target_offset() -> Vector2:
	var camera := _player.camera
	var eye: Vector3 = camera.get_aim_ray()[0]
	var space := _player.get_world_3d().direct_space_state
	var team := Player.team_of(_player.player_id)
	var best := Vector2.ZERO
	var best_length := INF
	for other in _player.get_parent().get_children():
		var enemy := other as Player
		if enemy == null or not enemy.is_alive() or Player.team_of(enemy.player_id) == team \
				or eye.distance_to(enemy.global_position) > max_distance:
			continue
		var offset: Variant = camera.screen_offset_of(enemy.global_position)
		if offset == null or absf(offset.x) > box_size.x / 2.0 or absf(offset.y) > box_size.y / 2.0:
			continue
		# Caché derrière un obstacle (ou le mur de la zone d'apparition adverse) : ignoré.
		var query := PhysicsRayQueryParameters3D.create(eye, enemy.global_position,
				Player.WORLD_LAYER | Player.enemy_spawn_layer(team))
		if not space.intersect_ray(query).is_empty():
			continue
		if offset.length() < best_length:
			best = offset
			best_length = offset.length()
	return best
