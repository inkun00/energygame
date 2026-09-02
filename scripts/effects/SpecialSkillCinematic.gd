extends Control
class_name SpecialSkillCinematic

## 3D 효과가 카메라 밖으로 일부 벗어나도 기술 발동을 분명히 보여 주는 화면 연출입니다.

const DURATION := 1.35

var skill_id := "eco_dash"
var target_position := Vector2.ZERO
var elapsed := 0.0
var primary := Color("61ef88")
var secondary := Color("d8ffe0")


func setup(skill: Dictionary, screen_position: Vector2, character_color: Color) -> void:
	skill_id = str(skill.get("id", "eco_dash"))
	target_position = screen_position
	match skill_id:
		"wind_path":
			primary = Color("63e5ff")
			secondary = Color("d6fbff")
		"lightning_leap":
			primary = Color("ffe552")
			secondary = Color.WHITE
		"solar_charge":
			primary = Color("ffd14a")
			secondary = Color("fff3a6")
		"starlight_charge":
			primary = Color("b8efff")
			secondary = Color.WHITE
		"purifying_wave":
			primary = Color("4ddcff")
			secondary = Color("d6fbff")
		"earth_barrier":
			primary = Color("d7a965")
			secondary = Color("ffdf9a")
		"forest_supply":
			primary = Color("65e582")
			secondary = Color("ffe075")
		"recycle_salvage":
			primary = Color("55e87a")
			secondary = Color("caff8b")
		"mycelium_harvest":
			primary = Color("d285ff")
			secondary = Color("91f2a0")
		_:
			primary = character_color.lightened(0.18)
			secondary = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	if elapsed >= DURATION:
		queue_free()


func _draw() -> void:
	var progress := clampf(elapsed / DURATION, 0.0, 1.0)
	var pulse := sin(progress * PI)
	var viewport_size := size
	var center := Vector2(
		clampf(target_position.x, 110.0, maxf(viewport_size.x - 110.0, 110.0)),
		clampf(target_position.y, 110.0, maxf(viewport_size.y - 120.0, 110.0))
	)
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(primary, 0.035 * pulse), true)
	draw_rect(Rect2(Vector2(5, 5), viewport_size - Vector2(10, 10)), Color(primary, 0.48 * pulse), false, 4.0)
	var ring_radius := lerpf(22.0, 112.0, progress)
	draw_arc(center, ring_radius, 0.0, TAU, 72, Color(primary, 0.82 * (1.0 - progress)), 5.0, true)

	match skill_id:
		"lightning_leap":
			_draw_lightning(center, progress, pulse)
		"solar_charge":
			_draw_sun(center, progress, pulse)
		"starlight_charge":
			_draw_stars(center, progress, pulse)
		"purifying_wave":
			_draw_water(center, progress, pulse)
		"earth_barrier":
			_draw_barrier(center, progress, pulse)
		"forest_supply", "eco_dash":
			_draw_leaves(center, progress, pulse)
		"wind_path":
			_draw_wind(center, progress, pulse)
		"recycle_salvage":
			_draw_recycle(center, progress, pulse)
		"mycelium_harvest":
			_draw_spores(center, progress, pulse)


func _draw_lightning(center: Vector2, progress: float, pulse: float) -> void:
	for branch in range(3):
		var points := PackedVector2Array()
		var angle := -1.25 + float(branch) * 1.25
		for index in range(8):
			var distance := float(index) * (18.0 + progress * 4.0)
			var side := Vector2(-sin(angle), cos(angle)) * (8.0 if index % 2 == 0 else -8.0)
			points.append(center + Vector2(cos(angle), sin(angle)) * distance + side)
		draw_polyline(points, Color(primary, 0.95 * pulse), 7.0, true)
		draw_polyline(points, Color(Color.WHITE, 0.9 * pulse), 2.0, true)


func _draw_sun(center: Vector2, progress: float, pulse: float) -> void:
	draw_circle(center, 30.0 + pulse * 12.0, Color(primary, 0.72 * pulse))
	draw_circle(center, 17.0 + pulse * 6.0, Color(secondary, 0.9 * pulse))
	for index in range(12):
		var angle := TAU * float(index) / 12.0 + progress * 0.8
		var inner := center + Vector2(cos(angle), sin(angle)) * 48.0
		var outer := center + Vector2(cos(angle), sin(angle)) * (78.0 + pulse * 18.0)
		draw_line(inner, outer, Color(primary, 0.85 * pulse), 7.0, true)


