class_name HairDryer
extends Node3D
## Sèche-cheveux allumé, debout au milieu d'un socle rond (scenes/game/hair_dryer.tscn) :
## il souffle en permanence de l'air chaud vers le haut. Tout canard en l'air dans la colonne
## est porté vers le haut (Player, cf. lift) : il monte vers le haut de la colonne et y flotte
## tant qu'il y reste. La puissance du souffle varie doucement (sinusoïde) : le canard qui flotte
## monte et descend un peu (cf. power). Sauter depuis le socle lance en plus l'envol (`launch_speed` au lieu du
## saut normal).
##
## Le courant d'air chaud se voit : un jet conique qui sort de la buse et une colonne en voile
## transparent (shader assets/shaders/hot_air.gdshader, qui laisse voir les bulles), des filets
## d'air qui montent, une lueur orange dans la buse. Il s'entend aussi (souffle généré).
## Colonne, jet et filets sont créés dans _ready d'après les réglages ci-dessous.
##
## Sans `show_model`, seul le souffle reste (pas de socle ni de modèle) : on le pose sous la
## buse d'un sèche-cheveux modélisé dans la carte, l'origine au sol, `nozzle_height` /
## `nozzle_radius` réglés sur sa buse (cf. arena5.tscn).

const GROUP := &"hair_dryers"
## Hauteur (m, depuis le bas du socle) au-dessus de laquelle on n'est plus « sur le socle ».
const PAD_TOP := 1.5
const HOT_AIR_SHADER := preload("res://assets/shaders/hot_air.gdshader")

## Socle rond et modèle du sèche-cheveux (faux : souffle seul, cf. en-tête).
@export var show_model := true
## Hauteur (m, depuis le sol) et rayon (m) de la sortie de la buse (modèle de hair_dryer.tscn :
## 2,55 et 0,42).
@export var nozzle_height := 2.55
@export var nozzle_radius := 0.42
@export_group("Envol")
## Rayon (m) de la zone d'envol : sauter à moins de cette distance du centre fait s'envoler.
@export var zone_radius := 3.2
## Vitesse verticale (m/s) donnée au canard qui saute depuis le socle (saut normal : 8,5).
@export var launch_speed := 14.0
## Vitesse de montée (m/s) que l'air donne au bas de la colonne ; elle diminue avec la
## hauteur jusqu'à 0 en haut de la colonne, où le canard finit par flotter.
@export var updraft_speed := 9.0
## Accélération (m/s²) avec laquelle l'air rattrape cette vitesse (canard qui tombe dans la
## colonne, ou qui y entre par le côté).
@export var lift_acceleration := 30.0
## Canard plus rapide que l'air (juste après l'envol) : sa gravité est multipliée par ce facteur
## (montée lente et flottante).
@export_range(0.0, 1.0) var lift_gravity := 0.4
## Hauteur (m) de la colonne d'air chaud (au-dessus, gravité normale).
@export var column_height := 16.0
## Hauteur (m, au-dessus du socle) où flotte le canard, à puissance moyenne.
@export var hover_height := 13.0
## Variation de la puissance du souffle (0,15 = ± 15 %) : la hauteur où flotte le canard varie
## d'autant (± 2 m environ).
@export_range(0.0, 0.5) var power_variation := 0.15
## Durée (s) d'une oscillation de la puissance.
@export var power_period := 3.0
@export_group("Bulles et gouttes")
## Vitesse de montée (m/s) que l'air donne aux petits objets qui traversent la colonne
## (bulles, gouttes du canon à eau, gouttes des éclaboussures), atteinte avec
## `projectile_lift_acceleration` (m/s²) au lieu de leur gravité (cf. lift_projectile).
## Constante (pas de variation de puissance) : ils montent pareil sur tous les ordinateurs.
@export var projectile_lift_speed := 6.0
@export var projectile_lift_acceleration := 30.0
@export_group("Air chaud")
## Blanc neutre : l'air ne doit pas ressembler à une zone à défendre (colonnes colorées).
@export var air_color := Color(0.96, 0.98, 1.0)
## Nombre de filets d'air visibles en même temps (environ).
@export var streaks := 70
@export var hum_volume_db := -14.0

var _noise: NoiseTexture2D
@onready var _glow: OmniLight3D = $SecheCheveux/Lueur
@onready var _glow_energy := _glow.light_energy
var _puff: CPUParticles3D
var _hum: AudioStreamPlayer3D
var _hum_playback: AudioStreamGeneratorPlayback
var _hum_phase := 0.0
var _hum_brown := 0.0


