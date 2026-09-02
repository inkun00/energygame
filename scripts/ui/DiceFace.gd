extends Control
class_name DiceFace

## 외부 이미지 없이 주사위 면과 눈금을 직접 그립니다.

@export_range(1, 6, 1) var value: int = 1:
	set(next_value):
		value = clampi(next_value, 1, 6)
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var die_rect := Rect2(Vector2(4, 2), size - Vector2(8, 4))
	var shadow_rect := Rect2(die_rect.position + Vector2(2, 3), die_rect.size)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	shadow.set_corner_radius_all(9)
	draw_style_box(shadow, shadow_rect)

	var face := StyleBoxFlat.new()
	face.bg_color = Color("f5fbf4")
	face.border_color = Color("2b695f")
	face.set_border_width_all(2)
	face.set_corner_radius_all(9)
	draw_style_box(face, die_rect)

	var left := die_rect.position.x + die_rect.size.x * 0.27
	var center_x := die_rect.position.x + die_rect.size.x * 0.5
	var right := die_rect.position.x + die_rect.size.x * 0.73
	var top := die_rect.position.y + die_rect.size.y * 0.27
	var center_y := die_rect.position.y + die_rect.size.y * 0.5
	var bottom := die_rect.position.y + die_rect.size.y * 0.73
	var pip_color := Color("173c38")
	var pip_radius := maxf(3.0, minf(die_rect.size.x, die_rect.size.y) * 0.065)

	if value in [2, 3, 4, 5, 6]:
		draw_circle(Vector2(left, top), pip_radius, pip_color)
		draw_circle(Vector2(right, bottom), pip_radius, pip_color)
	if value in [4, 5, 6]:
		draw_circle(Vector2(right, top), pip_radius, pip_color)
		draw_circle(Vector2(left, bottom), pip_radius, pip_color)
	if value in [1, 3, 5]:
		draw_circle(Vector2(center_x, center_y), pip_radius, pip_color)
	if value == 6:
		draw_circle(Vector2(left, center_y), pip_radius, pip_color)
		draw_circle(Vector2(right, center_y), pip_radius, pip_color)
