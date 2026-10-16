@tool
class_name Player
extends CharacterBody3D
## Joueur (canard, modèle assets/models/duck_v4.glb, textures dans assets/materials).
## L'équipe (et donc la couleur du réservoir d'eau sur le dos) dépend de `player_id` :
## joueurs 1-2 = équipe bleue, joueurs 3-4 = équipe rouge.
##
## En réseau, l'ordinateur qui a l'autorité sur ce nœud simule le cube et
## diffuse `sync_position` (nœud Sync) ; les autres ordinateurs lissent le
## cube vers cette position.
##
## Vie : `health` (diffusée par l'ordinateur qui a l'autorité). Dégâts via
## take_damage() (depuis n'importe quel ordinateur, avec le joueur qui a tiré : à la mort,
## eliminated est émis partout avec lui, pour le fil des éliminations) ; sans dégâts pendant
## `regen_delay` s, la vie remonte de `regen_rate` PV/s. À 0 PV, le canard joue
## l'animation de mort (sur le dos, pattes en l'air), disparaît dans un pop de bulle, puis
## réapparaît à son point de départ `respawn_delay` s après sa mort.
##
## Sons (nœuds *Sound, joués sur tous les ordinateurs) : tir, pas calés sur
## l'animation (cf. FOOTSTEPS), dash, saut, touché, mort et réapparition.
##
## Réserve d'eau (`water`, de 0 à 1, propre à l'ordinateur qui contrôle le canard) : un tir
## en coûte `water_per_shot`, la grosse bulle `water_per_capture`, le jet `water_per_second`
## en continu. Sans assez d'eau, rien ne part (signal water_denied : la jauge clignote).
## Après `water_recharge_delay` s sans dépenser d'eau, elle se recharge de plus en plus vite
## (la vitesse double toutes les `water_recharge_doubling` s).
##
## Canon à eau (prototype) : tant que l'action water_cannon (clic droit) est maintenue, le canard
## arrose en continu vers le point visé (cannon_on, cannon_target ; gouttes simulées par WaterCannon).
##
## Capture : l'action capture (clic molette) tire une grosse bulle (toutes les
## `capture_cooldown` s). Un adversaire touché est piégé (capture()) : enfermé dans une
## bulle à la couleur de l'équipe qui l'a eu, il décolle de `capture_lift` m puis
## s'élève lentement de `capture_rise` m pendant toute la durée de la bulle (2 s), sans
## pouvoir bouger, sauter, dasher ni tirer. Il peut toujours prendre des dégâts.
##
## Plastron (`dummy`) : canard d'entraînement, sans équipe (get_team() = 0, réservoir gris) :
## adversaire de tout le monde, il ne bouge pas, encaisse les tirs, se fait capturer et
## réapparaît où il a été posé. Contrôlé par l'hôte, il ne compte pas dans les zones.

## Émis sur tous les ordinateurs quand la vie change / à la mort / à la réapparition.
signal health_changed(health: float)
signal died
## Émis sur tous les ordinateurs quand ce joueur est éliminé : `killer_id` = joueur (1 à 4)
## qui l'a éclaté, 0 sans tireur (chute hors de l'arène).
signal eliminated(killer_id: int)
signal respawned
## Émis sur tous les ordinateurs quand ce joueur tire (Game crée la bulle ;
## `capture` : bulle de capture ; `visual_origin` : bout du canon, d'où la bulle semble partir).
signal shot(origin: Vector3, direction: Vector3, capture: bool, visual_origin: Vector3)
## Émis (ordinateur du joueur) quand un tir est refusé faute d'eau.
signal water_denied

## Couleur de chaque équipe (index 0 = équipe 1).
const TEAM_COLORS: Array[Color] = [
	Color("3b82f6"), # Équipe 1 : bleue
	Color("e5484d"), # Équipe 2 : rouge
]
const TEAM_NAMES: Array[String] = ["bleue", "rouge"]
## Pseudo au-dessus du canard (cf. update_name_tag) : hauteur au-dessus du centre du canard (m),
## taille du texte et police.
const NAME_TAG_HEIGHT := 1.6
const NAME_TAG_FONT_SIZE := 64
const NAME_TAG_PIXEL_SIZE := 0.005
const NAME_TAG_FONT := preload("res://assets/fonts/titan_one/TitanOne-Regular.ttf")
## Durée (s) d'apparition / disparition du pseudo quand le canard devient visible / caché.
const NAME_TAG_FADE := 0.15
## Points du canard (par rapport à son centre) vers lesquels on regarde depuis la caméra : le
## pseudo s'affiche si l'un d'eux n'est pas caché par le décor (tête, corps, pieds, et les
## côtés du corps vus depuis la caméra, à NAME_TAG_SIGHT_SIDE m).
const NAME_TAG_SIGHT_POINTS: Array[Vector3] = [Vector3(0, 0.8, 0), Vector3.ZERO, Vector3(0, -0.8, 0)]
const NAME_TAG_SIGHT_SIDE := 0.65
## Calques physiques des murs invisibles des zones d'apparition (ZoneSpawn) :
## calque 3 « spawn_blue » (valeur 4), calque 4 « spawn_red » (valeur 8). Un joueur
## (et ses bulles) est bloqué par la zone d'apparition de l'équipe adverse.
const WORLD_LAYER := 1
## Groupe des surfaces d'eau profonde (baignoire, toilettes, cf. arena5.gd) : le canard y marche
## un peu enfoncé, c'est de l'eau (dash qui glisse, pas mouillés) et il en sort d'un grand saut.
const DEEP_WATER_GROUP := &"eau_profonde"
const PLAYERS_LAYER := 2
const SPAWN_LAYERS: Array[int] = [4, 8]
## Vitesse de rattrapage des cubes distants (plus élevé = plus réactif, moins lisse).
const REMOTE_SMOOTHING := 25.0
## Au-delà de cet écart, un cube distant est téléporté (ex. réapparition).
## Animations du canard (machine à états du nœud AnimationTree, transitions et fondus
## réglables dans l'éditeur). Le script ne fait que renseigner ses conditions :
## idle à l'arrêt, walk en dessous de RUN_SPEED (m/s), run au-delà ; dashing pendant
## le dash (dash_start → dash), dash_over ensuite (dash → dash_end).
## L'état walk mélange walk / walk_back / walk_left / walk_right (BlendSpace2D) selon
## la direction du déplacement vue par le canard : en posture de combat (il regarde là
## où il vise), il recule ou marche de côté, et reste dans walk même au-delà de RUN_SPEED.
const MOVING_SPEED := 0.3
const RUN_SPEED := 4.0
## Vitesse à laquelle le canard se tourne vers sa direction de déplacement.
const TURN_SPEED := 14.0
## Vitesse à laquelle le mélange des marches (avant, arrière, côtés) suit la direction.
const STRAFE_BLEND_SPEED := 10.0
## Posture de combat : vitesse à laquelle il se tourne vers sa visée (demi-tour en ~0,1 s).
const AIM_TURN_SPEED := 30.0
## Courbe du dash (fractions de dash_duration) : fin de la montée en vitesse,
## début du ralentissement.
const DASH_RAMP := 0.15
const DASH_SLOWDOWN_START := 0.3
## Portée de la visée (m) : au-delà, on vise un point à cette distance.
const AIM_DISTANCE := 80.0
## Mesh du pistolet dans le modèle (les bulles partent du bout de son canon).
const GUN_MESH := "Gun"
## Matériaux texturés des meshes du modèle. Le réservoir, le tuyau et la ceinture
## partagent la texture « container », à la couleur de l'équipe (index 0 = équipe 1).
const MESH_MATERIALS := {
	&"Duck_body": preload("res://assets/materials/duck_body.tres"),
	&"Gun": preload("res://assets/materials/duck_gun.tres"),
}
const TEAM_COLORED_MESHES: Array[StringName] = [&"Water_Container", &"Tube", &"Belt"]
const TEAM_MATERIALS: Array[Material] = [
	preload("res://assets/materials/duck_container_blue.tres"),
	preload("res://assets/materials/duck_container_red.tres"),
]
const DUMMY_MATERIAL := preload("res://assets/materials/duck_container_dummy.tres")
## Couleur du plastron (pseudo, fil des éliminations), et son nom.
const DUMMY_COLOR := Color(0.62, 0.64, 0.68)
const DUMMY_NAME := "Plastron"
const REMOTE_SNAP_DISTANCE := 3.0
## Montée des marches : en dessous de cette hauteur (m), la capsule passe d'elle-même.
const STEP_MIN_HEIGHT := 0.01
## Vitesse à laquelle le modèle et la caméra rattrapent une marche montée d'un coup.
const STEP_SMOOTHING := 18.0
## Mort : le canard joue l'animation « death » (il bascule sur le dos, pattes en l'air), retombe
## au sol s'il était en l'air (DEATH_FALL_TIME s, jusqu'à DEATH_FLOOR_SEARCH m plus bas), puis
## disparaît dans un pop de bulle (DEATH_POP_TIME s) juste avant de réapparaître.
const DEATH_FALL_TIME := 0.35
const DEATH_FLOOR_SEARCH := 8.0
const DEATH_POP_TIME := 0.18
const DEATH_POP_SOUND := preload("res://assets/audio/sfx/bubble_pop.tres")
## Bruits de pas : instants (fractions de l'animation) où un pied se pose, relevés sur
## les pistes foot_ik_L / foot_ik_R de walk et run (assets/models/duck_v4.glb).
const FOOTSTEPS := {
	&"walk": [0.49, 0.98],
	&"run": [0.47, 0.95],
}
## Hauteur minimale du départ des bulles au-dessus des pieds (m), cf. get_muzzle_position.
const MIN_MUZZLE_HEIGHT := 0.6825
## Vitesse de chute (m/s) au-delà de laquelle toucher le sol fait le son d'atterrissage
## (après un saut : ~8,5 m/s ; les marches montées ou descendues en marchant n'en font pas).
const LAND_SOUND_MIN_SPEED := 4.0
## Canon à eau : intervalle (s) entre deux envois du point visé aux autres ordinateurs.
const CANNON_AIM_SYNC_INTERVAL := 0.066
## Canon à eau : un appui plus court que ça (s) est un « simple appui » (cf. cannon_tap_duration).
const CANNON_TAP_TIME := 0.2
## Sillage sur l'eau pendant une glissade : un rond et une gerbe toutes les WAKE_INTERVAL s.
const WAKE_INTERVAL := 0.035
## Capture : vitesse à laquelle il rejoint sa hauteur de lévitation, vitesse du flottement.
const CAPTURE_RISE_SPEED := 10.0
const CAPTURE_BOB_SPEED := 4.0
## Marge (m) au-dessus des pieds pour chercher un plafond pendant la montée (cf. _simulate_captured).
const CAPTURE_CEILING_TEST := 0.02

