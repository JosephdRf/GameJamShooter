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
## Flaque : en éclatant sur une surface presque horizontale (sol, dessus d'un meuble),
## elle émet `splashed` (Game y crée une flaque d'eau, cf. Puddles).
##
## Réseau : chaque ordinateur fait voler sa propre copie de la bulle (même
## départ, même trajectoire) ; seule celle de l'ordinateur du tireur inflige
## les dégâts (Player.take_damage les transmet au bon ordinateur).
##
## Bulle de capture : scenes/game/capture_bubble.tscn (scène héritée de celle-ci,
## plus grosse et plus lente), tirée avec l'action capture (clic molette).

## Vitesse (m/s).
@export var speed := 30.0
## Portée (m) : la bulle éclate au-delà (le viseur pâlit au-delà de RANGE, cf. Crosshair). Bulle de capture : 1000 m, portée illimitée en
## pratique (elle vole jusqu'à toucher quelque chose) ; tirée dans le vide, elle finit par disparaître.
@export var max_distance := RANGE
@export var damage := 30.0
## Dégâts aussi sur les coéquipiers (sinon la bulle éclate sans les blesser).
@export var friendly_fire := false
## Durée de l'animation d'éclatement (s).
@export var pop_duration := 0.12
## La bulle sort du canon petite et atteint sa taille en `grow_duration` s.
@export var grow_duration := 0.12
@export var start_scale := 0.2
## Rayon (m) de la zone de contact ; le mesh est mis à la même échelle. Garder égal
## à RADIUS ici (Player vise avec la surface de la bulle).
@export var radius := RADIUS
## Rayon (m) de contact avec le décor (sol, murs…) et les murs des zones d'apparition ;
## négatif = `radius`. Plus petit que la bulle, elle frôle le sol sans éclater : la bulle
## de capture est plus grosse que la hauteur du canon au-dessus du sol (0,4 m).
@export var world_radius := -1.0
## Rayon visible de la bulle (m) ; négatif = `radius`. La bulle normale est dessinée à la
## taille de son contact avec le décor (0,3 m) : plus petite que la hauteur du canon
## (0,4 m), elle file au-dessus du sol au lieu d'y être à moitié enfoncée. Elle garde un
## contact plus généreux (`radius`) avec les canards.
@export var visual_radius := -1.0
## Hauteur (m) dont la bulle visible et son contact avec les canards sont relevés au-dessus
## de la trajectoire : la grosse bulle (aussi grande que celle qui enferme un canard) roule
## au ras du sol au lieu de s'y enfoncer, et englobe le canard visé de la tête aux pieds.
@export var visual_lift := 0.0
@export_group("Capture")
## Bulle de capture : piège l'adversaire touché (sans dégâts) au lieu de le blesser.
@export var capture := false
## Durée pendant laquelle l'adversaire touché reste piégé (s).
@export var capture_duration := 2.0
@export_group("Explosion")
## En éclatant (sur un canard, le décor, ou au bout de sa portée), la bulle blesse les
## adversaires à moins de `explosion_radius` m de son centre (0 = pas d'explosion) :
## `explosion_damage_max` PV au centre, jusqu'à `explosion_damage_min` PV au bord (distance
## mesurée jusqu'au corps du canard). Un canard capturé (dont celui que la bulle vient de
## piéger) n'est pas blessé par l'explosion.
@export var explosion_radius := 0.0
@export var explosion_damage_max := 50.0
@export var explosion_damage_min := 20.0
@export_group("Flaque")
## Rayon de la tache d'eau laissée en éclatant sur le sol (m) ; 0 = pas de flaque.
@export var puddle_radius := 2.0
@export_group("")

## Rayon du SphereMesh de la scène (m).
const RADIUS := 0.455
## Portée de la bulle normale (m), cf. max_distance.
const RANGE := 25.0
## Amortissement (m/s²) de la montée donnée par un sèche-cheveux, une fois sortie de son air.
const LIFT_DECAY := 30.0
## Vitesse à laquelle l'image de la bulle rejoint sa vraie trajectoire (cf. _visual_offset).
const VISUAL_CATCH_UP_SPEED := 25.0
## Rayon de contact avec le décor des bulles (m), cf. `world_radius` des deux scènes.
const WORLD_CONTACT_RADIUS := 0.3
## Surface considérée comme un sol (flaque) si la composante verticale de sa normale dépasse ce seuil.
const GROUND_MIN_NORMAL_Y := 0.7

## Émis quand la bulle éclate sur le sol : `point` sur la surface, rayon de la flaque (m),
## normale de la surface (l'éclaboussure suit une pente).
signal splashed(point: Vector3, puddle_radius: float, normal: Vector3)

## Matériau de chaque équipe (index 0 = équipe 1), partagé par toutes ses bulles :
## celui de la scène, teinté à la couleur de l'équipe (même transparence).
static var _team_materials: Array[StandardMaterial3D] = []

var _direction := Vector3.FORWARD
## Vitesse de montée (m/s) donnée par l'air chaud d'un sèche-cheveux (cf. _update_lift).
var _lift := 0.0
var _travelled := 0.0
var _shooter_team := 0
var _shooter_id := 0
var _deals_damage := false
## Canard touché de plein fouet : piégé, il n'est pas blessé par l'explosion (sur l'ordinateur
## du tireur, sa capture n'est peut-être pas encore arrivée quand la bulle explose).
var _direct_hit: Player
## Détection : [décor, joueurs], chacune avec sa forme (world_radius, radius).
var _queries: Array[PhysicsShapeQueryParameters3D] = []
## Formes de détection : grandissent avec la bulle (sinon, à sa sortie du canon tenu bas,
## elle toucherait déjà le sol avec son rayon final).
var _world_shape := SphereShape3D.new()
var _hit_shape := SphereShape3D.new()
var _grow_tween: Tween
## Écart entre l'image de la bulle et sa vraie position, qui fond en VISUAL_CATCH_UP_SPEED :
## partie de la ligne de visée, elle semble sortir du canon (cf. launch, `visual_from`).
var _visual_offset := Vector3.ZERO


