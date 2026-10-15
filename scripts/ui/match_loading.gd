extends Control
## Préparation du combat, entre la sélection d'équipe et le combat (sur tous les
## ordinateurs, cf. NetworkManager._load_game) : même mise en page que l'écran de
## chargement (texte à gauche, pourcentage à droite, barre dessous, fond noir), mais avec
## une rangée de bulles (BubbleBar) à la couleur de l'équipe du joueur.
## Au centre, deux fiches se succèdent (NOTE_TIME s chacune) : l'histoire des canards,
## puis les commandes, avec les touches de l'appareil utilisé (clavier, manette Nintendo,
## PlayStation ou Xbox, cf. InputManager.device_type ; elles changent si le joueur en change).
## Décor : en haut, deux planches « carnet d'inventeur » (le canard et son pistolet à bulles,
## de face et de profil, assets/ui/plates) posées de travers, avec une ombre et du ruban
## adhésif ; les fiches s'affichent en dessous.
## La scène de combat (avec l'arène) se charge pour de vrai en arrière-plan, puis elle est créée
## sur un autre fil (WorkerThreadPool) et l'arène est rendue une première fois dans une vue cachée
## (compilation de ses shaders) : le passage au combat ne fige plus l'image. l'écran dure DURATION s
## (plus longtemps seulement si le chargement n'est pas fini), puis le combat s'affiche.

const DURATION := 8.0
## Temps passé à 100 % avant de changer d'écran (compris dans DURATION).
const FINAL_HOLD := 0.35
## Durée d'affichage de chaque fiche (s) et de leur fondu d'entrée / de sortie.
const NOTE_TIME := 4.0
const NOTE_FADE := 0.25
const NOTE_WIDTH := 720.0
const CONTROLS_WIDTH := 920.0
## Planches du décor : image, centre (fraction de l'écran), largeur (px), inclinaison (deg).
const PLATES := [
	[preload("res://assets/ui/plates/plate_duck.jpg"), Vector2(0.27, 0.235), 480.0, -3.0],
	[preload("res://assets/ui/plates/plate_gun.jpg"), Vector2(0.73, 0.235), 480.0, 2.5],
]
const TAPE_COLOR := Color(0.93, 0.9, 0.78, 0.75)
const FONT := preload("res://assets/fonts/titan_one/TitanOne-Regular.ttf")
const PAPER := Color(0.97, 0.97, 0.94)
const INK := Color(0.12, 0.2, 0.3)
const LORE_COLOR := Color(0.95, 0.68, 0.1)

const LORE_TITLE := "Le saviez-vous ?"
const LORE_TEXT := "Abandonnés dans une salle de bain, les canards se font chier comme jamais… Alors ils ont tout mis en bordel : serviettes, rouleaux de papier et flacons traînent partout. Maintenant, c'est la guerre des bulles !"
const CONTROLS_TITLE := "Commandes"
## Actions de la fiche des commandes : action (InputMap), ce qu'elle fait.
const CONTROLS := [
	[&"shoot", "Tirer des bulles de savon"],
	[&"capture", "Capturer un canard adverse"],
	[&"water_cannon", "Arroser au jet d'eau"],
	[&"dash", "Dasher"],
]
## Touches affichées par appareil (cf. InputManager.DeviceType) : action -> [type de
## pastille, texte, couleur de la lettre, symbole]. Mêmes touches que dans l'InputMap
## (manette : repérées par position, cf. InputManager).
const BADGES := {
	InputManager.DeviceType.KEYBOARD: {
		&"shoot": [InputBadge.Kind.KEY, "Clic gauche"],
		&"capture": [InputBadge.Kind.KEY, "Clic molette"],
		&"water_cannon": [InputBadge.Kind.KEY, "Clic droit"],
		&"dash": [InputBadge.Kind.KEY, "Maj"],
	},
	InputManager.DeviceType.NINTENDO: {
		&"shoot": [InputBadge.Kind.SHOULDER, "ZR"],
		&"capture": [InputBadge.Kind.SHOULDER, "R"],
		&"water_cannon": [InputBadge.Kind.SHOULDER, "ZL"],
		&"dash": [InputBadge.Kind.FACE, "Y", Color(0.95, 0.95, 0.95)],
	},
	InputManager.DeviceType.PLAYSTATION: {
		&"shoot": [InputBadge.Kind.SHOULDER, "R2"],
		&"capture": [InputBadge.Kind.SHOULDER, "R1"],
		&"water_cannon": [InputBadge.Kind.SHOULDER, "L2"],
		&"dash": [InputBadge.Kind.FACE, "", Color.WHITE, InputBadge.Symbol.SQUARE],
	},
	InputManager.DeviceType.XBOX: {
		&"shoot": [InputBadge.Kind.SHOULDER, "RT"],
		&"capture": [InputBadge.Kind.SHOULDER, "RB"],
		&"water_cannon": [InputBadge.Kind.SHOULDER, "LT"],
		&"dash": [InputBadge.Kind.FACE, "X", Color("4f8ff7")],
	},
}

