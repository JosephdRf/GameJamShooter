class_name WaterTunnel
extends Node3D
## Tunnel d'eau (le tuyau `pipe_path`, de la douche au bas du meuble) : en y entrant par un
## bout, le canard passe automatiquement en dash et parcourt le tuyau jusqu'à l'autre bout, la
## caméra collée juste derrière lui ; il reprend la main en sortant (cf. Player.enter_tunnel,
## _simulate_tunnel). Rien à placer à la main : au démarrage, ce nœud calcule tout seul l'axe du
## tuyau à partir de son maillage (cf. _build_curve), pose un repère d'entrée à chaque bout
## (zone + un peu de recul) et une mare d'eau (ruban bleu translucide) qui en tapisse le fond.

const GROUP := &"water_tunnels"
## Rayon (m) utilisé pour la mare d'eau et les zones d'entrée, un peu en dessous du rayon réel
## du tuyau (mesuré sur son maillage) pour rester bien dedans.
const RADIUS_MARGIN := 0.75
## Nombre de tranches le long du tuyau pour calculer son axe (cf. _build_curve).
const SLICES := 40
## Une tranche avec moins de sommets que cette fraction de la médiane est écartée : ce sont
## les bouchons aux deux bouts du tube, dont le centre tire l'axe hors de l'ouverture.
const SPARSE_SLICE := 0.5
## Les SMOOTH_PASSES lissages successifs (moyenne sur 3 tranches voisines) effacent le bruit
## dans les coudes serrés, sans trop couper les virages.
const SMOOTH_PASSES := 3
const WATER_COLOR := Color(0.55, 0.78, 0.92, 0.72)

@export var pipe_path: NodePath
## Distance (m) entre le bout du tuyau et la zone qui déclenche le dash (on sent qu'on y entre,
## au lieu de se téléporter dès qu'on frôle l'ouverture).
@export var trigger_margin := 0.6
## Vitesse (m/s) du canard dans le tunnel.
@export var dash_speed := 30.0
## Vitesse (m/s) à la sortie, dans l'axe du tuyau (la lancée continue un peu après).
@export var exit_speed := 10.0
## Distance (m) devant l'ouverture où la main est rendue : le canard sort du tuyau et
## continue tout droit jusque là avant de reprendre le contrôle normal (sinon il
## réapparaîtrait pile dans l'ouverture, ou pire, encore dans le mur).
@export var exit_margin := 2.5
## Distance (m) entre le canard et la caméra dans le tunnel, qui traîne derrière lui sur
## l'axe même du tuyau (cf. Player._simulate_tunnel) : elle reste ainsi toujours dedans,
## contrairement au bras à ressort habituel (pensé pour l'extérieur, bien plus large que
## le tuyau) qui en ressortirait.
@export var camera_trail := 2.0
## Abaissement (m) de la caméra sous l'axe du tuyau (0 : pile au centre).
@export var camera_drop := 0.0

var curve: Curve3D
var radius := 1.5
## Les deux bouts du tuyau : point, tangente qui pointe vers l'intérieur (cf. _at).
var ends: Array[Dictionary] = []

@onready var _pipe: MeshInstance3D = get_node(pipe_path)


func _ready() -> void:
	add_to_group(GROUP)
	curve = _build_curve(_pipe)
	radius = _measure_radius(_pipe)
	ends = [
		{"point": to_global(curve.get_point_position(0)), "tangent": global_transform.basis * _tangent_at(0.0)},
		{"point": to_global(curve.get_point_position(curve.point_count - 1)),
				"tangent": global_transform.basis * -_tangent_at(curve.get_baked_length())},
	]
	_add_triggers()
	_add_water()


## Point et tangente (normalisée, dans le sens de parcours vers l'avant), en repère monde,
## à la distance `offset` (m) depuis le début du tuyau (cf. ends[0]).
func sample(offset: float) -> Dictionary:
	offset = clampf(offset, 0.0, curve.get_baked_length())
	return {"point": to_global(curve.sample_baked(offset, true)), "tangent": global_transform.basis * _tangent_at(offset)}


func length() -> float:
	return curve.get_baked_length()