func _draw_stars(center: Vector2, progress: float, pulse: float) -> void:
	for index in range(9):
		var angle := TAU * float(index) / 9.0 + progress * 1.4
		var orbit := 42.0 + float(index % 3) * 25.0
		var star_center := center + Vector2(cos(angle), sin(angle)) * orbit
		var star := _star_points(star_center, 7.0 + float(index % 2) * 4.0, angle)
		draw_colored_polygon(star, Color(secondary if index % 2 == 0 else primary, 0.92 * pulse))


func _draw_water(center: Vector2, progress: float, pulse: float) -> void:
	for index in range(4):
		var radius := 25.0 + float(index) * 22.0 + progress * 25.0
		draw_arc(center, radius, 0.18 * PI, 0.82 * PI, 36, Color(primary, (0.9 - float(index) * 0.13) * pulse), 6.0, true)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var bubble_center := center + Vector2(cos(angle), sin(angle)) * (38.0 + progress * 52.0)
		draw_circle(bubble_center, 5.0 + float(index % 3) * 2.0, Color(secondary, 0.68 * pulse), false, 2.5, true)


func _draw_barrier(center: Vector2, progress: float, pulse: float) -> void:
	draw_arc(center, 62.0 + progress * 10.0, PI, TAU, 48, Color(secondary, 0.88 * pulse), 9.0, true)
	draw_line(center + Vector2(-62, 0), center + Vector2(-48, 45), Color(primary, 0.8 * pulse), 8.0, true)
	draw_line(center + Vector2(62, 0), center + Vector2(48, 45), Color(primary, 0.8 * pulse), 8.0, true)
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + progress * 0.45
		var rock_center := center + Vector2(cos(angle), sin(angle)) * 88.0
		draw_rect(Rect2(rock_center - Vector2(7, 6), Vector2(14, 12)), Color(primary, 0.78 * pulse), true)


func _draw_leaves(center: Vector2, progress: float, pulse: float) -> void:
	for index in range(12):
		var angle := TAU * float(index) / 12.0 + progress * 2.2
		var distance := 28.0 + float(index % 4) * 20.0 + progress * 18.0
		var leaf_center := center + Vector2(cos(angle), sin(angle)) * distance
		var tangent := Vector2(-sin(angle), cos(angle))
		var forward := Vector2(cos(angle), sin(angle))
		var leaf := PackedVector2Array([
			leaf_center + forward * 11.0,
			leaf_center + tangent * 6.0,
			leaf_center - forward * 11.0,
			leaf_center - tangent * 6.0
		])
		draw_colored_polygon(leaf, Color(primary if index % 3 else secondary, 0.82 * pulse))


func _draw_wind(center: Vector2, progress: float, pulse: float) -> void:
	for index in range(4):
		var radius := 32.0 + float(index) * 19.0 + progress * 22.0
		var start := progress * 3.0 + float(index) * 0.65
		draw_arc(center, radius, start, start + PI * 1.35, 42, Color(primary, (0.92 - index * 0.14) * pulse), 7.0 - index, true)


func _draw_recycle(center: Vector2, progress: float, pulse: float) -> void:
	for index in range(3):
		var start := -PI * 0.5 + TAU * float(index) / 3.0 + progress * 1.7
		var radius := 65.0
		draw_arc(center, radius, start, start + PI * 0.52, 24, Color(primary, 0.9 * pulse), 9.0, true)
		var tip_angle := start + PI * 0.52
		var tip := center + Vector2(cos(tip_angle), sin(tip_angle)) * radius
		var tangent := Vector2(-sin(tip_angle), cos(tip_angle))
		var outward := Vector2(cos(tip_angle), sin(tip_angle))
		draw_colored_polygon(PackedVector2Array([tip + tangent * 12.0, tip - tangent * 12.0, tip + outward * 18.0]), Color(secondary, 0.9 * pulse))


func _draw_spores(center: Vector2, progress: float, pulse: float) -> void:
	for index in range(18):
		var angle := float(index) * 2.31 + progress * (1.4 + float(index % 3) * 0.2)
		var distance := 18.0 + float(index % 6) * 15.0
		var spore_center := center + Vector2(cos(angle), sin(angle)) * distance - Vector2(0, progress * 28.0)
		var color := primary if index % 3 else secondary
		draw_circle(spore_center, 3.5 + float(index % 4) * 1.5, Color(color, 0.76 * pulse))


func _star_points(center: Vector2, radius: float, rotation: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(10):
		var angle := rotation - PI * 0.5 + float(index) * PI / 5.0
		var point_radius := radius if index % 2 == 0 else radius * 0.42
		points.append(center + Vector2(cos(angle), sin(angle)) * point_radius)
	return points
