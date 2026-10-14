class_name Puddles
extends Node3D
## Flaques d'eau laissées par les bulles qui éclatent sur le sol (prototype).
##
## Chaque éclatement ajoute une « tache » d'humidité douce (add_puddle) dans une carte vue
## du dessus ; l'eau s'affiche là où l'humidité dépasse `threshold`. Deux taches proches
## se recouvrent : leurs humidités s'additionnent et comblent l'espace entre elles, elles
## forment une seule grande flaque. Tirer plusieurs fois au même endroit agrandit la flaque.
## Contours irréguliers : le rayon de chaque tache est déformé par un bruit (FastNoiseLite)
## qui ne dépend que de la position dans le monde, donc identique sur tous les ordinateurs.
##
## Affichage : la carte est découpée en carreaux de CHUNK_SIZE m, chacun projeté sur le
## décor par un Decal. Un carreau par « étage » de LAYER_HEIGHT m : il ne colore que les
## surfaces proches de cette hauteur (une flaque sur une étagère ne déborde pas sur le sol
## en dessous). Un éclatement ne met à jour que les carreaux qu'il touche.
## Peinture étalée sur plusieurs images (au plus `paint_budget_ms` ms par image) : une
## grosse flaque apparaît en quelques images au lieu de faire saccader le jeu.
## Les canards (calque visuel DUCK_VISUAL_LAYER) ne sont pas mouillés par les Decals.
##
## Rendu : autour de l'eau, un halo de sol mouillé (plus sombre, mat) ; l'eau elle-même est
## brillante (reflets de la lumière), bleu clair au bord et plus sombre là où elle est profonde, avec de petites rides (normal map partagée,
## sans raccord d'un carreau à l'autre). Chaque éclatement fait des ronds dans l'eau et
## quelques gouttes (_play_splash). Les canards font aussi réagir l'eau : un rond à chaque pas
## (step_splash) et un sillage quand ils glissent dessus (wake), cf. Player.
##
## Les joueurs savent s'ils marchent dans l'eau avec is_wet() (groupe GROUP).
##
## Réseau : rien n'est envoyé. Chaque ordinateur fait éclater sa copie de la bulle au même
## endroit (même tir, décor fixe), donc les flaques sont les mêmes partout.

## Côté d'un carreau (m) et hauteur d'un étage (m).
const CHUNK_SIZE := 8.0
const LAYER_HEIGHT := 0.5
## Calque visuel des canards (cf. Player._apply_color) et des éclaboussures, exclu des Decals :
## l'eau ne les colore pas.
const DUCK_VISUAL_LAYER := 2
## Groupe du nœud des flaques (un par partie), pour que les joueurs le trouvent.
const GROUP := &"puddles"
## Canon à eau : un rond dans l'eau toutes les DRIP_RING_EVERY gouttes (cf. drip).
const DRIP_RING_EVERY := 3

## Résolution de la carte d'humidité (pixels par mètre). Le coût d'une flaque est
## proportionnel à son carré.
@export var pixels_per_meter := 12
## Temps de peinture maximal par image (ms) ; le reste attend l'image suivante.
@export var paint_budget_ms := 2.0
## Humidité à partir de laquelle il y a de l'eau (une tache vaut 1 en son centre).
@export var threshold := 0.5
@export_group("Rendu")
## Couleur de l'eau peu profonde (bord) ; l'alpha règle sa transparence.
@export var water_color := Color(0.25, 0.55, 0.72, 0.6)
## Couleur de l'eau profonde (beaucoup d'humidité) et son opacité.
@export var deep_color := Color(0.04, 0.25, 0.4)
@export var deep_alpha := 0.85
## Bord de la flaque, un peu plus sombre (largeur en humidité au-dessus du seuil).
@export var rim_width := 0.1
## Halo de sol mouillé autour de l'eau : couleur (alpha = intensité) et largeur (en
## humidité sous le seuil).
@export var damp_color := Color(0.22, 0.2, 0.18, 0.35)
@export var damp_width := 0.22
## Rugosité (0 = miroir) de l'eau et du sol mouillé.
@export var water_roughness := 0.04
@export var damp_roughness := 0.5
## Relief des petites rides de l'eau (0 = eau parfaitement plate).
@export var ripple_strength := 6.0
@export_group("Éclaboussure")
## Ronds dans l'eau et gouttes : éclatements, pas et glissades des canards.
@export var splash_effects := true
## Durée des ronds dans l'eau (s) et nombre de gouttes.
@export var splash_duration := 0.7
@export var splash_drops := 14
@export_group("")
## Humidité maximale (une flaque très arrosée n'est pas infinie).
@export var max_wetness := 3.0
## Irrégularité des contours : le rayon d'une tache varie de ± cette fraction (0 = ronds).
@export var shape_noise := 0.45
## Taille des « lobes » du contour (m) : plus petit = contour plus découpé.
@export var shape_noise_scale := 0.9

