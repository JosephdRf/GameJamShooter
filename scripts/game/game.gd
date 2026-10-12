extends Node3D
## Scène principale : l'arène + les 4 joueurs + le menu pause.
## Chaque ordinateur affiche la caméra du joueur qu'il a choisi dans le salon.
## Les joueurs non choisis restent sur place (contrôlés par personne).
## Échap (ui_cancel) quitte le jeu ; P / + (hôte) ouvre le menu pause.
##
## Fin du combat (hôte) : après match_duration secondes, ou via le bouton de test
## du menu pause. Les scores sont fictifs en attendant le vrai système de score.

## Durée d'un combat en secondes (0 = pas de limite).
@export var match_duration := 0.0

@onready var _arena: Node3D = $Arena
@onready var _players: Node3D = $Players
@onready var _pause_menu: CanvasLayer = $PauseMenu


func _ready() -> void:
	# La souris est capturée pour que le trackpad pilote la caméra.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for player: Player in _players.get_children():
		player.camera.face(_arena.global_position) # Au départ, chaque joueur regarde le centre.
	_apply_slots()
	NetworkManager.slots_changed.connect(_apply_slots)
	NetworkManager.match_started.connect(_on_match_started)
	_pause_menu.end_match_requested.connect(_end_match)
	NetworkManager.notify_game_ready()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()


## Donne à chaque ordinateur l'autorité sur le cube qu'il a choisi (l'hôte garde les autres).
func _apply_slots() -> void:
	if not is_inside_tree(): # Scène en cours de remplacement (retour au salon, fin du combat).
		return
	var my_id := multiplayer.get_unique_id()
	for player: Player in _players.get_children():
		var owner_id := NetworkManager.get_slot_owner(player.player_id)
		player.set_multiplayer_authority(owner_id if owner_id != 0 else 1)
		player.is_local = owner_id == my_id
		player.camera.set_view_active(player.is_local)


func _on_match_started() -> void:
	for player: Player in _players.get_children():
		player.activate()
	if multiplayer.is_server() and match_duration > 0.0:
		# Timer du nœud : il s'arrête pendant la pause.
		var timer := Timer.new()
		timer.one_shot = true
		timer.timeout.connect(_end_match)
		add_child(timer)
		timer.start(match_duration)


func _end_match() -> void:
	NetworkManager.end_match(_placeholder_scores())


## TODO : remplacer par les vrais scores quand le combat sera implémenté.
func _placeholder_scores() -> Dictionary:
	var scores := {}
	for player: Player in _players.get_children():
		scores[player.player_id] = randi_range(0, 10)
	return scores
