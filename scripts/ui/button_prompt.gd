class_name ButtonPrompt
extends Control
## Icône de la touche « valider » ou « annuler » des menus, selon l'appareil utilisé en
## dernier (InputManager.device_type) : clavier, ou manette PlayStation, Nintendo, Xbox.
## Les boutons sont repérés par leur position (cf. InputManager) : valider = bouton de
## droite (◯ / A / B), annuler = bouton du bas (✕ / B / A).

enum Role { ACCEPT, BACK }

const PS_ICONS := {
	Role.ACCEPT: preload("res://assets/ui/team_select/o_button.png"),
	Role.BACK: preload("res://assets/ui/team_select/x_button.png"),
}
## Lettre et couleur de la lettre du bouton : Nintendo, puis Xbox.
const NINTENDO_LETTERS := {Role.ACCEPT: ["A", Color(0.95, 0.95, 0.95)], Role.BACK: ["B", Color(0.95, 0.95, 0.95)]}
const XBOX_LETTERS := {Role.ACCEPT: ["B", Color("e5484d")], Role.BACK: ["A", Color("5cc35c")]}
const KEYS := {Role.ACCEPT: "Entrée", Role.BACK: "Retour"}

@export var role := Role.ACCEPT
@export var font_size := 18

var _style := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.bg_color = Color(0.97, 0.98, 1.0)
	_style.border_color = Color(0.07, 0.25, 0.45)
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(8)
	InputManager.device_type_changed.connect(_on_device_changed)
	_on_device_changed()


func _get_minimum_size() -> Vector2:
	var height := size.y if size.y > 0.0 else 44.0
	if InputManager.device_type == InputManager.DeviceType.KEYBOARD:
		var text_width := get_theme_default_font().get_string_size(KEYS[role], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		return Vector2(text_width + 24.0, height)
	return Vector2(height, height)


func _draw() -> void:
	var font := get_theme_default_font()
	var device: int = InputManager.device_type
	if device == InputManager.DeviceType.KEYBOARD:
		var key := Rect2(Vector2(0, size.y * 0.12), Vector2(size.x, size.y * 0.76))
		draw_style_box(_style, key)
		_draw_centered(font, KEYS[role], key, font_size, _style.border_color)
	elif device == InputManager.DeviceType.PLAYSTATION:
		draw_texture_rect(PS_ICONS[role], Rect2(Vector2.ZERO, Vector2.ONE * size.y), false)
	else:
		var letters: Dictionary = NINTENDO_LETTERS if device == InputManager.DeviceType.NINTENDO else XBOX_LETTERS
		var letter: Array = letters[role]
		var radius := size.y / 2.0
		draw_circle(Vector2.ONE * radius, radius, Color(0.06, 0.06, 0.08))
		_draw_centered(font, letter[0], Rect2(Vector2.ZERO, Vector2.ONE * size.y), int(size.y * 0.55), letter[1])


func _draw_centered(font: Font, text: String, area: Rect2, text_size: int, color: Color) -> void:
	var text_box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size)
	var baseline := area.get_center() + Vector2(-text_box.x / 2.0, font.get_ascent(text_size) - text_box.y / 2.0)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)


func _on_device_changed() -> void:
	update_minimum_size()
	queue_redraw()
