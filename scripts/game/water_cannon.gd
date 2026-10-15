class_name WaterCannon
extends Node3D
## Canon à eau (prototype) : jets d'eau continus des joueurs (Player.cannon_on), simulés et
## affichés ici pour tous les joueurs à la fois.
##
## Tant que le canon d'un joueur est actif, des gouttes partent du bout de son canon
## (`drops_per_second`) vers le point visé (Player.cannon_target) : elles sont lancées un peu
## vers le haut pour que leur arc (gravité) retombe sur ce point, comme un tuyau d'arrosage.
## Au-delà de `max_range`, le jet vise le point de la ligne de visée situé à cette distance :
## il part vers le viseur (vers le haut si l'on vise en l'air) et retombe avant, au lieu d'un
## grand tir en cloche qui ignorerait le viseur.
## Chaque goutte a une vitesse un peu différente : les plus lentes tombent avant et arrosent
## le sol le long du jet. Une goutte qui touche le sol y ajoute un peu d'eau (Puddles) : là où
## l'on arrose, une flaque se forme et grandit. Contre un mur, un objet ou un canard, elle
## rejaillit en gouttelettes. Chaque goutte qui touche un adversaire lui inflige
## `damage_per_drop` PV (rien aux coéquipiers).
##
## Affichage : toutes les gouttes dans un seul MultiMeshInstance3D, chacune étirée dans le
## sens de sa vitesse (le jet paraît continu). Pas de nœud par goutte.
##
## Réseau : seuls l'état du canon et le point visé sont envoyés (cf. Player) ; chaque
## ordinateur simule ses gouttes. L'écart et la vitesse de chaque goutte viennent de son
## numéro (pas du hasard), donc le jet est le même partout, à la latence près. Seul
## l'ordinateur du tireur compte les dégâts, regroupés par cible à chaque image (un seul
## Player.take_damage par cible et par image, pas un par goutte).

## Une goutte sur PAINT_EVERY qui touche le sol y peint, avec PAINT_EVERY fois plus d'eau :
## même trace (les gouttes tombent presque au même endroit), peinture bien moins coûteuse.
const PAINT_EVERY := 3
## Une goutte sur SLOW_EVERY part moins vite (cf. min_speed_ratio).
const SLOW_EVERY := 5

## Gouttes émises par seconde et par canon.
@export var drops_per_second := 140.0
## Vitesse de départ (m/s) : celle des gouttes les plus rapides (le cœur du jet).
@export var speed := 20.0
## Les gouttes les plus lentes partent à cette fraction de `speed` : elles retombent avant le
## point visé (le jet se déverse un peu sur le sol).
@export_range(0.0, 1.0) var min_speed_ratio := 0.85
## Écart maximal de direction d'une goutte (radians) : le jet s'évase un peu.
@export var spread := 0.035
## Portée utile du jet (m, à l'horizontale) : jusque-là, l'eau retombe sur le viseur.
@export var max_range := 16.0
## Gravité appliquée aux gouttes (m/s²) : plus fort = le jet retombe plus vite.
@export var gravity := 9.0
## Durée de vie maximale d'une goutte (s).
@export var lifetime := 2.5
## Rayon (m) et quantité d'eau de la tache laissée au sol par une goutte (cf. Puddles).
@export var puddle_radius := 1.3
@export var puddle_amount := 0.2
## Dégâts infligés par chaque goutte qui touche un adversaire (PV).
@export var damage_per_drop := 0.4
## Taille d'une goutte (m) et étirement selon sa vitesse.
@export var drop_size := 0.15
@export var stretch := 0.03

## Gouttes en vol : [position, vitesse, âge, joueur].
var _drops: Array[Array] = []
## Joueur -> gouttes en attente d'émission (fraction) et nombre de gouttes émises.
var _emission := {}
var _multimesh := MultiMesh.new()
## Gouttes tombées au sol, pour n'en peindre qu'une sur PAINT_EVERY.
var _landed := 0
## Dégâts de l'image en cours, par cible (Player -> PV), envoyés en une fois (cf. _deal_damage).
var _pending_damage := {}
var _puddles: Puddles

@onready var _players: Node = get_node(^"../Players")


## Direction de lancement (vitesse `launch_speed`, gravité `g`) pour que l'arc parte de `from`
## et retombe sur `to` : tir tendu (le plus bas des deux arcs possibles). Hors de portée :
## vers le point à 45°, la portée maximale.
static func launch_direction(from: Vector3, to: Vector3, launch_speed: float, g: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var d := flat.length()
	if d < 0.01:
		return (to - from).normalized()
	var h := to.y - from.y
	var v2 := launch_speed * launch_speed
	var root := v2 * v2 - g * (g * d * d + 2.0 * h * v2)
	var angle := PI / 4.0 if root < 0.0 else atan((v2 - sqrt(root)) / (g * d))
	return (flat / d * cos(angle) + Vector3.UP * sin(angle)).normalized()


func _ready() -> void:
	_puddles = get_tree().get_first_node_in_group(Puddles.GROUP) as Puddles
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	# Couleur unie, sans ombrage : les gouttes qui se chevauchent forment un ruban d'eau continu
	# et translucide (ombrées, elles ressemblaient à une file de perles grises).
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.9, 1.0, 0.4)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = mesh
	_multimesh.instance_count = 256
	_multimesh.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.multimesh = _multimesh
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.layers = Puddles.DUCK_VISUAL_LAYER # Les flaques (Decals) ne colorent pas les gouttes.
	add_child(view)


