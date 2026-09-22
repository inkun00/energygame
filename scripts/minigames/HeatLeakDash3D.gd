extends SubViewportContainer
class_name HeatLeakDash3D

## 여름 냉방 중 열린 창문을 직접 닫는 30초 3D 아케이드.
## 창문이 열려 있는 동안 더운 공기가 들어와 에어컨 사용 속도가 증가합니다.
signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const WINDOW_MODEL = preload("res://assets/third_party/kenney/standby_house/wallWindow.glb")
const FLOOR_MODEL = preload("res://assets/third_party/kenney/standby_house/floorFull.glb")
const WINDOW_X := [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0]
const RUN_SPEED := 6.3
const CLOSE_REACH := 0.76
const WAVE_INTERVAL := 6.0
const WAVE_COUNT := 5
const OPEN_PER_WAVE := 3
const BASE_COOLING_USE := 0.10
const OPEN_WINDOW_USE := 0.42

var viewport: SubViewport
var world: Node3D
var hero: Node3D
var windows: Array[Dictionary] = []
var temperature_label: Label
var leak_label: Label
var heater_label: Label
var action_label: Label
var flash: ColorRect
var hero_x := 0.0
var elapsed := 0.0
var cooling_used := 0.0
var room_temperature := 24.0
var closed_count := 0
var next_wave := 1
var game_seed := 1
var space_was_down := false
var running := false
var notice := "A/D 이동 · 열린 창문 앞에서 Space로 닫기"
var notice_remaining := 3.0
var flash_remaining := 0.0

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 286)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_overlay()
	set_process(true)

func setup(player_data: Dictionary, round_seed: int) -> void:
	game_seed = round_seed
	hero_x = 0.0
	elapsed = 0.0
	cooling_used = 0.0
	room_temperature = 24.0
	closed_count = 0
	next_wave = 1
	space_was_down = false
	notice = "A/D 이동 · 열린 창문 앞에서 Space로 닫기"
	notice_remaining = 3.0
	flash_remaining = 0.0
	_spawn_hero(player_data)
	for window in windows:
		window["open"] = false
		window["closed"] = true
		window["since"] = 0.0
		window["open_amount"] = 0.0
		_update_window_visual(window)
	_spawn_wave(0)
	_update_overlay()
	running = true

func set_running(value: bool) -> void:
	running = value
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	if is_instance_valid(hero):
		hero.call("_set_avatar_animation_state", false)

static func wave_positions(round_seed: int, wave: int) -> Array[int]:
	var choices: Array[int] = [0, 1, 2, 3, 4, 5]
	var wave_rng := RandomNumberGenerator.new()
	wave_rng.seed = round_seed + wave * 65537
	for index in range(choices.size() - 1, 0, -1):
		var swap_index := wave_rng.randi_range(0, index)
		var saved := choices[index]
		choices[index] = choices[swap_index]
		choices[swap_index] = saved
	return choices

static func score_for_close(open_seconds: float) -> int:
	return maxi(35, 110 - roundi(maxf(0.0, open_seconds) * 11.0))

func _build_world() -> void:
	viewport = SubViewport.new()
	viewport.name = "HeatLeakViewport"
	viewport.size = Vector2i(960, 286)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var sky := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("73cbea")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff0cd")
	environment.ambient_light_energy = 0.9
	sky.environment = environment
	world.add_child(sky)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-46, -22, 0)
	sunlight.light_energy = 1.1
	sunlight.shadow_enabled = false
	world.add_child(sunlight)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.9
	camera.position = Vector3(0.0, 4.35, 13.0)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 1.55, 0.0), Vector3.UP)
	_box(world, Vector3(0.0, -0.20, 0.0), Vector3(16.4, 0.35, 5.3), Color("c5b393"))
	_box(world, Vector3(0.0, 3.43, -1.42), Vector3(16.0, 0.85, 0.18), Color("eed8b2"))
	_box(world, Vector3(0.0, 0.43, -1.42), Vector3(16.0, 0.86, 0.18), Color("eed8b2"))
	for index in range(16):
		var floor_tile := FLOOR_MODEL.instantiate() as Node3D
		floor_tile.position = Vector3(-7.5 + float(index), -0.02, 0.25)
		world.add_child(floor_tile)
	for index in range(WINDOW_X.size()):
		_build_window(index)
	# 에어컨은 열린 창문 수에 따라 커지는 냉방 에너지 사용량을 보여 줍니다.
	_box(world, Vector3(-7.45, 2.60, -0.88), Vector3(1.00, 0.58, 0.40), Color("e8f8fb"))
	_box(world, Vector3(-7.45, 2.39, -0.65), Vector3(0.72, 0.08, 0.08), Color("6cb7c9"), true)
	_label3d(world, "에어컨", Vector3(-7.40, 3.16, -0.65), Color("eaffff"))
	var sun := _sphere(world, Vector3(7.25, 4.15, -1.0), 0.42, Color("ffd45f"), true)
	sun.name = "SummerSun"
	_label3d(world, "무더운 여름 34°C", Vector3(5.85, 3.75, -0.55), Color("ffe0a1"))

