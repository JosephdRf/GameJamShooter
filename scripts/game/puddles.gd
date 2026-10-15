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
## en dessous). Un éclatement ne met à jour que les carreaux qu'il touche. Sur une pente,
## chaque pixel de la tache va dans l'étage de sa propre hauteur (celle du plan de la pente
## touchée) : la flaque couvre la pente, au lieu d'une bande horizontale de LAYER_HEIGHT m.
## Peinture étalée sur plusieurs images (au plus `paint_budget_ms` ms par image) : une
## grosse flaque ne fait pas saccader le jeu. Elle est peinte par anneaux, du centre vers
## les bords, et s'étale en `spread_time` s (sous l'éclaboussure, qui masque cette croissance).
## Les canards (calque visuel DUCK_VISUAL_LAYER) ne sont pas mouillés par les Decals.
##
## Rendu : autour de l'eau, un halo de sol mouillé (plus sombre, mat) ; l'eau elle-même est
## brillante (reflets de la lumière), d'une seule teinte (plus d'eau au même endroit ne la fonce
## pas ; seul son bord est un peu plus sombre), avec de petites rides (normal map partagée,
## sans raccord d'un carreau à l'autre). Chaque éclatement fait des ronds dans l'eau et
## quelques gouttes (_play_splash). Les canards font aussi réagir l'eau : un rond à chaque pas
## (step_splash) et un sillage quand ils glissent dessus (wake), cf. Player. Ronds et gouttes
## suivent la surface touchée (`normal`) : posés à plat sur une pente, gouttes projetées
## perpendiculairement à elle (sinon, sur une pente, l'éclaboussure ressemblait à un rebond).
##
## Évaporation : chaque pixel retient l'instant de son dernier arrosage ; `water_lifetime` s
## plus tard il sèche, après avoir pâli pendant les `fade_duration` dernières secondes.
## Réarroser une flaque la rafraîchit. Le temps compté est celui de la partie (figé en pause).
## Passe d'évaporation toutes les EVAPORATION_STEP s, sur les seuls pixels mouillés, dans le
## même budget de temps par image que la peinture.
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
## Intervalle (s) entre deux passes d'évaporation (pâlissement par paliers de cette durée).
const EVAPORATION_STEP := 0.2
## Canon à eau : un rond dans l'eau toutes les DRIP_RING_EVERY gouttes (cf. drip).
const DRIP_RING_EVERY := 3

## Résolution de la carte d'humidité (pixels par mètre). Le coût d'une flaque est
## proportionnel à son carré.
@export var pixels_per_meter := 12
## Temps de peinture maximal par image (ms) ; le reste attend l'image suivante.
@export var paint_budget_ms := 3.0
## Durée (s) pendant laquelle une flaque s'étale, du centre jusqu'à ses bords.
@export var spread_time := 0.3
## Humidité à partir de laquelle il y a de l'eau (une tache vaut 1 en son centre).
@export var threshold := 0.5
@export_group("Rendu")
## Couleur de l'eau (une seule teinte, quelle que soit la quantité) ; l'alpha règle sa transparence.
@export var water_color := Color(0.25, 0.55, 0.72, 0.6)
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
@export_group("Évaporation")
## Temps (s) après le dernier arrosage au bout duquel l'eau a disparu.
@export var water_lifetime := 63.0
## Pendant ses dernières secondes (s), l'eau pâlit jusqu'à disparaître.
@export var fade_duration := 3.0
## Couleur vers laquelle l'eau pâlit (de plus en plus claire avant de disparaître).
@export var fade_color := Color(0.85, 0.92, 0.96)
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
## Éclaboussure sur un canard touché : coque d'eau qui gonfle et s'efface (cf. duck_splash).
var _burst_mesh: SphereMesh
## Gouttes du canon à eau reçues (cf. drip) : seule une sur DRIP_RING_EVERY fait un rond.
var _drips := 0

