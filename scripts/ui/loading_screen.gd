extends Control
## Écran de chargement (fictif) : la jauge (WaterGauge, comme la jauge d'eau du combat)
## se remplit par à-coups pendant DURATION secondes (bonds rapides, pauses), puis l'écran
## d'accueil s'affiche. « Chargement… » à gauche, pourcentage à droite. En fond, une image du jeu
## (assets/ui/loading : canards en pleine bataille dans la salle de bain, vue en plongée), assombrie
## en bas pour que le texte et la jauge restent lisibles.

const DURATION := 3.0
## Temps passé à 100 % avant de changer d'écran (compris dans DURATION).
const FINAL_HOLD := 0.25
const STEP_COUNT := 9
## Probabilité qu'une étape soit un "blocage" (la barre ne bouge pas).
const STALL_CHANCE := 0.3

@onready var _gauge: WaterGauge = %Gauge
@onready var _percent: Label = %Percent

## Progression (%), animée par le tween.
var _value := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(Music.MENU)
	var tween := create_tween()
	for step in _random_steps():
		if step.value == null:
			tween.tween_interval(step.duration)
		else:
			# Départ rapide puis ralentissement : un bond, comme un vrai chargement.
			tween.tween_property(self, ^"_value", step.value, step.duration) \
					.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(FINAL_HOLD)
	tween.finished.connect(get_tree().change_scene_to_file.bind(Screens.TITLE))


func _process(_delta: float) -> void:
	_gauge.ratio = _value / 100.0
	_percent.text = "%d %%" % roundi(_gauge.get_shown_ratio() * 100.0) # Ce que montre la jauge.


## Étapes { value, duration } dont la durée totale vaut DURATION - FINAL_HOLD.
## value = null pour une pause.
func _random_steps() -> Array[Dictionary]:
	var durations: Array[float] = []
	var gains: Array[float] = []
	for i in STEP_COUNT:
		durations.append(randf_range(0.4, 1.6))
		# La dernière étape avance toujours (pour finir à 100 %).
		var stall := i < STEP_COUNT - 1 and randf() < STALL_CHANCE
		gains.append(0.0 if stall else pow(randf_range(0.3, 1.0), 2.0))

	var total_duration: float = durations.reduce(func(a, b): return a + b)
	var total_gain: float = gains.reduce(func(a, b): return a + b)
	var steps: Array[Dictionary] = []
	var value := 0.0
	for i in STEP_COUNT:
		var duration := durations[i] / total_duration * (DURATION - FINAL_HOLD)
		if gains[i] == 0.0:
			steps.append({value = null, duration = duration})
		else:
			value += gains[i] / total_gain * 100.0
			steps.append({value = 100.0 if i == STEP_COUNT - 1 else value, duration = duration})
	return steps
