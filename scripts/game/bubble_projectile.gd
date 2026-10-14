class_name BubbleProjectile
extends Node3D
## Bulle tirée par un joueur (scène instanciée par Game sous Projectiles).
##
## Avance tout droit à `speed` m/s et éclate (pop) au premier de ces événements :
##   - elle touche un obstacle (calque « world » : sol, murs, plafond, objets),
##     ou le mur invisible de la zone d'apparition adverse ;
##   - elle touche un joueur : `damage` PV de dégâts s'il est de l'autre équipe
##     (bulle de capture, `capture` : il est piégé `capture_duration` s, cf. Player.capture) ;
##   - elle a parcouru `max_distance` mètres.
## Puis le nœud est supprimé (queue_free) à la fin de l'animation et du son d'éclatement.
##
## Optimisation : pas de corps physique ni de zone de collision. À chaque image
## physique, une sphère de la taille de la bulle est « lancée » de l'ancienne à
## la nouvelle position (cast_motion) : rien ne peut être traversé, même à
## grande vitesse. Mesh, matériau et forme de collision sont partagés par
## toutes les bulles.
##
## Réseau : chaque ordinateur fait voler sa propre copie de la bulle (même
## départ, même trajectoire) ; seule celle de l'ordinateur du tireur inflige
## les dégâts (Player.take_damage les transmet au bon ordinateur).
##
## Bulle de capture : scenes/game/capture_bubble.tscn (scène héritée de celle-ci,
## plus grosse et plus lente), tirée avec l'action capture (clic molette).

## Vitesse (m/s).
@export var speed := 30.0
## Portée (m) : la bulle éclate au-delà. Bulle de capture : 1000 m, portée illimitée en
## pratique (elle vole jusqu'à toucher quelque chose) ; tirée dans le vide, elle finit par disparaître.
@export var max_distance := 25.0
@export var damage := 30.0
## Dégâts aussi sur les coéquipiers (sinon la bulle éclate sans les blesser).
@export var friendly_fire := false
## Durée de l'animation d'éclatement (s).
@export var pop_duration := 0.12
## La bulle sort du canon petite et atteint sa taille en `grow_duration` s.
@export var grow_duration := 0.12
@export var start_scale := 0.2
## Rayon (m) de la zone de contact ; le mesh est mis à la même échelle. Garder égal
## à RADIUS ici et à CAPTURE_RADIUS dans capture_bubble.tscn (Player vise avec la surface de la bulle).
@export var radius := RADIUS
## Rayon (m) de contact avec le décor (sol, murs…) et les murs des zones d'apparition ;
## négatif = `radius`. Plus petit que la bulle, elle frôle le sol sans éclater : la bulle
## de capture est plus grosse que la hauteur du canon au-dessus du sol (0,4 m).
@export var world_radius := -1.0
@export_group("Capture")
## Bulle de capture : piège l'adversaire touché (sans dégâts) au lieu de le blesser.
@export var capture := false
## Durée pendant laquelle l'adversaire touché reste piégé (s).
@export var capture_duration := 2.0
@export_group("")

## Rayon du SphereMesh de la scène (m).
const RADIUS := 0.455
## Rayon de la bulle de capture (m), cf. `radius` de capture_bubble.tscn.
const CAPTURE_RADIUS := 0.7

## Matériau de chaque équipe (index 0 = équipe 1), partagé par toutes ses bulles :
## celui de la scène, teinté à la couleur de l'équipe (même transparence).
static var _team_materials: Array[StandardMaterial3D] = []

var _direction := Vector3.FORWARD
var _travelled := 0.0
var _shooter_team := 0
var _deals_damage := false
## Détection : [décor, joueurs], chacune avec sa forme (world_radius, radius).
var _queries: Array[PhysicsShapeQueryParameters3D] = []
## Formes de détection : grandissent avec la bulle (sinon, à sa sortie du canon tenu bas,
## elle toucherait déjà le sol avec son rayon final).
var _world_shape := SphereShape3D.new()
var _hit_shape := SphereShape3D.new()
var _grow_tween: Tween


