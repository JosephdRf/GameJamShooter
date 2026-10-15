@tool
class_name ZoneSpawn
extends Node3D
## Zone d'apparition d'une équipe : disque au sol à la couleur de l'équipe.
##
## Au début de la partie, Game place chaque joueur de l'équipe `team` sur un
## des emplacements de cette zone (côte à côte au centre) ; un
## joueur qui tombe de l'arène réapparaît à son emplacement.
## Position, rayon et équipe se règlent sur chaque instance, dans la scène de jeu.
##
## Mur invisible (Barrier, cylindre de 8 m de haut) : sur le calque de l'équipe
## (Player.SPAWN_LAYERS), il bloque les joueurs et les bulles de l'équipe adverse.

@export_range(1, 2) var team := 1:
	set(value):
		team = value
		_update_visuals()
@export var radius := 3.0:
	set(value):
		radius = value
		_update_shape()
## Hauteur du centre des joueurs au-dessus du sol à l'apparition (m) : moitié du canard.
@export var spawn_height := 1.05625
## Distance entre les centres de deux joueurs voisins à l'apparition (m).
@export var spawn_spacing := 3.0

@onready var _disk: MeshInstance3D = $Disk
@onready var _ring: MeshInstance3D = $Ring
@onready var _barrier: StaticBody3D = $Barrier
@onready var _barrier_shape: CylinderShape3D = $Barrier/Shape.shape


func _ready() -> void:
	_update_shape()
	_update_visuals()


## Emplacement (position globale) du joueur n° `index` (0, 1…) parmi `count` joueurs.
## Les joueurs sont côte à côte, sur une ligne perpendiculaire à la direction du centre de
## l'arène (origine) : tous à la même distance du centre.
func get_spawn_position(index: int, count: int) -> Vector3:
	var to_center := Vector3(-global_position.x, 0.0, -global_position.z).normalized()
	var side := to_center.cross(Vector3.UP) if not to_center.is_zero_approx() else Vector3.RIGHT
	var offset := side * (index - (count - 1) / 2.0) * spawn_spacing
	return global_position + offset + Vector3.UP * spawn_height


func _update_visuals() -> void:
	if not is_node_ready():
		return
	_barrier.collision_layer = Player.SPAWN_LAYERS[team - 1]
	var color := Player.TEAM_COLORS[team - 1]
	(_disk.material_override as StandardMaterial3D).albedo_color = Color(color, 0.35)
	(_ring.material_override as StandardMaterial3D).albedo_color = color


func _update_shape() -> void:
	if not is_node_ready():
		return
	(_disk.mesh as CylinderMesh).top_radius = radius
	(_disk.mesh as CylinderMesh).bottom_radius = radius
	(_ring.mesh as TorusMesh).outer_radius = radius
	(_ring.mesh as TorusMesh).inner_radius = radius - 0.2
	_barrier_shape.radius = radius
