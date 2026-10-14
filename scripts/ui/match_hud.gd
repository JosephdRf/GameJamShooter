extends CanvasLayer
## Interface affichée pendant le combat (instanciée dans scenes/game/game.tscn) :
## score bleu | compte à rebours | score rouge, et en dessous la barre de capture
## de la zone ; en bas à gauche, la réserve d'eau du joueur. La scène de jeu
## appelle les fonctions set_* ; ce script ne fait qu'afficher.

## Jauge d'eau : couleur normale, en recharge, et du clignotement « pas assez d'eau ».
const WATER_COLOR := Color(0.3, 0.68, 1.0)
const WATER_RECHARGE_COLOR := Color(0.55, 0.82, 1.0)
const WATER_DENIED_COLOR := Color(0.95, 0.3, 0.3)

@onready var _timer_panel: Control = %TimerPanel
@onready var _timer_label: Label = %TimerLabel
@onready var _blue_score_label: Label = %BlueScoreLabel
@onready var _red_score_label: Label = %RedScoreLabel
@onready var _capture: Control = %Capture
@onready var _capture_label: Label = %CaptureLabel
@onready var _capture_bar: ProgressBar = %CaptureBar
@onready var _water: Control = %Water
@onready var _water_bar: ProgressBar = %WaterBar
@onready var _water_percent: Label = %WaterPercent

var _water_flash: Tween


## Affiche le temps restant au format m:ss, arrondi à la seconde supérieure
## (1:00 pendant la première seconde, puis 0:59…). Négatif = chrono masqué.
func set_time_left(seconds: float) -> void:
	_timer_panel.visible = seconds >= 0.0
	var whole := ceili(maxf(seconds, 0.0))
	_timer_label.text = "%d:%02d" % [whole / 60, whole % 60]


## Jauge d'eau : `ratio` de 0 à 1 (négatif = masquée), plus claire pendant la recharge.
func set_water(ratio: float, recharging: bool) -> void:
	_water.visible = ratio >= 0.0
	_water_bar.value = ratio
	_water_percent.text = "%d %%" % roundi(ratio * 100.0)
	_water_fill().bg_color = WATER_RECHARGE_COLOR if recharging else WATER_COLOR


## Pas assez d'eau pour tirer : toute la jauge clignote en rouge (visible même vide) et
## tremble un peu.
func flash_water() -> void:
	if _water_flash and _water_flash.is_running():
		return # Déjà en train de clignoter (et de trembler) : on ne cumule pas les décalages.
	_water_flash = create_tween()
	for i in 2:
		_water_flash.tween_property(_water, ^"modulate", WATER_DENIED_COLOR, 0.06)
		_water_flash.tween_property(_water, ^"modulate", Color.WHITE, 0.12)
	# Tremblement : des décalages dont la somme est nulle, la jauge revient pile à sa place.
	var shake := create_tween()
	for x: float in [8.0, -14.0, 10.0, -4.0]:
		shake.tween_property(_water, ^"position:x", x, 0.045).as_relative()


func _water_fill() -> StyleBoxFlat:
	return _water_bar.get_theme_stylebox(&"fill") as StyleBoxFlat


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
