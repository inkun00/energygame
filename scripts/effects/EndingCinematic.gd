extends Control
class_name EndingCinematic

## 게임 종료 직후 결과창 앞에서 재생되는 성공/실패 전용 엔딩 연출입니다.

signal animation_finished

const DURATION := 3.4
const FADE_OUT_START := 2.85
const PARTICLE_COUNT := 42

var is_success := false
var village_energy := 0
var target_energy := 70
var elapsed := 0.0
var title_text := ""
var subtitle_text := ""
var particles: Array[Dictionary] = []
var _finished_emitted := false

func setup(success: bool, energy_value: int, target_value: int) -> void:
	is_success = success
	village_energy = energy_value
	target_energy = target_value
	title_text = "왕국 복원 성공!" if is_success else "에너지 연결이 부족해요"
	subtitle_text = (
		"요정마을에 깨끗한 빛이 돌아왔습니다!"
		if is_success
		else "모은 재료와 지식을 가지고 다시 도전해요!"
	)
	_build_particles()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	# 연출을 보기도 전에 잘못 눌러 넘기지 않도록 첫 0.8초 뒤부터 클릭으로 건너뜁니다.
	if elapsed >= 0.8 and event is InputEventMouseButton and event.pressed:
		_finish()

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	if elapsed >= DURATION:
		_finish()

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	animation_finished.emit()
	queue_free()

func _build_particles() -> void:
	particles.clear()
	var random := RandomNumberGenerator.new()
	random.seed = 7319 if is_success else 9137
	for index in range(PARTICLE_COUNT):
		particles.append({
			"x": random.randf(),
			"y": random.randf(),
			"speed": random.randf_range(0.10, 0.32),
			"size": random.randf_range(2.0, 6.0),
			"phase": random.randf_range(0.0, TAU),
			"warm": index % 3 == 0
		})

func _draw() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var intro := smoothstep(0.0, 1.0, clampf(elapsed / 0.65, 0.0, 1.0))
	var outro := 1.0 - smoothstep(0.0, 1.0, clampf((elapsed - FADE_OUT_START) / (DURATION - FADE_OUT_START), 0.0, 1.0))
	var alpha := intro * outro
	var center := viewport_size * Vector2(0.5, 0.43)
	_draw_sky(viewport_size, alpha)
	if is_success:
		_draw_success_energy(center, alpha)
	else:
		_draw_failure_weather(viewport_size, center, alpha)
	_draw_village(viewport_size, alpha)
	_draw_particles(viewport_size, alpha)
	_draw_titles(viewport_size, alpha)

func _draw_sky(viewport_size: Vector2, alpha: float) -> void:
	var top_color := Color("082f43") if is_success else Color("101b2b")
	var bottom_color := Color("12685e") if is_success else Color("26313c")
	for band in range(12):
		var ratio := float(band) / 11.0
		var band_color := top_color.lerp(bottom_color, ratio)
		band_color.a = 0.97 * alpha
		draw_rect(Rect2(0.0, viewport_size.y * ratio, viewport_size.x, viewport_size.y / 11.0 + 2.0), band_color)

func _draw_success_energy(center: Vector2, alpha: float) -> void:
	var pulse := (sin(elapsed * 4.0) + 1.0) * 0.5
	for ray_index in range(18):
		var angle := TAU * float(ray_index) / 18.0 + elapsed * 0.08
		var inner := center + Vector2(cos(angle), sin(angle)) * 78.0
		var outer := center + Vector2(cos(angle), sin(angle)) * (205.0 + pulse * 28.0)
		draw_line(inner, outer, Color(0.58, 1.0, 0.82, 0.18 * alpha), 7.0, true)
	var ring_progress := clampf(elapsed / 1.45, 0.0, 1.0)
	draw_arc(center, 118.0, -PI * 0.5, -PI * 0.5 + TAU * ring_progress, 96, Color(0.37, 1.0, 0.73, 0.92 * alpha), 8.0, true)
	draw_arc(center, 93.0 + pulse * 7.0, elapsed * 0.45, elapsed * 0.45 + PI * 1.55, 72, Color(1.0, 0.88, 0.32, 0.78 * alpha), 5.0, true)
	draw_circle(center, 59.0 + pulse * 9.0, Color(0.33, 1.0, 0.76, 0.16 * alpha))
	draw_circle(center, 35.0 + pulse * 5.0, Color(0.90, 1.0, 0.74, 0.86 * alpha))
	draw_circle(center, 18.0, Color(1.0, 0.97, 0.72, alpha))

func _draw_failure_weather(viewport_size: Vector2, center: Vector2, alpha: float) -> void:
	var flicker := 0.45 + sin(elapsed * 7.0) * 0.12
	var ring_progress := clampf(float(village_energy) / maxf(float(target_energy), 1.0), 0.0, 1.0)
	draw_arc(center, 112.0, -PI * 0.5, -PI * 0.5 + TAU * ring_progress, 96, Color(0.35, 0.76, 0.90, 0.82 * alpha), 8.0, true)
	draw_arc(center, 112.0, -PI * 0.5 + TAU * ring_progress, PI * 1.5, 96, Color(0.34, 0.42, 0.50, 0.58 * alpha), 8.0, true)
	draw_circle(center, 42.0, Color(0.34, 0.76, 0.88, flicker * alpha))
	draw_circle(center, 19.0, Color(0.75, 0.93, 1.0, 0.82 * alpha))
	for cloud_index in range(7):
		var cloud_x := viewport_size.x * (0.10 + float(cloud_index) * 0.135)
		var cloud_y := viewport_size.y * (0.18 + float(cloud_index % 2) * 0.035)
		draw_circle(Vector2(cloud_x, cloud_y), 46.0, Color(0.18, 0.25, 0.33, 0.72 * alpha))
		draw_circle(Vector2(cloud_x + 38.0, cloud_y + 8.0), 36.0, Color(0.18, 0.25, 0.33, 0.72 * alpha))