## À appeler juste après l'ajout à la scène. `deals_damage` : vrai seulement
## sur l'ordinateur du tireur.
func launch(shooter: Player, origin: Vector3, direction: Vector3, deals_damage: bool) -> void:
	global_position = origin
	_direction = direction.normalized()
	_shooter_team = Player.team_of(shooter.player_id)
	var mesh := $Mesh as MeshInstance3D
	mesh.scale = Vector3.ONE * radius / RADIUS
	if _team_materials.is_empty():
		var base := mesh.get_active_material(0) as StandardMaterial3D
		for team_color in Player.TEAM_COLORS:
			var material := base.duplicate() as StandardMaterial3D
			material.albedo_color = Color(team_color.lerp(Color.WHITE, 0.1), base.albedo_color.a + 0.25)
			_team_materials.append(material)
	mesh.material_override = _team_materials[_shooter_team - 1]
	_deals_damage = deals_damage
	for layers: Array in [[_world_shape, Player.WORLD_LAYER | Player.enemy_spawn_layer(_shooter_team)],
			[_hit_shape, Player.PLAYERS_LAYER]]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = layers[0]
		query.collision_mask = layers[1]
		query.exclude = [shooter.get_rid()] # Ne se touche pas soi-même au départ.
		_queries.append(query)
	reset_physics_interpolation()
	scale = Vector3.ONE * start_scale
	_grow_tween = create_tween()
	_grow_tween.tween_property(self, ^"scale", Vector3.ONE, grow_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	var step := minf(speed * delta, max_distance - _travelled)
	var space := get_world_3d().direct_space_state
	var grown := minf(scale.x, 1.0)
	_hit_shape.radius = radius * grown
	_world_shape.radius = (world_radius if world_radius >= 0.0 else radius) * grown
	var motion := _direction * step
	# Premier contact (décor ou joueur) : [fraction sans contact, fraction au contact]
	# du déplacement ; 1 = aucun obstacle.
	var first: PhysicsShapeQueryParameters3D = null
	var first_fractions := PackedFloat32Array([1.0, 1.0])
	for query in _queries:
		query.transform = Transform3D(Basis.IDENTITY, global_position)
		if _travelled == 0.0:
			# Premier pas : cast_motion ignore ce qui touche déjà la bulle (canon collé à un mur, à un adversaire…).
			query.motion = Vector3.ZERO
			var overlap := space.get_rest_info(query)
			if not overlap.is_empty():
				_on_hit(instance_from_id(overlap.collider_id))
				return
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions[1] < first_fractions[1]:
			first = query
			first_fractions = fractions
	if first:
		first.transform.origin = global_position + motion * first_fractions[1]
		var contact := space.get_rest_info(first)
		global_position += motion * first_fractions[0]
		_on_hit(instance_from_id(contact.collider_id) if not contact.is_empty() else null)
		return
	global_position += motion
	_travelled += step
	if _travelled >= max_distance:
		_pop()


func _on_hit(collider: Object) -> void:
	var player := collider as Player
	if player and _deals_damage and (friendly_fire or Player.team_of(player.player_id) != _shooter_team):
		if capture:
			player.capture(capture_duration, _shooter_team)
		else:
			player.take_damage(damage)
	_pop()


## Éclatement : la bulle gonfle et s'efface (avec un son d'éclatement au hasard,
## assets/audio/sfx/bubble_pop.tres), puis le nœud est supprimé une fois le son fini.
func _pop() -> void:
	set_physics_process(false)
	if _grow_tween:
		_grow_tween.kill()
	var pop_sound := $PopSound as AudioStreamPlayer3D
	pop_sound.play()
	var mesh := $Mesh as GeometryInstance3D
	var tween := create_tween().set_parallel()
	tween.tween_property(self, ^"scale", Vector3.ONE * 1.8, pop_duration)
	tween.tween_property(mesh, ^"transparency", 1.0, pop_duration)
	await tween.finished
	if pop_sound.playing:
		await pop_sound.finished
	queue_free()
