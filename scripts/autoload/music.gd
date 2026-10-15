extends Node
## Musique de fond, commune à tous les écrans (autoload : elle continue sans coupure
## d'un écran à l'autre et pendant la pause).
## Chaque écran choisit sa musique dans son _ready() :
##   - play(MENU) : tous les menus (chargement, accueil, hôte/IP, sélection des
##     équipes, fin) ; elle continue pendant la préparation du combat ;
##   - stop() : combat, sans musique.
## Si la musique demandée joue déjà, elle continue sans se relancer ; une musique
## interrompue reprend là où elle s'était arrêtée (sauf `from_start`). Les changements
## se font en fondu (FADE_TIME) : l'ancienne s'éteint, puis la nouvelle monte.

## « Happy Clappy Loop » (OwlishMedia, OpenGameArt, CC0) : boucle sans coupure
## (bouclage réglé dans les options d'import du .wav).
const MENU := preload("res://assets/audio/music/happy_clappy_loop.wav")
## Volume de chaque musique (dB), sous les effets sonores.
const VOLUMES_DB := {MENU: -10.0}
## Début de chaque musique (s), si elle ne commence pas à 0 (pour sauter une intro).
const START_POSITIONS := {}
## Volume en fin de fondu (dB) : inaudible.
const SILENT_DB := -40.0
## Durée d'un fondu (s).
const FADE_TIME := 0.8

var _player := AudioStreamPlayer.new()
var _fade: Tween
## Musique -> position (s) où elle s'est arrêtée, pour la reprendre au même endroit.
var _resume_positions := {}
## Musique demandée en dernier (celle qui joue, ou va jouer après le fondu de sortie).
var _wanted: AudioStream


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Continue pendant la pause.
	add_child(_player)


## Joue `stream` en boucle ; ne fait rien (sauf annuler un fondu de sortie) s'il joue déjà.
## `from_start` : repart du début au lieu de reprendre où elle s'était arrêtée.
func play(stream: AudioStream, from_start := false) -> void:
	_wanted = stream
	if from_start:
		_resume_positions.erase(stream)
	if _player.playing and _player.stream == stream:
		_fade_to(_volume_of(stream))
	elif _player.playing:
		# Une autre musique joue : on l'éteint en fondu, puis la nouvelle démarre.
		_fade_to(SILENT_DB).finished.connect(func() -> void:
			_pause()
			_start(_wanted))
	else:
		_start(stream)


## Arrête la musique en fondu.
func stop() -> void:
	_wanted = null
	if _player.playing:
		_fade_to(SILENT_DB).finished.connect(_pause)


func _start(stream: AudioStream) -> void:
	if stream == null:
		return
	_player.stream = stream
	_player.volume_db = SILENT_DB
	_player.play(_resume_positions.get(stream, START_POSITIONS.get(stream, 0.0)))
	_fade_to(_volume_of(stream))


func _pause() -> void:
	_resume_positions[_player.stream] = _player.get_playback_position()
	_player.stop()


func _volume_of(stream: AudioStream) -> float:
	return VOLUMES_DB.get(stream, -10.0)


func _fade_to(volume_db: float) -> Tween:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_player, ^"volume_db", volume_db, FADE_TIME)
	return _fade
