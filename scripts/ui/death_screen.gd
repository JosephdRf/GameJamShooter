extends CanvasLayer
## Écran de mort du joueur local (instancié dans scenes/game/game.tscn) :
## l'image passe en gris et « You died » s'affiche jusqu'à la réapparition.
## Au-dessus du HUD (grisé lui aussi), sous le menu pause.

@onready var _title: Label = %Title


func _ready() -> void:
	visible = false


func show_death() -> void:
	visible = true
	_title.pivot_offset = _title.size / 2.0
	_title.scale = Vector2.ONE * 1.4
	_title.modulate.a = 0.0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_title, ^"scale", Vector2.ONE, 0.35)
	tween.tween_property(_title, ^"modulate:a", 1.0, 0.25)


func hide_death() -> void:
	visible = false