@export_range(1, 4) var player_id := 1:
	set(value):
		player_id = value
		_apply_color()
## Plastron (canard d'entraînement sans équipe), cf. en-tête.
@export var dummy := false:
	set(value):
		dummy = value
		_apply_color()

@export var move_speed := 6.0
## Élevée = réponse quasi instantanée au stick / aux touches.
@export var acceleration := 90.0
@export var jump_velocity := 8.5
## Saut depuis l'eau profonde (cf. DEEP_WATER_GROUP) : assez haut (~4,4 m) pour passer le bord de
## la baignoire (3,2 m au-dessus de l'eau) ou des toilettes.
@export var water_jump_velocity := 12.5
## Multiplicateur de la gravité du projet (plus élevé = saut moins flottant).
@export var gravity_scale := 1.8
## Hauteur maximale d'un relief (marche, rebord…) que le canard monte en marchant, sans sauter (m).
@export var max_step_height := 0.55
## Vitesse de montée aux échelles (m/s). Une échelle = Area3D du groupe "echelles",
## son axe -Z local pointe vers le mur : avancer dans ce sens fait monter.
@export var climb_speed := 3.0
@export_group("Dash")
## Vitesse de pointe du dash (m/s).
@export var dash_speed := 25.0
## Durée du dash (s). Courbe de vitesse : montée douce jusqu'à dash_speed
## (DASH_RAMP), plateau, puis ralentissement doux jusqu'à move_speed.
## Distance ≈ 10 m avec les valeurs par défaut. Si on la change, ajuster aussi la durée
## de dash_start dans l'AnimationTree (timeline de son nœud, la moitié de dash_duration).
@export var dash_duration := 0.6
## Temps minimum entre deux dashs (s).
@export var dash_cooldown := 2.0
## Sur l'eau (flaques), le dash ne s'use pas : il garde sa vitesse tant que le canard glisse
## sur la flaque, et la distance du dash ne compte que sur le sol sec.
@export var dash_slides_on_water := true
## Pendant le dash, gauche / droite le font tourner (radians par seconde) ; avant / arrière
## n'ont pas d'effet (ni accélérer ni freiner).
@export var dash_steer_speed := 1.75
## Pendant le dash, le canard reste collé au sol jusqu'à cette distance (m) : en descente
## rapide, il suit la pente au lieu de s'envoler tout droit (hors dash : floor_snap_length).
@export var dash_floor_snap := 0.6
@export_group("Tir")
## Temps minimum entre deux appuis sur la touche de tir (s).
@export var fire_cooldown := 0.15
## Touche de tir maintenue : une bulle toutes les `auto_fire_interval` s.
@export var auto_fire_interval := 0.2
## Posture de combat : pendant la visée (action aim) et cette durée (s) après le
## dernier tir, le canard reste tourné vers sa visée, même s'il recule.
@export var combat_stance_duration := 0.6
@export_group("Capture")
## Temps minimum entre deux bulles de capture (s).
@export var capture_cooldown := 1.0
## Hauteur à laquelle décolle un joueur capturé, au-dessus du sol (m).
@export var capture_lift := 0.25
## Hauteur qu'il prend ensuite, lentement, pendant toute la capture (m).
@export var capture_rise := 1.0
## Amplitude du flottement d'un joueur capturé (m).
@export var capture_bob := 0.05
@export_group("Eau")
## Eau dépensée (fraction de la réserve) par un tir, une grosse bulle, et par seconde de jet.
@export var water_per_shot := 0.05
@export var water_per_capture := 0.2
@export var water_per_second := 0.2
## Simple appui sur le jet d'eau : le jet part devant le canard et balaie le sol en ligne droite
## (de 1,5 m à cannon_tap_range m, en cannon_tap_duration s), pour laisser une trace sur laquelle
## dasher. Maintenu, le jet vise le viseur comme d'habitude.
@export var cannon_tap_duration := 0.6
@export var cannon_tap_range := 14.0
## Temps sans dépenser d'eau avant que la réserve se recharge (s).
@export var water_recharge_delay := 2.0
## Recharge : vitesse au départ (fraction par seconde), qui double toutes les
## `water_recharge_doubling` s, jusqu'à `water_recharge_max_rate`.
@export var water_recharge_rate := 0.08
@export var water_recharge_doubling := 0.6
@export var water_recharge_max_rate := 0.9
@export_group("Vie")
@export var max_health := 100.0
## Piégé dans une bulle de capture, le canard ne prend que cette fraction des dégâts : arrosé de
## bulles sans arrêt dès sa capture (à 6 à 10 m), il meurt tout juste à la fin de la bulle (2 s) ;
## au jet d'eau, il survit de justesse (mesuré : 270 à 300 PV de bulles, 220 à 240 PV de jet
## pendant les 2 s, sans réduction).
@export var captured_damage_scale := 0.37
## Vie regagnée par seconde (PV/s) quand le joueur ne prend pas de dégâts.
@export var regen_rate := 10.0
## Temps sans dégâts avant que la vie commence à remonter (s).
@export var regen_delay := 2.0
## Temps entre la mort et la réapparition (s).
@export var respawn_delay := 2.0
## En dessous de cette hauteur, le joueur meurt (chute hors de l'arène).
@export var kill_height := -10.0
@export_group("")

## Vrai si ce cube est piloté par les entrées de cet ordinateur.
var is_local := false
## Pseudo du joueur, au-dessus du canard (créé dans _ready).
var _name_tag: Label3D
## Vrai si le pseudo doit s'afficher (cf. update_name_tag), quand le canard est en vue.
var _name_tag_wanted := false
var _name_tag_alpha := 0.0
## Nom affiché à la place du pseudo s'il n'est pas vide (canard que personne ne contrôle,
## cf. get_display_name).
var display_name_override := ""
## Faux tant que la partie n'a pas commencé : le cube reste figé.
var active := false
## Position diffusée sur le réseau par l'ordinateur qui contrôle ce cube.
var sync_position: Vector3
## Points de vie (0 = mort). Diffusé par le nœud Sync quand il change.
var health := 100.0:
	set(value):
		var previous := health
		var was_alive := health > 0.0
		health = value
		health_changed.emit(health)
		if was_alive and health <= 0.0:
			_on_died()
		elif not was_alive and health > 0.0:
			_on_respawned()
		elif health < previous and _hit_sound and not _hit_sound.playing:
			# Touché (sur tous les ordinateurs : la vie est diffusée). Pas relancé s'il joue déjà :
			# le jet d'eau inflige des dégâts à chaque image.
			_hit_sound.play()