func _build_window(index: int) -> void:
	var x := float(WINDOW_X[index])
	var model := WINDOW_MODEL.instantiate() as Node3D
	model.name = "KenneyWindow%d" % index
	model.position = Vector3(x, 0.75, -1.36)
	model.scale = Vector3.ONE * 1.15
	world.add_child(model)
	var window_pane := model.find_child("window", true, false) as Node3D
	var pane_base_position := window_pane.position if window_pane else Vector3.ZERO
	var status := _label3d(world, "창문 열림!", Vector3(x, 3.17, -0.65), Color("ffb16f"))
	var particles: Array[MeshInstance3D] = []
	for particle_index in range(3):
		var particle := _box(world, Vector3(x + 0.68, 1.74 + float(particle_index) * 0.32, -0.30), Vector3(0.18, 0.13, 0.13), Color("ff754f"), true)
		particles.append(particle)
	windows.append({"x": x, "model": model, "pane": window_pane, "pane_base_position": pane_base_position, "status": status, "particles": particles, "open": false, "closed": true, "since": 0.0, "open_amount": 0.0})

func _spawn_hero(player_data: Dictionary) -> void:
	if is_instance_valid(hero):
		hero.queue_free()
	hero = PLAYER_PAWN.new()
	world.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_player", hero_data)
	hero.call("set_side_run_enabled", true)
	hero.position = Vector3(0.0, 0.07, 1.25)
	hero.scale = Vector3.ONE * 2.45
	if hero.shadow_mesh:
		hero.shadow_mesh.visible = false
	hero.call("_set_avatar_animation_state", false)

func _build_overlay() -> void:
	temperature_label = _overlay_label(Vector2(20, 9), Vector2(300, 42), "실내 24.0°C", Color("fff0bf"), 22)
	leak_label = _overlay_label(Vector2(330, 9), Vector2(630, 42), "열린 창문 3개", Color("a8eaff"), 22)
	heater_label = _overlay_label(Vector2(655, 9), Vector2(940, 42), "냉방 +1.4/초", Color("ffd2a4"), 20)
	action_label = _overlay_label(Vector2(95, 254), Vector2(865, 283), "A/D 이동 · 열린 창문 앞에서 Space로 닫기", Color("fff0bf"), 17)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color.TRANSPARENT
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

func _process(delta: float) -> void:
	flash_remaining = maxf(0.0, flash_remaining - delta)
	if flash_remaining <= 0.0:
		flash.color = Color.TRANSPARENT
	_animate_heat(delta)
	if not running:
		return
	elapsed += delta
	notice_remaining = maxf(0.0, notice_remaining - delta)
	while next_wave < WAVE_COUNT and elapsed >= float(next_wave) * WAVE_INTERVAL:
		_spawn_wave(next_wave)
		next_wave += 1
	var active_count := _open_window_count()
	cooling_used += (BASE_COOLING_USE + OPEN_WINDOW_USE * float(active_count)) * delta
	room_temperature = clampf(room_temperature + (-0.025 + 0.090 * float(active_count)) * delta, 22.0, 30.0)
	var axis := float(int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)))
	hero_x = clampf(hero_x + axis * RUN_SPEED * delta, -7.0, 7.0)
	if is_instance_valid(hero):
		hero.position.x = hero_x
		if hero.is_moving != (axis != 0.0):
			hero.call("_set_avatar_animation_state", axis != 0.0)
		if axis != 0.0 and hero.avatar_sprite:
			hero.avatar_sprite.flip_h = axis < 0.0
	var space_down := Input.is_key_pressed(KEY_SPACE)
	if space_down and not space_was_down:
		_try_close()
	space_was_down = space_down
	_update_overlay()

