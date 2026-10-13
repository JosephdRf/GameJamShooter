extends CanvasLayer
## Interface affichée pendant le combat (instanciée dans scenes/game/game.tscn) :
## score bleu | compte à rebours | score rouge, et en dessous la barre de capture
## de la zone. La scène de jeu appelle les fonctions set_* ; ce script ne fait
## qu'afficher.

@onready var _timer_panel: Control = %TimerPanel
@onready var _timer_label: Label = %TimerLabel
@onready var _blue_score_label: Label = %BlueScoreLabel
@onready var _red_score_label: Label = %RedScoreLabel
@onready var _capture: Control = %Capture
@onready var _capture_label: Label = %CaptureLabel
@onready var _capture_bar: ProgressBar = %CaptureBar


## Affiche le temps restant au format m:ss, arrondi à la seconde supérieure
## (1:00 pendant la première seconde, puis 0:59…). Négatif = chrono masqué.
func set_time_left(seconds: float) -> void:
	_timer_panel.visible = seconds >= 0.0
	var whole := ceili(maxf(seconds, 0.0))
	_timer_label.text = "%d:%02d" % [whole / 60, whole % 60]


func set_scores(blue: int, red: int) -> void:
	_blue_score_label.text = str(blue)
	_red_score_label.text = str(red)


## Barre de capture : `team` = équipe qui capture (0 = barre masquée),
## `ratio` = progression de 0 à 1, `contested` = les deux équipes sont dans la zone.
func set_capture(team: int, ratio: float, contested: bool) -> void:
	_capture.visible = team != 0
	if team == 0:
		return
	_capture_bar.value = ratio
	(_capture_bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = Player.TEAM_COLORS[team - 1]
	if contested:
		_capture_label.text = "Zone contestée !"
	else:
		_capture_label.text = "Capture de la zone par l'équipe %s…" % Player.TEAM_NAMES[team - 1]