## Posture de combat : direction horizontale (x, z) que regarde le canard pendant qu'il
## vise ou tire ; Vector2.ZERO sinon (il regarde alors là où il va). Diffusée par le nœud Sync.
var sync_facing := Vector2.ZERO
## Vrai pendant qu'il est piégé dans une bulle de capture (sur tous les ordinateurs).
var captured := false
## Réserve d'eau, de 0 (vide) à 1 (pleine) ; tenue par l'ordinateur qui contrôle le canard.
var water := 1.0
## Canon à eau en marche, et point visé par le jet (sur tous les ordinateurs, cf. WaterCannon).
var cannon_on := false
var cannon_target := Vector3.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_position: Vector3
## Temps restant de la posture de combat (s).
var _combat_left := 0.0
## Temps restant du dash en cours (s), 0 si pas de dash.
var _dash_time := 0.0
## Temps restant avant de pouvoir dasher à nouveau (s).
var _dash_cooldown_left := 0.0
var _dash_direction: Vector3
## Vitesse horizontale au moment du dash (point de départ de la courbe).
var _dash_start_speed := 0.0
## Temps restant du dash pour ses animations (condition « dashing »), décompté sur
## tous les ordinateurs (cf. _play_dash).
var _dash_animation_left := 0.0
## Éclaboussures de savon de chaque côté du canard pendant le dash (cf. _create_dash_splash),
## tournées comme le modèle.
var _dash_splash: Node3D
## Direction du déplacement vue par le canard (x : droite, y : avant), pour l'état walk.
var _strafe := Vector2(0, 1)
## Bout du canon (Marker3D créé dans _ready sur le mesh du pistolet) : départ des bulles.
var _muzzle: Marker3D
## Temps écoulé depuis le dernier tir (s).
var _since_last_shot := INF
## Temps restant avant que la vie remonte (s).
var _regen_cooldown_left := 0.0
## Temps restant avant la réapparition, quand le joueur est mort (s).
var _respawn_left := 0.0
## Décalage vertical du modèle et de la caméra après une marche montée d'un coup,
## ramené en douceur à 0 (cf. _step_up).
var _step_offset := 0.0
## Mort : descente du modèle jusqu'au sol (m, négatif) et animation de la mort en cours.
var _death_drop := 0.0
var _death_tween: Tween
var _model_base_y: float
var _model_base_scale: Vector3
var _camera_base_y: float
## Animation et position (fraction) à l'image précédente, pour les bruits de pas.
var _footstep_animation: StringName
var _footstep_phase := 0.0
## Flaques de la partie (Puddles), cherchées au premier besoin ; null hors d'une partie.
var _puddles: Puddles
## Temps restant avant le prochain rond du sillage (s).
var _wake_left := 0.0
## Temps restant avant le prochain envoi de cannon_target (s).
var _cannon_sync_left := 0.0
## Jet d'un simple appui : temps écoulé depuis l'appui (-1 hors balayage), départ (pieds) et
## direction (horizontale) de la trace.
var _cannon_tap_elapsed := -1.0
var _cannon_tap_origin := Vector3.ZERO
var _cannon_tap_forward := Vector3.FORWARD
## floor_snap_length hors dash (celui de la scène), cf. dash_floor_snap.
var _floor_snap_default := 0.1
## Temps depuis la dernière dépense d'eau (s), pour la recharge.
var _water_idle := INF
## Temps restant avant de pouvoir tirer une bulle de capture (s).
var _capture_cooldown_left := 0.0
## Capture en cours (ordinateur qui a l'autorité) : temps restant (s), hauteur de
## décollage, durée totale et temps écoulé (s).
var _captured_left := 0.0
var _capture_height := 0.0
var _capture_duration := 0.0
var _capture_time := 0.0
var _capture_tween: Tween
## Tunnel en cours (ordinateur qui a l'autorité seulement) : tuyau parcouru, distance (m)
## depuis son entrée et sens (true : parcouru de l'extrémité d'arrivée vers le départ).
var _tunnel: WaterTunnel
var _tunnel_offset := 0.0
var _tunnel_reverse := false
## Point au sol où il reprend la main à la sortie (cf. _tunnel_landing_spot), cherché une
## fois sorti du tuyau.
var _tunnel_landing := Vector3.ZERO
var _tunnel_landing_found := false
## Vrai pendant la traversée d'un tunnel, sur tous les ordinateurs (cf. _set_tunnel) : garde
## la pose du dash tout le trajet (variable, contrairement à un dash normal) et resserre la
## caméra locale (cf. PlayerCamera.tunnel_mode).
var _in_tunnel := false

## Caméra du joueur : les déplacements sont relatifs à son orientation.
@onready var camera: PlayerCamera = $PlayerCamera
## Aide à la visée (déplace le viseur vers un adversaire proche du centre de l'écran).
@onready var aim_assist: AimAssist = $AimAssist
@onready var _model: Node3D = $Model
@onready var _animation_tree: AnimationTree = $AnimationTree
@onready var _animation_playback: AnimationNodeStateMachinePlayback = _animation_tree.get(&"parameters/playback")
@onready var _collision_shape: CollisionShape3D = $CollisionShape
@onready var _sync: MultiplayerSynchronizer = $Sync
## Son du tir : un son de bulle au hasard (assets/audio/sfx/bubble_shoot.tres).
@onready var _shoot_sound: AudioStreamPlayer3D = $ShootSound
## Autres sons du canard, chacun tiré au hasard dans assets/audio/sfx/duck_*.tres.
@onready var _step_sound: AudioStreamPlayer3D = $StepSound
## Pas dans l'eau : « splotch » au lieu du bruit de pas.
@onready var _water_step_sound: AudioStreamPlayer3D = $WaterStepSound
@onready var _dash_sound: AudioStreamPlayer3D = $DashSound
@onready var _jump_sound: AudioStreamPlayer3D = $JumpSound
@onready var _land_sound: AudioStreamPlayer3D = $LandSound
@onready var _hit_sound: AudioStreamPlayer3D = $HitSound
@onready var _death_sound: AudioStreamPlayer3D = $DeathSound
@onready var _respawn_sound: AudioStreamPlayer3D = $RespawnSound
## Capture : bulle autour du canard piégé et ses sons (tir, piégé, libéré).
@onready var _capture_bubble: MeshInstance3D = $CaptureBubble
@onready var _capture_shoot_sound: AudioStreamPlayer3D = $CaptureShootSound
@onready var _capture_sound: AudioStreamPlayer3D = $CaptureSound
@onready var _release_sound: AudioStreamPlayer3D = $ReleaseSound


## Équipe (1 ou 2) du joueur `id`.
static func team_of(id: int) -> int:
	return 1 if id <= 2 else 2


## Équipe de ce canard : celle de `player_id`, 0 pour un plastron (adversaire de tous).
func get_team() -> int:
	return 0 if dummy else team_of(player_id)


## Couleur de ce canard : celle de son équipe, gris pour un plastron.
func get_team_color() -> Color:
	return DUMMY_COLOR if dummy else TEAM_COLORS[team_of(player_id) - 1]


static func color_of(id: int) -> Color:
	return TEAM_COLORS[team_of(id) - 1]


## Calque de la zone d'apparition adverse de l'équipe `team`.
static func enemy_spawn_layer(team: int) -> int:
	return SPAWN_LAYERS[2 - team]


func _ready() -> void:
	_apply_color()
	if not Engine.is_editor_hint():
		_create_muzzle()
		_create_name_tag()
		_create_dash_splash()
	# L'éditeur enregistre parfois les triangles du mélange des marches avant ses points :
	# ils sont alors ignorés au chargement et la marche reste figée. On les recalcule.
	var walk_space := (_animation_tree.tree_root as AnimationNodeStateMachine).get_node(&"walk") as AnimationNodeBlendSpace2D
	if walk_space and walk_space.get_triangle_count() == 0:
		walk_space.auto_triangles = false
		walk_space.auto_triangles = true
	_model_base_y = _model.position.y
	_model_base_scale = _model.scale
	_floor_snap_default = floor_snap_length
	_camera_base_y = camera.position.y
	_spawn_position = global_position
	sync_position = position
	health = max_health


func activate() -> void:
	active = true
	_sync.public_visibility = true


## Fin du combat : le cube s'arrête et ne répond plus aux commandes.
func freeze() -> void:
	active = false
	velocity = Vector3.ZERO
	cannon_on = false


## Affiche le pseudo (get_display_name, « Joueur N » sans pseudo choisi) au-dessus du canard :
## sur les canards des autres joueurs (pas le sien), vivants, et en vue
## (cf. _update_name_tag_visibility).
## Appelé par Game quand les choix des joueurs changent, et à la mort / réapparition.
func update_name_tag() -> void:
	if _name_tag == null:
		return
	_name_tag.text = get_display_name()
	_name_tag.outline_modulate = get_team_color().darkened(0.35)
	_name_tag_wanted = not is_local and is_alive()


## Le pseudo est dessiné par-dessus tout (même l'air chaud ou l'eau, transparents, qui le
## masquaient) : il ne s'affiche donc que si le canard est au moins en partie visible depuis la
## caméra de cet ordinateur (sinon on verrait le pseudo d'un canard caché derrière un mur).
func _update_name_tag_visibility(delta: float) -> void:
	if _name_tag == null:
		return
	var seen := false
	if _name_tag_wanted:
		var camera_3d := get_viewport().get_camera_3d()
		seen = camera_3d != null and _is_seen_from(camera_3d.global_position)
	_name_tag_alpha = move_toward(_name_tag_alpha, 1.0 if seen else 0.0, delta / NAME_TAG_FADE)
	_name_tag.visible = _name_tag_alpha > 0.0
	_name_tag.modulate.a = _name_tag_alpha
	_name_tag.outline_modulate.a = _name_tag_alpha


