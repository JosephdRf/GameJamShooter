@tool
class_name ZoneSpawn
extends Node3D
## Zone d'apparition d'une équipe : disque au sol à la couleur de l'équipe.
##
## Au début de la partie, Game place chaque joueur de l'équipe `team` sur un
## des emplacements de cette zone (répartis en cercle autour du centre) ; un
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
@export var spawn_height := 0.65

@onready var _disk: MeshInstance3D = $Disk
@onready var _ring: MeshInstance3D = $Ring
@onready var _barrier: StaticBody3D = $Barrier
@onready var _barrier_shape: CylinderShape3D = $Barrier/Shape.shape


func _ready() -> void:
	_update_shape()
	_update_visuals()


## Emplacement (position globale) du joueur n° `index` (0, 1…) parmi `count` joueurs.
## Les joueurs sont répartis à mi-rayon, côte à côte (le long de l'axe X local).
func get_spawn_position(index: int, count: int) -> Vector3:
	var offset := Vector3.ZERO
	if count > 1:
		var angle := PI + TAU * index / count
		offset = Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.5
	return global_transform * (offset + Vector3.UP * spawn_height)


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
