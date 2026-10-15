extends Control
## Écran de fin, au style des autres menus : titre jaune, serviette bleue et serviette rouge
## avec le score de chaque équipe (NetworkManager.final_scores, envoyés par l'hôte) et les
## pseudos de ses joueurs, badge « Gagné ! » sur la serviette gagnante (aucun en cas d'égalité),
## puis Rejouer (bouton jaune -> sélection d'équipe) ou Quitter (bulle, ferme le jeu).
## Rejouer est individuel : chaque ordinateur revient au salon quand il veut.
## À l'ouverture, les scores défilent de 0 à leur valeur, puis la serviette gagnante grossit
## et le badge apparaît. Les boutons grossissent au survol (et au focus clavier / manette).
## Échap ou B / Retour arrière : Quitter.

## Échelle du bouton « Rejouer » survolé, et de la bulle « Quitter » survolée.
const BUTTON_HOVER_SCALE := 1.06
const BUBBLE_HOVER_SCALE := 1.12
## Vitesse de l'animation d'échelle (plus élevé = plus rapide).
const SCALE_SPEED := 14.0
## Durée (s) du défilement des scores, et échelle de la serviette gagnante.
const COUNT_DURATION := 0.9
const WINNER_SCALE := 1.06
## Serviette perdante : un peu assombrie.
const LOSER_MODULATE := Color(0.78, 0.8, 0.86)
## Contour du texte « Victoire de l'équipe … » : bleu ou rouge des boutons de l'équipe.
const TEAM_OUTLINES: Array[Color] = [Color(0.1, 0.38, 0.72), Color(0.72, 0.1, 0.16)]

## Bouton -> vrai tant que la souris le survole.
var _hovered := {}

@onready var _winner: Label = %Winner
@onready var _towels: Array[TextureRect] = [%Towel1, %Towel2]
@onready var _badge: TextureRect = %Badge
@onready var _replay_button: TextureButton = %ReplayButton
@onready var _quit_button: TextureButton = %QuitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(Music.MENU)
	_replay_button.pressed.connect(_replay)
	_quit_button.pressed.connect(get_tree().quit)
	for button: BaseButton in [_replay_button, _quit_button]:
		button.mouse_entered.connect(func() -> void: _hovered[button] = true)
		button.mouse_exited.connect(func() -> void: _hovered[button] = false)
	_show_scores(NetworkManager.final_scores)
	_replay_button.grab_focus()


func _process(delta: float) -> void:
	# La souris l'emporte sur le focus : seul le bouton survolé grossit.
	var mouse_over_any: bool = _hovered.values().has(true)
	for button: BaseButton in [_replay_button, _quit_button]:
		var target := 1.0
		if _hovered.get(button, false) or (button.has_focus() and not mouse_over_any):
			target = BUBBLE_HOVER_SCALE if button == _quit_button else BUTTON_HOVER_SCALE
		button.scale = button.scale.lerp(Vector2.ONE * target, 1.0 - exp(-SCALE_SPEED * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"menu_back"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


## `scores` : équipe (1 ou 2) -> points.
func _show_scores(scores: Dictionary) -> void:
	var totals: Array[int] = [int(scores.get(1, 0)), int(scores.get(2, 0))]
	var winner := 0 if totals[0] > totals[1] else 1 if totals[1] > totals[0] else -1
	if winner == -1:
		_winner.text = "Égalité !"
	else:
		_winner.text = "Victoire de l'équipe %s !" % Player.TEAM_NAMES[winner]
		_winner.add_theme_color_override(&"font_outline_color", TEAM_OUTLINES[winner])
	for i in _towels.size():
		(_towels[i].get_node(^"Players") as Label).text = _team_names(i + 1)
		var score: Label = _towels[i].get_node(^"Score/Text")
		var tween := create_tween()
		tween.tween_method(func(value: float) -> void: score.text = str(roundi(value)),
				0.0, float(totals[i]), COUNT_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await get_tree().create_timer(COUNT_DURATION).timeout
	if winner == -1:
		return
	_towels[1 - winner].modulate = LOSER_MODULATE
	var towel := _towels[winner]
	create_tween().tween_property(towel, ^"scale", Vector2.ONE * WINNER_SCALE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_badge(towel)


## Badge « Gagné ! » penché sur le coin haut droit de la serviette `towel` (sous la ligne du vainqueur), qui apparaît puis
## pulse doucement.
func _show_badge(towel: TextureRect) -> void:
	_badge.position = towel.position + Vector2(towel.size.x - _badge.size.x * 0.8, -_badge.size.y * 0.15)
	_badge.rotation_degrees = 8.0
	_badge.scale = Vector2.ZERO
	_badge.visible = true
	var tween := create_tween()
	tween.tween_property(_badge, ^"scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		var pulse := create_tween().set_loops()
		pulse.tween_property(_badge, ^"scale", Vector2.ONE * 1.06, 0.6).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_badge, ^"scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE))


## Pseudos des joueurs de l'équipe `team` qui ont joué (un par ligne), sinon « Personne ».
func _team_names(team: int) -> String:
	var names := PackedStringArray()
	for player_id in range(1, NetworkManager.MAX_PLAYERS + 1):
		if Player.team_of(player_id) == team and NetworkManager.get_slot_owner(player_id) != 0:
			names.append(NetworkManager.get_player_name(player_id))
	return "\n".join(names) if not names.is_empty() else "Personne"


func _replay() -> void:
	# Hors ligne (ou hôte parti), la sélection d'équipe renvoie à l'écran hôte/IP.
	get_tree().change_scene_to_file(Screens.TEAM_SELECT)