var _noise := FastNoiseLite.new()
## Partagés par tous les carreaux et éclaboussures : rides de l'eau (normal map), rond dans
## l'eau (surface plate posée au-dessus de l'eau : un Decal serait masqué par celui de la
## flaque) et goutte.
var _ripples: ImageTexture
var _ring_mesh: QuadMesh
var _drop_mesh: SphereMesh
## Gouttes du canon à eau reçues (cf. drip) : seule une sur DRIP_RING_EVERY fait un rond.
var _drips := 0

## Carreau (Vector3i(x, étage, z)) -> { wet: PackedFloat32Array, albedo: Image,
## orm: Image, decal: Decal, dirty: bool }.
var _chunks := {}
## Taches à peindre, dans l'ordre : une par carreau touché, peinte ligne par ligne
## (cf. _make_job, _paint_rows).
var _jobs: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(GROUP)
	_noise.seed = 7 # Fixe : mêmes contours sur tous les ordinateurs.
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0 / shape_noise_scale
	_noise.fractal_octaves = 2
	_ripples = _make_ripples()
	_ring_mesh = _make_ring_mesh()
	_drop_mesh = _make_drop_mesh()


## Vrai s'il y a de l'eau en `point` (à la surface du sol) : humidité au-dessus du seuil.
func is_wet(point: Vector3) -> bool:
	var key := Vector3i(floori(point.x / CHUNK_SIZE), roundi(point.y / LAYER_HEIGHT), floori(point.z / CHUNK_SIZE))
	if not _chunks.has(key):
		return false
	var size := _chunk_pixels()
	var local := (Vector2(point.x, point.z) - Vector2(key.x, key.z) * CHUNK_SIZE) * pixels_per_meter
	var i := clampi(int(local.y), 0, size - 1) * size + clampi(int(local.x), 0, size - 1)
	return (_chunks[key].wet as PackedFloat32Array)[i] > threshold


## Ajoute une tache d'eau de rayon `radius` (m) centrée sur `point` (surface du sol), avec
## une éclaboussure (ronds et gouttes) si `splash`.
func add_puddle(point: Vector3, radius: float, amount := 1.0, splash := true) -> void:
	if splash and splash_effects:
		_play_splash(point, radius)
	var layer := roundi(point.y / LAYER_HEIGHT)
	var reach := radius * (1.0 + shape_noise) # Place pour les lobes les plus grands.
	var min_chunk := Vector2i(floori((point.x - reach) / CHUNK_SIZE), floori((point.z - reach) / CHUNK_SIZE))
	var max_chunk := Vector2i(floori((point.x + reach) / CHUNK_SIZE), floori((point.z + reach) / CHUNK_SIZE))
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cz in range(min_chunk.y, max_chunk.y + 1):
			_jobs.append(_make_job(_get_chunk(Vector3i(cx, layer, cz)), Vector2(cx, cz) * CHUNK_SIZE,
					point, radius, amount))


func _process(_delta: float) -> void:
	var deadline := Time.get_ticks_usec() + int(paint_budget_ms * 1000.0)
	while not _jobs.is_empty() and Time.get_ticks_usec() < deadline:
		if _paint_rows(_jobs[0], deadline):
			_jobs.pop_front()
	for chunk: Dictionary in _chunks.values():
		if chunk.dirty:
			chunk.dirty = false
			# Nouvelles textures à chaque changement : Godot recopie les textures des Decals
			# dans un atlas commun, mis à jour seulement quand une texture de Decal est ajoutée
			# ou retirée. Un simple ImageTexture.update() n'apparaîtrait qu'au prochain ajout
			# (flaques en retard, voire jamais affichées).
			chunk.decal.texture_albedo = ImageTexture.create_from_image(chunk.albedo)
			chunk.decal.texture_orm = ImageTexture.create_from_image(chunk.orm)


## Tache à peindre dans le carreau dont le coin (x, z) minimal est `origin` (m).
func _make_job(chunk: Dictionary, origin: Vector2, point: Vector3, radius: float, amount: float) -> Dictionary:
	var size := _chunk_pixels()
	var center := (Vector2(point.x, point.z) - origin) * pixels_per_meter
	var r := radius * pixels_per_meter
	var reach := r * (1.0 + shape_noise)
	return {
		"chunk": chunk, "origin": origin, "center": center, "r": r, "reach": reach, "amount": amount,
		"row": maxi(floori(center.y - reach), 0), "last_row": mini(ceili(center.y + reach), size - 1),
		"first_col": maxi(floori(center.x - reach), 0), "last_col": mini(ceili(center.x + reach), size - 1),
	}


