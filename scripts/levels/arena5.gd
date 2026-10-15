@tool
extends Node3D

## Inherited map root (scene_v*.glb). Ensures every mesh has a StaticBody collider
## in the editor and at runtime so the scene stays editable while playable.

const SKIP := ["eau"]


func _ready() -> void:
	_ensure_colliders(self)


func _ensure_colliders(node: Node) -> void:
	if node is MeshInstance3D:
		_ensure_mesh_collider(node as MeshInstance3D)
	for child in node.get_children():
		_ensure_colliders(child)


func _should_skip(mi: MeshInstance3D) -> bool:
	var n := String(mi.name).to_lower()
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


func _ensure_mesh_collider(mi: MeshInstance3D) -> void:
	# sans_collision : choisi à l'import (eau, petits objets), cf. tools/arena_glb_post_import.gd.
	if mi.mesh == null or _should_skip(mi) or mi.has_meta(&"sans_collision"):
		return
	if _has_valid_collider(mi):
		return

	_clear_static_bodies(mi)
	mi.create_trimesh_collision()
	if _has_valid_collider(mi):
		return

	_clear_static_bodies(mi)
	mi.create_convex_collision(true, false)
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
