extends Control
## Sélection d'équipe (maquette : assets/ui/team_select/maquette.png) : deux serviettes,
## bleue (joueurs 1-2) et rouge (joueurs 3-4), avec un bouton par joueur.
##
## Chaque ordinateur choisit son joueur avec le joystick gauche, la croix ou les flèches
## (dans les 4 directions : les joueurs sont en grille, 1-2 à gauche et 3-4 à droite, de
## haut en bas), ou en cliquant sur un joueur libre. Un joueur pris par un autre
## ordinateur est grisé : on ne peut pas aller dessus.
## Les aides en bas à gauche montrent les touches de l'appareil utilisé (ButtonPrompt).
## A (ou Entrée, ou un clic sur son propre joueur) valide le choix et place le curseur
## sur « Lancer » ; B (ou Retour arrière) annule la validation. L'hôte lance la partie
## avec Start ou la bulle « Lancer ».
## Une fois le choix validé, une fenêtre demande son pseudo (pré-rempli avec le dernier
## utilisé, gardé dans NAME_FILE) : Entrée (ou A, Échap, un clic à côté) le valide, vide =
## « JOUEUR N ». Pseudos tout en majuscules. Un pseudo choisi remplace l'image « Joueur N » du
## bouton (même style : blanc, gros contour à la couleur de l'équipe), pour tous (NetworkManager.names). Échap / bulle « Quitter » -> écran hôte/IP.
## Les boutons grossissent au survol (et au focus clavier / manette).
## Joueur choisi par cet ordinateur : un peu plus gros, entouré d'un contour jaune qui
## pulse (fixe une fois le choix validé). Joueur pris par un autre ordinateur : grisé.
## Nécessite une session réseau (sinon retour à l'écran hôte/IP).

## Échelle d'un joueur survolé, du joueur choisi par cet ordinateur, et d'une bulle survolée.
const PLAYER_HOVER_SCALE := 1.06
const MINE_SCALE := 1.03
const BUBBLE_HOVER_SCALE := 1.12
## Actions de déplacement du choix -> direction dans la grille.
const DIRECTIONS := {
	&"menu_left": Vector2i.LEFT, &"menu_right": Vector2i.RIGHT,
	&"menu_up": Vector2i.UP, &"menu_down": Vector2i.DOWN,
}
## Place de chaque joueur dans la grille (colonne = équipe, rangée).
const GRID := {1: Vector2i(0, 0), 2: Vector2i(0, 1), 3: Vector2i(1, 0), 4: Vector2i(1, 1)}
## Vitesse de l'animation d'échelle (plus élevé = plus rapide).
const SCALE_SPEED := 14.0
## Teinte d'un joueur pris par un autre ordinateur.
const TAKEN_MODULATE := Color(0.5, 0.52, 0.58)
## Contour du joueur choisi par cet ordinateur : couleur, épaisseur (px) et pulsation (Hz).
const MINE_FRAME_COLOR := Color(1, 0.82, 0.1)
const MINE_FRAME_WIDTH := 6
const MINE_FRAME_PULSE := 1.2
## Dernier pseudo utilisé sur cet ordinateur.
const NAME_FILE := "user://profil.cfg"
const TITAN_FONT := preload("res://assets/fonts/titan_one/TitanOne-Regular.ttf")
## Couleur de la fenêtre du pseudo (bleu des boutons de l'équipe bleue).
const NAME_BLUE := Color(0.16, 0.42, 0.82)
## Pseudo sur le bouton d'un joueur : contour de chaque équipe (celui des images « Joueur N »),
## taille de police maximale et minimale, largeur disponible (px).
const PSEUDO_OUTLINES: Array[Color] = [Color("2a84c3"), Color("ef3240")]
const PSEUDO_MAX_FONT_SIZE := 46
const PSEUDO_MIN_FONT_SIZE := 20
const PSEUDO_WIDTH := 290.0