## Peint les lignes suivantes de la tache `job` jusqu'à `deadline` (µs). Vrai quand elle est finie.
func _paint_rows(job: Dictionary, deadline: int) -> bool:
	var chunk: Dictionary = job.chunk
	var size := _chunk_pixels()
	var origin: Vector2 = job.origin
	var center: Vector2 = job.center
	var r: float = job.r
	var reach2: float = job.reach * job.reach
	var amount: float = job.amount
	var dry := threshold - damp_width # En dessous, le pixel reste transparent (cf. _shade).
	var wet: PackedFloat32Array = chunk.wet
	while job.row <= job.last_row and Time.get_ticks_usec() < deadline:
		var py: int = job.row
		job.row += 1
		for px in range(job.first_col, job.last_col + 1):
			var pixel := Vector2(px + 0.5, py + 0.5)
			var dist2 := (pixel - center).length_squared()
			if dist2 >= reach2:
				continue # Hors de portée même du plus grand lobe : pas besoin du bruit.
			var world := origin + pixel / pixels_per_meter
			# Rayon déformé selon l'endroit : contour en lobes, pas en cercle.
			var local_r := r * (1.0 + shape_noise * _noise.get_noise_2d(world.x, world.y))
			var d2 := dist2 / (local_r * local_r)
			if d2 >= 1.0:
				continue
			var i := py * size + px
			# Tache douce (1 au centre, 0 au bord) : deux taches proches se rejoignent.
			wet[i] = minf(wet[i] + amount * (1.0 - d2) * (1.0 - d2), max_wetness)
			if wet[i] > dry:
				_shade(chunk, px, py, wet[i])
	chunk.wet = wet
	chunk.dirty = true
	return job.row > job.last_row


## Couleur d'un pixel selon son humidité : halo de sol mouillé juste sous le seuil, puis
## eau de plus en plus profonde (plus sombre, plus opaque) au-dessus.
func _shade(chunk: Dictionary, px: int, py: int, wetness: float) -> void:
	var damp := smoothstep(threshold - damp_width, threshold - 0.04, wetness)
	var water := smoothstep(threshold - 0.04, threshold + 0.04, wetness)
	var depth := smoothstep(threshold, threshold + 1.2, wetness)
	var rim := (1.0 - smoothstep(threshold, threshold + rim_width, wetness)) * water
	var water_rgb := water_color.lerp(deep_color, depth).darkened(rim * 0.3)
	var water_alpha := minf(lerpf(water_color.a, deep_alpha, depth) + rim * 0.15, 1.0)
	var color := Color(damp_color, damp * damp_color.a).lerp(Color(water_rgb, water_alpha), water)
	(chunk.albedo as Image).set_pixel(px, py, color)
	var roughness := lerpf(damp_roughness, water_roughness, water)
	(chunk.orm as Image).set_pixel(px, py, Color(1.0, roughness, 0.0, maxf(damp, water)))


func _get_chunk(key: Vector3i) -> Dictionary:
	if _chunks.has(key):
		return _chunks[key]
	var size := _chunk_pixels()
	var wet := PackedFloat32Array()
	wet.resize(size * size)
	var albedo := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var decal := Decal.new()
	decal.size = Vector3(CHUNK_SIZE, LAYER_HEIGHT, CHUNK_SIZE)
	decal.position = Vector3((key.x + 0.5) * CHUNK_SIZE, key.y * LAYER_HEIGHT, (key.z + 0.5) * CHUNK_SIZE)
	decal.texture_albedo = ImageTexture.create_from_image(albedo)
	decal.texture_orm = ImageTexture.create_from_image(orm)
	decal.texture_normal = _ripples
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	decal.normal_fade = 0.6 # Pas sur les côtés verticaux (marches, rebords).
	decal.cull_mask = ~DUCK_VISUAL_LAYER & 0xFFFFF
	add_child(decal)
	var chunk := {"wet": wet, "albedo": albedo, "orm": orm, "decal": decal, "dirty": false}
	_chunks[key] = chunk
	return chunk


func _chunk_pixels() -> int:
	return roundi(CHUNK_SIZE * pixels_per_meter)


## Éclatement d'une bulle : deux ronds qui s'élargissent dans l'eau et des gouttes qui retombent.
func _play_splash(point: Vector3, radius: float) -> void:
	_spawn_ring(point, radius * 1.1, 0.0, splash_duration)
	_spawn_ring(point, radius * 0.7, 0.12, splash_duration)
	_spawn_drops(point, splash_drops, Vector3.UP, 35.0, 2.5, 4.5, 0.15)


