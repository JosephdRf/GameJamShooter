@tool
extends EditorScenePostImport

## Collisions de l'arène (GLB), légères (« low poly ») : la forme exacte d'un objet détaillé
## (serviettes pliées, toilettes, tongs…) fait accrocher et trembler le canard. Selon l'objet :
##   - aucune : l'eau (on la traverse) et les petits objets (moins de TINY_SIZE m), pour ne pas
##     buter dessus ;
##   - forme exacte (trimesh) : la structure (sol, murs, plafond, marches)
##     et les objets déjà simples (au plus TRIMESH_MAX_TRIANGLES triangles) ;
##   - boîte : les objets « en pavé » (BOX_PREFIXES : serviettes, magazines, étagères…) ;
##   - forme exacte simplifiée (au plus CONCAVE_TRIANGLES triangles, cf. SurfaceTool.generate_lod) :
##     les objets creux ou sur pieds dont la forme compte pour se déplacer (CONCAVE_PREFIXES :
##     baignoire, placard ouvert sous le lavabo, matelas, planche à repasser, toilettes, carton…) ;
##   - une coque convexe simplifiée : tout le reste.
## Les objets sans collision reçoivent la métadonnée `sans_collision` (arena5.gd n'en ajoute pas).
## Préfixes : « Bateau_* » garde ses collisions ; noms comparés en minuscules.

const SKIP := ["eau"]
const TINY_SIZE := 1.0
const TRIMESH_MAX_TRIANGLES := 150
const TRIMESH_PREFIXES := ["sol", "murs", "plafond", "marche"]
const BOX_PREFIXES := ["serviette", "magazine", "rebord", "etagere", "machine_a_laver",
		"panier_linge", "socle_seche_cheveux", "cadre", "vitre", "porte"]
const CONCAVE_PREFIXES := ["cuve", "placard", "tabouret", "bouee_matelas", "pieds_baignoire", "toilettes", "table_repassage",
		"bateau_coque", "carton", "vasque", "tuyaux"]
const CONCAVE_TRIANGLES := 400


func _post_import(scene: Node) -> Object:
	var counts := {}
	_add_collisions(scene, counts)
	print("arena GLB post-import: ", counts)
	return scene


func _add_collisions(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var kind := _collider_for(node as MeshInstance3D)
		counts[kind] = counts.get(kind, 0) + 1
	for child in node.get_children():
		_add_collisions(child, counts)


func _collider_for(mi: MeshInstance3D) -> String:
	for child in mi.get_children():
		if child is StaticBody3D:
			mi.remove_child(child)
			child.free()
	var name := String(mi.name).to_lower()
	var aabb := mi.mesh.get_aabb()
	var world_size := (_scene_basis(mi) * aabb.size).abs()
	if _starts(name, SKIP) or maxf(world_size.x, maxf(world_size.y, world_size.z)) < TINY_SIZE:
		mi.set_meta(&"sans_collision", true)
		return "aucune"
	if _starts(name, TRIMESH_PREFIXES) or _triangles(mi.mesh) <= TRIMESH_MAX_TRIANGLES:
		mi.create_trimesh_collision()
		return "trimesh"
	if _starts(name, BOX_PREFIXES):
		var body := StaticBody3D.new()
		body.name = "StaticBody3D"
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = aabb.size.abs().max(Vector3.ONE * 0.05)
		shape.shape = box
		shape.position = aabb.get_center()
		body.add_child(shape)
		mi.add_child(body)
		body.owner = mi.owner
		shape.owner = mi.owner
		return "boîte"
	if _starts(name, CONCAVE_PREFIXES):
		var faces := _simplified_faces(mi.mesh, CONCAVE_TRIANGLES)
		if faces.is_empty():
			mi.create_trimesh_collision()
			return "trimesh"
		var body := StaticBody3D.new()
		body.name = "StaticBody3D"
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(faces)
		shape.shape = concave
		body.add_child(shape)
		mi.add_child(body)
		body.owner = mi.owner
		shape.owner = mi.owner
		return "simplifiée"
	mi.create_convex_collision(true, true)
	return "coque"


## Orientation et échelle de `node` dans la scène importée (pas encore dans l'arbre).
func _scene_basis(node: Node) -> Basis:
	var basis := Basis.IDENTITY
	while node is Node3D:
		basis = (node as Node3D).transform.basis * basis
		node = node.get_parent()
	return basis


func _starts(name: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if name.begins_with(prefix):
			return true
	return false


## Triangles du maillage simplifié à environ `target` triangles (répartis entre ses surfaces).
func _simplified_faces(mesh: Mesh, target: int) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var total := maxi(_triangles(mesh), 1)
	for s in mesh.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(mesh, s)
		tool.index()
		var arrays := tool.commit_to_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var wanted := maxi(int(float(target) * (indices.size() / 3) / total), 4) * 3
		var lod: PackedInt32Array = tool.generate_lod(25.0, wanted) if indices.size() > wanted else indices
		if lod.is_empty():
			lod = indices
		for i in lod:
			faces.append(vertices[i])
	return faces


func _triangles(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		count += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count
