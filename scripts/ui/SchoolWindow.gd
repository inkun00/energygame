extends Control
## The opening and the electricity report show the same school at night.

var night_supply := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_night_supply(ratio: float) -> void:
	night_supply = clampf(ratio, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var scale_factor := minf(size.x / 124.0, size.y / 88.0)
	if scale_factor <= 0.0:
		return
	draw_set_transform((size - Vector2(124, 88) * scale_factor) * 0.5, 0.0, Vector2.ONE * scale_factor)
	draw_rect(Rect2(10, 35, 104, 45), Color("#baced1"))
	draw_colored_polygon(PackedVector2Array([Vector2(3, 36), Vector2(62, 9), Vector2(121, 36)]), Color("#549a91"))
	draw_circle(Vector2(62, 25), 7, Color("#f6ebcf"), true, -1, true)
	draw_line(Vector2(62, 21), Vector2(62, 25), Color("#253d46"), 1.5, true)
	draw_line(Vector2(62, 25), Vector2(66, 25), Color("#253d46"), 1.5, true)
	draw_rect(Rect2(54, 57, 16, 23), Color("#355461"))
	var lit_windows := roundi(night_supply * 6.0)
	for column in range(3):
		for side in range(2):
			var x := 15 + column * 12 + side * 61
			var light := Color("#fff09a") if column * 2 + side < lit_windows else Color("#31485f")
			draw_rect(Rect2(x, 44, 10, 20), Color("#637c83"))
			draw_rect(Rect2(x + 1, 45, 8, 17), light)
			draw_line(Vector2(x + 1, 53), Vector2(x + 9, 53), Color("#637c83"), 1.2)
	draw_line(Vector2(4, 81), Vector2(120, 81), Color("#91b79e"), 3.0, true)
