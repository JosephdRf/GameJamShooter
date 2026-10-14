extends CanvasLayer
## Viseur (instancié dans scenes/game/game.tscn) : un petit cercle et quatre traits
## en diagonale, au centre de l'écran ou décalé par l'aide à la visée (AimAssist).
## Sur un adversaire, il se resserre et prend `target_color`. Game le masque quand
## le joueur local est mort. Les bulles partent vers le point visé (Player.aim()).

@export var color := Color(1, 1, 1, 0.95)
@export var target_color := Color("ff5a5f")
@export var outline_color := Color(0, 0, 0, 0.45)
## Rayon du cercle central (px, à 1080 px de haut).
@export var dot_radius := 12.0
## Distance des traits au centre : au repos et sur une cible (px).
@export var tick_distance := 40.0
@export var tick_distance_on_target := 26.0
@export var tick_length := 18.0
## Debug mode : couleur du rectangle de l'aide à la visée.
@export var assist_box_color := Color(1, 1, 1, 0.35)

var _on_target := false
var _spread := 1.0 # 1 = au repos, 0 = sur une cible.
## Décalage du viseur depuis le centre de l'écran (px, à 1080 px de haut).
var _offset := Vector2.ZERO
## Debug mode : rectangle de l'aide à la visée (px, à 1080 px de haut ; zéro = caché).
var _assist_box := Vector2.ZERO

@onready var _canvas: Control = $Canvas


func _ready() -> void:
	_canvas.draw.connect(_draw_crosshair)


func set_on_target(on_target: bool) -> void:
	_on_target = on_target


## Position du viseur (décalage depuis le centre) et rectangle de l'aide à la visée à afficher.
func set_aim(offset: Vector2, assist_box: Vector2) -> void:
	if offset != _offset or assist_box != _assist_box:
		_offset = offset
		_assist_box = assist_box
		_canvas.queue_redraw()


func _process(delta: float) -> void:
	var target_spread := 0.0 if _on_target else 1.0
	if not is_equal_approx(_spread, target_spread):
		_spread = move_toward(_spread, target_spread, delta * 8.0)
		_canvas.queue_redraw()


func _draw_crosshair() -> void:
	var ui_scale := _canvas.size.y / 1080.0
	if _assist_box != Vector2.ZERO: # Debug mode.
		var box := _assist_box * ui_scale
		_canvas.draw_rect(Rect2(_canvas.size / 2.0 - box / 2.0, box), assist_box_color, false, 2.0 * ui_scale)
	var center := _canvas.size / 2.0 + _offset * ui_scale
	var tint := target_color.lerp(color, _spread)
	_ring(center, dot_radius * ui_scale, tint, 2.5 * ui_scale)
	_canvas.draw_circle(center, 2.5 * ui_scale, tint)
	var distance := lerpf(tick_distance_on_target, tick_distance, _spread) * ui_scale
	for i in 4:
		var direction := Vector2.from_angle(PI / 4.0 + i * PI / 2.0)
		var from := center + direction * distance
		var to := from + direction * tick_length * ui_scale
		_canvas.draw_line(from, to, outline_color, 6.0 * ui_scale, true)
		_canvas.draw_line(from, to, tint, 3.0 * ui_scale, true)


func _ring(center: Vector2, radius: float, tint: Color, width: float) -> void:
	_canvas.draw_arc(center, radius, 0.0, TAU, 32, outline_color, width + 2.0, true)
	_canvas.draw_arc(center, radius, 0.0, TAU, 32, tint, width, true)
