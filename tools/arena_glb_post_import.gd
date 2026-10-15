@tool
extends EditorScenePostImport

## Adds a StaticBody collider to every MeshInstance3D in the arena GLB.
## Tries trimesh first, then convex if trimesh fails / is empty.
## Only skips water (names starting with "Eau") so players can still walk through it.
## Prefix match: "Bateau_*" must keep its colliders.

const SKIP := ["eau"]


func _post_import(scene: Node) -> Object:
	var added := _add_collisions(scene)
	print("arena GLB post-import: colliders on %d meshes" % added)
	return scene


func _should_skip(node: Node) -> bool:
	var n := String(node.name).to_lower()
	for key in SKIP:
		if n.begins_with(key):
			return true
	return false


func _has_static_body(mi: MeshInstance3D) -> bool:
	for child in mi.get_children():
		if child is StaticBody3D:
			return true
	return false


func _body_has_shape(mi: MeshInstance3D) -> bool:
	for child in mi.get_children():
		if child is StaticBody3D:
			for shape_node in child.get_children():
				if shape_node is CollisionShape3D and (shape_node as CollisionShape3D).shape != null:
					return true
	return false


func _add_collisions(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and not _should_skip(mi):
			if not _has_static_body(mi):
				mi.create_trimesh_collision()
			if not _body_has_shape(mi):
				# Clear empty bodies then try convex.
				for child in mi.get_children():
					if child is StaticBody3D:
						mi.remove_child(child)
						child.free()
				mi.create_convex_collision(true, false)
			if _body_has_shape(mi):
				count += 1
			else:
				push_warning("No collider generated for mesh: %s" % mi.name)
	for child in node.get_children():
		count += _add_collisions(child)
	return count