## Bouton -> vrai tant que la souris le survole.
var _hovered := {}
## Contour jaune de chaque joueur (visible sur celui de cet ordinateur).
var _frames: Array[Panel] = []
## Pseudo de chaque joueur, à la place de l'image « Joueur N » quand il en a choisi un.
var _pseudos: Array[Label] = []
## Fenêtre du pseudo (fond assombri + carte) et son champ de saisie.
var _name_entry: Control
var _name_edit: LineEdit

@onready var _info: Label = %Info
@onready var _players: Array[TextureButton] = [%Player1, %Player2, %Player3, %Player4]
@onready var _leave_button: TextureButton = %LeaveButton
@onready var _start_button: TextureButton = %StartButton


func _ready() -> void:
	if not NetworkManager.is_online():
		set_process(false)
		_leave.call_deferred()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play(Music.MENU)
	for i in _players.size():
		_players[i].pressed.connect(_on_player_pressed.bind(i + 1))
		_frames.append(_make_frame(_players[i]))
		_pseudos.append(_make_pseudo(_players[i], Player.team_of(i + 1)))
	for button: BaseButton in _players + [_start_button, _leave_button]:
		button.mouse_entered.connect(func() -> void: _hovered[button] = true)
		button.mouse_exited.connect(func() -> void: _hovered[button] = false)
	_leave_button.pressed.connect(_leave)
	_start_button.pressed.connect(NetworkManager.start_match)
	_start_button.visible = multiplayer.is_server()
	_name_entry = _make_name_entry()
	add_child(_name_entry)
	NetworkManager.slots_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if not NetworkManager.is_my_slot_locked():
		for action: StringName in DIRECTIONS:
			if Input.is_action_just_pressed(action):
				_move_choice(DIRECTIONS[action])
	if multiplayer.is_server() and Input.is_action_just_pressed(&"start"):
		UiSounds.play_confirm()
		NetworkManager.start_match()
	_animate_scales(delta)
	_animate_frames()


func _unhandled_input(event: InputEvent) -> void:
	# Les boutons qui ont le focus consomment ui_accept avant d'arriver ici.
	if event.is_action_pressed(&"ui_accept") and not NetworkManager.is_my_slot_locked():
		get_viewport().set_input_as_handled()
		_set_locked(true)
	elif event.is_action_pressed(&"menu_back") and NetworkManager.is_my_slot_locked():
		get_viewport().set_input_as_handled()
		_set_locked(false)
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()


## Clic sur un joueur : le choisir s'il est libre, valider (ou annuler) si c'est le sien.
## (Le son de validation est joué par UiSounds, branché sur tous les boutons.)
func _on_player_pressed(player_id: int) -> void:
	if NetworkManager.get_my_slot() == player_id:
		_set_locked(not NetworkManager.is_my_slot_locked(), false)
	elif not NetworkManager.is_my_slot_locked():
		NetworkManager.choose_slot(player_id)


## Va sur le joueur voisin dans la direction `direction`, s'il existe et qu'il est libre.
func _move_choice(direction: Vector2i) -> void:
	var cell: Vector2i = GRID.get(NetworkManager.get_my_slot(), Vector2i.ZERO) + direction
	var target: int = GRID.find_key(cell) if GRID.values().has(cell) else 0
	if target != 0 and NetworkManager.get_slot_owner(target) == 0:
		UiSounds.play_click()
		NetworkManager.choose_slot(target)


## `sound` : faux si le son est déjà joué (clic sur un bouton, cf. UiSounds).
func _set_locked(value: bool, sound := true) -> void:
	if sound:
		if value:
			UiSounds.play_confirm()
		else:
			UiSounds.play_click()
	NetworkManager.set_my_slot_locked(value)
	if value:
		_open_name_entry()
	else:
		_close_name_entry()
		get_viewport().gui_release_focus() # ← → servent à choisir le joueur, pas à naviguer.