## Vrai si l'un des NAME_TAG_SIGHT_POINTS du canard n'est pas caché par le décor depuis `eye`.
func _is_seen_from(eye: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var side := (global_position - eye).cross(Vector3.UP).normalized() * NAME_TAG_SIGHT_SIDE
	for point: Vector3 in NAME_TAG_SIGHT_POINTS + [side, -side]:
		var query := PhysicsRayQueryParameters3D.create(eye, global_position + point, WORLD_LAYER, [get_rid()])
		if space.intersect_ray(query).is_empty():
			return true
	return false


func _create_name_tag() -> void:
	_name_tag = Label3D.new()
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.font = NAME_TAG_FONT
	_name_tag.font_size = NAME_TAG_FONT_SIZE
	_name_tag.pixel_size = NAME_TAG_PIXEL_SIZE
	_name_tag.outline_size = 14
	_name_tag.modulate = Color.WHITE
	# Dessiné en dernier, par-dessus tout (cf. _update_name_tag_visibility).
	_name_tag.no_depth_test = true
	_name_tag.render_priority = 127
	_name_tag.outline_render_priority = 126
	_name_tag.position.y = NAME_TAG_HEIGHT
	_name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_name_tag.layers = Puddles.DUCK_VISUAL_LAYER # Les flaques (Decals) ne le colorent pas.
	_name_tag.visible = false
	add_child(_name_tag)


## Bout du canon, une fois le canard tourné vers sa visée (départ des bulles et du jet d'eau),
## jamais à moins de MIN_MUZZLE_HEIGHT au-dessus des pieds : en marchant ou en courant,
## l'animation balance le pistolet jusqu'à 0,2 m du sol, et une bulle partie si bas raclerait
## le sol (rayon de contact 0,3 m) et éclaterait au hasard.
func get_muzzle_position() -> Vector3:
	if _muzzle == null:
		return global_position
	# Le canard n'a peut-être pas fini de se tourner vers sa visée.
	var turn := atan2(sync_facing.x, sync_facing.y) - _model.rotation.y
	var muzzle := global_position + (_muzzle.global_position - global_position).rotated(Vector3.UP, turn)
	muzzle.y = maxf(muzzle.y, _feet_position().y + MIN_MUZZLE_HEIGHT)
	return muzzle


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not active:
		_update_model(Vector3.ZERO, delta)
		_update_name_tag_visibility(delta)
		return
	var previous_position := position
	if is_multiplayer_authority():
		if is_alive():
			if _tunnel:
				_simulate_tunnel(delta)
			elif _captured_left > 0.0:
				_simulate_captured(delta)
			else:
				_simulate(delta)
			_regenerate(delta)
		else:
			_respawn_left -= delta
			if _respawn_left <= 0.0:
				respawn()
		sync_position = position
	else:
		_follow_network(delta)
	# Vitesse réelle (aussi pour les canards des autres ordinateurs, qui ne reçoivent que la position).
	_update_model((position - previous_position) / delta, delta)
	_update_name_tag_visibility(delta)


## Oriente la caméra et le canard vers `point` (sur le plan horizontal).
func face(point: Vector3) -> void:
	camera.face(point)
	_turn_model_towards(Vector3.FORWARD.rotated(Vector3.UP, camera.get_yaw()), 1.0)


## Définit le point d'apparition (et y place le joueur), cf. ZoneSpawn.
func set_spawn_position(point: Vector3) -> void:
	_spawn_position = point
	global_position = point
	sync_position = position
	reset_physics_interpolation()


func is_alive() -> bool:
	return health > 0.0


## Inflige `amount` PV de dégâts, de la part du joueur `attacker_id` (0 = personne).
## Appelable depuis n'importe quel ordinateur : les dégâts sont appliqués par celui qui a
## l'autorité sur ce cube.
func take_damage(amount: float, attacker_id := 0) -> void:
	if is_multiplayer_authority():
		_apply_damage(amount, attacker_id)
	else:
		_apply_damage.rpc_id(get_multiplayer_authority(), amount, attacker_id)


## Pseudo affiché pour ce joueur (au-dessus du canard, fil des éliminations).
func get_display_name() -> String:
	if not display_name_override.is_empty():
		return display_name_override
	# Le plastron réutilise la scène du joueur 1 : pas le pseudo de ce joueur.
	return DUMMY_NAME if dummy else NetworkManager.get_player_name(player_id)


## Piège ce joueur `duration` s dans une bulle de capture de l'équipe `team`.
## Appelable depuis n'importe quel ordinateur (comme take_damage).
func capture(duration: float, team: int) -> void:
	if is_multiplayer_authority():
		_apply_capture(duration, team)
	else:
		_apply_capture.rpc_id(get_multiplayer_authority(), duration, team)


## Fait entrer ce joueur dans `tunnel` (dash automatique jusqu'à l'autre bout, cf. WaterTunnel) ;
## `reverse` : true s'il y entre par l'extrémité d'arrivée (il le parcourt donc à l'envers).
## Appelable depuis n'importe quel ordinateur (comme take_damage).
func enter_tunnel(tunnel: WaterTunnel, reverse: bool) -> void:
	if is_multiplayer_authority():
		_apply_tunnel(tunnel.get_path(), reverse)
	else:
		_apply_tunnel.rpc_id(get_multiplayer_authority(), tunnel.get_path(), reverse)


## Réapparition au point de départ, avec toute sa vie.
func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_dash_time = 0.0
	_step_offset = 0.0
	_combat_left = 0.0
	_capture_cooldown_left = 0.0
	sync_facing = Vector2.ZERO
	_regen_cooldown_left = 0.0
	water = 1.0
	_water_idle = INF
	health = max_health
	reset_physics_interpolation()


func _simulate(delta: float) -> void:
	var input := Vector2.ZERO
	if is_local:
		input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if Input.is_action_just_pressed(&"jump") and is_on_floor():
			# Sur le socle d'un sèche-cheveux : le saut devient un envol (cf. HairDryer).
			var dryer := HairDryer.under(get_tree(), _feet_position())
			if dryer:
				velocity.y = dryer.launch_speed
				_play_updraft.rpc()
			else:
				velocity.y = water_jump_velocity if is_in_deep_water() else jump_velocity
				_play_jump.rpc()
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera.get_yaw())

	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_capture_cooldown_left = maxf(_capture_cooldown_left - delta, 0.0)
	if is_local and Input.is_action_just_pressed(&"dash") and is_on_floor() and _dash_cooldown_left == 0.0:
		_start_dash(direction)

	# Petite marge : sans elle, 12 pas de 1/60 s font 0,19999… < 0,2 s (arrondis) et le tir prend une image de retard.
	_since_last_shot += delta + 0.0001
	# Nouvel appui : tir dès fire_cooldown écoulé ; touche maintenue : toutes les auto_fire_interval.
	var pressed := Input.is_action_just_pressed(&"shoot") and _since_last_shot >= fire_cooldown
	var held := Input.is_action_pressed(&"shoot") and _since_last_shot >= auto_fire_interval
	var capture_pressed := Input.is_action_just_pressed(&"capture") and _capture_cooldown_left == 0.0
	var cannon := is_local and Input.is_action_pressed(&"water_cannon")
	if is_local:
		cannon = _update_cannon_tap(cannon, delta)
	# Réserve d'eau : sans assez d'eau, rien ne part (et la jauge clignote au nouvel appui).
	_recharge_water(delta)
	if is_local and (pressed or held) and water < water_per_shot:
		if pressed:
			water_denied.emit()
		pressed = false
		held = false
	if is_local and capture_pressed and water < water_per_capture:
		water_denied.emit()
		capture_pressed = false
	if cannon and water <= 0.0:
		if Input.is_action_just_pressed(&"water_cannon"):
			water_denied.emit()
		cannon = false
	_combat_left = maxf(_combat_left - delta, 0.0)
	if is_local and (camera.aiming or pressed or held or capture_pressed or cannon):
		_combat_left = combat_stance_duration
	sync_facing = _aim_facing() if _combat_left > 0.0 else Vector2.ZERO
	_update_cannon(cannon, delta)
	if is_local and (pressed or held):
		_since_last_shot = 0.0
		_spend_water(water_per_shot)
		_fire(false)
	if is_local and capture_pressed:
		_capture_cooldown_left = capture_cooldown
		_spend_water(water_per_capture)
		_fire(true)

	var ladder_up := _ladder_climb_axis(direction)
	if ladder_up != Vector3.ZERO:
		# Contre une échelle en avançant vers elle : on monte le long de l'échelle (en suivant
		# son inclinaison), sans gravité ; sinon on la traverserait sans avoir fini de monter.
		velocity = ladder_up * climb_speed
	else:
		var updraft := HairDryer.column_at(get_tree(), global_position) if not is_on_floor() else null
		if updraft:
			# Dans la colonne d'air chaud d'un sèche-cheveux : porté vers le haut.
			velocity.y = updraft.lift(global_position, velocity.y, _gravity * gravity_scale, delta)
		elif not is_on_floor():
			velocity.y -= _gravity * gravity_scale * delta
		if _dash_time > 0.0:
			# Dash : vitesse selon la courbe. Au sol, elle suit la surface (pente montante ou
			# descendante) ; en l'air, elle reste horizontale et la gravité s'applique.
			if not _dash_paused_on_water():
				_dash_time = maxf(_dash_time - delta, 0.0)
			# Gauche / droite infléchissent un peu la trajectoire (input.x > 0 : vers la droite).
			_dash_direction = _dash_direction.rotated(Vector3.UP, -input.x * dash_steer_speed * delta)
			var speed := _dash_speed_at(1.0 - _dash_time / dash_duration)
			if is_on_floor():
				var ground := get_floor_normal()
				velocity = (_dash_direction - ground * _dash_direction.dot(ground)).normalized() * speed
			else:
				velocity.x = _dash_direction.x * speed
				velocity.z = _dash_direction.z * speed
		else:
			var target := direction * move_speed
			velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
			velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

	# Pendant le dash, collé au sol de plus loin (suit une descente rapide au lieu de s'envoler).
	floor_snap_length = dash_floor_snap if _dash_time > 0.0 else _floor_snap_default
	var fall_speed := -velocity.y
	var was_on_floor := is_on_floor()
	if not _step_up(delta):
		move_and_slide()
	if is_local and not was_on_floor and is_on_floor() and fall_speed > LAND_SOUND_MIN_SPEED:
		_play_land.rpc()

	if global_position.y < kill_height:
		_apply_damage(health)


