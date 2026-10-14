extends Node
## Musique de fond, commune à tous les écrans (autoload : elle continue sans coupure
## d'un écran à l'autre et pendant la pause).
## Chaque écran choisit sa musique dans son _ready() :
##   - play(MENU) : tous les menus (chargement, accueil, hôte/IP, sélection des
##     équipes, fin) ;
##   - stop() : combat.
## Si la musique demandée joue déjà, elle continue sans se relancer ; après un arrêt,
## elle reprend là où elle s'était arrêtée. Les changements se font en fondu (FADE_TIME).

## « Happy Clappy Loop » (OwlishMedia, OpenGameArt, CC0) : boucle sans coupure
## (bouclage réglé dans les options d'import du .wav).
const MENU := preload("res://assets/audio/music/happy_clappy_loop.wav")
## Volume de la musique (dB), sous les effets sonores.
const VOLUME_DB := -10.0
## Volume en fin de fondu (dB) : inaudible.
const SILENT_DB := -40.0
## Durée d'un fondu (s).
const FADE_TIME := 0.8

var _player := AudioStreamPlayer.new()
var _fade: Tween
## Position (s) où la musique s'est arrêtée, pour la reprendre au même endroit.
var _resume_position := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Continue pendant la pause.
	add_child(_player)


## Joue `stream` en boucle ; ne fait rien (sauf annuler un fondu de sortie) s'il joue déjà.
func play(stream: AudioStream) -> void:
	if _player.playing and _player.stream == stream:
		_fade_to(VOLUME_DB)
		return
	if _player.stream != stream:
		_player.stream = stream
		_resume_position = 0.0
	_player.volume_db = SILENT_DB
	_player.play(_resume_position)
	_fade_to(VOLUME_DB)


## Arrête la musique en fondu.
func stop() -> void:
	if _player.playing:
		_fade_to(SILENT_DB).finished.connect(_pause)


func _pause() -> void:
	_resume_position = _player.get_playback_position()
	_player.stop()


func _fade_to(volume_db: float) -> Tween:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_player, ^"volume_db", volume_db, FADE_TIME)
	return _fade
