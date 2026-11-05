extends RefCounted
class_name CommercialUI

## 전체 화면에서 공유하는 상용 게임 UI 팔레트와 컴포넌트 스타일입니다.

const INK := Color("0b201d")
const PANEL := Color("17352f")
const PANEL_RAISED := Color("24483e")
const PANEL_SOFT := Color("315b4d")
const TEAL := Color("8be2b2")
const TEAL_DARK := Color("4b9475")
const GOLD := Color("ffda78")
const GOLD_DARK := Color("d99a37")
const TEXT := Color("f3fbf8")
const TEXT_BRIGHT := Color("ffffff")
const TEXT_MUTED := Color("b6cec1")
const DANGER := Color("ff6b6b")
const SUCCESS := Color("75e69b")
const BORDER_MUTED := Color("45665a")
const BORDER_ACCENT := Color("8be2b2")
const NAVY_PANEL_ALT := Color("102923")
const NAVY_CARD := Color("1b3c33")

static func apply_panel_container(container: PanelContainer, bg: Color = PANEL, border: Color = TEAL_DARK, radius: int = 12) -> void:
	container.add_theme_stylebox_override("panel", panel(bg, border, radius))

static func panel(bg: Color = PANEL, border: Color = TEAL_DARK, radius: int = 12, border_width: int = 1, shadow_size: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.015, 0.035, 0.025, 0.26)
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2(0, 3)
	style.anti_aliasing = true
	return style

static func padded_panel(bg: Color = PANEL, border: Color = TEAL_DARK, padding: float = 14.0, radius: int = 12) -> StyleBoxFlat:
	var style := panel(bg, border.darkened(0.12), radius, 1, 6)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style

static func button_style(bg: Color, border: Color, radius: int = 10, padding_x: float = 14.0, padding_y: float = 8.0) -> StyleBoxFlat:
	var style := panel(bg, border, radius, 1, 3)
	style.border_width_bottom = 4
	style.content_margin_left = padding_x
	style.content_margin_top = padding_y
	style.content_margin_right = padding_x
	style.content_margin_bottom = padding_y
	return style

static func apply_primary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button_style(GOLD, Color("fff0b0"), 10))
	button.add_theme_stylebox_override("hover", button_style(Color("ffe190"), Color.WHITE, 10))
	button.add_theme_stylebox_override("pressed", pressed_style(GOLD_DARK, Color("ffe6a3")))
	button.add_theme_stylebox_override("disabled", button_style(Color("52636a"), Color("71838a"), 10))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_stylebox_override("focus", focus_ring(TEAL))
	button.add_theme_color_override("font_disabled_color", Color("b6c1c3"))
	button.add_theme_color_override("icon_normal_color", INK)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bind_button_feedback(button)

static func apply_secondary_button(button: Button, accent: Color = TEAL) -> void:
	button.add_theme_stylebox_override("normal", button_style(PANEL_RAISED, accent.darkened(0.28), 10))
	button.add_theme_stylebox_override("hover", button_style(PANEL_SOFT, accent, 10))
	button.add_theme_stylebox_override("pressed", pressed_style(PANEL, accent.darkened(0.10)))
	button.add_theme_stylebox_override("disabled", button_style(Color("263a43"), Color("425a62"), 10))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_focus_color", TEXT_BRIGHT)
	button.add_theme_stylebox_override("focus", focus_ring(GOLD))
	button.add_theme_color_override("font_disabled_color", Color("71858a"))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bind_button_feedback(button)

static func pressed_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := button_style(bg, border)
	style.border_width_bottom = 1
	style.shadow_size = 0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 6.0
	return style

static func focus_ring(accent: Color = GOLD) -> StyleBoxFlat:
	var style := panel(Color.TRANSPARENT, accent, 12, 2, 0)
	style.set_expand_margin_all(3.0)
	style.set_content_margin_all(0.0)
	return style

static func _bind_button_feedback(button: Button) -> void:
	# Styles refresh when network state changes. Connect feedback exactly once.
	if button.has_meta("commercial_feedback"):
		return
	button.set_meta("commercial_feedback", true)
	button.button_down.connect(_button_motion.bind(button, true))
	button.button_up.connect(_button_motion.bind(button, false))
	button.pressed.connect(_button_click.bind(button))

static func _button_motion(button: Button, down: bool) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	var previous: Tween = button.get_meta("commercial_motion") if button.has_meta("commercial_motion") else null
	if previous and previous.is_valid():
		previous.kill()
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	button.set_meta("commercial_motion", tween)
	tween.tween_property(button, "scale", Vector2(0.985, 0.96) if down else Vector2.ONE, 0.07 if down else 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func _button_click(button: Button) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	var audio := button.get_tree().root.get_node_or_null("AudioManager")
	if audio:
		audio.call("play_move_sfx")

static func apply_input(control: Control) -> void:
	var normal := button_style(Color("0a202a"), Color("396772"), 9, 13.0, 8.0)
	var focus := button_style(Color("0d2934"), TEAL, 9, 13.0, 8.0)
	control.add_theme_stylebox_override("normal", normal)
	control.add_theme_stylebox_override("focus", focus)
	control.add_theme_stylebox_override("hover", focus)
	control.add_theme_stylebox_override("pressed", focus)
	control.add_theme_color_override("font_color", TEXT)
	control.add_theme_color_override("font_placeholder_color", TEXT_MUTED.darkened(0.15))
	control.add_theme_color_override("caret_color", GOLD)

static func progress_background() -> StyleBoxFlat:
	var style := button_style(INK, BORDER_MUTED, 8, 2.0, 2.0)
	style.border_width_bottom = 1
	style.shadow_size = 0
	return style

static func progress_fill(color: Color = TEAL) -> StyleBoxFlat:
	var style := button_style(color, color.lightened(0.22), 8, 2.0, 2.0)
	style.border_width_bottom = 1
	style.shadow_size = 0
	return style