## Axe de montée (le long de l'échelle, vers le haut) si le canard touche une échelle en
## avançant vers son mur (`direction`), ZERO sinon.
func _ladder_climb_axis(direction: Vector3) -> Vector3:
	for area: Area3D in get_tree().get_nodes_in_group(&"echelles"):
		if area.overlaps_body(self):
			var to_wall := -area.global_basis.z
			to_wall.y = 0.0
			if direction.dot(to_wall.normalized()) > 0.3:
				return area.global_basis.y.normalized()
	return Vector3.ZERO


## Tire une bulle (de capture si `capture`) vers le point visé, depuis le bout du canon.
func _fire(capture: bool) -> void:
	# Tout droit devant la caméra (à l'horizontale), depuis le centre du cube.
	var target := aim()
	# Sur le décor (mur, sol, plafond, objet), la bulle vise avec sa surface : son centre
	# s'arrête à son rayon de contact avec le décor (0,3 m) de la surface visée, et son bord
	# la touche pile sous le viseur. Ce rayon est plus petit que la hauteur du canon (0,4 m) :
	# la bulle descend vers un point du sol au lieu de partir à l'horizontale. Sur un canard,
	# on vise le point lui-même.
	var aim_point: Vector3 = target.point
	if target.collider is not Player:
		aim_point += target.normal * BubbleProjectile.WORLD_CONTACT_RADIUS
	# La bulle part du bout du canon. Mais le canon est plus bas que la caméra : face à une
	# montée, au bord d'un meuble…, la ligne canon → viseur peut traverser le décor alors que
	# la caméra voit le point visé. Dans ce cas, la bulle part de la ligne de visée (à hauteur
	# du canard) si elle va ainsi nettement plus loin vers le point visé ; elle semble quand
	# même sortir du canon (BubbleProjectile.launch, `visual_from`).
	var muzzle := get_muzzle_position()
	var origin := muzzle
	var reach := INF if capture else BubbleProjectile.RANGE
	var from_muzzle := _shot_reach(muzzle, aim_point, reach)
	if from_muzzle < minf(muzzle.distance_to(aim_point), reach) - 0.5:
		var sight := _sight_origin()
		if _shot_reach(sight, aim_point, reach) > from_muzzle + 0.5:
			origin = sight
	_shoot.rpc(origin, _shot_direction(origin, aim_point), capture, muzzle)


## Point de départ du rayon de visée : sur la ligne caméra → viseur, à hauteur du canard (ce
## qui est entre la caméra et le canard est ignoré).
func _sight_origin() -> Vector3:
	var ray := camera.get_aim_ray()
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	return origin + direction * maxf((global_position - origin).dot(direction), 0.0)


## Distance (m) que parcourt une bulle partie de `from` vers `to` (le point visé, déjà
## décalé de son rayon de contact) avant de toucher le décor, sans dépasser `max_distance`.
func _shot_reach(from: Vector3, to: Vector3, max_distance: float) -> float:
	var distance := minf(from.distance_to(to), max_distance)
	var shape := SphereShape3D.new()
	shape.radius = BubbleProjectile.WORLD_CONTACT_RADIUS * 0.9
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = (to - from).normalized() * distance
	query.collision_mask = WORLD_LAYER | enemy_spawn_layer(team_of(player_id))
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.cast_motion(query)[0] * distance


## Du bout du canon `origin` vers `aim_point` ; si la cible est trop proche (derrière le
## canon), simplement dans l'axe de la caméra.
func _shot_direction(origin: Vector3, aim_point: Vector3) -> Vector3:
	var direction := (aim_point - origin).normalized()
	if direction.dot(camera.get_aim_ray()[1]) < 0.5:
		direction = camera.get_aim_ray()[1]
	return direction


## Recharge du dash, de 0 (vient de dasher) à 1 (prêt), pour la jauge du MatchHud.
func get_dash_ready_ratio() -> float:
	return 1.0 - _dash_cooldown_left / dash_cooldown if dash_cooldown > 0.0 else 1.0


## Vrai si la réserve d'eau est en train de se recharger.
func is_water_recharging() -> bool:
	return water < 1.0 and _water_idle >= water_recharge_delay


## Réserve d'eau pleine d'un coup (récompense d'une élimination, cf. Game).
func refill_water() -> void:
	water = 1.0


func _spend_water(amount: float) -> void:
	water = maxf(water - amount, 0.0)
	_water_idle = 0.0


## Après water_recharge_delay s sans dépense, la réserve se remplit de plus en plus vite.
func _recharge_water(delta: float) -> void:
	_water_idle += delta
	var recharging_for := _water_idle - water_recharge_delay
	if recharging_for < 0.0 or water >= 1.0:
		return
	var rate := minf(water_recharge_rate * pow(2.0, recharging_for / water_recharge_doubling), water_recharge_max_rate)
	water = minf(water + rate * delta, 1.0)


## Canon à eau (ordinateur qui contrôle ce canard) : le met en marche ou l'arrête pour tout
## le monde, et pendant qu'il arrose, suit la visée et l'envoie régulièrement aux autres.
func _update_cannon(want: bool, delta: float) -> void:
	if want and not cannon_on:
		cannon_target = _cannon_aim_point() # Avant le premier envoi : le jet part tout de suite au bon endroit.
		_sync_cannon_target.rpc(cannon_target)
	if want != cannon_on:
		_set_cannon.rpc(want)
	if not cannon_on:
		return
	_spend_water(water_per_second * delta)
	cannon_target = _cannon_aim_point()
	_cannon_sync_left -= delta
	if _cannon_sync_left <= 0.0:
		_cannon_sync_left = CANNON_AIM_SYNC_INTERVAL
		_sync_cannon_target.rpc(cannon_target)


## Jet d'un simple appui (ordinateur qui contrôle ce canard) : à l'appui, démarre le balayage ;
## il s'arrête si la touche est encore tenue après CANNON_TAP_TIME (jet visé normal) ou au bout
## de cannon_tap_duration. Rend vrai si le jet doit couler (touche tenue ou balayage en cours).
func _update_cannon_tap(held: bool, delta: float) -> bool:
	if Input.is_action_just_pressed(&"water_cannon"):
		_cannon_tap_elapsed = 0.0
		_cannon_tap_origin = _feet_position()
		_cannon_tap_forward = Vector3.FORWARD.rotated(Vector3.UP, camera.get_yaw())
	elif _cannon_tap_elapsed >= 0.0:
		_cannon_tap_elapsed += delta
		if (held and _cannon_tap_elapsed > CANNON_TAP_TIME) or _cannon_tap_elapsed >= cannon_tap_duration:
			_cannon_tap_elapsed = -1.0
	return held or _cannon_tap_elapsed >= 0.0


## Point visé par le jet : le viseur, ou pendant le balayage d'un simple appui, le sol sur la
## ligne droite devant le canard.
func _cannon_aim_point() -> Vector3:
	if _cannon_tap_elapsed < 0.0:
		return aim().point
	var t := clampf(_cannon_tap_elapsed / cannon_tap_duration, 0.0, 1.0)
	var point := _cannon_tap_origin + _cannon_tap_forward * lerpf(1.5, cannon_tap_range, t)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * 2.0, point + Vector3.DOWN * 4.0, WORLD_LAYER))
	return hit.position if hit else point


@rpc("authority", "call_local", "reliable")
func _set_cannon(value: bool) -> void:
	cannon_on = value


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_cannon_target(point: Vector3) -> void:
	cannon_target = point


## Piégé dans une bulle de capture : immobile, il décolle, puis s'élève lentement (de
## capture_rise m sur toute la durée) en flottant ; libéré, la gravité le repose au sol.
func _simulate_captured(delta: float) -> void:
	if cannon_on:
		_set_cannon.rpc(false) # Piégé dans la bulle : plus de jet d'eau.
	_captured_left -= delta
	_capture_time += delta
	velocity = Vector3.ZERO
	_dash_time = 0.0
	_combat_left = 0.0
	sync_facing = Vector2.ZERO
	var rise := capture_rise * clampf(_capture_time / _capture_duration, 0.0, 1.0)
	var target_y := _capture_height + rise + sin(_capture_time * CAPTURE_BOB_SPEED) * capture_bob
	var step := lerpf(global_position.y, target_y, 1.0 - exp(-CAPTURE_RISE_SPEED * delta)) - global_position.y
	if step > 0.0:
		# S'arrête sous un plafond, une étagère… Le test part 2 cm plus haut : sinon le sol
		# sous ses pieds (contact au repos) compterait comme un obstacle et bloquerait la montée.
		var ceiling := KinematicCollision3D.new()
		if test_move(global_transform.translated(Vector3.UP * CAPTURE_CEILING_TEST), Vector3.UP * step, ceiling):
			step = maxf(CAPTURE_CEILING_TEST + ceiling.get_travel().y, 0.0)
	global_position.y += step
	if _captured_left <= 0.0:
		_set_captured.rpc(false, 0)


