@tool
extends EditorScenePostImport
## Script d'import de assets/models/bain-de-coin-coin.blend (arène salle de bain).
## Exécuté par Godot à chaque (ré)import du .blend : modifier ce fichier puis
## réimporter le .blend (onglet Import > Réimporter) pour appliquer les changements.
##
##   - Supprime le canard "hero" et son disque d'équipe (aperçu du personnage).
##   - Remplace les matériaux procéduraux de Blender (exportés en blanc) par
##     leur couleur dominante, et rend l'eau et les bulles transparentes.
##   - Ajoute des collisions grossières : une boîte par objet (StaticBody3D
##     "Collisions", calque "world"), sauf pour les objets décoratifs ci-dessous.
## L'échelle (0,16 : le canard mesure ~1 m, comme un joueur), l'exclusion des
## caméras et des lumières de Blender sont réglées dans les options d'import.

## Objets supprimés (préfixes de noms).
const REMOVED := ["hero", "team_disk", "team_ring"]
## Objets sans collision ni ombre : effets, liquides, petits détails.
const DECOR := ["foam", "fizz", "bubbleair", "drop", "jet", "water", "flame", "leaf",
		"skyplane", "tooth", "puddle", "rug", "hook", "succ", "mini_"]
## Objets plus petits que ça (en mètres) n'ont pas de collision.
const MIN_COLLIDER_SIZE := 0.3
## Couleurs dominantes des matériaux procéduraux (valeurs linéaires de Blender).
const MATERIAL_COLORS := {
	"floor": Color(0.50, 0.79, 0.75),
	"wall_lo_b": Color(0.24, 0.52, 0.66), "wall_lo_s": Color(0.24, 0.52, 0.66),
	"mos_b": Color(0.07, 0.55, 0.63), "mos_s": Color(0.07, 0.55, 0.63),
	"wall_hi_b": Color(0.86, 0.90, 0.90), "wall_hi_s": Color(0.86, 0.90, 0.90),
	"cloth_towel_b": Color(0.56, 0.83, 0.97), "cloth_towel_y": Color(1.0, 0.74, 0.07),
	"cloth_towel_p": Color(0.97, 0.52, 0.67), "wicker": Color(0.69, 0.46, 0.24),
	"sponge": Color(1.0, 0.80, 0.25), "bomb0": Color(0.19, 0.64, 0.87),
	"bomb1": Color(0.89, 0.21, 0.45), "bomb2": Color(0.11, 0.54, 0.39),
	"ring_rw": Color(0.86, 0.08, 0.07), "ring_tc": Color(0.07, 0.55, 0.63),
}
const WORLD_LAYER := 1


func _post_import(scene: Node) -> Object:
	for prefix: String in REMOVED:
		for node in scene.find_children(prefix + "*", "Node3D", true, false):
			if is_instance_valid(node) and node.get_parent():
				node.get_parent().remove_child(node)
				node.free()

	var body := StaticBody3D.new()
	body.name = "Collisions"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	scene.add_child(body)
	body.owner = scene

	for mesh_instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		_fix_materials(mesh_instance.mesh)
		if _is_decor(mesh_instance.name):
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_add_box_collider(body, mesh_instance, scene)
	return scene


func _is_decor(node_name: String) -> bool:
	for prefix: String in DECOR:
		if node_name.begins_with(prefix):
			return true
	return false


## Boîte orientée englobant le mesh.
func _add_box_collider(body: StaticBody3D, mesh_instance: MeshInstance3D, scene: Node) -> void:
	var xform := _transform_in(scene, mesh_instance)
	var aabb := mesh_instance.get_aabb()
	var size := aabb.size * xform.basis.get_scale()
	if maxf(size.x, maxf(size.y, size.z)) < MIN_COLLIDER_SIZE:
		return
	var box := BoxShape3D.new()
	box.size = size.max(Vector3.ONE * 0.05) # Les objets plats (sol, murs) gardent un peu d'épaisseur.
	var shape := CollisionShape3D.new()
	shape.name = mesh_instance.name
	shape.shape = box
	shape.transform = Transform3D(xform.basis.orthonormalized(), xform * aabb.get_center())
	body.add_child(shape)
	shape.owner = scene


func _fix_materials(mesh: Mesh) -> void:
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as StandardMaterial3D
		if material == null:
			continue
		var key := material.resource_name
		if MATERIAL_COLORS.has(key):
			material.albedo_color = MATERIAL_COLORS[key].linear_to_srgb()
		elif key == "water" or key.begins_with("bubble"):
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 0.45 if key == "water" else 0.3
			material.roughness = 0.05
			material.cull_mode = BaseMaterial3D.CULL_DISABLED if key == "water" else BaseMaterial3D.CULL_BACK


## Transformation de `node` relative à `root` (les nœuds ne sont pas encore dans l'arbre).
static func _transform_in(root: Node, node: Node3D) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != root and parent is Node3D:
		xform = parent.transform * xform
		parent = parent.get_parent()
	return xform