## Carreau (Vector3i(x, étage, z)) -> { wet: PackedFloat32Array, albedo: Image,
## orm: Image, decal: Decal, dirty: bool, stamp: PackedFloat32Array (instant du dernier
## arrosage + 1 par pixel, 0 = sec), wet_pixels: PackedInt32Array (pixels mouillés),
## oldest: float (plus vieux stamp), evaporating: bool }.
var _chunks := {}
## Taches en train de s'étaler : { parts (une par carreau touché, cf. _make_job), done (rayon
## déjà peint, px), reach (rayon final, px), age (s) }, peintes anneau par anneau (_paint_ring).
var _jobs: Array[Dictionary] = []
## Passes d'évaporation en cours, une par carreau (cf. _evaporate).
var _evaporations: Array[Dictionary] = []
## Temps de la partie (s), qui n'avance pas en pause.
var _clock := 0.0
var _evaporation_left := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_noise.seed = 7 # Fixe : mêmes contours sur tous les ordinateurs.
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0 / shape_noise_scale
	_noise.fractal_octaves = 2
	_ripples = _make_ripples()
	_ring_mesh = _make_ring_mesh()
	_drop_mesh = _make_drop_mesh()
	_burst_mesh = _make_burst_mesh()


## Vrai s'il y a de l'eau en `point` (à la surface du sol) : humidité au-dessus du seuil.
func is_wet(point: Vector3) -> bool:
	var key := Vector3i(floori(point.x / CHUNK_SIZE), roundi(point.y / LAYER_HEIGHT), floori(point.z / CHUNK_SIZE))
	if not _chunks.has(key):
		return false
	var size := _chunk_pixels()
	var local := (Vector2(point.x, point.z) - Vector2(key.x, key.z) * CHUNK_SIZE) * pixels_per_meter
	var i := clampi(int(local.y), 0, size - 1) * size + clampi(int(local.x), 0, size - 1)
	return (_chunks[key].wet as PackedFloat32Array)[i] > threshold


## Ajoute une tache d'eau de rayon `radius` (m) centrée sur `point` (surface du sol, de
## normale `normal`), avec une éclaboussure (ronds et gouttes) si `splash`.
func add_puddle(point: Vector3, radius: float, amount := 1.0, splash := true, normal := Vector3.UP) -> void:
	if splash and splash_effects:
		_play_splash(point, radius, normal)
	var reach := radius * (1.0 + shape_noise) # Place pour les lobes les plus grands.
	# Pente : la tache suit le plan de la surface touchée ; elle s'étend sur les étages que ce
	# plan traverse dans son rayon (un seul sur un sol plat). Surface trop raide : à plat.
	var slope := normal.normalized() if normal.y > 0.2 else Vector3.UP
	var rise := reach * Vector2(slope.x, slope.z).length() / slope.y
	var min_chunk := Vector2i(floori((point.x - reach) / CHUNK_SIZE), floori((point.z - reach) / CHUNK_SIZE))
	var max_chunk := Vector2i(floori((point.x + reach) / CHUNK_SIZE), floori((point.z + reach) / CHUNK_SIZE))
	var parts: Array[Dictionary] = []
	for layer in range(roundi((point.y - rise) / LAYER_HEIGHT), roundi((point.y + rise) / LAYER_HEIGHT) + 1):
		for cx in range(min_chunk.x, max_chunk.x + 1):
			for cz in range(min_chunk.y, max_chunk.y + 1):
				parts.append(_make_job(_get_chunk(Vector3i(cx, layer, cz)), Vector2(cx, cz) * CHUNK_SIZE,
						point, radius, amount, slope, layer, rise > 0.0))
	_jobs.append({"parts": parts, "done": 0.0, "reach": reach * pixels_per_meter, "age": 0.0})


func _process(delta: float) -> void:
	_clock += delta
	_schedule_evaporation(delta)
	var deadline := Time.get_ticks_usec() + int(paint_budget_ms * 1000.0)
	for job: Dictionary in _jobs.duplicate():
		if _spread(job, delta, deadline):
			_jobs.erase(job)
	while not _evaporations.is_empty() and Time.get_ticks_usec() < deadline:
		if _evaporate(_evaporations[0], deadline):
			_evaporations.pop_front()
	for chunk: Dictionary in _chunks.values():
		if chunk.dirty:
			chunk.dirty = false
			# Nouvelles textures à chaque changement : Godot recopie les textures des Decals
			# dans un atlas commun, mis à jour seulement quand une texture de Decal est ajoutée
			# ou retirée. Un simple ImageTexture.update() n'apparaîtrait qu'au prochain ajout
			# (flaques en retard, voire jamais affichées).
			chunk.decal.texture_albedo = ImageTexture.create_from_image(chunk.albedo)
			chunk.decal.texture_orm = ImageTexture.create_from_image(chunk.orm)