## Traversée automatique d'un tunnel d'eau : avance le long de sa courbe à dash_speed, la
## caméra locale posée sur ce même axe en traînant derrière (cf. PlayerCamera.
## set_tunnel_position/set_tunnel_target, WaterTunnel.camera_trail) ; une fois sorti du
## tuyau, glisse en ligne droite de l'ouverture jusqu'à un point au sol bien dégagé devant
## elle (cf. _tunnel_landing_spot), puis reprend la main (cf. _apply_tunnel).
func _simulate_tunnel(delta: float) -> void:
	if cannon_on:
		_set_cannon.rpc(false) # Dans le tunnel : plus de jet d'eau.
	var direction := -1.0 if _tunnel_reverse else 1.0
	_tunnel_offset += direction * _tunnel.dash_speed * delta
	var length := _tunnel.length()
	var sample := _tunnel.sample_extrapolated(_tunnel_offset)
	var tangent: Vector3 = (sample.tangent as Vector3) * direction
	var past := maxf(-_tunnel_offset, 0.0) if _tunnel_reverse else maxf(_tunnel_offset - length, 0.0)
	var landed := false
	if past > 0.0:
		var end: Dictionary = _tunnel.ends[0 if _tunnel_reverse else 1]
		var mouth: Vector3 = end.point
		if not _tunnel_landing_found:
			_tunnel_landing = _tunnel_landing_spot(_tunnel, end)
			_tunnel_landing_found = true
		var run := maxf(mouth.distance_to(_tunnel_landing), 0.01)
		global_position = mouth.lerp(_tunnel_landing, minf(past / run, 1.0))
		tangent = (_tunnel_landing - mouth).normalized()
		landed = past >= run
	else:
		global_position = sample.point
	velocity = Vector3.ZERO
	if is_local:
		var cam_sample := _tunnel.sample_extrapolated(_tunnel_offset - direction * _tunnel.camera_trail)
		var cam_point: Vector3 = cam_sample.point - Vector3.UP * _tunnel.camera_drop
		camera.set_tunnel_position(cam_point)
		camera.set_tunnel_target(tangent)
	if landed:
		var tunnel := _tunnel
		_tunnel = null
		velocity = Vector3(tangent.x, 0.0, tangent.z).normalized() * tunnel.exit_speed
		_set_tunnel.rpc(false)
		_play_dash.rpc() # Pose du dash maintenue en fondu à la sortie, comme un dash normal.


## Point (repère monde, centre du canard) où il reprend la main en sortant de `tunnel` par
## son extrémité `end` (cf. WaterTunnel.ends) : droit devant l'ouverture, à exit_margin (ou un
## peu plus loin, ou plus près si la place est prise), posé sur le sol, là où sa capsule tient
## sans toucher de mur et sans mur entre l'ouverture et lui (sinon il le traverserait).
func _tunnel_landing_spot(tunnel: WaterTunnel, end: Dictionary) -> Vector3:
	var mouth: Vector3 = end.point
	var out := -(end.tangent as Vector3) # La tangente d'une extrémité pointe vers l'intérieur.
	var flat := Vector3(out.x, 0.0, out.z).normalized()
	var space := get_world_3d().direct_space_state
	var feet := (_collision_shape.shape as CapsuleShape3D).height / 2.0
	var fits := PhysicsShapeQueryParameters3D.new()
	fits.shape = _collision_shape.shape
	fits.collision_mask = WORLD_LAYER
	fits.exclude = [get_rid()]
	for extra: float in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, -0.5, -1.0, -1.5]:
		var probe := mouth + flat * (tunnel.exit_margin + extra)
		var blocked := PhysicsRayQueryParameters3D.create(mouth, probe, WORLD_LAYER, [get_rid()])
		if not space.intersect_ray(blocked).is_empty():
			continue
		var down := PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * 6.0, WORLD_LAYER, [get_rid()])
		var ground := space.intersect_ray(down)
		if ground.is_empty():
			continue
		var spot: Vector3 = ground.position + Vector3.UP * (feet + 0.05)
		fits.transform = Transform3D(_collision_shape.global_basis, spot + _collision_shape.position)
		if space.intersect_shape(fits, 1).is_empty():
			return spot
	return mouth + flat * tunnel.exit_margin


func _regenerate(delta: float) -> void:
	_regen_cooldown_left = maxf(_regen_cooldown_left - delta, 0.0)
	if _regen_cooldown_left == 0.0 and health < max_health:
		health = minf(health + regen_rate * delta, max_health)


## Sur tous les ordinateurs (appelé par celui qui contrôle ce cube).
@rpc("authority", "call_local", "reliable")
func _shoot(origin: Vector3, direction: Vector3, capture: bool, visual_origin: Vector3) -> void:
	var sound := _capture_shoot_sound if capture else _shoot_sound
	sound.global_position = visual_origin # Le son part du canon, en même temps que la bulle.
	sound.play()
	shot.emit(origin, direction, capture, visual_origin)


## Ordinateur qui a l'autorité sur ce cube : début de la capture (cf. capture()).
@rpc("any_peer", "call_remote", "reliable")
func _apply_capture(duration: float, team: int) -> void:
	if not is_alive() or captured or duration <= 0.0:
		return
	_captured_left = duration
	_capture_duration = duration
	_capture_time = 0.0
	# Hauteur de lévitation : capture_lift au-dessus du sol (sur place s'il n'y a pas de sol dessous).
	var feet := (_collision_shape.shape as CapsuleShape3D).height / 2.0
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 3.0,
			WORLD_LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_capture_height = (hit.position.y + feet if not hit.is_empty() else global_position.y) + capture_lift
	_set_captured.rpc(true, team)


## Sur tous les ordinateurs : affiche (ou fait éclater) la bulle autour du canard.
@rpc("authority", "call_local", "reliable")
func _set_captured(value: bool, team: int) -> void:
	if value == captured:
		return
	captured = value
	if value:
		_dash_animation_left = 0.0
		_capture_bubble.material_override = _capture_material(team)
		_show_capture_bubble()
		_capture_sound.play()
	else:
		_captured_left = 0.0
		_hide_capture_bubble(true)


## Ordinateur qui a l'autorité sur ce cube : entrée dans le tunnel (cf. enter_tunnel()).
@rpc("any_peer", "call_remote", "reliable")
func _apply_tunnel(tunnel_path: NodePath, reverse: bool) -> void:
	if not is_alive() or captured or _tunnel:
		return
	var tunnel := get_node(tunnel_path) as WaterTunnel
	if tunnel == null:
		return
	_tunnel = tunnel
	_tunnel_reverse = reverse
	_tunnel_offset = tunnel.length() if reverse else 0.0
	_tunnel_landing_found = false
	_dash_time = 0.0
	_combat_left = 0.0
	sync_facing = Vector2.ZERO
	_set_tunnel.rpc(true)
	_play_dash.rpc()


## Sur tous les ordinateurs : garde (ou relâche) la pose du dash et resserre (ou rend) la
## caméra locale pendant la traversée (cf. _in_tunnel, PlayerCamera.tunnel_mode).
@rpc("authority", "call_local", "reliable")
func _set_tunnel(value: bool) -> void:
	_in_tunnel = value
	if is_local:
		camera.tunnel_mode = value


## Matériau de la bulle de capture : celui de la scène, teinté à la couleur de l'équipe `team`.
func _capture_material(team: int) -> Material:
	var base := _capture_bubble.mesh.surface_get_material(0) as StandardMaterial3D
	var material := base.duplicate() as StandardMaterial3D
	material.albedo_color = Color(TEAM_COLORS[team - 1].lerp(Color.WHITE, 0.25), base.albedo_color.a)
	return material


