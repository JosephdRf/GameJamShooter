extends Node
## Sons des menus, communs à tous les écrans (autoload : le son continue pendant
## un changement d'écran et pendant la pause).
##   - clic (ui_click.tres) : le focus passe à un autre bouton au clavier / à la
##     manette, ou on change de joueur dans la sélection d'équipe ;
##   - validation (ui_confirm.tres) : un bouton est pressé, ou une action de menu
##     est validée sans bouton (Start, choix du joueur…).
## Tous les boutons (BaseButton) de toutes les scènes sont branchés automatiquement.

## Actions de navigation : un changement de focus n'est sonore que s'il vient de l'une d'elles
## (pas des grab_focus() faits à l'ouverture d'un écran).
const NAVIGATION_ACTIONS: Array[StringName] = [
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev",
]

var _click := AudioStreamPlayer.new()
var _confirm := AudioStreamPlayer.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Le menu pause fonctionne jeu en pause.
	_click.stream = preload("res://assets/audio/sfx/ui_click.tres")
	_click.volume_db = -6.0
	_click.max_polyphony = 2
	_confirm.stream = preload("res://assets/audio/sfx/ui_confirm.tres")
	_confirm.volume_db = -4.0
	add_child(_click)
	add_child(_confirm)
	get_tree().node_added.connect(_on_node_added)


func play_click() -> void:
	_click.play()


func play_confirm() -> void:
	_confirm.play()


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	button.pressed.connect(play_confirm)
	button.focus_entered.connect(_on_focus_entered)


func _on_focus_entered() -> void:
	for action in NAVIGATION_ACTIONS:
		if Input.is_action_just_pressed(action):
			play_click()
			return