## Tache à peindre dans le carreau dont le coin (x, z) minimal est `origin` (m), étage
## `layer`. Si `on_slope`, seuls les pixels dont la hauteur sur le plan (`point`, `slope`)
## tombe dans cet étage sont peints.
func _make_job(chunk: Dictionary, origin: Vector2, point: Vector3, radius: float, amount: float,
		slope := Vector3.UP, layer := 0, on_slope := false) -> Dictionary:
	var size := _chunk_pixels()
	var center := (Vector2(point.x, point.z) - origin) * pixels_per_meter
	var r := radius * pixels_per_meter
	var reach := r * (1.0 + shape_noise)
	return {
		"chunk": chunk, "origin": origin, "center": center, "r": r, "reach": reach, "amount": amount,
		"point": point, "slope": slope, "layer": layer, "on_slope": on_slope,
		"row": maxi(floori(center.y - reach), 0), "last_row": mini(ceili(center.y + reach), size - 1),
		"first_col": maxi(floori(center.x - reach), 0), "last_col": mini(ceili(center.x + reach), size - 1),
	}


## Étale la tache `job` : peint les anneaux suivants jusqu'au rayon qu'elle doit avoir atteint
## (ease-out sur spread_time s), sans dépasser `deadline` (µs) ; en retard, elle rattrape aux
## images suivantes. Vrai quand elle est finie.
func _spread(job: Dictionary, delta: float, deadline: int) -> bool:
	job.age += delta
	var t := clampf(job.age / spread_time, 0.0, 1.0) if spread_time > 0.0 else 1.0
	var target: float = job.reach * (1.0 - pow(1.0 - t, 2.0))
	var step := 4.0 # Largeur d'un anneau (px).
	while job.done < target and Time.get_ticks_usec() < deadline:
		var outer: float = job.done + step
		if outer >= job.reach:
			outer = job.reach + 1.0 # Dernier anneau : jusqu'au bout de la tache.
		for part: Dictionary in job.parts:
			_paint_ring(part, job.done, outer)
		job.done = outer
	return job.done >= job.reach


