extends CanvasLayer
## Écrans de dégâts du joueur local (instancié dans scenes/game/game.tscn).
##
## Pas de barre de vie : plus le joueur a perdu de vie, plus l'écran se couvre
## de bulles. Chaque enfant est un « écran de dégâts » (scenes/ui/damage/) qui
## apparaît sur une tranche de vie. Avec N écrans, l'écran n° i (0, 1…) apparaît
## entre 100 % - i/N et 100 % - (i+1)/N de vie : avec 3 écrans, le 1er de 100 à
## 67 PV, le 2e de 67 à 33 PV, le 3e de 33 à 0 PV.
## Niveau d'apparition (0 à 1) : passé au paramètre `amount` du shader de
## l'écran s'il en a un (les bulles grossissent / rétrécissent), sinon à son
## opacité (fondu). On peut donc remplacer un écran par n'importe quel Control,
## une image par exemple ; l'ordre des enfants compte.


func _ready() -> void:
	set_health_ratio(1.0)


## `ratio` = vie / vie max, de 0 (mort) à 1 (pleine vie).
func set_health_ratio(ratio: float) -> void:
	var screens := get_children()
	var count := screens.size()
	for i in count:
		var start := 1.0 - float(i) / count
		var amount := clampf((start - ratio) * count, 0.0, 1.0)
		var screen := screens[i] as CanvasItem
		var material := screen.material as ShaderMaterial
		if material and material.get_shader_parameter(&"amount") != null:
			material.set_shader_parameter(&"amount", amount)
		else:
			screen.modulate.a = amount
		screen.visible = amount > 0.0