## Goutte du canon à eau qui touche `point` (surface de normale `normal`) : de temps en temps,
## un petit rond discret au sol, ou quelques gouttelettes qui rejaillissent ailleurs.
func drip(point: Vector3, normal := Vector3.UP) -> void:
	_drips += 1
	if not splash_effects or _drips % DRIP_RING_EVERY != 0:
		return
	if normal.y > 0.7:
		_spawn_ring(point, 0.5, 0.0, 0.35, 0.3)
	else:
		_spawn_drops(point - Vector3.UP * 0.05, 3, (normal + Vector3.UP * 0.5).normalized(), 50.0, 1.0, 2.5, 0.05, 0.6)


## Pas d'un canard dans l'eau (`point` sous son pied) : petit rond et quelques gouttes.
func step_splash(point: Vector3) -> void:
	if splash_effects:
		_spawn_ring(point, 0.9, 0.0, 0.5, 0.65)
		_spawn_drops(point, 5, Vector3.UP, 30.0, 1.0, 2.0, 0.08, 0.7)


## Sillage d'un canard qui glisse sur l'eau, à appeler régulièrement pendant la glissade :
## rond sous ses pieds et gerbes projetées sur les côtés et vers l'arrière de `velocity`.
func wake(point: Vector3, velocity: Vector3) -> void:
	if not splash_effects:
		return
	var back := Vector3(-velocity.x, 0.0, -velocity.z).normalized()
	_spawn_ring(point, 1.1, 0.0, 0.6, 0.45)
	_spawn_drops(point, 6, (back + Vector3.UP * 1.3).normalized(), 60.0, 2.0, 3.5, 0.15, 0.8)


## Rond qui apparaît après `delay` s, s'élargit jusqu'à `size` m en `duration` s et s'efface.
## `opacity` : 1 = aussi marqué que l'éclatement d'une bulle.
func _spawn_ring(point: Vector3, size: float, delay: float, duration: float, opacity := 1.0) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.layers = DUCK_VISUAL_LAYER # Sinon la flaque (Decal) le peindrait couleur d'eau.
	ring.position = point + Vector3.UP * 0.02
	ring.scale = Vector3.ONE * 0.1
	ring.transparency = 1.0
	add_child(ring)
	var tween := ring.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(ring, ^"transparency", 1.0 - opacity, 0.05)
	tween.parallel().tween_property(ring, ^"scale", Vector3.ONE * size, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(ring, ^"transparency", 1.0, duration - 0.05).set_delay(0.05)
	tween.tween_callback(ring.queue_free)


## Gerbe de `amount` gouttes lancées dans `direction` (± `spread` degrés), entre `min_speed` et
## `max_speed` m/s, depuis une sphère de rayon `radius` ; `size` : taille des gouttes.
func _spawn_drops(point: Vector3, amount: int, direction: Vector3, spread: float, min_speed: float,
		max_speed: float, radius: float, size := 1.0) -> void:
	var drops := CPUParticles3D.new()
	drops.mesh = _drop_mesh
	drops.amount = amount
	drops.lifetime = 0.55
	drops.one_shot = true
	drops.explosiveness = 0.9
	drops.direction = direction
	drops.spread = spread
	drops.initial_velocity_min = min_speed
	drops.initial_velocity_max = max_speed
	drops.gravity = Vector3(0, -14, 0)
	drops.scale_amount_min = 0.6 * size
	drops.scale_amount_max = 1.3 * size
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	drops.emission_sphere_radius = radius
	drops.position = point + Vector3.UP * 0.05
	drops.layers = DUCK_VISUAL_LAYER
	add_child(drops)
	drops.emitting = true
	drops.finished.connect(drops.queue_free)


## Petites rides de l'eau : bruit sans raccord (il se répète d'un carreau à l'autre) converti en
## normal map.
func _make_ripples() -> ImageTexture:
	var ripples := FastNoiseLite.new()
	ripples.seed = 11
	ripples.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ripples.frequency = 0.045
	ripples.fractal_octaves = 3
	var image := ripples.get_seamless_image(256, 256)
	image.convert(Image.FORMAT_RGBA8)
	image.bump_map_to_normal_map(ripple_strength)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Rond dans l'eau : surface plate de 1 m (agrandie par l'éclaboussure) portant un anneau
## clair et flou, transparent ailleurs.
func _make_ring_mesh() -> QuadMesh:
	var size := 128
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var r := (Vector2(x + 0.5, y + 0.5) / size * 2.0 - Vector2.ONE).length()
			var alpha := exp(-pow((r - 0.8) / 0.11, 2.0))
			# Blanc partout (seul l'alpha varie) : pas de liseré sombre une fois l'image réduite.
			image.set_pixel(x, y, Color(0.92, 0.97, 1.0, alpha))
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := QuadMesh.new()
	mesh.orientation = PlaneMesh.FACE_Y
	mesh.size = Vector2.ONE
	mesh.material = material
	return mesh


## Goutte : petite sphère d'eau claire, un peu transparente.
func _make_drop_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.88, 1.0, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.05
	material.metallic_specular = 1.0
	mesh.material = material
	return mesh
