@tool
extends EditorScenePostImport

## Collisions de l'arène (GLB), légères (« low poly ») : la forme exacte d'un objet détaillé
## (serviettes pliées, toilettes, tongs…) fait accrocher et trembler le canard. Selon l'objet :
##   - aucune : l'eau (on la traverse) et les petits objets (moins de TINY_SIZE m), pour ne pas
##     buter dessus ; aussi Socle_Seche_Cheveux, qui malgré son nom (objet réutilisé dans Blender)
##     est le tuyau du tunnel douche-meuble : sa collision ne sert à rien, on y entre et en sort
##     par un dash automatique, cf. scripts/game/water_tunnel.gd ;
##   - forme exacte (trimesh) : la structure (sol, murs, plafond, marches)
##     et les objets déjà simples (au plus TRIMESH_MAX_TRIANGLES triangles) ;
##   - coque convexe prolongée jusqu'au sol (RAMPS) : la serviette pliée en pente, sur laquelle on
##     monte ;
##   - boîte : les objets « en pavé » (BOX_PREFIXES : serviettes, magazines, étagères…) ;
##   - forme exacte simplifiée (au plus CONCAVE_TRIANGLES triangles, cf. SurfaceTool.generate_lod) :
##     les objets creux ou sur pieds dont la forme compte pour se déplacer (CONCAVE_PREFIXES :
##     baignoire, placard ouvert sous le lavabo, matelas, bouée oiseau, planche à repasser,
##     toilettes, carton…) ;
##     certains gardent plus de triangles (CONCAVE_DETAILED : le panier à linge, renversé, pour
##     garder les trous par lesquels on entre dessous : le grand trou d'un côté et les poignées) ;
##     le panier et le carton ont un dessus en boîte (TOP_BOX), pour y marcher sans accrocher ;
##     ceux de MULTICONVEX_PREFIXES (vide pour l'instant) sont décomposés en plusieurs coques
##     convexes (VHACD) plutôt qu'en une seule forme concave ;
##   - une coque convexe simplifiée : tout le reste.
## Les objets sans collision reçoivent la métadonnée `sans_collision` (arena5.gd n'en ajoute pas).
## Préfixes : « Bateau_* » garde ses collisions ; noms comparés en minuscules.

const SKIP := ["eau", "socle_seche_cheveux"]
const TINY_SIZE := 1.0
const TRIMESH_MAX_TRIANGLES := 150
const TRIMESH_PREFIXES := ["sol", "murs", "plafond", "marche"]
const BOX_PREFIXES := ["serviette", "magazine", "rebord", "etagere", "machine_a_laver",
		"cadre", "vitre", "porte"]
const CONCAVE_PREFIXES := ["cuve", "placard", "tabouret", "bouee_matelas", "pieds_baignoire", "toilettes", "table_repassage",
		"bateau_coque", "carton", "vasque", "tuyaux", "panier_linge",
		"bouee_detail"]
const CONCAVE_TRIANGLES := 400
const CONCAVE_DETAILED := {"panier_linge": 3000}
## Coques convexes prolongées jusqu'au sol : nom de l'objet -> points ajoutés à sa coque (dans la
## scène). Serviette_005, pliée en pente contre la pile de serviettes, a un bord bas arrondi de
## 0,6 à 0,8 m, plus haut que la marche que le canard franchit seul (Player.max_step_height) : sa
## coque, étendue jusqu'à une arête au sol, devient une pente lisse (environ 30°) du sol au haut de
## la pile, sans sauter.
const RAMPS := {
	"serviette_005": [Vector3(-27.45, -0.27, -17.3), Vector3(-27.8, -0.27, -10.8)],
}
## Parmi CONCAVE_PREFIXES, ceux sur lesquels on marche directement : décomposés en coques
## convexes (cf. ci-dessus) plutôt qu'une seule forme concave.
const MULTICONVEX_PREFIXES := []
## Nombre de coques convexes au plus (plus = forme plus fidèle, mais plus de calcul).
const MULTICONVEX_MAX_HULLS := 24
## Hauteur (m) du bas de l'objet sans collision : le rebord du panier posé au sol, sur lequel le
## canard bute à l'entrée des poignées.
const COLLISION_BOTTOM_CUT := {"panier_linge": 0.2}
## Dessus remplacé par une boîte (épaisseur en m, depuis le point le plus haut) : le panier à linge
## (renversé) et le carton, sur lesquels on marche. La forme fidèle (simplifiée) ne garde que les
## parois en dessous, avec les trous par lesquels on entre ; la boîte, orientée comme l'objet,
## couvre le dessus : on y marche sans accrocher sur les arêtes des triangles.
const TOP_BOX := {"panier_linge": 0.8, "carton": 0.6}