func _show_capture_bubble() -> void:
	if _capture_tween:
		_capture_tween.kill()
	_capture_bubble.visible = true
	_capture_bubble.transparency = 0.0
	_capture_bubble.scale = Vector3.ONE * 0.3
	_capture_tween = create_tween()
	_capture_tween.tween_property(_capture_bubble, ^"scale", Vector3.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fait disparaître la bulle de capture : elle éclate (avec un son) si `pop`, sinon tout de suite.
func _hide_capture_bubble(pop: bool) -> void:
	if _capture_tween:
		_capture_tween.kill()
	if not pop:
		_capture_bubble.visible = false
		return
	_release_sound.play()
	_capture_tween = create_tween().set_parallel()
	_capture_tween.tween_property(_capture_bubble, ^"scale", Vector3.ONE * 1.4, 0.15)
	_capture_tween.tween_property(_capture_bubble, ^"transparency", 1.0, 0.15)
	_capture_tween.chain().tween_callback(_capture_bubble.hide)


## Effet de savon du dash : deux gerbes de mousse blanche, projetées sur les côtés
## (et un peu vers le haut et l'arrière) au ras du sol, tant que le canard file en dash (sur tous
## les ordinateurs : l'animation du dash est déjà envoyée, cf. _play_dash).
func _create_dash_splash() -> void:
	_dash_splash = Node3D.new()
	_dash_splash.name = "DashSplash"
	_dash_splash.position.y = _model.position.y # Au niveau des pieds.
	add_child(_dash_splash)
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh.radial_segments = 8
	mesh.rings = 4
	# Mousse blanche, ombrée (brillance et côté sombre) : se détache aussi bien sur le sol clair
	# que sur une traînée d'eau.
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.15
	material.rim_enabled = true
	material.rim = 0.6
	mesh.material = material
	var colors := Gradient.new()
	colors.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	colors.add_point(0.5, Color(0.9, 0.96, 1.0, 0.95))
	colors.set_color(2, Color(0.85, 0.94, 1.0, 0.0))
	var sizes := Curve.new()
	sizes.add_point(Vector2(0.0, 0.6))
	sizes.add_point(Vector2(0.25, 1.0))
	sizes.add_point(Vector2(1.0, 0.3))
	for side in [-1.0, 1.0]:
		var splash := CPUParticles3D.new()
		splash.emitting = false
		splash.amount = 90
		splash.lifetime = 0.6
		splash.local_coords = false # Les gouttes restent derrière le canard qui file.
		splash.mesh = mesh
		splash.position = Vector3(side * 0.55, 0.15, 0.1)
		splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		splash.emission_sphere_radius = 0.15
		splash.direction = Vector3(side, 0.8, -0.35)
		splash.spread = 22.0
		splash.initial_velocity_min = 3.5
		splash.initial_velocity_max = 6.5
		splash.gravity = Vector3(0, -16, 0)
		splash.scale_amount_min = 0.5
		splash.scale_amount_max = 1.4
		splash.scale_amount_curve = sizes
		splash.color_ramp = colors
		splash.layers = Puddles.DUCK_VISUAL_LAYER # Les flaques (Decals) ne les colorent pas.
		_dash_splash.add_child(splash)


## Sur tous les ordinateurs (appelé par celui qui contrôle ce cube) : lance les
## animations et le son du dash.
@rpc("authority", "call_local", "reliable")
func _play_dash() -> void:
	_dash_animation_left = dash_duration
	_dash_sound.play()


## Sur tous les ordinateurs (appelé par celui qui contrôle ce cube) : son du saut.
@rpc("authority", "call_local", "reliable")
func _play_jump() -> void:
	_jump_sound.play()


## Sur tous les ordinateurs (appelé par celui qui contrôle ce cube) : son d'atterrissage.
@rpc("authority", "call_local", "reliable")
func _play_land() -> void:
	_land_sound.play()


## Sur tous les ordinateurs : envol depuis un sèche-cheveux (son du saut plus grave,
## bouffée d'air chaud).
@rpc("authority", "call_local", "reliable")
func _play_updraft() -> void:
	_jump_sound.play()
	_dash_sound.play()
	var dryer := HairDryer.under(get_tree(), _feet_position())
	if dryer:
		dryer.puff()


## Direction horizontale (x, z) du rayon du viseur.
func _aim_facing() -> Vector2:
	var direction: Vector3 = camera.get_aim_ray()[1]
	return Vector2(direction.x, direction.z).normalized()


## Ce que vise le joueur (centre de l'écran) : { point, normal, collider (ou null) }.
## Le rayon part de la hauteur du canard (pas de la caméra) pour ignorer ce qui
## se trouve entre la caméra et lui.
func aim() -> Dictionary:
	var origin := _sight_origin()
	var direction: Vector3 = camera.get_aim_ray()[1]
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * AIM_DISTANCE,
			WORLD_LAYER | PLAYERS_LAYER | enemy_spawn_layer(team_of(player_id)), [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"point": origin + direction * AIM_DISTANCE, "normal": Vector3.ZERO, "collider": null}
	return {"point": hit.position, "normal": hit.normal, "collider": hit.collider}


## Vrai si le point visé est à portée d'une bulle normale (sinon le viseur pâlit).
func is_bubble_in_range() -> bool:
	return get_muzzle_position().distance_to(aim().point) <= BubbleProjectile.RANGE


## Vrai si le viseur est sur un adversaire vivant.
func is_aiming_at_enemy() -> bool:
	var target := aim().collider as Player
	return target != null and target.is_alive() and target.get_team() != get_team()


## Crée un repère au bout du canon : extrémité du mesh du pistolet, côté avant du canard.
func _create_muzzle() -> void:
	var gun := _model.find_child(GUN_MESH, true, false) as MeshInstance3D
	if gun == null:
		return
	var box := gun.get_aabb()
	var half := box.get_longest_axis() * box.get_longest_axis_size() / 2.0
	var end_a := box.get_center() + half
	var end_b := box.get_center() - half
	var forward := _model.global_basis.z # Le canard regarde vers +Z.
	_muzzle = Marker3D.new()
	_muzzle.name = &"Muzzle"
	gun.add_child(_muzzle)
	_muzzle.position = end_a if (gun.to_global(end_a) - gun.to_global(end_b)).dot(forward) > 0.0 else end_b


## Animation et orientation du canard selon sa vitesse, sa visée (posture de combat)
## et le dash en cours.
func _update_model(velocity_now: Vector3, delta: float) -> void:
	_step_offset *= exp(-STEP_SMOOTHING * delta)
	_model.position.y = _model_base_y + _step_offset + _death_drop
	if not camera.tunnel_mode: # Dans le tunnel, la caméra est posée sur l'axe du tuyau (cf. PlayerCamera).
		camera.position.y = _camera_base_y + _step_offset
	var horizontal := Vector3(velocity_now.x, 0.0, velocity_now.z)
	var speed := horizontal.length()
	var moving := speed > MOVING_SPEED and is_alive()
	var combat := sync_facing != Vector2.ZERO and is_alive()
	if combat:
		# Posture de combat : il regarde là où il vise, même en reculant.
		_turn_model_towards(Vector3(sync_facing.x, 0.0, sync_facing.y), 1.0 - exp(-AIM_TURN_SPEED * delta))
	elif moving:
		_turn_model_towards(horizontal, 1.0 - exp(-TURN_SPEED * delta))
	# Glissade sur l'eau : l'animation du dash dure aussi longtemps que la glissade (cf.
	# _dash_paused_on_water ; les autres ordinateurs la devinent à sa vitesse), et l'eau
	# s'écarte derrière le canard (sillage).
	var sliding := _dash_animation_left > 0.0 and speed > move_speed and is_on_water()
	if not (dash_slides_on_water and sliding):
		_dash_animation_left = maxf(_dash_animation_left - delta, 0.0)
	_wake_left -= delta
	if sliding and _wake_left <= 0.0:
		_wake_left = WAKE_INTERVAL
		_puddles.wake(_feet_position(), horizontal, _ground_normal())
	var dashing := _dash_animation_left > 0.0 or _in_tunnel
	if _dash_splash:
		_dash_splash.rotation.y = _model.rotation.y
		for splash: CPUParticles3D in _dash_splash.get_children():
			splash.emitting = _dash_animation_left > 0.0 and speed > move_speed
	_animation_tree.set(&"parameters/conditions/dashing", dashing)
	_animation_tree.set(&"parameters/conditions/dash_over", not dashing)
	_animation_tree.set(&"parameters/conditions/idle", not moving)
	_animation_tree.set(&"parameters/conditions/walk", moving and (combat or speed <= RUN_SPEED))
	_animation_tree.set(&"parameters/conditions/run", moving and not combat and speed > RUN_SPEED)
	# Le modèle regarde vers +Z : sa droite est -X.
	var strafe := Vector2(0, 1)
	if combat and moving:
		var local := _model.global_basis.inverse() * horizontal
		strafe = Vector2(-local.x, local.z).normalized()
	_strafe = _strafe.lerp(strafe, 1.0 - exp(-STRAFE_BLEND_SPEED * delta))
	_animation_tree.set(&"parameters/walk/blend_position", _strafe)
	# Au sol : les canards des autres ordinateurs n'ont pas is_on_floor(), on regarde leur vitesse verticale.
	var grounded := is_on_floor() if is_multiplayer_authority() else absf(velocity_now.y) < 1.0
	_play_footsteps(active and moving and grounded)


## Bruit de pas quand l'animation walk / run passe sur un instant de FOOTSTEPS
## (un pied se pose). Calé sur l'animation : marche et course gardent leur rythme.
func _play_footsteps(enabled: bool) -> void:
	var animation := _animation_playback.get_current_node()
	var length := _animation_playback.get_current_length()
	if not enabled or not FOOTSTEPS.has(animation) or length <= 0.0:
		_footstep_animation = &""
		return
	var phase := fmod(_animation_playback.get_current_play_position() / length, 1.0)
	if animation == _footstep_animation:
		for contact: float in FOOTSTEPS[animation]:
			var crossed := (_footstep_phase < contact and contact <= phase) if phase >= _footstep_phase \
					else (contact > _footstep_phase or contact <= phase) # L'animation a bouclé.
			if crossed and is_on_water():
				_water_step_sound.play()
				_puddles.step_splash(_feet_position(), _ground_normal())
			elif crossed:
				_step_sound.play()
	_footstep_animation = animation
	_footstep_phase = phase


## Le modèle regarde vers +Z : on l'aligne sur `direction` (weight = 1 : d'un coup).
func _turn_model_towards(direction: Vector3, weight: float) -> void:
	if Vector2(direction.x, direction.z).is_zero_approx():
		return
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(direction.x, direction.z), weight)