## Le sèche-cheveux sur le socle duquel se trouve `feet` (point sous les pieds), sinon null.
static func under(tree: SceneTree, feet: Vector3) -> HairDryer:
	for dryer: HairDryer in tree.get_nodes_in_group(GROUP):
		if dryer.is_on_pad(feet):
			return dryer
	return null


func _ready() -> void:
	add_to_group(GROUP)
	if not show_model:
		var pad := $Socle as CSGCombiner3D
		pad.use_collision = false
		pad.visible = false
		($SecheCheveux as Node3D).visible = false
		$SecheCheveux/Collision.queue_free()
	_noise = NoiseTexture2D.new()
	_noise.seamless = true
	_noise.width = 256
	_noise.height = 256
	var fast := FastNoiseLite.new()
	fast.frequency = 0.012
	fast.fractal_octaves = 3
	_noise.noise = fast
	# Colonne d'air chaud au-dessus de tout le socle, et jet plus marqué qui sort de la buse.
	_add_air_cone(zone_radius, zone_radius, 0.3, column_height, 0.08, 0.6)
	_add_air_cone(nozzle_radius, zone_radius * 0.75, nozzle_height, 5.0, 0.25, 1.4)
	_add_streaks()
	_puff = _make_puff()
	add_child(_puff)
	_add_hum()


func is_on_pad(feet: Vector3) -> bool:
	var local := to_local(feet)
	return Vector2(local.x, local.z).length() <= zone_radius and local.y > -0.5 and local.y < PAD_TOP


## Vrai si `point` est dans la colonne d'air chaud (un peu plus large que le socle).
func in_column(point: Vector3) -> bool:
	var local := to_local(point)
	return Vector2(local.x, local.z).length() <= zone_radius + 0.6 and local.y > -0.5 and local.y < column_height


## Le sèche-cheveux dont la colonne d'air contient `point`, sinon null.
static func column_at(tree: SceneTree, point: Vector3) -> HairDryer:
	for dryer: HairDryer in tree.get_nodes_in_group(GROUP):
		if dryer.in_column(point):
			return dryer
	return null


## Vitesse verticale (m/s), après `delta` s, d'un petit objet (bulle, goutte) à `point` qui
## monte ou tombe à `vertical_speed` : dans la colonne d'un des sèche-cheveux `dryers`, l'air le
## pousse vers projectile_lift_speed ; ailleurs, sa gravité `gravity` (m/s²) s'applique.
## `dryers` : get_tree().get_nodes_in_group(GROUP), lu une fois par image pour tous les objets.
static func lift_projectile(dryers: Array[Node], point: Vector3, vertical_speed: float, gravity: float,
		delta: float) -> float:
	for dryer: HairDryer in dryers:
		if dryer.in_column(point):
			return move_toward(vertical_speed, dryer.projectile_lift_speed,
					dryer.projectile_lift_acceleration * delta)
	return vertical_speed - gravity * delta


## Accélération verticale (m/s²) d'un petit objet immobile à `point` : vers le haut dans une
## colonne d'air chaud, `-gravity` ailleurs (gouttes en particules, qui ont une gravité fixe).
static func projectile_gravity_at(tree: SceneTree, point: Vector3, gravity: float) -> float:
	var dryer := column_at(tree, point)
	return dryer.projectile_lift_acceleration * 0.5 if dryer else -gravity


## Vitesse verticale (m/s) d'un canard en l'air à `point` dans la colonne, après `delta` s
## de souffle : l'air le pousse vers updraft_speed (de moins en moins en montant, vers le bas
## au-dessus de hover_height) ; plus rapide que l'air,
## il ralentit avec une gravité réduite (`gravity` : la sienne, m/s²).
func lift(point: Vector3, vertical_speed: float, gravity: float, delta: float) -> float:
	var power := get_power()
	# Au-dessus de la hauteur où il flotte, l'air le laisse redescendre doucement.
	var air := updraft_speed * power * clampf(1.0 - to_local(point).y / (hover_height * power), -0.3, 1.0)
	if vertical_speed < air:
		return move_toward(vertical_speed, air, lift_acceleration * delta)
	return maxf(vertical_speed - gravity * lift_gravity * delta, air)


## Puissance du souffle (1 en moyenne), qui oscille de ± power_variation en power_period s.
## Calculée sur l'horloge du jeu : la même pour tous les canards de cet ordinateur.
func get_power() -> float:
	return 1.0 + power_variation * sin(TAU * Time.get_ticks_msec() / 1000.0 / power_period)