## Parties de maillage retirées (rendu et collisions) : nom de l'objet -> boîte, dans l'espace
## du maillage, des triangles à enlever (ceux dont les 3 sommets sont dedans). Les trous laissés
## dans le reste du maillage sont bouchés. Tabouret : les 4 barres entre les pieds, pour passer
## dessous.
const REMOVED_PARTS := {
	"tabouret": [
		AABB(Vector3(-3.25, -8.8, -5.4), Vector3(6.8, 1.75, 0.7)),
		AABB(Vector3(-3.25, -8.8, 4.95), Vector3(6.8, 1.75, 0.45)),
		AABB(Vector3(-5.0, -8.8, -3.25), Vector3(0.35, 1.75, 6.85)),
		AABB(Vector3(4.9, -8.8, -3.25), Vector3(0.45, 1.75, 6.85)),
	],
}


func _post_import(scene: Node) -> Object:
	var counts := {}
	_add_collisions(scene, counts)
	print("arena GLB post-import: ", counts)
	return scene


func _add_collisions(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var parts: Array = REMOVED_PARTS.get(String(node.name).to_lower(), [])
		if not parts.is_empty():
			(node as MeshInstance3D).mesh = without_parts((node as MeshInstance3D).mesh, parts)
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
	for prefix: String in RAMPS:
		if name.begins_with(prefix):
			mi.create_convex_collision(true, false)
			var hull: ConvexPolygonShape3D = mi.find_children("*", "CollisionShape3D", true, false)[0].shape
			var points := hull.points
			var to_mesh := _scene_transform(mi).affine_inverse()
			for point: Vector3 in RAMPS[prefix]:
				points.append(to_mesh * point)
			hull.points = points
			return "coque + rampe"
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
		var target: int = CONCAVE_TRIANGLES
		for prefix: String in CONCAVE_DETAILED:
			if name.begins_with(prefix):
				target = CONCAVE_DETAILED[prefix]
		var faces := _simplified_faces(mi.mesh, target)
		for prefix: String in COLLISION_BOTTOM_CUT:
			if name.begins_with(prefix):
				faces = _without_bottom(faces, _scene_transform(mi), COLLISION_BOTTOM_CUT[prefix])
		if faces.is_empty():
			mi.create_trimesh_collision()
			return "trimesh"
		for prefix: String in TOP_BOX:
			if name.begins_with(prefix):
				return _walls_and_top_box(mi, faces, TOP_BOX[prefix])
		if _starts(name, MULTICONVEX_PREFIXES):
			var multi := _build_multiconvex(faces)
			if multi:
				mi.add_child(multi)
				_own_recursive(multi, mi.owner)
				return "coques multiples"
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


## Collision de `mi` : les triangles `faces` (espace du maillage) sous les `thickness` derniers
## mètres du haut (dans la scène), plus une boîte (orientée comme le maillage) englobant ceux du
## dessus.
static func _walls_and_top_box(mi: MeshInstance3D, faces: PackedVector3Array, thickness: float) -> String:
	var transform := _scene_transform(mi)
	var top := -INF
	for v in faces:
		top = maxf(top, (transform * v).y)
	var walls := PackedVector3Array()
	var top_box := AABB()
	var has_top := false
	for t in faces.size() / 3:
		var tri := faces.slice(t * 3, t * 3 + 3)
		var low := minf((transform * tri[0]).y, minf((transform * tri[1]).y, (transform * tri[2]).y))
		if low < top - thickness:
			walls.append_array(tri)
			continue
		for v in tri:
			top_box = top_box.expand(v) if has_top else AABB(v, Vector3.ZERO)
			has_top = true
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	mi.add_child(body)
	body.owner = mi.owner
	if not walls.is_empty():
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(walls)
		var shape := CollisionShape3D.new()
		shape.name = "Parois"
		shape.shape = concave
		body.add_child(shape)
		shape.owner = mi.owner
	if has_top:
		var box := BoxShape3D.new()
		box.size = top_box.size.max(Vector3.ONE * 0.05)
		var shape := CollisionShape3D.new()
		shape.name = "Dessus"
		shape.shape = box
		shape.position = top_box.get_center()
		body.add_child(shape)
		shape.owner = mi.owner
	return "parois + dessus"


## Décomposition convexe (VHACD) des triangles `faces` : StaticBody3D avec une ConvexPolygonShape3D
## par morceau, null si ça échoue.
static func _build_multiconvex(faces: PackedVector3Array) -> StaticBody3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var temp_mesh := ArrayMesh.new()
	temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var temp_mi := MeshInstance3D.new()
	temp_mi.mesh = temp_mesh
	var settings := MeshConvexDecompositionSettings.new()
	settings.max_convex_hulls = MULTICONVEX_MAX_HULLS
	temp_mi.create_multiple_convex_collisions(settings)
	var body: StaticBody3D = null
	for child in temp_mi.get_children():
		if child is StaticBody3D:
			body = child
			temp_mi.remove_child(child)
			break
	temp_mi.free()
	return body


## Donne `owner` à `node` et, récursivement, à tous ses enfants (nécessaire pour qu'ils soient
## sauvegardés avec la scène importée).
static func _own_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_own_recursive(child, owner)


## Triangles de `faces` sans ceux qui sont entièrement à moins de `height` m (dans la scène,
## `transform` place le maillage) du point le plus bas.
static func _without_bottom(faces: PackedVector3Array, transform: Transform3D, height: float) -> PackedVector3Array:
	var bottom := INF
	for v in faces:
		bottom = minf(bottom, (transform * v).y)
	var kept := PackedVector3Array()
	for t in faces.size() / 3:
		var tri := faces.slice(t * 3, t * 3 + 3)
		if (transform * tri[0]).y > bottom + height or (transform * tri[1]).y > bottom + height \
				or (transform * tri[2]).y > bottom + height:
			kept.append_array(tri)
	return kept


## Position, orientation et échelle de `node` dans la scène importée (pas encore dans l'arbre).
static func _scene_transform(node: Node) -> Transform3D:
	var transform := Transform3D.IDENTITY
	while node is Node3D:
		transform = (node as Node3D).transform * transform
		node = node.get_parent()
	return transform


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


## Copie de `mesh` sans les triangles dont les 3 sommets sont dans l'une des boîtes `parts`. Les
## trous laissés là où ces triangles touchaient le reste sont bouchés (éventail de triangles).
static func without_parts(mesh: Mesh, parts: Array) -> ArrayMesh:
	var result := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		var removed_edges := {}
		for t in indices.size() / 3:
			var tri := [indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]]
			var inside := false
			for box: AABB in parts:
				if box.has_point(vertices[tri[0]]) and box.has_point(vertices[tri[1]]) \
						and box.has_point(vertices[tri[2]]):
					inside = true
					break
			if not inside:
				kept.append_array(tri)
				continue
			for k in 3:
				removed_edges[_edge_key(vertices[tri[k]], vertices[tri[(k + 1) % 3]])] = true
		# Bords du trou : arêtes d'un triangle gardé partagées avec un triangle retiré. La bouche
		# parcourt chaque arête dans l'autre sens : next[fin] = début.
		var next := {}
		var index_of := {}
		for t in kept.size() / 3:
			for k in 3:
				var a := kept[t * 3 + k]
				var b := kept[t * 3 + (k + 1) % 3]
				if removed_edges.has(_edge_key(vertices[a], vertices[b])):
					next[vertices[b].snappedf(0.001)] = vertices[a].snappedf(0.001)
					index_of[vertices[a].snappedf(0.001)] = a
					index_of[vertices[b].snappedf(0.001)] = b
		while not next.is_empty():
			var loop: Array[Vector3] = []
			var p: Vector3 = next.keys()[0]
			while next.has(p):
				loop.append(p)
				var q: Vector3 = next[p]
				next.erase(p)
				p = q
			for i in range(1, loop.size() - 1):
				kept.append_array([index_of[loop[0]], index_of[loop[i]], index_of[loop[i + 1]]])
		arrays[Mesh.ARRAY_INDEX] = kept
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(s, mesh.surface_get_material(s))
		result.surface_set_name(s, mesh.surface_get_name(s))
	result.resource_name = mesh.resource_name
	return result


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var sa := str(a.snappedf(0.001))
	var sb := str(b.snappedf(0.001))
	return sa + sb if sa < sb else sb + sa


## Triangles du maillage simplifié à environ `target` triangles (répartis entre ses surfaces).
static func _simplified_faces(mesh: Mesh, target: int) -> PackedVector3Array:
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


static func _triangles(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		count += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count