## À appeler juste après l'ajout à la scène. `deals_damage` : vrai seulement
## sur l'ordinateur du tireur.
## `visual_from` : point d'où la bulle semble partir (bout du canon), si elle part d'ailleurs.
func launch(shooter: Player, origin: Vector3, direction: Vector3, deals_damage: bool,
		visual_from := Vector3.INF) -> void:
	global_position = origin
	if visual_from.is_finite():
		_visual_offset = visual_from - origin
	_direction = direction.normalized()
	_shooter_team = Player.team_of(shooter.player_id)
	_shooter_id = shooter.player_id
	var mesh := $Mesh as MeshInstance3D
	mesh.scale = Vector3.ONE * (visual_radius if visual_radius >= 0.0 else radius) / RADIUS
	mesh.position = Vector3.UP * visual_lift
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
	_catch_up_visual(delta)
	var step := minf(speed * delta, max_distance - _travelled)
	var space := get_world_3d().direct_space_state
	var grown := minf(scale.x, 1.0)
	_hit_shape.radius = radius * grown
	_world_shape.radius = (world_radius if world_radius >= 0.0 else radius) * grown
	_update_lift(delta)
	var motion := _direction * step + Vector3.UP * _lift * delta
	# Premier contact (décor ou joueur) : [fraction sans contact, fraction au contact]
	# du déplacement ; 1 = aucun obstacle.
	var first: PhysicsShapeQueryParameters3D = null
	var first_fractions := PackedFloat32Array([1.0, 1.0])
	for query in _queries:
		var lift := visual_lift * grown if query.shape == _hit_shape else 0.0
		query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * lift)
		if _travelled == 0.0:
			# Premier pas : cast_motion ignore ce qui touche déjà la bulle (canon collé à un mur, à un adversaire…).
			query.motion = Vector3.ZERO
			var overlap := space.get_rest_info(query)
			if not overlap.is_empty():
				_on_hit(instance_from_id(overlap.collider_id), overlap)
				return
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions[1] < first_fractions[1]:
			first = query
			first_fractions = fractions
	if first:
		first.transform.origin += motion * first_fractions[1]
		var contact := space.get_rest_info(first)
		global_position += motion * first_fractions[0]
		_on_hit(instance_from_id(contact.collider_id) if not contact.is_empty() else null, contact)
		return
	global_position += motion
	_travelled += step
	if _travelled >= max_distance:
		_pop()


## Dans la colonne d'air chaud d'un sèche-cheveux, la bulle est poussée vers le haut ; une fois
## sortie, cette montée s'amortit en LIFT_DECAY m/s².
func _update_lift(delta: float) -> void:
	var dryers := get_tree().get_nodes_in_group(HairDryer.GROUP)
	# Hors de l'air, la montée s'amortit (LIFT_DECAY) au lieu de tomber : la bulle flotte.
	var lift := HairDryer.lift_projectile(dryers, global_position, _lift, LIFT_DECAY, delta)
	_lift = maxf(lift, 0.0) if lift < _lift else lift


## `contact` : résultat de get_rest_info ({ point, normal… }, vide si inconnu).
func _on_hit(collider: Object, contact: Dictionary) -> void:
	var player := collider as Player
	if player and _deals_damage and (friendly_fire or player.get_team() != _shooter_team):
		_direct_hit = player
		if capture:
			player.capture(capture_duration, _shooter_team)
		else:
			player.take_damage(damage, _shooter_id)
	elif not player and not contact.is_empty() and puddle_radius > 0.0 \
			and (contact.normal as Vector3).y > GROUND_MIN_NORMAL_Y:
		splashed.emit(contact.point, puddle_radius, contact.normal)
	_pop()


## Éclatement : la bulle gonfle et s'efface (avec un son d'éclatement au hasard,
## assets/audio/sfx/bubble_pop.tres), puis le nœud est supprimé une fois le son fini.
func _pop() -> void:
	set_physics_process(false)
	_visual_offset = Vector3.ZERO # Éclate là où elle est vraiment.
	$Mesh.position = Vector3.UP * visual_lift
	if _deals_damage and explosion_radius > 0.0:
		_explode(($Mesh as Node3D).global_position)
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

## Dégâts de l'explosion autour de `center` (ordinateur du tireur seulement, cf. _pop).
func _explode(center: Vector3) -> void:
	var shape := SphereShape3D.new()
	shape.radius = explosion_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = Player.PLAYERS_LAYER
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var player := hit.collider as Player
		if player == null or not player.is_alive() or player.captured or player == _direct_hit \
				or (not friendly_fire and player.get_team() == _shooter_team):
			continue
		var distance := maxf(center.distance_to(player.global_position) - player.get_body_radius(), 0.0)
		var t := clampf(distance / explosion_radius, 0.0, 1.0)
		player.take_damage(lerpf(explosion_damage_max, explosion_damage_min, t), _shooter_id)


## L'image de la bulle rejoint en douceur sa vraie trajectoire (le nœud, lui, est mis à
## l'échelle par la croissance : l'écart est donc divisé par son échelle).
func _catch_up_visual(delta: float) -> void:
	if _visual_offset == Vector3.ZERO:
		return
	_visual_offset *= exp(-VISUAL_CATCH_UP_SPEED * delta)
	if _visual_offset.length() < 0.01:
		_visual_offset = Vector3.ZERO
	$Mesh.position = _visual_offset / maxf(scale.x, 0.01) + Vector3.UP * visual_lift