## Fenêtre du pseudo, masquée au départ : fond assombri et carte au centre avec le champ.
func _make_name_entry() -> Control:
	var entry := ColorRect.new()
	entry.color = Color(0.02, 0.1, 0.2, 0.45)
	entry.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	entry.visible = false
	# Clic à côté de la carte : valide le pseudo.
	entry.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_submit_name())
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.97)
	style.border_color = NAME_BLUE
	style.set_border_width_all(6)
	style.set_corner_radius_all(28)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 10
	card.add_theme_stylebox_override(&"panel", style)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	entry.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	card.add_child(column)
	var title := _name_label("Ton pseudo", 30, Color(1, 0.82, 0.1))
	title.add_theme_color_override(&"font_outline_color", NAME_BLUE)
	title.add_theme_constant_override(&"outline_size", 10)
	column.add_child(title)
	_name_edit = LineEdit.new()
	_name_edit.max_length = NetworkManager.MAX_NAME_LENGTH
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size = Vector2(360, 58)
	_name_edit.add_theme_font_override(&"font", TITAN_FONT)
	_name_edit.add_theme_font_size_override(&"font_size", 28)
	_name_edit.add_theme_color_override(&"font_color", NAME_BLUE)
	_name_edit.add_theme_color_override(&"font_placeholder_color", Color(NAME_BLUE, 0.35))
	_name_edit.add_theme_color_override(&"caret_color", NAME_BLUE)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.9, 0.95, 1.0)
	field.border_color = Color(NAME_BLUE, 0.5)
	field.set_border_width_all(3)
	field.set_corner_radius_all(18)
	field.content_margin_left = 14
	field.content_margin_right = 14
	_name_edit.add_theme_stylebox_override(&"normal", field)
	_name_edit.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_submit_name.unbind(1))
	_name_edit.focus_exited.connect(_submit_name)
	_name_edit.gui_input.connect(_on_name_input)
	column.add_child(_name_edit)
	column.add_child(_name_label("Entrée pour valider", 16, Color(NAME_BLUE, 0.7)))
	return entry


func _name_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", TITAN_FONT)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


## Pseudos tout en majuscules : chaque lettre tapée passe en majuscule (le curseur ne bouge pas).
func _on_name_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		var caret := _name_edit.caret_column
		_name_edit.text = upper
		_name_edit.caret_column = caret


## Échap ou A (manette) dans le champ : valide le pseudo (Échap ne quitte pas le salon).
func _on_name_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") \
			or (event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept")):
		_name_edit.accept_event()
		_submit_name()


func _open_name_entry() -> void:
	var config := ConfigFile.new()
	config.load(NAME_FILE)
	_name_edit.text = NetworkManager.clean_name(config.get_value("profil", "pseudo", ""))
	_name_edit.placeholder_text = NetworkManager.default_name(NetworkManager.get_my_slot())
	_name_entry.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


## Masque la fenêtre sans rien valider (le champ masqué perd le focus : _submit_name ne
## fait alors plus rien).
func _close_name_entry() -> void:
	_name_entry.visible = false


func _submit_name() -> void:
	if not _name_entry.visible:
		return
	var player_name := NetworkManager.clean_name(_name_edit.text)
	_name_entry.visible = false
	NetworkManager.set_my_name(player_name)
	var config := ConfigFile.new()
	config.load(NAME_FILE)
	config.set_value("profil", "pseudo", player_name)
	config.save(NAME_FILE)
	UiSounds.play_confirm()
	if multiplayer.is_server():
		_start_button.grab_focus()
	else:
		get_viewport().gui_release_focus()


func _leave() -> void:
	NetworkManager.leave()
	get_tree().change_scene_to_file(Screens.CONNECT)


## Grossit en douceur les boutons survolés / avec le focus, et le joueur choisi.
func _animate_scales(delta: float) -> void:
	var my_slot := NetworkManager.get_my_slot()
	# La souris l'emporte sur le focus : seul le bouton survolé grossit.
	var mouse_over_any: bool = _hovered.values().has(true)
	for button: BaseButton in _players + [_start_button, _leave_button]:
		var is_player := button in _players
		var target := 1.0
		if _hovered.get(button, false) or (button.has_focus() and not mouse_over_any):
			target = PLAYER_HOVER_SCALE if is_player else BUBBLE_HOVER_SCALE
		elif is_player and _players.find(button) + 1 == my_slot:
			target = MINE_SCALE
		var weight := 1.0 - exp(-SCALE_SPEED * delta)
		button.scale = button.scale.lerp(Vector2.ONE * target, weight)