## Comme sample(), mais extrapolé en ligne droite (dans l'axe du bout le plus proche) au-delà
## des deux extrémités du tuyau, au lieu de s'y figer : pour la caméra qui traîne derrière le
## canard (cf. camera_trail) et peut donc se trouver avant l'entrée ou après la sortie, ou pour
## le canard lui-même, qui continue tout droit après la sortie (cf. Player._simulate_tunnel).
func sample_extrapolated(offset: float) -> Dictionary:
	var total := curve.get_baked_length()
	if offset < 0.0:
		var at_start := sample(0.0)
		return {"point": (at_start.point as Vector3) + (at_start.tangent as Vector3) * offset, "tangent": at_start.tangent}
	if offset > total:
		var at_end := sample(total)
		return {"point": (at_end.point as Vector3) + (at_end.tangent as Vector3) * (offset - total), "tangent": at_end.tangent}
	return sample(offset)


func _tangent_at(offset: float) -> Vector3:
	var total := curve.get_baked_length()
	var step := 0.2
	var a := curve.sample_baked(clampf(offset - step, 0.0, total), true)
	var b := curve.sample_baked(clampf(offset + step, 0.0, total), true)
	return (b - a).normalized()


## Zone (Area3D) à chaque bout, un peu en retrait de l'ouverture (trigger_margin) : on y entre
## en marchant dans le tuyau, pas en le frôlant de l'extérieur.
func _add_triggers() -> void:
	for i in ends.size():
		var end: Dictionary = ends[i]
		var point: Vector3 = end.point
		var tangent: Vector3 = end.tangent
		var area := Area3D.new()
		area.name = "Entree%d" % i
		area.collision_layer = 0
		area.collision_mask = Player.PLAYERS_LAYER
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius * 0.9
		shape.shape = sphere
		area.add_child(shape)
		add_child(area)
		area.global_position = point + tangent * trigger_margin
		area.body_entered.connect(_on_entered.bind(i))


func _on_entered(body: Node3D, end_index: int) -> void:
	var player := body as Player
	if player and player.is_alive() and not player.captured:
		player.enter_tunnel(self, end_index == 1)


## Mare d'eau : ruban qui suit le fond du tuyau (translucide, comme Eau_Baignoire).
func _add_water() -> void:
	var water_radius := maxf(radius - RADIUS_MARGIN, 0.4)
	var total := curve.get_baked_length()
	var steps := maxi(int(total / 0.8), 4)
	var positions: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for i in steps + 1:
		var offset := total * i / steps
		var point: Vector3 = curve.sample_baked(offset, true)
		var tangent := _tangent_at(offset)
		var side := tangent.cross(Vector3.UP)
		if side.length() < 0.05:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized() * water_radius
		# Le fond du tuyau est environ un rayon sous l'axe : l'eau y repose, au lieu de flotter
		# au centre.
		var bottom := point - Vector3.UP * (water_radius * 0.75)
		positions.append(to_local(bottom - side))
		uvs.append(Vector2(0, offset * 0.2))
		positions.append(to_local(bottom + side))
		uvs.append(Vector2(1, offset * 0.2))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# generate_normals() n'accepte qu'une liste de triangles : on y convertit la lanière
	# (2 triangles par segment, sens alterné comme une triangle-strip classique).
	for i in positions.size() - 2:
		var order := [i, i + 1, i + 2] if i % 2 == 0 else [i + 1, i, i + 2]
		for idx in order:
			st.set_uv(uvs[idx])
			st.add_vertex(positions[idx])
	st.generate_normals()
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = WATER_COLOR
	material.metallic = 0.3
	material.roughness = 0.05
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Rayon typique du tuyau : distance moyenne de ses sommets à l'axe (curve) le plus proche.
func _measure_radius(mesh_instance: MeshInstance3D) -> float:
	var xform := mesh_instance.global_transform
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var total := curve.get_baked_length()
	var sum := 0.0
	var count := 0
	for v in verts:
		var world := xform * v
		var closest := curve.get_closest_point(to_local(world))
		var d := world.distance_to(to_global(closest))
		if d < total: # Écarte les points aberrants (bout du tuyau mal lissé) plutôt que fausser la moyenne.
			sum += d
			count += 1
	return sum / maxf(count, 1)