## Peint, dans le carreau de `job`, les pixels de la tache dont la distance au centre (px) est
## dans [inner, outer[.
func _paint_ring(job: Dictionary, inner: float, outer: float) -> void:
	var chunk: Dictionary = job.chunk
	var size := _chunk_pixels()
	var origin: Vector2 = job.origin
	var center: Vector2 = job.center
	var r: float = job.r
	var reach2: float = job.reach * job.reach
	var amount: float = job.amount
	var on_slope: bool = job.on_slope
	var point: Vector3 = job.point
	var slope: Vector3 = job.slope
	var layer: int = job.layer
	# Demi-hauteur d'étage, plus de quoi déborder de 2 pixels sur l'étage voisin : sans ce
	# recouvrement, le lissage de la texture au bord de l'étage dessine une ligne claire.
	# (Le Decal coupe net au bord de l'étage : le débordement ne se voit pas.)
	var band := LAYER_HEIGHT / 2.0 + 2.0 / pixels_per_meter * Vector2(slope.x, slope.z).length() / slope.y + 0.01
	var dry := threshold - damp_width # En dessous, le pixel reste transparent (cf. _shade).
	var now := _clock + 1.0 # (+1 : 0 veut dire « sec »)
	var inner2 := inner * inner
	var outer2 := minf(outer * outer, reach2)
	var first_row := maxi(job.row, floori(center.y - outer))
	var last_row := mini(job.last_row, ceili(center.y + outer))
	if first_row > last_row or job.first_col > job.last_col:
		return
	# Anneau qui ne passe pas sur ce carreau (tout entier plus près ou plus loin du centre) : rien.
	var near := Vector2(clampf(center.x, job.first_col, job.last_col + 1), clampf(center.y, job.row, job.last_row + 1))
	var far := Vector2(job.first_col if center.x - job.first_col > job.last_col + 1 - center.x else job.last_col + 1,
			job.row if center.y - job.row > job.last_row + 1 - center.y else job.last_row + 1)
	if (near - center).length() >= outer or (far - center).length() < inner:
		return
	# Tableaux sortis du carreau le temps de la peinture : seuls à les tenir, on les modifie
	# sur place (sinon chaque anneau en recopierait tout le contenu).
	var wet: PackedFloat32Array = chunk.wet
	var stamp: PackedFloat32Array = chunk.stamp
	var wet_pixels: PackedInt32Array = chunk.wet_pixels
	chunk.wet = PackedFloat32Array()
	chunk.stamp = PackedFloat32Array()
	chunk.wet_pixels = PackedInt32Array()
	var painted := false
	for py in range(first_row, last_row + 1):
		var dy := py + 0.5 - center.y
		if dy * dy >= outer2:
			continue
		# Colonnes de l'anneau sur cette ligne : deux segments (un seul près du haut et du bas).
		var half_out := sqrt(outer2 - dy * dy)
		var half_in := sqrt(maxf(inner2 - dy * dy, 0.0))
		var left_start := maxi(floori(center.x - half_out - 1.0), job.first_col)
		var left_end := mini(ceili(center.x - half_in), job.last_col)
		var right_start := maxi(floori(center.x + half_in - 1.0), job.first_col)
		var right_end := mini(ceili(center.x + half_out), job.last_col)
		var merged := left_end >= right_start
		for span in 1 if merged else 2:
			for px in range(left_start if span == 0 else right_start, (right_end if merged else left_end) + 1 if span == 0 else right_end + 1):
				var pixel := Vector2(px + 0.5, py + 0.5)
				var dist2 := (pixel - center).length_squared()
				if dist2 < inner2 or dist2 >= outer2:
					continue # Autre anneau, ou hors de portée même du plus grand lobe.
				painted = true
				var world := origin + pixel / pixels_per_meter
				if on_slope: # Hauteur de la pente ici : ce pixel est-il dans l'étage de ce carreau ?
					var height := point.y - (slope.x * (world.x - point.x) + slope.z * (world.y - point.z)) / slope.y
					if absf(height - layer * LAYER_HEIGHT) > band:
						continue
				# Rayon déformé selon l'endroit : contour en lobes, pas en cercle.
				var local_r := r * (1.0 + shape_noise * _noise.get_noise_2d(world.x, world.y))
				var d2 := dist2 / (local_r * local_r)
				if d2 >= 1.0:
					continue
				var i := py * size + px
				# Tache douce (1 au centre, 0 au bord) : deux taches proches se rejoignent.
				wet[i] = minf(wet[i] + amount * (1.0 - d2) * (1.0 - d2), max_wetness)
				if stamp[i] == 0.0:
					wet_pixels.append(i) # Pixel qui vient d'être mouillé : à faire sécher plus tard.
				stamp[i] = now # Arrosé : l'évaporation repart de zéro.
				if wet[i] > dry:
					_shade(chunk, px, py, wet[i])
	chunk.wet = wet
	chunk.stamp = stamp
	chunk.wet_pixels = wet_pixels
	if painted:
		chunk.oldest = minf(chunk.oldest, now)
		chunk.dirty = true


## Toutes les EVAPORATION_STEP s, lance une passe sur chaque carreau où de l'eau commence à
## pâlir (son plus vieux pixel a dépassé water_lifetime - fade_duration).
func _schedule_evaporation(delta: float) -> void:
	_evaporation_left -= delta
	if _evaporation_left > 0.0:
		return
	_evaporation_left = EVAPORATION_STEP
	var fading_since := _clock + 1.0 - (water_lifetime - fade_duration)
	for chunk: Dictionary in _chunks.values():
		if not chunk.evaporating and chunk.oldest <= fading_since:
			chunk.evaporating = true
			# La passe prend la liste des pixels mouillés ; ceux mouillés pendant la passe vont
			# dans une nouvelle liste, réunies à la fin.
			_evaporations.append({"chunk": chunk, "pixels": chunk.wet_pixels, "index": 0,
					"kept": PackedInt32Array(), "oldest": INF})
			chunk.wet_pixels = PackedInt32Array()
			chunk.oldest = INF