func _draw_village(viewport_size: Vector2, alpha: float) -> void:
	var ground_y := viewport_size.y * 0.76
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, ground_y), Vector2(viewport_size.x, ground_y - 18.0),
		Vector2(viewport_size.x, viewport_size.y), Vector2(0.0, viewport_size.y)
	]), Color(0.04, 0.18, 0.17, 0.96 * alpha) if is_success else Color(0.08, 0.12, 0.16, 0.96 * alpha))
	var reveal := smoothstep(0.0, 1.0, clampf((elapsed - 0.35) / 0.9, 0.0, 1.0))
	for house_index in range(9):
		var x := viewport_size.x * (0.08 + float(house_index) * 0.105)
		var house_height := (54.0 + float(house_index % 3) * 15.0) * reveal
		var body_color := Color(0.20, 0.52, 0.42, alpha) if is_success else Color(0.19, 0.24, 0.28, alpha)
		draw_rect(Rect2(x, ground_y - house_height, 66.0, house_height), body_color)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 8.0, ground_y - house_height), Vector2(x + 33.0, ground_y - house_height - 34.0), Vector2(x + 74.0, ground_y - house_height)
		]), Color(0.12, 0.35, 0.30, alpha) if is_success else Color(0.13, 0.17, 0.21, alpha))
		var window_color := Color(1.0, 0.87, 0.32, 0.92 * alpha) if is_success else Color(0.24, 0.34, 0.40, 0.55 * alpha)
		draw_rect(Rect2(x + 23.0, ground_y - house_height * 0.58, 19.0, 22.0), window_color)
	_draw_turbine(Vector2(viewport_size.x * 0.17, ground_y - 4.0), 92.0 * reveal, alpha)
	_draw_turbine(Vector2(viewport_size.x * 0.84, ground_y - 12.0), 108.0 * reveal, alpha)

func _draw_turbine(base: Vector2, height: float, alpha: float) -> void:
	var hub := base - Vector2(0.0, height)
	var tower_color := Color(0.75, 0.94, 0.88, 0.82 * alpha) if is_success else Color(0.39, 0.47, 0.50, 0.65 * alpha)
	draw_line(base, hub, tower_color, 6.0, true)
	draw_circle(hub, 7.0, tower_color)
	var rotation_speed := elapsed * (1.8 if is_success else 0.18)
	for blade_index in range(3):
		var angle := rotation_speed + TAU * float(blade_index) / 3.0
		var tip := hub + Vector2(cos(angle), sin(angle)) * 43.0
		draw_line(hub, tip, tower_color, 7.0, true)

func _draw_particles(viewport_size: Vector2, alpha: float) -> void:
	for particle in particles:
		var x := float(particle["x"]) * viewport_size.x + sin(elapsed * 1.4 + float(particle["phase"])) * 24.0
		var base_y := float(particle["y"]) * viewport_size.y
		var direction := -1.0 if is_success else 1.0
		var y := fposmod(base_y + direction * elapsed * float(particle["speed"]) * viewport_size.y, viewport_size.y)
		var point_color := (Color("ffe36c") if bool(particle["warm"]) else Color("65f2c1")) if is_success else Color("7ba5b7")
		point_color.a = (0.72 if is_success else 0.46) * alpha
		if is_success:
			draw_circle(Vector2(x, y), float(particle["size"]), point_color)
		else:
			draw_line(Vector2(x, y), Vector2(x - 5.0, y + 22.0), point_color, 2.0, true)

func _draw_titles(viewport_size: Vector2, alpha: float) -> void:
	var font := ThemeDB.fallback_font
	var title_y := viewport_size.y * 0.14
	var title_color := Color(1.0, 0.91, 0.43, alpha) if is_success else Color(0.72, 0.88, 0.94, alpha)
	draw_string(font, Vector2(0.0, title_y), title_text, HORIZONTAL_ALIGNMENT_CENTER, viewport_size.x, 44, title_color)
	draw_string(font, Vector2(0.0, title_y + 50.0), subtitle_text, HORIZONTAL_ALIGNMENT_CENTER, viewport_size.x, 22, Color(0.90, 1.0, 0.96, 0.9 * alpha))
	var progress_text := "친환경 에너지 지수  %d / %d" % [village_energy, target_energy]
	draw_string(font, Vector2(0.0, viewport_size.y * 0.66), progress_text, HORIZONTAL_ALIGNMENT_CENTER, viewport_size.x, 19, Color(0.78, 0.95, 0.90, 0.82 * alpha))
	if elapsed >= 0.8:
		draw_string(font, Vector2(0.0, viewport_size.y - 28.0), "클릭하면 결과 화면으로 이동", HORIZONTAL_ALIGNMENT_CENTER, viewport_size.x, 14, Color(0.78, 0.88, 0.88, 0.56 * alpha))