@onready var _bar: BubbleBar = %Bar
@onready var _label: Label = %Label
@onready var _percent: Label = %Percent

## Progression (%), animée par le tween.
var _value := 0.0
var _done := false
## Combat préparé pendant l'écran : scène chargée, instance créée sur un autre fil, et vue cachée
## qui rend l'arène pour compiler ses shaders d'avance.
var _game_scene: PackedScene
var _game: Node
var _instancing_task := -1
var _warmup: SubViewport
var _warmup_arena: Node
var _warmup_camera: Camera3D
var _warmup_time := 0.0
var _team_color := Player.TEAM_COLORS[0]
var _notes: Array[Control] = []
## Lignes de la fiche des commandes : action -> conteneur de sa pastille.
var _badge_slots := {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ResourceLoader.load_threaded_request(Screens.GAME)
	var slot := NetworkManager.get_my_slot()
	_team_color = Player.color_of(slot) if slot > 0 else Player.TEAM_COLORS[0]
	_bar.color = _team_color
	for label in [_label, _percent]:
		label.add_theme_color_override(&"font_shadow_color", _team_color)
		label.add_theme_color_override(&"font_outline_color", _team_color.darkened(0.45))
	_build_decor()
	_build_notes()
	InputManager.device_type_changed.connect(_update_badges)
	_update_badges()
	# Trois bonds (départ rapide puis ralentissement) séparés de courtes hésitations.
	var tween := create_tween()
	var stops := [randf_range(0.25, 0.45), randf_range(0.6, 0.8), 1.0]
	var pauses := [0.0, randf_range(0.15, 0.35), randf_range(0.15, 0.35)]
	var duration: float = (DURATION - FINAL_HOLD - pauses[1] - pauses[2]) / stops.size()
	for i in stops.size():
		tween.tween_interval(pauses[i])
		tween.tween_property(self, ^"_value", stops[i] * 100.0, duration) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(FINAL_HOLD)
	tween.finished.connect(func() -> void: _done = true)
	# Fiches : l'une après l'autre, entrée en glissant vers le haut, sortie en fondu.
	var notes_tween := create_tween()
	for i in _notes.size():
		var note := _notes[i]
		notes_tween.tween_callback(func() -> void:
			note.show()
			note.position.y += 24.0)
		notes_tween.tween_property(note, ^"modulate:a", 1.0, NOTE_FADE)
		notes_tween.parallel().tween_property(note, ^"position:y", -24.0, NOTE_FADE).as_relative() \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		notes_tween.tween_interval(NOTE_TIME - NOTE_FADE * (2.0 if i < _notes.size() - 1 else 1.0))
		if i < _notes.size() - 1:
			notes_tween.tween_property(note, ^"modulate:a", 0.0, NOTE_FADE)
			notes_tween.tween_callback(note.hide)


func _process(delta: float) -> void:
	_bar.ratio = _value / 100.0
	_percent.text = "%d %%" % roundi(_value)
	_prepare_game(delta)
	if not _done:
		return
	if _instancing_task != -1 and not WorkerThreadPool.is_task_completed(_instancing_task):
		return # Encore en création : on attend sur l'écran (la barre reste à 100 %).
	if _game_scene == null and ResourceLoader.load_threaded_get_status(Screens.GAME) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_done = false
	if _instancing_task != -1:
		WorkerThreadPool.wait_for_task_completion(_instancing_task)
		_instancing_task = -1
	_free_warmup()
	if _game:
		var game := _game
		_game = null
		get_tree().change_scene_to_node(game)
	else:
		get_tree().change_scene_to_file(Screens.GAME)


func _exit_tree() -> void:
	if _instancing_task != -1:
		WorkerThreadPool.wait_for_task_completion(_instancing_task)
		_instancing_task = -1
	if _game: # Écran quitté sans lancer le combat (déconnexion…).
		_game.free()
		_game = null
	if _warmup_arena and not _warmup_arena.is_inside_tree():
		_warmup_arena.free()
	_warmup_arena = null


## Dès que la scène de combat est chargée : création sur un autre fil, et rendu de l'arène dans
## une vue cachée (caméra qui tourne au centre) jusqu'à la fin de l'écran.
func _prepare_game(delta: float) -> void:
	if _game_scene == null:
		if ResourceLoader.load_threaded_get_status(Screens.GAME) != ResourceLoader.THREAD_LOAD_LOADED:
			return
		_game_scene = ResourceLoader.load_threaded_get(Screens.GAME) as PackedScene
		if _game_scene == null:
			return
		var arena_scene := _arena_scene()
		_instancing_task = WorkerThreadPool.add_task(func() -> void:
			_game = _game_scene.instantiate()
			if arena_scene:
				_warmup_arena = arena_scene.instantiate())
	if _warmup == null and _warmup_arena and WorkerThreadPool.is_task_completed(_instancing_task):
		_start_warmup()
	if _warmup_camera:
		_warmup_time += delta
		_warmup_camera.rotation.y = _warmup_time * 1.5


## Scène de l'arène (nœud Arena de la scène de combat).
func _arena_scene() -> PackedScene:
	var state := _game_scene.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) == &"Arena" and state.get_node_instance(i):
			return state.get_node_instance(i)
	return null