## Passe d'évaporation sur un carreau, jusqu'à `deadline` (µs) : les pixels trop vieux sèchent,
## ceux en fin de vie pâlissent. Vrai quand elle est finie.
func _evaporate(job: Dictionary, deadline: int) -> bool:
	var chunk: Dictionary = job.chunk
	var size := _chunk_pixels()
	var wet: PackedFloat32Array = chunk.wet
	var stamp: PackedFloat32Array = chunk.stamp
	var pixels: PackedInt32Array = job.pixels
	var kept: PackedInt32Array = job.kept
	var now := _clock + 1.0
	var fade_start := water_lifetime - fade_duration
	var dry := threshold - damp_width
	var albedo: Image = chunk.albedo
	var orm: Image = chunk.orm
	var changed := false
	while job.index < pixels.size():
		if job.index % 64 == 0 and Time.get_ticks_usec() >= deadline:
			break
		var i := pixels[job.index]
		job.index += 1
		if stamp[i] == 0.0:
			continue
		var age := now - stamp[i]
		var px := i % size
		var py := i / size
		if age >= water_lifetime: # Sec.
			wet[i] = 0.0
			stamp[i] = 0.0
			albedo.set_pixel(px, py, Color(0, 0, 0, 0))
			orm.set_pixel(px, py, Color(0, 0, 0, 0))
			changed = true
			continue
		kept.append(i)
		job.oldest = minf(job.oldest, stamp[i])
		if age > fade_start and wet[i] > dry:
			_shade(chunk, px, py, wet[i], (age - fade_start) / fade_duration)
			changed = true
	chunk.wet = wet
	chunk.stamp = stamp
	job.kept = kept
	if changed:
		chunk.dirty = true
	if job.index < pixels.size():
		return false
	chunk.wet_pixels = kept + chunk.wet_pixels
	chunk.oldest = minf(chunk.oldest, job.oldest)
	chunk.evaporating = false
	return true


## Couleur d'un pixel selon son humidité : halo de sol mouillé juste sous le seuil, puis
## eau d'une seule teinte au-dessus (bord un peu plus sombre). `fade` (0 à 1) : en fin de
## vie, l'eau pâlit (plus claire, plus transparente) jusqu'à disparaître.
func _shade(chunk: Dictionary, px: int, py: int, wetness: float, fade := 0.0) -> void:
	var damp := smoothstep(threshold - damp_width, threshold - 0.04, wetness)
	var water := smoothstep(threshold - 0.04, threshold + 0.04, wetness)
	var rim := (1.0 - smoothstep(threshold, threshold + rim_width, wetness)) * water
	var water_rgb := Color(water_color.r, water_color.g, water_color.b).darkened(rim * 0.3)
	var water_alpha := minf(water_color.a + rim * 0.15, 1.0)
	var color := Color(damp_color, damp * damp_color.a).lerp(Color(water_rgb, water_alpha), water)
	if fade > 0.0:
		color = Color(Color(color.r, color.g, color.b).lerp(fade_color, fade * 0.7), color.a * (1.0 - fade))
	(chunk.albedo as Image).set_pixel(px, py, color)
	var roughness := lerpf(lerpf(damp_roughness, water_roughness, water), damp_roughness, fade)
	(chunk.orm as Image).set_pixel(px, py, Color(1.0, roughness, 0.0, maxf(damp, water) * (1.0 - fade)))


func _get_chunk(key: Vector3i) -> Dictionary:
	if _chunks.has(key):
		return _chunks[key]
	var size := _chunk_pixels()
	var wet := PackedFloat32Array()
	wet.resize(size * size)
	var stamp := PackedFloat32Array()
	stamp.resize(size * size)
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
	var chunk := {"wet": wet, "albedo": albedo, "orm": orm, "decal": decal, "dirty": false,
			"stamp": stamp, "wet_pixels": PackedInt32Array(), "oldest": INF, "evaporating": false}
	_chunks[key] = chunk
	return chunk


func _chunk_pixels() -> int:
	return roundi(CHUNK_SIZE * pixels_per_meter)


## Éclatement d'une bulle sur une surface de normale `normal` : deux ronds qui s'élargissent
## à plat sur la surface et des gouttes projetées perpendiculairement à elle.
func _play_splash(point: Vector3, radius: float, normal := Vector3.UP) -> void:
	_spawn_ring(point, radius * 1.1, 0.0, splash_duration, 1.0, normal)
	_spawn_ring(point, radius * 0.7, 0.12, splash_duration, 1.0, normal)
	_spawn_drops(point, splash_drops, normal, 35.0, 2.5, 4.5, 0.15)


