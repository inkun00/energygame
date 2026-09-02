extends Node2D
class_name BoardBackdrop

## 이미지 없이 Godot의 2D 드로잉 API만으로 보드 배경과 이동 경로를 렌더링합니다.

const BOARD_SIZE := Vector2(1280, 720)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	_draw_sky_gradient()
	_draw_landscape()
	_draw_playfield()
	_draw_route()
	_draw_shortcuts()
	_draw_grid_cells()
	_draw_decorations()

func _draw_sky_gradient() -> void:
	var top_color := Color("0d1d33")
	var bottom_color := Color("164b53")
	var band_height := BOARD_SIZE.y / 18.0
	for band in range(18):
		var ratio := float(band) / 17.0
		var band_color := top_color.lerp(bottom_color, ratio)
		draw_rect(Rect2(0, band * band_height, BOARD_SIZE.x, band_height + 1.0), band_color)

	var stars := [
		Vector2(52, 120), Vector2(140, 160), Vector2(230, 110), Vector2(350, 170),
		Vector2(480, 120), Vector2(620, 165), Vector2(760, 115), Vector2(890, 160),
		Vector2(1020, 118), Vector2(1150, 175), Vector2(1230, 125)
	]
	for star in stars:
		draw_circle(star, 2.5, Color(0.75, 0.95, 1.0, 0.6))

func _draw_landscape() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 420), Vector2(130, 335), Vector2(260, 415), Vector2(410, 315),
		Vector2(560, 420), Vector2(730, 300), Vector2(900, 410), Vector2(1080, 320),
		Vector2(1280, 405), Vector2(1280, 720), Vector2(0, 720)
	]), Color("113c3f"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 500), Vector2(180, 405), Vector2(350, 500), Vector2(540, 390),
		Vector2(710, 500), Vector2(910, 400), Vector2(1080, 480), Vector2(1280, 390),
		Vector2(1280, 720), Vector2(0, 720)
	]), Color("145344"))
	draw_rect(Rect2(0, 560, BOARD_SIZE.x, 160), Color("113d36"))

func _draw_playfield() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.025, 0.07, 0.11, 0.72)
	panel.border_color = Color(0.28, 0.88, 0.75, 0.55)
	panel.set_border_width_all(3)
	panel.set_corner_radius_all(20)
	draw_style_box(panel, Rect2(16, 108, 1248, 500))

func _draw_route() -> void:
	var points := PackedVector2Array(BoardGrid.TILE_POSITIONS)
	# 번호 진행선은 각 행을 왕복하는 스네이크 경로로 이어집니다.
	draw_polyline(points, Color(0.01, 0.06, 0.09, 0.95), 24.0, true)
	draw_polyline(points, Color(0.18, 0.75, 0.65, 0.8), 14.0, true)
	draw_polyline(points, Color(0.72, 1.0, 0.92, 0.45), 4.0, true)

func _draw_grid_cells() -> void:
	# 이동선 위를 셀 베이스가 덮도록 드로잉 (50% 확대된 220x96 규격)
	for index in range(BoardGrid.TILE_POSITIONS.size()):
		var point := BoardGrid.TILE_POSITIONS[index]
		var row: int = floori(float(index) / float(BoardGrid.COLUMN_COUNT))
		var cell_rect := Rect2(point - Vector2(55, 42), Vector2(110, 84))
		draw_rect(Rect2(cell_rect.position + Vector2(4, 5), cell_rect.size), Color(0.0, 0.0, 0.0, 0.45), true)
		var cell_color := Color(0.06, 0.18, 0.24, 0.95) if row % 2 == 0 else Color(0.05, 0.15, 0.20, 0.95)
		draw_rect(cell_rect, cell_color, true)
		draw_rect(cell_rect, Color(0.25, 0.78, 0.70, 0.40), false, 2.0)

func _draw_shortcuts() -> void:
	for tile in BoardGrid.TILE_DATA:
		var tile_type: int = tile["type"]
		if tile_type == BoardGrid.TileType.LADDER:
			_draw_ladder(BoardGrid.get_tile_position(tile["index"]), BoardGrid.get_tile_position(tile["target"]))
		elif tile_type == BoardGrid.TileType.SLIDE:
			_draw_slide(BoardGrid.get_tile_position(tile["index"]), BoardGrid.get_tile_position(tile["target"]))

func _draw_ladder(from: Vector2, to: Vector2) -> void:
	var direction := (to - from).normalized()
	var side := Vector2(-direction.y, direction.x) * 10.0
	var rail_color := Color(1.0, 0.82, 0.20, 0.88)
	draw_line(from + side, to + side, rail_color, 6.0, true)
	draw_line(from - side, to - side, rail_color, 6.0, true)
	for rung in range(1, 8):
		var center := from.lerp(to, float(rung) / 8.0)
		draw_line(center - side, center + side, Color(1.0, 0.95, 0.50, 0.95), 4.0, true)

func _draw_slide(from: Vector2, to: Vector2) -> void:
	var direction := to - from
	var normal := Vector2(-direction.y, direction.x).normalized()
	var curve := PackedVector2Array()
	for step in range(21):
		var ratio := float(step) / 20.0
		var wave := sin(ratio * PI * 3.0) * 14.0
		curve.append(from.lerp(to, ratio) + normal * wave)
	draw_polyline(curve, Color(0.35, 0.04, 0.06, 0.8), 16.0, true)
	draw_polyline(curve, Color(1.0, 0.28, 0.25, 0.9), 9.0, true)
	draw_polyline(curve, Color(1.0, 0.8, 0.8, 0.6), 3.0, true)

func _draw_decorations() -> void:
	# 태양과 햇살
	var sun_center := Vector2(1170, 145)
	draw_circle(sun_center, 30.0, Color(1.0, 0.80, 0.22, 0.65))
	for ray in range(8):
		var angle := TAU * float(ray) / 8.0
		var ray_dir := Vector2(cos(angle), sin(angle))
		draw_line(sun_center + ray_dir * 38.0, sun_center + ray_dir * 52.0, Color(1.0, 0.88, 0.40, 0.6), 3.5, true)

	# 풍력 터빈
	_draw_wind_turbine(Vector2(60, 480), 45.0)
	_draw_wind_turbine(Vector2(1225, 480), 45.0)

func _draw_wind_turbine(base: Vector2, height: float) -> void:
	var hub := base - Vector2(0, height)
	draw_line(base, hub, Color(0.72, 0.9, 0.88, 0.55), 4.0, true)
	draw_circle(hub, 5.0, Color(0.9, 1.0, 0.96, 0.8))
	for blade in range(3):
		var angle := -PI / 2.0 + TAU * float(blade) / 3.0
		var blade_end := hub + Vector2(cos(angle), sin(angle)) * height * 0.42
		draw_line(hub, blade_end, Color(0.78, 0.96, 0.94, 0.7), 5.0, true)
