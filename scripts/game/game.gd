extends Node3D
## Scène principale : l'arène + les 4 joueurs.
## Chaque ordinateur affiche la caméra du joueur qu'il a choisi dans le lobby.
## Les joueurs non choisis restent sur place (contrôlés par personne).
## Échap (ui_cancel) quitte le jeu.

@onready var _arena: Node3D = $Arena
@onready var _players: Node3D = $Players


func _ready() -> void:
	# La souris est capturée pour que le trackpad pilote la caméra.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for player: Player in _players.get_children():
		player.camera.face(_arena.global_position) # Au départ, chaque joueur regarde le centre.
	_apply_slots()
	NetworkManager.slots_changed.connect(_apply_slots)
	NetworkManager.match_started.connect(_on_match_started)
	NetworkManager.notify_game_ready()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()


## Donne à chaque ordinateur l'autorité sur le cube qu'il a choisi (l'hôte garde les autres).
func _apply_slots() -> void:
	var my_id := multiplayer.get_unique_id()
	for player: Player in _players.get_children():
		var owner_id := NetworkManager.get_slot_owner(player.player_id)
		player.set_multiplayer_authority(owner_id if owner_id != 0 else 1)
		player.is_local = owner_id == my_id
		player.camera.set_view_active(player.is_local)


func _on_match_started() -> void:
	for player: Player in _players.get_children():
		player.activate()