## Contour arrondi (sans fond) qui suit la forme du bouton `button`, masqué au départ.
func _make_frame(button: Control) -> Panel:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = MINE_FRAME_COLOR
	style.set_border_width_all(MINE_FRAME_WIDTH)
	style.set_corner_radius_all(34)
	style.set_expand_margin_all(MINE_FRAME_WIDTH)
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override(&"panel", style)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_bottom = -6.0 # Le bas de l'image du bouton est un peu transparent.
	frame.visible = false
	button.add_child(frame)
	return frame


## Pseudo posé sur le bouton `button`, à la place de l'image « Joueur N » (masqué au départ).
func _make_pseudo(button: TextureButton, team: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var image := button.get_node(^"Name") as Control
	label.position = Vector2((button.size.x - PSEUDO_WIDTH) / 2.0, image.position.y - 6.0)
	label.size = Vector2(PSEUDO_WIDTH, image.size.y + 12.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", TITAN_FONT)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_outline_color", PSEUDO_OUTLINES[team - 1])
	label.add_theme_constant_override(&"outline_size", 14)
	label.visible = false
	button.add_child(label)
	return label


## Affiche `text` sur `label`, en réduisant la police pour qu'il tienne sur le bouton.
func _set_pseudo(label: Label, text: String) -> void:
	if label.text == text:
		return
	label.text = text
	var font_size := PSEUDO_MAX_FONT_SIZE
	while font_size > PSEUDO_MIN_FONT_SIZE \
			and TITAN_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 14.0 > PSEUDO_WIDTH:
		font_size -= 2
	label.add_theme_font_size_override(&"font_size", font_size)


## Le contour du joueur de cet ordinateur pulse tant que le choix n'est pas validé.
func _animate_frames() -> void:
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * TAU * MINE_FRAME_PULSE)
	var alpha := 1.0 if NetworkManager.is_my_slot_locked() else pulse
	for frame in _frames:
		frame.modulate.a = alpha


func _refresh() -> void:
	var my_id := multiplayer.get_unique_id()
	for i in _players.size():
		var player_id := i + 1
		var owner_id: int = NetworkManager.slots.get(player_id, 0)
		var is_locked: bool = NetworkManager.locked.get(player_id, false)
		var state: Label = _players[i].get_node(^"State")
		var taken := owner_id != 0 and owner_id != my_id
		_players[i].modulate = TAKEN_MODULATE if taken else Color.WHITE
		_frames[i].visible = owner_id == my_id
		# Pseudo choisi : à la place de l'image « Joueur N ». Dessous : qui l'a pris (sans
		# pseudo), puis « prêt » une fois validé.
		var has_pseudo := owner_id != 0 and not str(NetworkManager.names.get(owner_id, "")).is_empty()
		_players[i].get_node(^"Name").visible = not has_pseudo
		_pseudos[i].visible = has_pseudo
		if has_pseudo:
			_set_pseudo(_pseudos[i], NetworkManager.get_player_name(player_id))
		var parts := PackedStringArray()
		if not has_pseudo and taken:
			parts.append("Pris par l'hôte" if owner_id == 1 else "Pris")
		if owner_id != 0 and is_locked:
			parts.append("✔ prêt")
		state.text = "  ".join(parts)

	var count := NetworkManager.get_connected_count()
	if multiplayer.is_server():
		var addresses := NetworkManager.get_local_ipv4_addresses()
		var ip_text := "  ou  ".join(addresses) if not addresses.is_empty() else "introuvable (es-tu connecté à un réseau ?)"
		_info.text = "Tu héberges la partie. Les autres ordinateurs doivent rejoindre l'IP : %s\nOrdinateurs connectés : %d / %d" % [ip_text, count, NetworkManager.MAX_PLAYERS]
	else:
		_info.text = "Connecté à l'hôte  ·  Ordinateurs connectés : %d / %d\nEn attente que l'hôte lance la partie…" % [count, NetworkManager.MAX_PLAYERS]
