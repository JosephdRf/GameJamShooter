class_name KillFeed
extends CanvasLayer
## Fil des éliminations, en haut à droite : « Romeo a éclaté Edouard » (pseudos aux couleurs
## des équipes), « Edouard est tombé » sans tireur (chute hors de l'arène). Les messages qui
## concernent le joueur de cet ordinateur sont entourés de jaune. Chaque message reste
## `message_duration` s puis s'efface ; au plus `max_messages` à la fois (les plus anciens
## partent). Rempli par Game (signal Player.eliminated), sur chaque ordinateur.
## En bas de l'écran, à droite de la jauge d'eau, chez le tireur seulement : « Vous avez éliminé
## ROMEO » (pseudo à la couleur de son équipe, « Joueur N » sans pseudo), avec un son
## d'élimination (pop de bulle + arpège de clochettes, sfx/kill) ; il apparaît en gonflant,
## reste `banner_duration` s puis s'efface ; une nouvelle élimination le remplace.

const TITAN_FONT := preload("res://assets/fonts/titan_one/TitanOne-Regular.ttf")
const FADE_DURATION := 0.4
## Contour des messages qui concernent le joueur de cet ordinateur.
const MINE_BORDER := Color(1, 0.82, 0.1)
const KILL_SOUND := preload("res://assets/audio/sfx/kill/kill.wav")
## Message d'élimination : bord gauche (px, à droite de la jauge d'eau du MatchHud) et hauteur
## de sa ligne (au niveau de la jauge, en bas de l'écran).
const BANNER_LEFT := 510.0
const BANNER_TOP := -92.0
const BANNER_BOTTOM := -28.0

@export var message_duration := 5.0
@export var max_messages := 5
@export var font_size := 22
@export var banner_duration := 2.5
@export var banner_font_size := 34

var _list: VBoxContainer
## Message « Vous avez éliminé … » en bas de l'écran.
var _banner: HBoxContainer
var _banner_tween: Tween
var _kill_sound := AudioStreamPlayer.new()


func _ready() -> void:
	layer = 5
	_list = VBoxContainer.new()
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_list.offset_right = -24.0
	_list.offset_top = 24.0
	_list.alignment = BoxContainer.ALIGNMENT_BEGIN
	_list.add_theme_constant_override(&"separation", 6)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	_banner = HBoxContainer.new()
	_banner.alignment = BoxContainer.ALIGNMENT_BEGIN
	_banner.add_theme_constant_override(&"separation", 12)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 1.0
	_banner.anchor_bottom = 1.0
	_banner.offset_left = BANNER_LEFT
	_banner.offset_top = BANNER_TOP
	_banner.offset_bottom = BANNER_BOTTOM
	_banner.visible = false
	add_child(_banner)
	_kill_sound.stream = KILL_SOUND
	_kill_sound.volume_db = -4.0
	add_child(_kill_sound)


## Chez le tireur : « Vous avez éliminé `victim` » en bas de l'écran.
func show_my_elimination(victim: Player) -> void:
	for child in _banner.get_children():
		_banner.remove_child(child)
		child.queue_free()
	var text := _text_label("Vous avez éliminé")
	var victim_label := _name_label(victim)
	for label: Label in [text, victim_label]:
		label.add_theme_font_size_override(&"font_size", banner_font_size)
		label.add_theme_constant_override(&"outline_size", 12)
		_banner.add_child(label)
	_kill_sound.play()
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner.pivot_offset = Vector2(0.0, _banner.size.y / 2.0) # Gonfle depuis la gauche.
	_banner.scale = Vector2.ONE * 0.6
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, ^"modulate:a", 1.0, 0.12)
	_banner_tween.parallel().tween_property(_banner, ^"scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(banner_duration)
	_banner_tween.tween_property(_banner, ^"modulate:a", 0.0, FADE_DURATION)
	_banner_tween.tween_callback(_banner.hide)


## `killer` : null s'il n'y a pas de tireur (chute). `mine` : le joueur de cet ordinateur est
## concerné.
func add_elimination(killer: Player, victim: Player, mine: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	if killer and killer != victim:
		row.add_child(_name_label(killer))
		row.add_child(_text_label("a éclaté"))
		row.add_child(_name_label(victim))
	else:
		row.add_child(_name_label(victim))
		row.add_child(_text_label("est tombé"))
	_push(row, mine)


func _push(row: Control, mine: bool) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.12, 0.22, 0.72)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	if mine:
		style.border_color = MINE_BORDER
		style.set_border_width_all(3)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.add_child(row)
	_list.add_child(panel)
	while _list.get_child_count() > max_messages:
		var oldest := _list.get_child(0)
		_list.remove_child(oldest)
		oldest.queue_free()
	# Apparaît en glissant depuis la droite, reste, puis s'efface.
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, ^"modulate:a", 1.0, 0.15)
	tween.tween_interval(message_duration)
	tween.tween_property(panel, ^"modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(panel.queue_free)


func _name_label(player: Player) -> Label:
	var label := _text_label(player.get_display_name())
	label.add_theme_color_override(&"font_color", player.get_team_color().lightened(0.25))
	return label


func _text_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", TITAN_FONT)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_outline_color", Color(0.02, 0.06, 0.12))
	label.add_theme_constant_override(&"outline_size", 6)
	return label
