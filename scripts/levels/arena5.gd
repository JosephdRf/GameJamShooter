@tool
extends Node3D

## Inherited map root (scene_v*.glb). Ensures every mesh has a StaticBody collider
## in the editor and at runtime so the scene stays editable while playable.

const SKIP := ["eau", "socle_seche_cheveux"] # Le tuyau du tunnel d'eau : cf. WaterTunnel.
## Eau profonde (exceptions à SKIP) : on y entre, enfoncé de WATER_SINK m (sa collision est sous
## la surface visible : on ne tombe pas au fond), on y marche et on en sort d'un grand saut
## (Player.DEEP_WATER_GROUP, water_jump_velocity). La baignoire ici ; les toilettes
## (Eau_Toilettes, dans arena5.tscn) ont la même chose.
const SOLID_WATER := ["eau_baignoire"]
const WATER_SINK := 0.5
## Même rendu que les flaques au sol (cf. Puddles.water_color) : bleu vif, brillant, ridé.
const WATER_COLOR := Color(0.25, 0.66, 1.0, 0.8)
## Rattrapage (collision manquante : import fait avant tools/arena_glb_post_import.gd, que Godot
## ne refait pas tout seul quand seul le script change) : forme exacte seulement pour la
## structure et les objets simples, sinon une coque convexe. La forme exacte d'un objet détaillé
## (toilettes, tongs, serviettes : des dizaines de milliers de triangles) fait ramer le jeu.
const EXACT_PREFIXES := ["sol", "murs", "plafond", "marche", "eau_baignoire"]
const EXACT_MAX_TRIANGLES := 150


func _ready() -> void:
	_place_copies()
	_ensure_colliders(self)
	_setup_deep_water()


## Eau profonde : collision enfoncée de WATER_SINK m, groupe DEEP_WATER_GROUP, rendu des flaques.
func _setup_deep_water() -> void:
	if Engine.is_editor_hint():
		return # Pas dans l'éditeur : la scène enregistrerait l'eau déjà enfoncée.
	var material := _water_material()
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).to_lower() in SOLID_WATER:
			mi.material_override = material
			for body in mi.get_children():
				if body is StaticBody3D and not body.is_in_group(Player.DEEP_WATER_GROUP):
					body.add_to_group(Player.DEEP_WATER_GROUP)
					body.global_position.y -= WATER_SINK
	var toilets := get_node_or_null(^"Eau_Toilettes") as StaticBody3D
	if toilets and not toilets.is_in_group(Player.DEEP_WATER_GROUP):
		toilets.add_to_group(Player.DEEP_WATER_GROUP)
		(toilets.get_node(^"Surface") as MeshInstance3D).material_override = material
		(toilets.get_node(^"Forme") as Node3D).position.y -= WATER_SINK


func _water_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = WATER_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.04
	material.metallic_specular = 0.8
	var ripples := NoiseTexture2D.new()
	ripples.seamless = true
	ripples.as_normal_map = true
	ripples.bump_strength = 3.0
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	ripples.noise = noise
	material.normal_enabled = true
	material.normal_texture = ripples
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.15
	return material


## Copies d'objets de la carte : chaque repère (Marker3D) qui a la métadonnée `copie_de` reçoit
## une copie de l'objet de ce nom (maillage et collision), à sa place. Évite d'enregistrer le
## maillage et ses textures dans la scène (une étagère copiée dans l'éditeur pesait 134 Mo).
func _place_copies() -> void:
	for marker: Node in find_children("*", "Marker3D", true, false):
		if not marker.has_meta(&"copie_de") or marker.get_child_count() > 0:
			continue
		var source := find_child(String(marker.get_meta(&"copie_de")), true, false) as Node3D
		if source == null:
			continue
		var copy := source.duplicate() as Node3D
		copy.transform = Transform3D.IDENTITY
		marker.add_child(copy)


func _ensure_colliders(node: Node) -> void:
	# Ajouts à la carte qui gèrent eux-mêmes leurs collisions : souffle d'un sèche-cheveux
	# (traversable), eau des toilettes (déjà solide), tunnel d'eau (traversé par dash, sans
	# collision : son ruban d'eau ne doit pas en recevoir une).
	if node is HairDryer or node is StaticBody3D or node is WaterTunnel:
		return
	if node is MeshInstance3D:
		_ensure_mesh_collider(node as MeshInstance3D)
	for child in node.get_children():
		_ensure_colliders(child)


func _should_skip(mi: MeshInstance3D) -> bool:
	var n := String(mi.name).to_lower()
	if n in SOLID_WATER:
		return false
	for key in SKIP:
		if n.begins_with(key): # prefix match: "Bateau_*" keeps its colliders
			return true
	return false


func _has_valid_collider(mi: MeshInstance3D) -> bool:
	for child in mi.get_children():
		if child is StaticBody3D:
			for shape_node in child.get_children():
				if shape_node is CollisionShape3D and (shape_node as CollisionShape3D).shape != null:
					return true
	return false


func _clear_static_bodies(mi: MeshInstance3D) -> void:
	var to_free: Array[Node] = []
	for child in mi.get_children():
		if child is StaticBody3D:
			to_free.append(child)
	for child in to_free:
		mi.remove_child(child)
		child.free()


func _collide_both_sides(mi: MeshInstance3D) -> void:
	for child in mi.get_children():
		if child is StaticBody3D:
			for shape_node in child.get_children():
				var shape := (shape_node as CollisionShape3D).shape as ConcavePolygonShape3D
				if shape:
					shape.backface_collision = true


## Vrai si `mi` peut garder sa forme exacte (cf. EXACT_PREFIXES).
func _is_exact(mi: MeshInstance3D) -> bool:
	var name := String(mi.name).to_lower()
	for prefix: String in EXACT_PREFIXES:
		if name.begins_with(prefix):
			return true
	var triangles := 0
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		triangles += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return triangles <= EXACT_MAX_TRIANGLES


func _ensure_mesh_collider(mi: MeshInstance3D) -> void:
	# sans_collision : choisi à l'import (eau, petits objets), cf. tools/arena_glb_post_import.gd.
	# L'eau de SOLID_WATER reste solide malgré tout.
	var solid_water := String(mi.name).to_lower() in SOLID_WATER
	if mi.mesh == null or _should_skip(mi) or (mi.has_meta(&"sans_collision") and not solid_water):
		return
	if _has_valid_collider(mi):
		return

	_clear_static_bodies(mi)
	if _is_exact(mi):
		mi.create_trimesh_collision()
		if _has_valid_collider(mi):
			if String(mi.name).to_lower() in SOLID_WATER:
				_collide_both_sides(mi) # Plan d'eau sans épaisseur : solide quelle que soit sa face.
			return
		_clear_static_bodies(mi)

	mi.create_convex_collision(true, true)
	if _has_valid_collider(mi):
		return

	# Last resort: AABB box collider so nothing is walk-through.
	_clear_static_bodies(mi)
	var aabb := mi.mesh.get_aabb()
	if aabb.size.length() <= 0.0001:
		return
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = aabb.size.abs()
	col.shape = box
	col.position = aabb.get_center()
	body.add_child(col)
	mi.add_child(body)
	if Engine.is_editor_hint():
		body.owner = get_tree().edited_scene_root
		col.owner = get_tree().edited_scene_root