func _start_warmup() -> void:
	_warmup = SubViewport.new()
	_warmup.size = Vector2i(320, 180)
	_warmup.own_world_3d = true
	_warmup.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warmup)
	_warmup.add_child(_warmup_arena)
	_warmup_camera = Camera3D.new()
	_warmup_camera.position = Vector3(0, 8, 0)
	_warmup_camera.far = 300.0
	_warmup.add_child(_warmup_camera)
	_warmup_camera.current = true


func _free_warmup() -> void:
	if _warmup:
		_warmup.queue_free()
		_warmup = null
		_warmup_camera = null
	elif _warmup_arena:
		_warmup_arena.free()
	_warmup_arena = null


## Planches du décor, juste au-dessus du fond et des bulles (sous la barre et les fiches).
func _build_decor() -> void:
	var index := get_node(^"Bubbles").get_index() + 1
	for spec: Array in PLATES:
		var texture: Texture2D = spec[0]
		var plate_size := Vector2(spec[2], spec[2] * texture.get_height() / texture.get_width())
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.anchor_left = spec[1].x
		holder.anchor_right = spec[1].x
		holder.anchor_top = spec[1].y
		holder.anchor_bottom = spec[1].y
		holder.rotation = deg_to_rad(spec[3])
		add_child(holder)
		move_child(holder, index)
		index += 1
		var shadow := ColorRect.new()
		shadow.color = Color(0, 0, 0, 0.45)
		shadow.size = plate_size
		shadow.position = -plate_size / 2.0 + Vector2(10, 12)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(shadow)
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_SCALE
		image.size = plate_size
		image.position = -plate_size / 2.0
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(image)
		# Deux bouts de ruban adhésif en haut.
		for side in [-1, 1]:
			var tape := ColorRect.new()
			tape.color = TAPE_COLOR
			tape.size = Vector2(70, 22)
			tape.pivot_offset = tape.size / 2.0
			tape.position = Vector2(side * plate_size.x * 0.36, -plate_size.y / 2.0) - tape.size / 2.0
			tape.rotation = deg_to_rad(side * 28.0)
			tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(tape)