func _physics_process(delta: float) -> void:
	for player: Player in _players.get_children():
		_emit(player, delta)
	_move_drops(delta)
	_deal_damage()
	_draw_drops()


## Nouvelles gouttes du canon de `player` pour cette image.
func _emit(player: Player, delta: float) -> void:
	if not player.cannon_on or not player.is_alive():
		_emission.erase(player)
		return
	var state: Array = _emission.get_or_add(player, [0.0, 0])
	state[0] += drops_per_second * delta
	var origin := player.get_muzzle_position()
	var target := player.cannon_target
	var reach := Vector2(target.x - origin.x, target.z - origin.z).length()
	if reach > max_range: # Trop loin : le point de la ligne de visée à portée utile.
		target = origin + (target - origin) * (max_range / reach)
	var aim := launch_direction(origin, target, speed, gravity)
	var side := aim.cross(Vector3.UP).normalized()
	var up := side.cross(aim).normalized()
	while state[0] >= 1.0:
		state[0] -= 1.0
		state[1] += 1
		# Écart et vitesse déterministes (mêmes gouttes sur tous les ordinateurs) : suites
		# pseudo-aléatoires bien réparties (angle d'or, nombre d'or).
		var n: int = state[1]
		var a := fmod(n * 2.399963, TAU)
		var r := spread * sqrt(fmod(n * 0.618034, 1.0))
		var direction := (aim + side * cos(a) * r + up * sin(a) * r).normalized()
		# Le cœur du jet va au point visé ; une goutte sur SLOW_EVERY, plus lente, retombe un
		# peu avant (le bout du jet se disperse).
		var slow := fmod(n * 0.754878, 1.0) if n % SLOW_EVERY == 0 else 0.0
		var velocity := direction * speed * lerpf(1.0, min_speed_ratio, slow)
		# Étale les gouttes de l'image le long du jet (sinon elles partent en paquets).
		var head_start: float = state[0] / drops_per_second
		_drops.append([origin + velocity * head_start, velocity, head_start, player])


func _move_drops(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var mask := Player.WORLD_LAYER | Player.PLAYERS_LAYER
	var alive: Array[Array] = []
	for drop in _drops:
		var position: Vector3 = drop[0]
		var velocity: Vector3 = drop[1]
		var shooter: Player = drop[3]
		velocity.y -= gravity * delta
		var next := position + velocity * delta
		drop[2] += delta
		var exclude: Array[RID] = []
		if is_instance_valid(shooter):
			exclude.append(shooter.get_rid()) # Le jet ne touche pas le tireur.
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(position, next, mask, exclude))
		if not hit.is_empty():
			_on_drop_hit(hit, shooter)
			continue
		if drop[2] > lifetime:
			continue
		drop[0] = next
		drop[1] = velocity
		alive.append(drop)
	_drops = alive


## Une goutte touche quelque chose : sur le sol, elle ajoute un peu d'eau ; ailleurs (mur,
## objet, canard), elle rejaillit. Un adversaire touché perd damage_per_drop PV (compté
## seulement sur l'ordinateur du tireur, comme les bulles).
func _on_drop_hit(hit: Dictionary, shooter: Player) -> void:
	var target := hit.collider as Player
	if target and is_instance_valid(shooter) and shooter.is_multiplayer_authority() and target.is_alive() 			and target.get_team() != shooter.get_team():
		_pending_damage[target] = _pending_damage.get(target, 0.0) + damage_per_drop
	if _puddles == null:
		return
	var normal: Vector3 = hit.normal
	if hit.collider is not Player and normal.y > BubbleProjectile.GROUND_MIN_NORMAL_Y:
		_landed += 1
		if _landed % PAINT_EVERY == 0:
			_puddles.add_puddle(hit.position, puddle_radius, puddle_amount * PAINT_EVERY, false, normal)
	_puddles.drip(hit.position, normal)


## Envoie les dégâts de l'image : un seul take_damage par cible.
func _deal_damage() -> void:
	for target: Player in _pending_damage:
		if is_instance_valid(target):
			target.take_damage(_pending_damage[target])
	_pending_damage.clear()


func _draw_drops() -> void:
	if _drops.size() > _multimesh.instance_count:
		_multimesh.instance_count = _drops.size() * 2 # Toujours de la place d'avance.
	_multimesh.visible_instance_count = _drops.size()
	for i in _drops.size():
		var position: Vector3 = _drops[i][0]
		var velocity: Vector3 = _drops[i][1]
		var length := drop_size + velocity.length() * stretch
		# Goutte étirée dans le sens de sa vitesse.
		var forward := velocity.normalized()
		var side := forward.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(forward)
		var basis := Basis(side * drop_size, up * drop_size, -forward * length)
		_multimesh.set_instance_transform(i, Transform3D(basis, position))
