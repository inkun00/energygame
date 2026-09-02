extends Control

## Lightweight title-screen atmosphere rendered directly by Godot.

var _time := 0.0
var _fireflies := [
	Vector3(74, 248, 0.8), Vector3(184, 122, 1.3), Vector3(344, 300, 1.8),
	Vector3(530, 188, 2.5), Vector3(710, 344, 3.1), Vector3(905, 140, 4.0),
	Vector3(1122, 282, 4.7), Vector3(1212, 518, 5.4), Vector3(650, 590, 6.1)
]

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	for radius in range(360, 40, -32):
		var alpha := 0.004 + (360.0 - radius) / 360.0 * 0.006
		draw_circle(Vector2(340, 390), radius, Color(0.34, 1.0, 0.30, alpha))
	draw_rect(Rect2(0, 0, viewport_size.x, 58), Color(0.0, 0.02, 0.01, 0.18))
	draw_rect(Rect2(0, viewport_size.y - 86, viewport_size.x, 86), Color(0.0, 0.025, 0.015, 0.22))

	for firefly in _fireflies:
		var phase: float = _time * 0.9 + firefly.z
		var point := Vector2(firefly.x + sin(phase * 1.37) * 18.0, firefly.y + cos(phase * 1.11) * 11.0)
		var pulse := 0.55 + sin(phase * 2.4) * 0.25
		draw_circle(point, 10.0, Color(0.78, 1.0, 0.30, 0.035 * pulse))
		draw_circle(point, 3.2, Color(0.92, 1.0, 0.46, 0.55 * pulse))
		draw_circle(point, 1.1, Color(1.0, 1.0, 0.86, 0.95))

	for index in range(7):
		var travel := fmod(_time * (16.0 + index * 2.3) + index * 210.0, viewport_size.x + 180.0)
		var point := Vector2(viewport_size.x + 90.0 - travel, 115.0 + index * 73.0 + sin(_time + index) * 24.0)
		_draw_leaf(point, -0.55 + sin(_time * 0.7 + index) * 0.35, 0.65 + index * 0.035)

func _draw_leaf(center: Vector2, angle: float, scale_value: float) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var side := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([
		center + direction * 13.0 * scale_value,
		center + side * 7.0 * scale_value,
		center - direction * 13.0 * scale_value,
		center - side * 7.0 * scale_value
	])
	draw_colored_polygon(points, Color(0.52, 0.89, 0.24, 0.22))
	draw_line(center - direction * 10.0 * scale_value, center + direction * 10.0 * scale_value, Color(0.78, 1.0, 0.48, 0.24), 1.0)