## Les deux fiches, sous les planches et au-dessus de la barre, masquées au départ.
func _build_notes() -> void:
	var lore_body := _text(LORE_TEXT, 22, INK)
	lore_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore_body.custom_minimum_size.x = NOTE_WIDTH - 60.0 # Largeur du texte (sinon sa hauteur est calculée sur une largeur nulle).
	_notes.append(_note("?", LORE_TITLE, LORE_COLOR, lore_body, -1.2))
	# Commandes sur deux colonnes : la fiche reste assez basse pour ne pas cacher la barre.
	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override(&"h_separation", 28)
	rows.add_theme_constant_override(&"v_separation", 8)
	for control: Array in CONTROLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		var slot := CenterContainer.new()
		slot.custom_minimum_size = Vector2(140, 38)
		row.add_child(slot)
		_badge_slots[control[0]] = slot
		var text := _text(control[1], 20, INK)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		rows.add_child(row)
	_notes.append(_note("!", CONTROLS_TITLE, _team_color, rows, 1.0, CONTROLS_WIDTH))
	for note in _notes:
		note.modulate.a = 0.0
		note.hide()


## Fiche : carte claire légèrement penchée, onglet de couleur avec une pastille (`icon`) et
## le titre, puis `body`.
func _note(icon: String, title: String, color: Color, body: Control, tilt_degrees: float, width := NOTE_WIDTH) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.border_color = color
	paper.set_border_width_all(0)
	paper.border_width_top = 10
	paper.set_corner_radius_all(22)
	paper.shadow_color = Color(0, 0, 0, 0.45)
	paper.shadow_size = 18
	paper.shadow_offset = Vector2(0, 8)
	paper.content_margin_left = 30
	paper.content_margin_right = 30
	paper.content_margin_top = 16
	paper.content_margin_bottom = 20
	card.add_theme_stylebox_override(&"panel", paper)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	card.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 14)
	column.add_child(header)
	var badge := PanelContainer.new()
	var dot := StyleBoxFlat.new()
	dot.bg_color = color
	dot.set_corner_radius_all(22)
	dot.content_margin_left = 14
	dot.content_margin_right = 14
	badge.add_theme_stylebox_override(&"panel", dot)
	badge.custom_minimum_size = Vector2(44, 44)
	var mark := _text(icon, 28, Color.WHITE)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(mark)
	header.add_child(badge)
	var heading := _text(title, 30, color.darkened(0.25))
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(heading)
	column.add_child(body)
	card.custom_minimum_size.x = width
	card.rotation = deg_to_rad(tilt_degrees)
	card.resized.connect(func() -> void: card.pivot_offset = card.size / 2.0)
	# Centrée au-dessus de la barre (le conteneur calcule la hauteur du texte sur plusieurs lignes).
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.anchor_top = 0.42
	holder.anchor_bottom = 0.7
	holder.add_child(card)
	add_child(holder)
	return holder


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override(&"font", FONT)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label


## Pastilles de la fiche des commandes, selon l'appareil utilisé en dernier.
func _update_badges() -> void:
	var badges: Dictionary = BADGES.get(InputManager.device_type, BADGES[InputManager.DeviceType.KEYBOARD])
	for action: StringName in _badge_slots:
		var slot: Control = _badge_slots[action]
		for child in slot.get_children():
			child.queue_free()
		var spec: Array = badges[action]
		var badge := InputBadge.new()
		badge.badge_height = 38.0
		slot.add_child(badge.setup(spec[0], spec[1],
				spec[2] if spec.size() > 2 else Color.WHITE,
				spec[3] if spec.size() > 3 else InputBadge.Symbol.NONE))