## Goutte du canon à eau qui touche `point` (surface de normale `normal`) : de temps en temps,
## un petit rond discret au sol, ou quelques gouttelettes qui rejaillissent ailleurs.
func drip(point: Vector3, normal := Vector3.UP) -> void:
	_drips += 1
	if not splash_effects or _drips % DRIP_RING_EVERY != 0:
		return
	if normal.y > 0.7:
		_spawn_ring(point, 0.5, 0.0, 0.35, 0.3, normal)
	else:
		_spawn_drops(point - Vector3.UP * 0.05, 3, (normal + Vector3.UP * 0.5).normalized(), 50.0, 1.0, 2.5, 0.05, 0.6)


## Bulle qui éclate sur un canard (`point` sur lui, `normal` vers l'extérieur) : gerbe d'eau
## projetée vers le tireur et vers le haut, fines gouttelettes tout autour et coque d'eau
## qui gonfle et s'efface (on voit qu'on l'a touché).
func duck_splash(point: Vector3, normal: Vector3) -> void:
	if not splash_effects:
		return
	_spawn_drops(point, 22, (normal + Vector3.UP * 0.7).normalized(), 70.0, 3.0, 6.5, 0.2, 2.0)
	_spawn_drops(point, 14, Vector3.UP, 180.0, 1.5, 3.5, 0.3, 0.7)
	var burst := MeshInstance3D.new()
	burst.mesh = _burst_mesh
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.layers = DUCK_VISUAL_LAYER
	burst.position = point
	burst.scale = Vector3.ONE * 0.3
	add_child(burst)
	var tween := burst.create_tween().set_parallel()
	tween.tween_property(burst, ^"scale", Vector3.ONE * 1.3, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(burst, ^"transparency", 1.0, 0.22).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(burst.queue_free)


## Pas d'un canard dans l'eau (`point` sous son pied, sol de normale `normal`) : petit rond et
## quelques gouttes.
func step_splash(point: Vector3, normal := Vector3.UP) -> void:
	if splash_effects:
		_spawn_ring(point, 0.9, 0.0, 0.5, 0.65, normal)
		_spawn_drops(point, 5, normal, 30.0, 1.0, 2.0, 0.08, 0.7)


## Sillage d'un canard qui glisse sur l'eau, à appeler régulièrement pendant la glissade :
## rond sous ses pieds et gerbes projetées sur les côtés et vers l'arrière de `velocity` (sol de
## normale `normal`).
func wake(point: Vector3, velocity: Vector3, normal := Vector3.UP) -> void:
	if not splash_effects:
		return
	var back := Vector3(-velocity.x, 0.0, -velocity.z).normalized()
	_spawn_ring(point, 1.1, 0.0, 0.6, 0.45, normal)
	_spawn_drops(point, 6, (back + normal * 1.3).normalized(), 60.0, 2.0, 3.5, 0.15, 0.8)


## Rond qui apparaît après `delay` s, s'élargit jusqu'à `size` m en `duration` s et s'efface,
## posé à plat sur la surface de normale `normal`. `opacity` : 1 = aussi marqué que
## l'éclatement d'une bulle.
func _spawn_ring(point: Vector3, size: float, delay: float, duration: float, opacity := 1.0,
		normal := Vector3.UP) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.layers = DUCK_VISUAL_LAYER # Sinon la flaque (Decal) le peindrait couleur d'eau.
	ring.position = point + normal * 0.02
	if normal.dot(Vector3.UP) > -0.99: # (Rond horizontal à l'origine : on le couche sur la surface.)
		ring.quaternion = Quaternion(Vector3.UP, normal.normalized())
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
	# Dans l'air chaud d'un sèche-cheveux, les gouttes s'envolent au lieu de retomber.
	drops.gravity = Vector3(0, HairDryer.projectile_gravity_at(get_tree(), point, 14.0), 0)
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


## Coque d'éclaboussure : sphère d'eau claire et transparente, plus blanche sur les bords.
func _make_burst_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.82, 0.94, 1.0, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
