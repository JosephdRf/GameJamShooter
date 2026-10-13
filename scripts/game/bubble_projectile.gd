class_name BubbleProjectile
extends Node3D
## Bulle tirée par un joueur (scène instanciée par Game sous Projectiles).
##
## Avance tout droit à `speed` m/s et éclate (pop) au premier de ces événements :
##   - elle touche un obstacle (calque « world » : sol, murs, plafond, objets) ;
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

const WORLD_LAYER := 1
const PLAYERS_LAYER := 2

## Vitesse (m/s).
@export var speed := 30.0
## Portée (m) : la bulle éclate au-delà.
@export var max_distance := 25.0
@export var damage := 40.0
## Dégâts aussi sur les coéquipiers (sinon la bulle éclate sans les blesser).
@export var friendly_fire := false
## Durée de l'animation d'éclatement (s).
@export var pop_duration := 0.12

## Forme de détection, partagée par toutes les bulles : même rayon que le mesh.
static var _hit_shape: SphereShape3D

var _direction := Vector3.FORWARD
var _travelled := 0.0
var _shooter_team := 0
var _deals_damage := false
var _query: PhysicsShapeQueryParameters3D


## À appeler juste après l'ajout à la scène. `deals_damage` : vrai seulement
## sur l'ordinateur du tireur.
func launch(shooter: Player, origin: Vector3, direction: Vector3, deals_damage: bool) -> void:
	global_position = origin
	_direction = direction.normalized()
	_shooter_team = Player.team_of(shooter.player_id)
	_deals_damage = deals_damage
	if _hit_shape == null:
		_hit_shape = SphereShape3D.new()
		_hit_shape.radius = (($Mesh as MeshInstance3D).mesh as SphereMesh).radius
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _hit_shape
	_query.collision_mask = WORLD_LAYER | PLAYERS_LAYER
	_query.exclude = [shooter.get_rid()] # Ne se touche pas soi-même au départ.
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	var step := minf(speed * delta, max_distance - _travelled)
	var space := get_world_3d().direct_space_state
	_query.transform = Transform3D(Basis.IDENTITY, global_position)
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
	var mesh := $Mesh as GeometryInstance3D
	var tween := create_tween().set_parallel()
	tween.tween_property(self, ^"scale", Vector3.ONE * 1.8, pop_duration)
	tween.tween_property(mesh, ^"transparency", 1.0, pop_duration)
	tween.chain().tween_callback(queue_free)