## Bouffée d'air au moment où un canard s'envole.
func puff() -> void:
	_puff.restart()


## Cône d'air (cylindre sans fond ni couvercle) de rayon `bottom` à `bottom_y` jusqu'à `top`
## à `bottom_y + height`, voile d'opacité `tint`.
func _add_air_cone(bottom: float, top: float, bottom_y: float, height: float, tint: float,
		speed: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.radial_segments = 32
	mesh.rings = 8
	var material := ShaderMaterial.new()
	material.shader = HOT_AIR_SHADER
	material.set_shader_parameter(&"noise_tex", _noise)
	material.set_shader_parameter(&"tint", air_color)
	material.set_shader_parameter(&"tint_strength", tint)
	material.set_shader_parameter(&"speed", speed)
	material.set_shader_parameter(&"half_height", height * 0.5)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position.y = bottom_y + height * 0.5
	add_child(instance)


## Filets d'air chaud qui montent de la buse et du socle en s'élargissant.
func _add_streaks() -> void:
	var particles := CPUParticles3D.new()
	particles.amount = streaks
	particles.lifetime = 1.8
	particles.preprocess = 2.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = zone_radius * 0.8
	particles.position.y = nozzle_height * 0.6
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.3
	particles.direction = Vector3.UP
	particles.spread = 8.0
	particles.gravity = Vector3.UP * 2.0
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 9.0
	particles.particle_flag_align_y = true
	particles.color_ramp = _fade_ramp(Color(air_color.lerp(Color.WHITE, 0.55), 0.0),
			Color(air_color.lerp(Color.WHITE, 0.4), 0.55))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 1.3)
	quad.material = _streak_material()
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)


## Bouffée (one shot) : filets plus rapides et plus nombreux depuis la buse.
func _make_puff() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.amount = 40
	particles.lifetime = 0.9
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = zone_radius * 0.6
	particles.position.y = 0.5
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 12.0
	particles.initial_velocity_max = 18.0
	particles.particle_flag_align_y = true
	particles.color_ramp = _fade_ramp(Color(1, 1, 1, 0), Color(air_color.lerp(Color.WHITE, 0.6), 0.7))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 1.8)
	quad.material = _streak_material()
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


## Couleur qui apparaît, garde `mid`, puis s'efface (de `edge` à `mid` et retour).
func _fade_ramp(edge: Color, mid: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, edge)
	ramp.set_color(1, edge)
	ramp.add_point(0.2, mid)
	ramp.add_point(0.6, Color(mid, mid.a * 0.6))
	return ramp


func _streak_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Filet plus fin aux bouts : dégradé sur la hauteur du quad.
	var fade := GradientTexture2D.new()
	fade.fill_from = Vector2(0.5, 0.0)
	fade.fill_to = Vector2(0.5, 0.5)
	fade.repeat = GradientTexture2D.REPEAT_MIRROR
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(1, 1, 1, 1))
	fade.gradient = gradient
	material.albedo_texture = fade
	return material


## Souffle continu du sèche-cheveux : bruit grave (moteur, air) et léger sifflement, généré.
func _add_hum() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.25
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = stream
	_hum.volume_db = hum_volume_db
	_hum.unit_size = 6.0
	_hum.max_distance = 40.0
	_hum.position.y = nozzle_height
	_hum.autoplay = false
	add_child(_hum)
	if DisplayServer.get_name() == "headless":
		return
	_hum.play()
	_hum_playback = _hum.get_stream_playback()


func _process(_delta: float) -> void:
	# La lueur de la buse et le souffle suivent la puissance.
	var power := get_power()
	_glow.light_energy = _glow_energy * power
	_hum.volume_db = hum_volume_db + linear_to_db(power)
	if _hum_playback == null:
		return
	var rate := 22050.0
	for i in _hum_playback.get_frames_available():
		# Bruit brun (souffle) + sifflement du moteur qui ondule un peu.
		_hum_brown = clampf(_hum_brown + randf_range(-0.06, 0.06), -1.0, 1.0) * 0.995
		_hum_phase = fmod(_hum_phase + 820.0 / rate, 1.0)
		var whine := sin(_hum_phase * TAU) * 0.05 * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.004))
		var sample := _hum_brown * 0.55 + randf_range(-0.12, 0.12) + whine
		_hum_playback.push_frame(Vector2(sample, sample))
