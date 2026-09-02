extends RefCounted
class_name CommercialUI

## 전체 화면에서 공유하는 상용 게임 UI 팔레트와 컴포넌트 스타일입니다.

const INK := Color("071722")
const PANEL := Color("102c38")
const PANEL_RAISED := Color("173b49")
const PANEL_SOFT := Color("244956")
const TEAL := Color("54e2c0")
const TEAL_DARK := Color("209b86")
const GOLD := Color("ffd166")
const GOLD_DARK := Color("d99a37")
const TEXT := Color("f3fbf8")
const TEXT_MUTED := Color("a9c6c6")
const DANGER := Color("ff6b6b")
const SUCCESS := Color("75e69b")

static func panel(bg: Color = PANEL, border: Color = TEAL_DARK, radius: int = 12, border_width: int = 2, shadow_size: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2(0, 4)
	style.anti_aliasing = true
	return style

static func padded_panel(bg: Color = PANEL, border: Color = TEAL_DARK, padding: float = 14.0, radius: int = 12) -> StyleBoxFlat:
	var style := panel(bg, border, radius, 2, 8)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style

static func button_style(bg: Color, border: Color, radius: int = 10, padding_x: float = 14.0, padding_y: float = 8.0) -> StyleBoxFlat:
	var style := panel(bg, border, radius, 2, 4)
	style.content_margin_left = padding_x
	style.content_margin_top = padding_y
	style.content_margin_right = padding_x
	style.content_margin_bottom = padding_y
	return style

static func apply_primary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button_style(GOLD, Color("fff0b0"), 10))
	button.add_theme_stylebox_override("hover", button_style(Color("ffe190"), Color.WHITE, 10))
	button.add_theme_stylebox_override("pressed", button_style(GOLD_DARK, Color("ffe6a3"), 10, 14.0, 10.0))
	button.add_theme_stylebox_override("disabled", button_style(Color("52636a"), Color("71838a"), 10))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("b6c1c3"))
	button.add_theme_color_override("icon_normal_color", INK)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func apply_secondary_button(button: Button, accent: Color = TEAL) -> void:
	button.add_theme_stylebox_override("normal", button_style(PANEL_RAISED, accent.darkened(0.28), 10))
	button.add_theme_stylebox_override("hover", button_style(PANEL_SOFT, accent, 10))
	button.add_theme_stylebox_override("pressed", button_style(PANEL, accent.darkened(0.10), 10, 14.0, 10.0))
	button.add_theme_stylebox_override("disabled", button_style(Color("263a43"), Color("425a62"), 10))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("71858a"))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

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
	return button_style(Color("061921"), Color("315967"), 8, 2.0, 2.0)

static func progress_fill(color: Color = TEAL) -> StyleBoxFlat:
	var style := button_style(color, color.lightened(0.22), 8, 2.0, 2.0)
	style.shadow_size = 0
	return style
