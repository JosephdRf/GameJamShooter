extends Control
## Écran de fin : scores (NetworkManager.final_scores, envoyés par l'hôte),
## équipe gagnante, puis Rejouer (-> sélection d'équipe) ou Quitter (ferme le jeu).
## Rejouer est individuel : chaque ordinateur revient au salon quand il veut.

@onready var _winner: Label = %Winner
@onready var _team_panels: Array[PanelContainer] = [
	$Margin/Layout/Teams/Team1,
	$Margin/Layout/Teams/Team2,
]
@onready var _replay_button: Button = %ReplayButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_replay_button.pressed.connect(_replay)
	_quit_button.pressed.connect(get_tree().quit)
	_show_scores(NetworkManager.final_scores)
	_replay_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


func _show_scores(scores: Dictionary) -> void:
	var totals := [0, 0]
	for player_id in range(1, NetworkManager.MAX_PLAYERS + 1):
		var team_index := Player.team_of(player_id) - 1
		var score: int = scores.get(player_id, 0)
		totals[team_index] += score

		var row := Label.new()
		row.text = "Joueur %d  :  %d" % [player_id, score]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_color_override(&"font_color", Player.PLAYER_COLORS[player_id - 1])
		_team_panels[team_index].get_node(^"Content/Players").add_child(row)

	for i in totals.size():
		_team_panels[i].get_node(^"Content/Total").text = str(totals[i])

	var winner := 0 if totals[0] > totals[1] else 1 if totals[1] > totals[0] else -1
	if winner == -1:
		_winner.text = "Égalité !"
	else:
		_winner.text = "Victoire de l'équipe %d !" % (winner + 1)
		_winner.add_theme_color_override(&"font_color", _team_color(winner))
	for i in _team_panels.size():
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(16)
		style.set_content_margin_all(24)
		style.bg_color = _team_color(i).darkened(0.55 if i == winner else 0.8)
		if i == winner:
			style.set_border_width_all(4)
			style.border_color = Color.WHITE
		_team_panels[i].add_theme_stylebox_override(&"panel", style)


## Couleur d'une équipe (0 ou 1) : celle de son premier joueur.
func _team_color(team_index: int) -> Color:
	return Player.PLAYER_COLORS[team_index * 2]


func _replay() -> void:
	# Hors ligne (ou hôte parti), la sélection d'équipe renvoie à l'écran hôte/IP.
	get_tree().change_scene_to_file(Screens.TEAM_SELECT)