## Axe du tuyau `mesh_instance`, en espace local à ce nœud : distance de chaque sommet au bout
## du tuyau le plus loin sur sa plus grande dimension, mesurée le long de la surface (plus court
## chemin sur le maillage), puis centre de chaque tranche de distance, lissé. Suit le tuyau même
## là où il tourne à angle droit (un découpage le long d'un axe fixe écraserait ces portions en
## un seul point, et le bout calculé tomberait au milieu du dernier coude).
func _build_curve(mesh_instance: MeshInstance3D) -> Curve3D:
	var xform := mesh_instance.global_transform
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Sommets fusionnés par position (le maillage les duplique pour ses normales et UV).
	var ids := {}
	var merged := PackedInt32Array()
	merged.resize(raw.size())
	var world := PackedVector3Array()
	for i in raw.size():
		var key := Vector3i((raw[i] * 1000.0).round())
		if not ids.has(key):
			ids[key] = world.size()
			world.append(xform * raw[i])
		merged[i] = ids[key]
	var neighbours: Array[Dictionary] = []
	for i in world.size():
		neighbours.append({})
	for t in range(0, indices.size(), 3):
		for e in 3:
			var a := merged[indices[t + e]]
			var b := merged[indices[t + (e + 1) % 3]]
			if a != b:
				neighbours[a][b] = true
				neighbours[b][a] = true
	# Départ : tous les sommets du bout le plus loin sur la plus grande dimension du tuyau.
	var size := (xform.basis * mesh_instance.mesh.get_aabb().size).abs()
	var axis := Vector3.RIGHT
	if size.z > size.x and size.z > size.y:
		axis = Vector3.BACK
	elif size.y > size.x and size.y > size.z:
		axis = Vector3.UP
	var far := -INF
	for p in world:
		far = maxf(far, p.dot(axis))
	var distance := PackedFloat32Array()
	distance.resize(world.size())
	distance.fill(INF)
	var heap: Array[Vector2] = []
	for i in world.size():
		if world[i].dot(axis) > far - 0.3:
			distance[i] = 0.0
			_heap_push(heap, Vector2(0.0, i))
	while not heap.is_empty():
		var top := _heap_pop(heap)
		var i := int(top.y)
		if top.x > distance[i]:
			continue
		for j: int in neighbours[i]:
			var d := top.x + world[i].distance_to(world[j])
			if d < distance[j]:
				distance[j] = d
				_heap_push(heap, Vector2(d, j))
	var longest := 0.0
	for d in distance:
		if d < INF:
			longest = maxf(longest, d)
	var sum: Array[Vector3] = []
	var count: Array[int] = []
	for i in SLICES:
		sum.append(Vector3.ZERO)
		count.append(0)
	for i in world.size():
		if distance[i] < INF:
			var b := mini(int(distance[i] / longest * SLICES), SLICES - 1)
			sum[b] += world[i]
			count[b] += 1
	var sorted := count.duplicate()
	sorted.sort()
	var median: int = sorted[SLICES / 2]
	var points := PackedVector3Array()
	for i in SLICES:
		if count[i] >= median * SPARSE_SLICE:
			points.append(sum[i] / count[i])
	for _pass in SMOOTH_PASSES:
		var smoothed := PackedVector3Array()
		smoothed.append(points[0])
		for i in range(1, points.size() - 1):
			smoothed.append((points[i - 1] + points[i] + points[i + 1]) / 3.0)
		smoothed.append(points[points.size() - 1])
		points = smoothed
	var curve3d := Curve3D.new()
	for p in points:
		curve3d.add_point(to_local(p))
	return curve3d


## Tas binaire (distance, sommet) pour le plus court chemin de _build_curve.
func _heap_push(heap: Array[Vector2], item: Vector2) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent].x <= heap[i].x:
			break
		var swap := heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


func _heap_pop(heap: Array[Vector2]) -> Vector2:
	var top := heap[0]
	var last: Vector2 = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var smallest := i
		for child in [2 * i + 1, 2 * i + 2]:
			if child < heap.size() and heap[child].x < heap[smallest].x:
				smallest = child
		if smallest == i:
			break
		var swap := heap[smallest]
		heap[smallest] = heap[i]
		heap[i] = swap
		i = smallest
	return top
