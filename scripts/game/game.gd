extends Node3D
## Scène principale : l'arène + les 4 joueurs.
## Seule la caméra du joueur 1 est active (réglée dans scenes/player/player_1.tscn).
## Échap (ui_cancel) quitte le jeu.

@onready var _arena: Node3D = $Arena


func _ready() -> void:
	# La souris est capturée pour que le trackpad pilote la caméra du joueur clavier.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for player: Player in $Players.get_children():
		player.camera.face(_arena.global_position) # Au départ, chaque joueur regarde le centre.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