func _spawn_wave(wave: int) -> void:
	var newly_opened := 0
	for window_index in wave_positions(game_seed, wave):
		var window: Dictionary = windows[window_index]
		if bool(window["open"]):
			continue
		window["open"] = true
		window["closed"] = false
		window["since"] = elapsed
		_update_window_visual(window)
		newly_opened += 1
		if newly_opened >= OPEN_PER_WAVE:
			break
	if wave > 0:
		_notice("더운 바람! 창문 %d개가 열렸어요 · 빨간 공기가 들어와요" % newly_opened if newly_opened > 0 else "모든 창문이 열렸어요! 가까운 곳부터 닫으세요.")

func _try_close() -> void:
	var closest: Dictionary = {}
	var nearest := CLOSE_REACH
	for window in windows:
		var distance := absf(hero_x - float(window["x"]))
		if distance <= nearest:
			closest = window
			nearest = distance
	if closest.is_empty():
		_notice("열린 창문 가까이 이동해 Space를 누르세요.")
		return
	if not bool(closest["open"]):
		arcade_event.emit(15, false, "이미 닫힌 창문이에요. 열린 창문을 찾으세요!", false)
		_notice("이미 닫힌 창문이에요. 열린 창문을 찾으세요!")
		return
	var open_for := maxf(0.0, elapsed - float(closest["since"]))
	var points := score_for_close(open_for)
	closest["open"] = false
	closest["closed"] = true
	closed_count += 1
	_update_window_visual(closest)
	arcade_event.emit(points, true, "창문을 닫았어요! 더운 공기가 멈춰 에어컨 사용 속도가 느려져요.", true)
	_notice("창문 닫기 +%d점 · 냉방 낭비가 줄었어요!" % points)
	flash.color = Color("8af2ae3c")
	flash_remaining = 0.20
	_update_overlay()

func _open_window_count() -> int:
	var count := 0
	for window in windows:
		if bool(window["open"]):
			count += 1
	return count

func _update_window_visual(window: Dictionary) -> void:
	var is_open := bool(window["open"])
	(window["status"] as Node3D).visible = is_open
	for particle in (window["particles"] as Array):
		(particle as Node3D).visible = is_open

func _animate_heat(delta: float) -> void:
	for window in windows:
		var target := 1.0 if bool(window["open"]) else 0.0
		window["open_amount"] = move_toward(float(window["open_amount"]), target, delta * 2.7)
		var pane := window["pane"] as Node3D
		if is_instance_valid(pane):
			var amount := float(window["open_amount"])
			pane.rotation.y = deg_to_rad(68.0) * amount
			pane.position = (window["pane_base_position"] as Vector3) + Vector3(-0.13 * amount, 0.0, 0.13 * amount)
		if not bool(window["open"]):
			continue
		var particles: Array = window["particles"]
		for index in range(particles.size()):
			var particle := particles[index] as Node3D
			var phase := fposmod(elapsed * 1.8 + float(index) * 0.34, 1.0)
			particle.position.x = float(window["x"]) + 0.58 - phase * 0.42
			particle.position.y = 1.75 + float(index) * 0.28 + sin(phase * PI) * 0.35
			particle.position.z = -1.00 + phase * 1.25

func _notice(message: String) -> void:
	notice = message
	notice_remaining = 1.9

func _update_overlay() -> void:
	temperature_label.text = "실내 %.1f°C" % room_temperature
	leak_label.text = "열린 창문 %d개" % _open_window_count()
	heater_label.text = "냉방 +%.1f/초 · 누적 %.1f" % [BASE_COOLING_USE + OPEN_WINDOW_USE * float(_open_window_count()), cooling_used]
	action_label.text = notice if notice_remaining > 0.0 else "A/D 이동 · 열린 창문 앞 Space · 닫으면 냉방 효율 상승"

func _box(parent: Node3D, where: Vector3, size_value: Vector3, color: Color, glowing: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = where
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.65
	node.material_override = material
	parent.add_child(node)
	return node

func _sphere(parent: Node3D, where: Vector3, radius: float, color: Color, glowing: bool = false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = where
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.70
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.75
	node.material_override = material
	parent.add_child(node)
	return node

func _label3d(parent: Node3D, content: String, where: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = content
	label.position = where
	label.modulate = color
	label.font_size = 42
	label.pixel_size = 0.009
	label.outline_size = 8
	label.no_depth_test = true
	parent.add_child(label)
	return label

func _overlay_label(from: Vector2, to: Vector2, content: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.position = from
	label.size = to - from
	label.text = content
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("173744"))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	return label
