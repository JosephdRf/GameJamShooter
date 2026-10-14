class_name TiledBackground
extends Control
## Fond des menus : mosaïque de carreaux de salle de bain (assets/ui/background/), tirés au
## hasard ; les carreaux « rares » (ui_bg_rare_*) sortent moins souvent.
## Remplit tout le nœud (ancré plein écran) et se redessine s'il change de taille.

const TILES: Array[Texture2D] = [
	preload("res://assets/ui/background/ui_bg_var_1.png"),
	preload("res://assets/ui/background/ui_bg_var_2.png"),
	preload("res://assets/ui/background/ui_bg_var_3.png"),
	preload("res://assets/ui/background/ui_bg_var_4.png"),
	preload("res://assets/ui/background/ui_bg_var_5.png"),
	preload("res://assets/ui/background/ui_bg_var_6.png"),
	preload("res://assets/ui/background/ui_bg_var_7.png"),
]
const RARE_TILES: Array[Texture2D] = [
	preload("res://assets/ui/background/ui_bg_rare_1.png"),
	preload("res://assets/ui/background/ui_bg_rare_2.png"),
]

## Nombre de rangées de carreaux sur la hauteur de l'écran.
@export var rows := 8.0
## Probabilité qu'un carreau soit un carreau rare.
@export_range(0.0, 1.0) var rare_chance := 0.06

var _seed := randi()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed # Même mosaïque à chaque redessin.
	var tile := size.y / rows
	for y in ceili(size.y / tile):
		for x in ceili(size.x / tile):
			var texture: Texture2D
			if rng.randf() < rare_chance:
				texture = RARE_TILES[rng.randi() % RARE_TILES.size()]
			else:
				texture = TILES[rng.randi() % TILES.size()]
			draw_texture_rect(texture, Rect2(Vector2(x, y) * tile, Vector2(tile, tile)), false)
