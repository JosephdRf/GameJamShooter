class_name BubbleProjectile
extends Node3D
## Bulle tirée par un joueur (scène instanciée par Game sous Projectiles).
##
## Avance tout droit à `speed` m/s et éclate (pop) au premier de ces événements :
##   - elle touche un obstacle (calque « world » : sol, murs, plafond, objets),
##     ou le mur invisible de la zone d'apparition adverse ;
##   - elle touche un joueur : `damage` PV de dégâts s'il est de l'autre équipe ;
##   - elle a parcouru `max_distance` mètres.
## Puis le nœud est supprimé (queue_free) à la fin de l'animation d'éclatement.
##
## Optimisation : pas de corps physique ni de zone de collision. À chaque image
## physique, une sphère de la taille de la bulle est « lancée » de l'ancienne à
## la nouvelle position (cast_motion) : rien ne peut être traversé, même à
## grande vitesse. Mesh, matériau et forme de collision sont partagés par
## toutes les bulles.
##
## Réseau : chaque ordinateur fait voler sa propre copie de la bulle (même
## départ, même trajectoire) ; seule celle de l'ordinateur du tireur inflige
## les dégâts (Player.take_damage les transmet au bon ordinateur).

## Vitesse (m/s).
@export var speed := 30.0
## Portée (m) : la bulle éclate au-delà.
@export var max_distance := 25.0
@export var damage := 40.0
## Dégâts aussi sur les coéquipiers (sinon la bulle éclate sans les blesser).
@export var friendly_fire := false
## Durée de l'animation d'éclatement (s).
@export var pop_duration := 0.12
## La bulle sort du canon petite et atteint sa taille en `grow_duration` s.
@export var grow_duration := 0.12
@export var start_scale := 0.2

## Rayon de la bulle (m) : garder égal au rayon du SphereMesh de la scène.
## Sert à la détection et à la visée (Player vise avec la surface de la bulle).
const RADIUS := 0.35

## Forme de détection, partagée par toutes les bulles.
static var _hit_shape: SphereShape3D
## Matériau de chaque équipe (index 0 = équipe 1), partagé par toutes ses bulles :
## celui de la scène, teinté à la couleur de l'équipe (même transparence).
static var _team_materials: Array[StandardMaterial3D] = []

var _direction := Vector3.FORWARD
var _travelled := 0.0
var _shooter_team := 0
var _deals_damage := false
var _query: PhysicsShapeQueryParameters3D
var _grow_tween: Tween


## À appeler juste après l'ajout à la scène. `deals_damage` : vrai seulement
## sur l'ordinateur du tireur.
func launch(shooter: Player, origin: Vector3, direction: Vector3, deals_damage: bool) -> void:
	global_position = origin
	_direction = direction.normalized()
	_shooter_team = Player.team_of(shooter.player_id)
	var mesh := $Mesh as MeshInstance3D
	if _team_materials.is_empty():
		var base := mesh.get_active_material(0) as StandardMaterial3D
		for team_color in Player.TEAM_COLORS:
			var material := base.duplicate() as StandardMaterial3D
			material.albedo_color = Color(team_color.lerp(Color.WHITE, 0.1), base.albedo_color.a + 0.25)
			_team_materials.append(material)
	mesh.material_override = _team_materials[_shooter_team - 1]
	_deals_damage = deals_damage
	if _hit_shape == null:
		_hit_shape = SphereShape3D.new()
		_hit_shape.radius = RADIUS
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _hit_shape
	_query.collision_mask = Player.WORLD_LAYER | Player.PLAYERS_LAYER | Player.enemy_spawn_layer(_shooter_team)
	_query.exclude = [shooter.get_rid()] # Ne se touche pas soi-même au départ.
	reset_physics_interpolation()
	scale = Vector3.ONE * start_scale
	_grow_tween = create_tween()
	_grow_tween.tween_property(self, ^"scale", Vector3.ONE, grow_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	var step := minf(speed * delta, max_distance - _travelled)
	var space := get_world_3d().direct_space_state
	_query.transform = Transform3D(Basis.IDENTITY, global_position)
	if _travelled == 0.0:
		# Premier pas : cast_motion ignore ce qui touche déjà la bulle (canon collé à un mur, à un adversaire…).
		_query.motion = Vector3.ZERO
		var overlap := space.get_rest_info(_query)
		if not overlap.is_empty():
			_on_hit(instance_from_id(overlap.collider_id))
			return
	_query.motion = _direction * step
	# [fraction sans contact, fraction au contact] du déplacement ; 1 = aucun obstacle.
	var fractions := space.cast_motion(_query)
	if fractions[1] < 1.0:
		_query.transform.origin = global_position + _query.motion * fractions[1]
		var contact := space.get_rest_info(_query)
		global_position += _query.motion * fractions[0]
		_on_hit(instance_from_id(contact.collider_id) if not contact.is_empty() else null)
		return
	global_position += _query.motion
	_travelled += step
	if _travelled >= max_distance:
		_pop()


func _on_hit(collider: Object) -> void:
	var player := collider as Player
	if player and _deals_damage and (friendly_fire or Player.team_of(player.player_id) != _shooter_team):
		player.take_damage(damage)
	_pop()


## Éclatement : la bulle gonfle et s'efface, puis le nœud est supprimé.
func _pop() -> void:
	set_physics_process(false)
	if _grow_tween:
		_grow_tween.kill()
	var mesh := $Mesh as GeometryInstance3D
	var tween := create_tween().set_parallel()
	tween.tween_property(self, ^"scale", Vector3.ONE * 1.8, pop_duration)
	tween.tween_property(mesh, ^"transparency", 1.0, pop_duration)
	tween.chain().tween_callback(queue_free)