@rpc("any_peer", "call_remote", "reliable")
func _apply_damage(amount: float, attacker_id := 0) -> void:
	if not is_alive() or amount <= 0.0:
		return
	if captured:
		amount *= captured_damage_scale
	_regen_cooldown_left = regen_delay
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_announce_elimination.rpc(attacker_id)


## Sur tous les ordinateurs (appelé par celui qui contrôle ce cube) : il vient d'être éliminé.
@rpc("authority", "call_local", "reliable")
func _announce_elimination(killer_id: int) -> void:
	eliminated.emit(killer_id)


## Sur tous les ordinateurs : le canard mort ne bloque plus personne et joue sa mort.
func _on_died() -> void:
	_respawn_left = respawn_delay
	_death_sound.play()
	cannon_on = false
	if captured: # Mort dans la bulle : elle disparaît avec lui.
		captured = false
		_captured_left = 0.0
		_hide_capture_bubble(false)
	_collision_shape.set_deferred(&"disabled", true)
	_play_death()
	update_name_tag()
	died.emit()


func _on_respawned() -> void:
	_dash_animation_left = 0.0
	_animation_playback.start(&"idle") # Repart de l'arrêt, pas de l'animation au moment de la mort.
	_respawn_sound.play()
	if _death_tween:
		_death_tween.kill()
	_death_drop = 0.0
	_model.scale = _model_base_scale
	_model.visible = true
	_collision_shape.set_deferred(&"disabled", false)
	update_name_tag()
	respawned.emit()


## Mort (sur tous les ordinateurs) : animation « death », chute jusqu'au sol s'il était en
## l'air, puis pop de bulle (gonfle, disparaît, éclaboussure) juste avant la réapparition.
func _play_death() -> void:
	_animation_playback.start(&"death")
	var drop := 0.0
	var feet := _feet_position()
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.1, feet + Vector3.DOWN * DEATH_FLOOR_SEARCH, WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		drop = minf(hit.position.y - feet.y, 0.0)
	if _death_tween:
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(self, ^"_death_drop", drop, DEATH_FALL_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_death_tween.tween_interval(maxf(respawn_delay - DEATH_FALL_TIME - DEATH_POP_TIME - 0.15, 0.0))
	_death_tween.tween_callback(_death_pop_effects)
	_death_tween.tween_property(_model, ^"scale", _model_base_scale * 1.25, DEATH_POP_TIME * 0.6).set_trans(Tween.TRANS_SINE)
	_death_tween.tween_property(_model, ^"scale", _model_base_scale * 0.01, DEATH_POP_TIME * 0.4)
	_death_tween.tween_callback(_model.hide)


func _death_pop_effects() -> void:
	var pop := AudioStreamPlayer3D.new()
	pop.stream = DEATH_POP_SOUND
	pop.max_distance = 40.0
	add_child(pop)
	pop.global_position = _model.global_position + Vector3.UP * 0.4
	pop.play()
	pop.finished.connect(pop.queue_free)
	if _puddles == null:
		_puddles = get_tree().get_first_node_in_group(Puddles.GROUP) as Puddles
	if _puddles:
		_puddles.duck_splash(_model.global_position + Vector3.UP * 0.4, Vector3.UP)


## Vitesse du dash à l'instant `t` (0 = début, 1 = fin).
func _dash_speed_at(t: float) -> float:
	var cruise := lerpf(dash_speed, move_speed, smoothstep(DASH_SLOWDOWN_START, 1.0, t))
	return lerpf(_dash_start_speed, cruise, smoothstep(0.0, DASH_RAMP, t))


## Vrai si le canard est sur une flaque d'eau (sous ses pieds).
func is_on_water() -> bool:
	if _puddles == null:
		_puddles = get_tree().get_first_node_in_group(Puddles.GROUP) as Puddles
	return (_puddles != null and _puddles.is_wet(_feet_position())) or is_in_deep_water()


## Vrai si le canard a les pieds dans l'eau profonde (baignoire, toilettes : DEEP_WATER_GROUP).
func is_in_deep_water() -> bool:
	var feet := _feet_position()
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.2, feet + Vector3.DOWN * 0.3,
			WORLD_LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.collider as Node).is_in_group(DEEP_WATER_GROUP)


## Normale du sol sous le canard (vers le haut si on ne la connaît pas : en l'air, ou canard
## d'un autre ordinateur, qui ne fait pas de move_and_slide ici).
func _ground_normal() -> Vector3:
	return get_floor_normal() if is_on_floor() else Vector3.UP


## Rayon de la capsule du canard (m).
func get_body_radius() -> float:
	return (_collision_shape.shape as CapsuleShape3D).radius


## Point du sol sous le canard (bas de sa capsule).
func _feet_position() -> Vector3:
	return global_position + Vector3.DOWN * (_collision_shape.shape as CapsuleShape3D).height / 2.0


## Vrai si le dash en cours ne s'use pas cette image : le canard glisse sur l'eau, au sol.
## Sauf pendant la montée en vitesse (il resterait à l'arrêt) et contre un mur (il resterait
## bloqué en plein dash).
func _dash_paused_on_water() -> bool:
	return dash_slides_on_water and 1.0 - _dash_time / dash_duration >= DASH_RAMP \
			and is_on_floor() and not is_on_wall() and is_on_water()


## Dash (au sol uniquement) dans la direction du joystick, ou devant la caméra s'il est au repos.
func _start_dash(direction: Vector3) -> void:
	if direction.is_zero_approx():
		direction = Vector3.FORWARD.rotated(Vector3.UP, camera.get_yaw())
	_dash_direction = direction.normalized()
	_dash_start_speed = Vector2(velocity.x, velocity.z).length()
	_dash_time = dash_duration
	_dash_cooldown_left = dash_cooldown
	_play_dash.rpc()


## Monte sur un relief d'au plus max_step_height (marche, rebord…) qui bloque le canard
## au sol : on rejoue le déplacement prévu max_step_height plus haut, puis on redescend
## dessus. Vrai si le canard a été posé sur la marche (move_and_slide est alors inutile).
## Les pentes praticables (≤ floor_max_angle) restent gérées par move_and_slide.
func _step_up(delta: float) -> bool:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if not is_on_floor() or velocity.y > 0.0 or motion.is_zero_approx():
		return false
	var blocked := KinematicCollision3D.new()
	if not test_move(global_transform, motion, blocked) \
			or blocked.get_normal().angle_to(Vector3.UP) <= floor_max_angle \
			or blocked.get_collider() is CharacterBody3D:
		return false # Rien devant, une pente praticable ou un autre canard.
	var lift := Vector3.UP * max_step_height
	var raised := global_transform.translated(lift)
	if test_move(global_transform, lift) or test_move(raised, motion):
		return false # Plafond au-dessus, ou obstacle plus haut qu'une marche.
	var drop := KinematicCollision3D.new()
	var above := raised.translated(motion)
	if not test_move(above, -lift, drop) or drop.get_collider() is CharacterBody3D:
		return false
	var landing := above.origin + drop.get_travel()
	var height := landing.y - global_position.y
	if height < STEP_MIN_HEIGHT or height > max_step_height:
		return false
	# Le dessus de la marche (juste après le point de contact) doit être praticable.
	var probe := drop.get_position() + motion.normalized() * 0.1 + Vector3.UP * 0.1
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			probe, probe + Vector3.DOWN * 0.3, collision_mask & ~PLAYERS_LAYER, [get_rid()]))
	if hit.is_empty() or hit.normal.angle_to(Vector3.UP) > floor_max_angle:
		return false
	# Hauteur réelle de la marche sous les pieds : le bas arrondi de la capsule, posé
	# sur l'arête, dépasse sinon max_step_height (et monterait de proche en proche).
	var feet := global_position.y - (_collision_shape.shape as CapsuleShape3D).height / 2.0
	if hit.position.y - feet > max_step_height:
		return false
	global_position = landing
	_step_offset -= height # Le modèle et la caméra rattrapent la hauteur en douceur.
	apply_floor_snap()
	return true


func _follow_network(delta: float) -> void:
	if position.distance_to(sync_position) > REMOTE_SNAP_DISTANCE:
		position = sync_position
		reset_physics_interpolation()
	else:
		position = position.lerp(sync_position, 1.0 - exp(-REMOTE_SMOOTHING * delta))


func _apply_color() -> void:
	collision_mask = WORLD_LAYER | PLAYERS_LAYER | (0 if dummy else enemy_spawn_layer(team_of(player_id)))
	if _model == null: # Setter appelé avant que le nœud soit prêt.
		return
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = Puddles.DUCK_VISUAL_LAYER # Les flaques (Decals) ne colorent pas le canard.
		if mesh.name in TEAM_COLORED_MESHES:
			mesh.material_override = DUMMY_MATERIAL if dummy else TEAM_MATERIALS[team_of(player_id) - 1]
		else:
			mesh.material_override = MESH_MATERIALS.get(mesh.name)
