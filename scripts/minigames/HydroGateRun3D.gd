extends SubViewportContainer
class_name HydroGateRun3D

## 저수위가 올라갈수록 낙차·유량·발전량이 증가하지만, 넘치기 전에 수문을 열어야 합니다.
## 수문 높이는 취수 가능 수위를 결정합니다. 세 수로는 같은 낮은 터빈 출구로 이어져
## 유효 낙차는 수면과 터빈 출구의 차이이며, 높은 수문 자체가 낙차를 늘리지는 않습니다.

signal arcade_event(points: int, success: bool, message: String, count_correct: bool)
signal game_over(generated_kwh: float)

const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const GATE_NAMES: Array[String] = ["하단", "중단", "상단"]
const GATE_LEVELS: Array[float] = [20.0, 48.0, 72.0]
const GATE_Y: Array[float] = [1.40, 2.90, 4.20]
const GATE_CAPACITY: Array[float] = [30.0, 52.0, 78.0]
const RAIN_SEGMENT_SECONDS := 5.0
const RAIN_PROFILES := [
	[7.0, 15.0, 5.8, 13.0, 7.8, 14.0],
	[8.0, 13.0, 6.0, 16.0, 5.5, 13.5],
	[6.5, 16.0, 7.2, 12.5, 8.0, 15.0],
]
const DRAIN_PER_FLOW := 0.78
const CHARGE_PER_TAP := 0.145
const CHARGE_DECAY_PER_SECOND := 1.8
const CHARGE_HOLD_SECONDS := 0.24
const HERO_RUN_SPEED := 3.15
const HERO_JUMP_SPEED := 7.3
const HERO_GRAVITY := 15.0
const HERO_MIN_X := -0.10
const HERO_MAX_X := 3.95
const PLATFORM_LEFT: Array[float] = [-0.10, 1.55, -0.10]
const PLATFORM_RIGHT: Array[float] = [3.95, 3.95, 2.55]
const LEVER_X: Array[float] = [0.42, 3.35, 0.42]
const LEVER_REACH := 0.55
const SCORE_SECONDS := 0.25
const SCORE_PER_KWH := 12.0
const TURBINE_EFFICIENCY := 0.88
const RESERVOIR_BOTTOM := 0.30
const RESERVOIR_HEIGHT := 5.40
const TAILWATER_Y := 1.05

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var hero: Node3D
var water: MeshInstance3D
var water_mesh: BoxMesh
var rain_streaks: Array[MeshInstance3D] = []
var head_marker: MeshInstance3D
var gate_doors: Array[MeshInstance3D] = []
var gate_labels: Array[Label3D] = []
var lever_lights: Array[MeshInstance3D] = []
var active_channels: Array[MeshInstance3D] = []
var channel_pulses: Array = []
var turbine: Node3D
var generator_light: MeshInstance3D
var city_light: MeshInstance3D
var power_line: MeshInstance3D

var selected_gate := -1
var open_gate := -1
var water_level := 34.0
var rain_seed := 0
var elapsed := 0.0
var hero_x := 3.45
var hero_y := 0.0
var hero_velocity_y := 0.0
var hero_floor_index := 0
var hero_move_axis := 0.0
var charge := 0.0
var tap_age := 10.0
var generated_kwh := 0.0
var awarded_points := 0
var score_elapsed := 0.0
var visual_time := 0.0
var running := false
var overflowed := false
var jump_was_down := false
var space_was_down := false
var close_was_down := false
var notice := "물이 차오릅니다. 낙차가 커질 때 수문을 여세요!"
var notice_remaining := 2.5

var level_label: Label
var head_label: Label
var output_label: Label
var energy_label: Label
var choice_label: Label
var control_label: Label
var charge_label: Label
var charge_bar: ProgressBar
var warning_label: Label
var forecast_label: Label
var result_label: Label
var flash: ColorRect
var gate_open_material: StandardMaterial3D
var gate_selected_material: StandardMaterial3D
var gate_closed_material: StandardMaterial3D
var charge_normal_style: StyleBoxFlat
var charge_danger_style: StyleBoxFlat

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 286)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_viewport()
	_build_world()
	_build_overlay()
	set_process(true)

func setup(player_data: Dictionary, game_seed: int) -> void:
	rain_seed = game_seed
	elapsed = 0.0
	selected_gate = -1
	open_gate = -1
	water_level = initial_level_for_seed(rain_seed)
	hero_x = 3.45
	hero_y = platform_height(0)
	hero_velocity_y = 0.0
	hero_floor_index = 0
	hero_move_axis = 0.0
	charge = 0.0
	tap_age = 10.0
	generated_kwh = 0.0
	awarded_points = 0
	score_elapsed = 0.0
	visual_time = 0.0
	overflowed = false
	jump_was_down = false
	space_was_down = false
	close_was_down = false
	notice = "물이 차오릅니다. 낙차가 커질 때 수문을 여세요!"
	notice_remaining = 2.5
	_spawn_hero(player_data)
	_update_visuals()
	running = true

func set_running(value: bool) -> void:
	running = value
	if is_instance_valid(hero):
		hero.call("_set_avatar_animation_state", false)

func finalize_generation_score() -> void:
	_flush_generation_score()

static func head_for_level(level: float) -> float:
	# 화면의 수면과 공통 터빈 출구의 높이 차이를 1 게임 단위 = 10m로 환산합니다.
	var surface_y := RESERVOIR_BOTTOM + clampf(level, 0.0, 100.0) / 100.0 * RESERVOIR_HEIGHT
	return maxf(0.0, (surface_y - TAILWATER_Y) * 10.0)

static func flow_for_gate(level: float, gate_index: int) -> float:
	if gate_index < 0 or gate_index >= GATE_LEVELS.size() or level <= GATE_LEVELS[gate_index]:
		return 0.0
	# 잠긴 취수구의 깊이가 커질수록 유량이 늘어납니다. 수로별 크기는 다릅니다.
	return GATE_CAPACITY[gate_index] * sqrt((level - GATE_LEVELS[gate_index]) / 100.0)

static func power_for_gate(level: float, gate_index: int) -> float:
	# P(MW) = rho(1000 kg/m³) * g * Q(m³/s) * H(m) * eta / 1,000,000.
	return 9.81 * flow_for_gate(level, gate_index) * head_for_level(level) * TURBINE_EFFICIENCY / 1000.0

static func best_gate_for_level(level: float) -> int:
	var best_index := -1
	var best_power := 0.0
	for gate_index in range(GATE_LEVELS.size()):
		var candidate := power_for_gate(level, gate_index)
		if candidate > best_power:
			best_power = candidate
			best_index = gate_index
	return best_index

static func initial_level_for_seed(seed_value: int) -> float:
	var seeded_rng := RandomNumberGenerator.new()
	seeded_rng.seed = seed_value
	return seeded_rng.randf_range(32.0, 37.0)

static func inflow_for_time(seconds: float, seed_value: int) -> float:
	var profile_index := posmod(seed_value, RAIN_PROFILES.size())
	var segment := clampi(int(floor(seconds / RAIN_SEGMENT_SECONDS)), 0, RAIN_PROFILES[profile_index].size() - 1)
	return float(RAIN_PROFILES[profile_index][segment])

static func platform_height(index: int) -> float:
	return GATE_Y[index] - 0.17

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.name = "HydroHeadTimingViewport"
	viewport.size = Vector2i(960, 286)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("a6dcf0")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e5f7ff")
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	world.add_child(environment_node)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-45, -24, 0)
	sunlight.light_energy = 1.1
	sunlight.shadow_enabled = false
	world.add_child(sunlight)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.2
	camera.position = Vector3(0.2, 6.0, 17.0)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 2.9, 0.0), Vector3.UP)
	gate_open_material = _material(Color("55e9bf"), true)
	gate_selected_material = _material(Color("ffe18d"), true)
	gate_closed_material = _material(Color("a7b3bc"), false)
	_build_dam()

func _build_dam() -> void:
	_box("Ground", Vector3(0, -0.30, -0.6), Vector3(24, 0.45, 9), Color("77ae78"))
	_box("ReservoirBack", Vector3(-6.4, 3.0, -1.6), Vector3(10.3, 6.2, 0.45), Color("a0b4ac"))
	_box("ReservoirLeft", Vector3(-11.2, 2.9, 0.2), Vector3(0.5, 6.0, 2.6), Color("8d9e94"))
	_box("DamWall", Vector3(-1.45, 3.0, -0.5), Vector3(0.9, 6.2, 2.2), Color("b7c2bd"))
	_box("DamTop", Vector3(-1.45, 6.2, -0.2), Vector3(1.8, 0.35, 3.2), Color("d5d4be"))
	water_mesh = BoxMesh.new()
	water_mesh.size = Vector3(9.4, 2.0, 1.7)
	water = MeshInstance3D.new()
	water.name = "RisingReservoirWater"
	water.mesh = water_mesh
	water.material_override = _material(Color("3f9bdfbd"), true)
	world.add_child(water)
	for rain_index in range(24):
		var rain_x := -10.4 + float(rain_index % 12) * 0.76
		var rain_y := 5.55 + float(rain_index / 12) * 0.42
		rain_streaks.append(_box("RainDrop%d" % rain_index, Vector3(rain_x, rain_y, 1.65), Vector3(0.035, 0.31, 0.035), Color("d1f2ffba"), true))
	_box("OverflowLine", Vector3(-6.2, 5.72, 1.0), Vector3(9.6, 0.09, 0.18), Color("fb7471"), true)
	_box("Tailwater", Vector3(7.2, 0.02, -0.2), Vector3(10.0, 0.18, 3.3), Color("4b9bd2"))
	for gate_index in range(3):
		var gate_y := GATE_Y[gate_index]
		var door := _box("GateDoor%d" % gate_index, Vector3(-0.92, gate_y, 0.78), Vector3(0.30, 0.55, 0.65), Color("e9ad70"))
		gate_doors.append(door)
		var gate_label := Label3D.new()
		gate_label.position = Vector3(-2.1, gate_y + 0.12, 1.2)
		gate_label.text = "%s %d%%" % [GATE_NAMES[gate_index], roundi(GATE_LEVELS[gate_index])]
		gate_label.font_size = 45
		gate_label.pixel_size = 0.006
		gate_label.outline_size = 8
		gate_label.no_depth_test = true
		world.add_child(gate_label)
		gate_labels.append(gate_label)
		var start := Vector3(-0.65, gate_y, 0.45)
		var finish := Vector3(4.65, TAILWATER_Y, 0.45)
		_sloped_channel("Penstock%d" % gate_index, start, finish, 0.24, Color("758e98"))
		var active_channel := _sloped_channel("FlowingWater%d" % gate_index, start + Vector3(0, 0, 0.18), finish + Vector3(0, 0, 0.18), 0.15, Color("5be3ff"), true)
		active_channels.append(active_channel)
		var pulses: Array[MeshInstance3D] = []
		for pulse_index in range(4):
			pulses.append(_sphere("WaterPulse%d_%d" % [gate_index, pulse_index], start, 0.15, Color("c1f8ff"), true))
		channel_pulses.append(pulses)
		var left_x := PLATFORM_LEFT[gate_index]
		var right_x := PLATFORM_RIGHT[gate_index]
		_box("ServicePlatform%d" % gate_index, Vector3((left_x + right_x) * 0.5, gate_y - 0.25, 1.45), Vector3(right_x - left_x, 0.12, 0.85), Color("dfc48a"))
		_box("PlatformRim%d" % gate_index, Vector3((left_x + right_x) * 0.5, gate_y - 0.19, 1.04), Vector3(right_x - left_x, 0.04, 0.08), Color("fff0bd"), true)
		_box("GateLever%d" % gate_index, Vector3(LEVER_X[gate_index], gate_y + 0.25, 1.15), Vector3(0.12, 0.78, 0.15), Color("435b6c"))
		lever_lights.append(_sphere("LeverBeacon%d" % gate_index, Vector3(LEVER_X[gate_index], gate_y + 0.75, 1.15), 0.18, Color("ffe173"), true))
		if gate_index < 2:
			var jump_hint := Label3D.new()
			jump_hint.position = Vector3(2.4, gate_y + 0.20, 1.75)
			jump_hint.text = "W 점프 ↑"
			jump_hint.font_size = 40
			jump_hint.pixel_size = 0.006
			jump_hint.outline_size = 7
			jump_hint.no_depth_test = true
			world.add_child(jump_hint)
	turbine = Node3D.new()
	turbine.name = "WaterTurbine"
	turbine.position = Vector3(4.8, TAILWATER_Y, 0.9)
	world.add_child(turbine)
	_sphere_on(turbine, Vector3.ZERO, 0.27, Color("d8f7fa"))
	for blade_index in range(4):
		var blade := _box("TurbineBlade%d" % blade_index, Vector3(0, 0.55, 0), Vector3(0.18, 0.9, 0.13), Color("e4f5f6"), false, turbine)
		blade.rotation_degrees.z = float(blade_index) * 90.0
		blade.position = Vector3(sin(float(blade_index) * PI / 2.0) * 0.46, cos(float(blade_index) * PI / 2.0) * 0.46, 0)
	_box("Generator", Vector3(6.45, 1.0, 0.8), Vector3(1.15, 1.2, 1.1), Color("566d79"))
	generator_light = _sphere("GeneratorPower", Vector3(6.45, 1.8, 1.25), 0.28, Color("ffe872"), true)
	power_line = _box("PowerToCity", Vector3(8.25, 2.0, 0.4), Vector3(3.5, 0.10, 0.12), Color("ffe872"), true)
	for house_x in [9.2, 10.7]:
		_box("CityHouse", Vector3(house_x, 0.8, -0.3), Vector3(1.1, 1.6, 1.0), Color("e7dbbb"))
	city_light = _sphere("CityLight", Vector3(9.7, 1.8, 0.75), 0.33, Color("ffe872"), true)
	var city_label := Label3D.new()
	city_label.position = Vector3(9.85, 3.1, 0.5)
	city_label.text = "도시 전력"
	city_label.font_size = 51
	city_label.pixel_size = 0.006
	city_label.outline_size = 8
	city_label.no_depth_test = true
	world.add_child(city_label)
	head_marker = _box("HeadDistance", Vector3(-10.45, 2.4, 1.45), Vector3(0.10, 2.5, 0.10), Color("ffe073"), true)

func _spawn_hero(player_data: Dictionary) -> void:
	if is_instance_valid(hero):
		hero.queue_free()
	hero = PLAYER_PAWN.new()
	world.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_player", hero_data)
	hero.call("set_side_run_enabled", true)
	hero.position = Vector3(hero_x, hero_y, 1.8)
	hero.scale = Vector3.ONE * 2.1
	if hero.shadow_mesh:
		hero.shadow_mesh.visible = false
	hero.call("_set_avatar_animation_state", false)

func _build_overlay() -> void:
	level_label = _overlay_label(Vector2(14, 7), Vector2(330, 36), "저수위 34%", Color("fff0b4"), HORIZONTAL_ALIGNMENT_LEFT, 20)
	energy_label = _overlay_label(Vector2(600, 7), Vector2(945, 36), "누적 생산 0.0 kWh", Color("ffe381"), HORIZONTAL_ALIGNMENT_RIGHT, 20)
	head_label = _overlay_label(Vector2(14, 38), Vector2(320, 67), "수면 → 터빈 낙차 39m", Color("aeebfa"), HORIZONTAL_ALIGNMENT_LEFT, 17)
	output_label = _overlay_label(Vector2(610, 38), Vector2(945, 67), "현재 발전 0.0 MW", Color("9af5d0"), HORIZONTAL_ALIGNMENT_RIGHT, 18)
	choice_label = _overlay_label(Vector2(245, 37), Vector2(735, 69), "레버 앞에서 수문을 열 수 있어요", Color("fff0b4"), HORIZONTAL_ALIGNMENT_CENTER, 17)
	warning_label = _overlay_label(Vector2(283, 7), Vector2(680, 35), "넘침까지 남은 시간", Color("ffca7e"), HORIZONTAL_ALIGNMENT_CENTER, 19)
	forecast_label = _overlay_label(Vector2(255, 72), Vector2(715, 100), "", Color("eafaff"), HORIZONTAL_ALIGNMENT_CENTER, 16)
	control_label = _overlay_label(Vector2(70, 213), Vector2(890, 242), "A/D 이동 · W 점프 · SPACE 연타로 열기 · E 닫기", Color("fff0b4"), HORIZONTAL_ALIGNMENT_CENTER, 16)
	charge_label = _overlay_label(Vector2(14, 249), Vector2(330, 278), "레버에 접근하세요", Color("fff0b4"), HORIZONTAL_ALIGNMENT_LEFT, 17)
	charge_bar = ProgressBar.new()
	charge_bar.position = Vector2(330, 247)
	charge_bar.size = Vector2(616, 26)
	charge_bar.max_value = 1.0
	charge_bar.show_percentage = false
	charge_normal_style = _bar_style(Color("52e4be"))
	charge_danger_style = _bar_style(Color("ff7b68"))
	charge_bar.add_theme_stylebox_override("background", _bar_style(Color("183645")))
	charge_bar.add_theme_stylebox_override("fill", charge_normal_style)
	add_child(charge_bar)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color.TRANSPARENT
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	result_label = _overlay_label(Vector2(160, 94), Vector2(800, 172), "", Color("ffe276"), HORIZONTAL_ALIGNMENT_CENTER, 34)
	result_label.visible = false

func _process(delta: float) -> void:
	visual_time += delta
	if not running or overflowed:
		_animate_world(delta)
		return
	var move_axis := float(int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)))
	var jump_down := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	_advance_hero(delta, move_axis, jump_down and not jump_was_down)
	jump_was_down = jump_down
	var space_down := Input.is_key_pressed(KEY_SPACE)
	if space_down and not space_was_down:
		_tap_selected_gate()
	space_was_down = space_down
	var close_down := Input.is_key_pressed(KEY_E)
	if close_down and not close_was_down:
		_close_open_gate(true)
	close_was_down = close_down
	_advance_simulation(delta)
	_animate_world(delta)

func _advance_hero(delta: float, move_axis: float, jump_pressed: bool) -> void:
	hero_move_axis = move_axis
	hero_x = clampf(hero_x + move_axis * HERO_RUN_SPEED * delta, HERO_MIN_X, HERO_MAX_X)
	if hero_floor_index >= 0:
		if jump_pressed:
			hero_velocity_y = HERO_JUMP_SPEED
			hero_floor_index = -1
		elif hero_x >= PLATFORM_LEFT[hero_floor_index] and hero_x <= PLATFORM_RIGHT[hero_floor_index]:
			hero_y = platform_height(hero_floor_index)
			hero_velocity_y = 0.0
			_update_station()
			return
		else:
			hero_floor_index = -1
	var previous_y := hero_y
	hero_velocity_y -= HERO_GRAVITY * delta
	hero_y += hero_velocity_y * delta
	if hero_velocity_y <= 0.0:
		for floor_index in range(2, -1, -1):
			var landing_y := platform_height(floor_index)
			if hero_x >= PLATFORM_LEFT[floor_index] and hero_x <= PLATFORM_RIGHT[floor_index] and previous_y >= landing_y and hero_y <= landing_y:
				hero_y = landing_y
				hero_velocity_y = 0.0
				hero_floor_index = floor_index
				break
	if hero_y < platform_height(0) - 1.6:
		hero_x = 3.45
		hero_y = platform_height(0)
		hero_velocity_y = 0.0
		hero_floor_index = 0
		notice = "발판에서 떨어졌어요! 다시 올라가세요."
		notice_remaining = 1.3
	_update_station()

func _update_station() -> void:
	var next_gate := -1
	if hero_floor_index >= 0 and absf(hero_x - LEVER_X[hero_floor_index]) <= LEVER_REACH:
		next_gate = hero_floor_index
	if next_gate != selected_gate:
		selected_gate = next_gate
		charge = 0.0
		tap_age = 10.0
	_update_visuals()

func _tap_selected_gate() -> void:
	if not running or overflowed or open_gate >= 0:
		return
	if selected_gate < 0:
		notice = "수문 레버까지 달려가야 열 수 있어요!"
		notice_remaining = 1.2
		return
	if water_level <= GATE_LEVELS[selected_gate] + 1.0:
		charge = 0.0
		notice = "%s 수문에는 아직 물이 닿지 않아요." % GATE_NAMES[selected_gate]
		notice_remaining = 1.2
		return
	charge = minf(1.0, charge + CHARGE_PER_TAP)
	tap_age = 0.0
	if charge >= 1.0:
		_open_selected_gate()
	_update_visuals()

func _open_selected_gate() -> void:
	open_gate = selected_gate
	charge = 0.0
	var power := power_for_gate(water_level, open_gate)
	notice = "%s 수문 개방! 낙차 %dm의 물이 터빈을 돌려 %.1f MW 발전" % [GATE_NAMES[open_gate], roundi(head_for_level(water_level)), power]
	notice_remaining = 1.6
	arcade_event.emit(0, true, notice, false)
	_update_visuals()

func _close_open_gate(manual: bool) -> void:
	if open_gate < 0 or (manual and selected_gate != open_gate):
		if manual:
			notice = "열린 수문의 레버에서 E를 눌러 닫으세요."
			notice_remaining = 1.2
		return
	var closed_gate := open_gate
	open_gate = -1
	notice = "%s 수문 닫힘 · 낙차를 다시 키울 수 있어요." % GATE_NAMES[closed_gate] if manual else "취수구가 드러나 수문이 닫혔어요."
	notice_remaining = 1.4
	_update_visuals()

func _advance_simulation(delta: float) -> void:
	if not running or overflowed:
		return
	tap_age += delta
	if tap_age > CHARGE_HOLD_SECONDS and charge > 0.0:
		charge = maxf(0.0, charge - CHARGE_DECAY_PER_SECOND * delta)
	notice_remaining = maxf(0.0, notice_remaining - delta)
	var inflow := inflow_for_time(elapsed + delta * 0.5, rain_seed)
	var flow := flow_for_gate(water_level, open_gate)
	var power := power_for_gate(water_level, open_gate)
	var gained_kwh := power * 1000.0 * delta / 3600.0
	generated_kwh += gained_kwh
	water_level += (inflow - flow * DRAIN_PER_FLOW) * delta
	elapsed += delta
	if open_gate >= 0 and water_level <= GATE_LEVELS[open_gate] + 1.0:
		_close_open_gate(false)
	score_elapsed += delta
	if score_elapsed >= SCORE_SECONDS:
		score_elapsed -= SCORE_SECONDS
		_flush_generation_score()
	if water_level >= 100.0:
		_overflow()
	_update_visuals()

func _overflow() -> void:
	if overflowed:
		return
	_flush_generation_score()
	water_level = 100.0
	overflowed = true
	running = false
	open_gate = -1
	charge = 0.0
	result_label.text = "댐 넘침! 게임 오버\n생산 전력 %.1f kWh" % generated_kwh
	result_label.visible = true
	flash.color = Color("f05c4260")
	arcade_event.emit(0, false, "댐이 넘쳤어요! 더 일찍 수문을 열어야 합니다.", false)
	game_over.emit(generated_kwh)

func _flush_generation_score() -> void:
	var points := roundi(generated_kwh * SCORE_PER_KWH) - awarded_points
	if points <= 0:
		return
	awarded_points += points
	arcade_event.emit(points, true, "터빈 발전 · 누적 %.1f kWh" % generated_kwh, false)

func _animate_world(delta: float) -> void:
	var rain_rate := inflow_for_time(elapsed, rain_seed)
	var visible_drops := roundi(24.0 * clampf((rain_rate - 3.0) / 13.0, 0.18, 1.0))
	for drop_index in range(rain_streaks.size()):
		var drop := rain_streaks[drop_index]
		drop.visible = drop_index < visible_drops
		drop.position.y -= delta * (2.4 + rain_rate * 0.27)
		if drop.position.y < RESERVOIR_BOTTOM + water_level / 100.0 * RESERVOIR_HEIGHT:
			drop.position.y = 6.05 + float(drop_index % 5) * 0.17
	if is_instance_valid(hero):
		hero.position = Vector3(hero_x, hero_y, 1.8)
		var moving := absf(hero_move_axis) > 0.01 or hero_floor_index < 0
		if hero.is_moving != moving:
			hero.call("_set_avatar_animation_state", moving)
		if absf(hero_move_axis) > 0.01 and hero.avatar_sprite:
			hero.avatar_sprite.flip_h = hero_move_axis < 0.0
	if open_gate < 0:
		return
	turbine.rotation_degrees.z += (180.0 + flow_for_gate(water_level, open_gate) * 3.0) * delta
	generator_light.scale = Vector3.ONE * (0.85 + 0.18 * sin(visual_time * 10.0))
	for pulse_index in range((channel_pulses[open_gate] as Array).size()):
		var pulse := channel_pulses[open_gate][pulse_index] as MeshInstance3D
		var progress := fposmod(visual_time * 1.35 + float(pulse_index) * 0.25, 1.0)
		pulse.position = Vector3(-0.65, GATE_Y[open_gate], 0.8).lerp(Vector3(4.65, TAILWATER_Y, 0.8), progress)

func _update_visuals() -> void:
	if not is_instance_valid(water):
		return
	var water_height := maxf(0.05, water_level / 100.0 * RESERVOIR_HEIGHT)
	water_mesh.size.y = water_height
	water.position = Vector3(-6.3, RESERVOIR_BOTTOM + water_height * 0.5, 0.1)
	head_marker.position.y = (RESERVOIR_BOTTOM + water_height + TAILWATER_Y) * 0.5
	(head_marker.mesh as BoxMesh).size.y = maxf(0.1, RESERVOIR_BOTTOM + water_height - TAILWATER_Y)
	var current_power := power_for_gate(water_level, open_gate)
	for gate_index in range(3):
		var submerged := water_level > GATE_LEVELS[gate_index] + 1.0
		var opened := open_gate == gate_index
		gate_doors[gate_index].material_override = gate_open_material if opened else (gate_selected_material if gate_index == selected_gate else gate_closed_material)
		gate_doors[gate_index].position.x = -0.68 if opened else -0.92
		gate_labels[gate_index].text = "%s %d%% %s" % [GATE_NAMES[gate_index], roundi(GATE_LEVELS[gate_index]), "열림" if opened else ("물 닿음" if submerged else "마름")]
		gate_labels[gate_index].modulate = Color("85ffcf") if opened else (Color("ffe696") if gate_index == selected_gate else Color("d6e6e9"))
		lever_lights[gate_index].material_override = gate_open_material if opened else (gate_selected_material if gate_index == selected_gate else gate_closed_material)
		active_channels[gate_index].visible = opened
		for pulse in channel_pulses[gate_index]:
			(pulse as MeshInstance3D).visible = opened
	generator_light.visible = open_gate >= 0
	city_light.visible = open_gate >= 0
	power_line.visible = open_gate >= 0
	level_label.text = "저수위 %d%%  %s" % [roundi(water_level), "넘침 위험!" if water_level >= 86.0 else "↑ 물이 차오름"]
	level_label.add_theme_color_override("font_color", Color("ff8675") if water_level >= 86.0 else Color("fff0b4"))
	energy_label.text = "누적 생산  %.1f kWh" % generated_kwh
	head_label.text = "수면 → 터빈 낙차  %dm" % roundi(head_for_level(water_level))
	output_label.text = "현재 발전  %.1f MW" % current_power
	if selected_gate >= 0:
		choice_label.text = "%s 수문 · 지금 열면 약 %.1f MW%s" % [GATE_NAMES[selected_gate], power_for_gate(water_level, selected_gate), " · E 닫기" if open_gate == selected_gate else ""]
	else:
		choice_label.text = "수문 레버까지 이동하세요 · 현재 층 %d" % (hero_floor_index + 1) if hero_floor_index >= 0 else "점프해서 위층 발판에 착지하세요"
	var overflow_eta := projected_overflow_seconds(water_level, elapsed, rain_seed, open_gate)
	warning_label.text = "넘침까지 약 %.1f초%s" % [overflow_eta, " · 방류 중" if open_gate >= 0 else ""] if overflow_eta >= 0.0 else ("방류 중 · 범람 위험 낮음" if open_gate >= 0 else "종료 전 범람 위험 낮음")
	warning_label.add_theme_color_override("font_color", Color("ff756e") if water_level >= 86.0 else Color("ffcf7d"))
	var current_inflow := inflow_for_time(elapsed, rain_seed)
	var next_change := RAIN_SEGMENT_SECONDS - fposmod(elapsed, RAIN_SEGMENT_SECONDS)
	var next_inflow := inflow_for_time(elapsed + next_change + 0.01, rain_seed)
	forecast_label.text = "현재 %s %.1f%%/초  ·  %.1f초 뒤 %s" % [_rain_name(current_inflow), current_inflow, next_change, _rain_name(next_inflow)] if elapsed + next_change < 30.0 else "현재 %s %.1f%%/초  ·  마지막 물결" % [_rain_name(current_inflow), current_inflow]
	forecast_label.add_theme_color_override("font_color", Color("ffad96") if next_inflow >= 13.0 and next_change < 3.0 else Color("eafaff"))
	control_label.text = notice if notice_remaining > 0.0 else "A/D 이동 · W 점프 · 레버 앞 SPACE 연타로 열기 · E로 닫기"
	charge_label.text = "%s 수문 개방  %d%%" % [GATE_NAMES[selected_gate], roundi(charge * 100.0)] if selected_gate >= 0 else "수문 레버로 이동"
	charge_bar.value = charge
	charge_bar.add_theme_stylebox_override("fill", charge_danger_style if water_level >= 86.0 else charge_normal_style)

static func _rain_name(rate: float) -> String:
	return "폭우" if rate >= 13.0 else ("비" if rate >= 8.0 else "약한 비")

static func dry_overflow_seconds(level: float, current_time: float, seed_value: int) -> float:
	var remaining := maxf(0.0, 100.0 - level)
	var cursor := current_time
	var seconds := 0.0
	while cursor < 30.0 and remaining > 0.0:
		var segment_end := minf(30.0, (floor(cursor / RAIN_SEGMENT_SECONDS) + 1.0) * RAIN_SEGMENT_SECONDS)
		var span := segment_end - cursor
		var rate := inflow_for_time(cursor + 0.001, seed_value)
		if remaining <= rate * span:
			return seconds + remaining / rate
		remaining -= rate * span
		seconds += span
		cursor = segment_end
	return -1.0

static func projected_overflow_seconds(level: float, current_time: float, seed_value: int, opened_gate: int) -> float:
	if opened_gate < 0:
		return dry_overflow_seconds(level, current_time, seed_value)
	var predicted_level := level
	var predicted_gate := opened_gate
	var cursor := current_time
	while cursor < 30.0:
		var step := minf(0.10, 30.0 - cursor)
		var rain := inflow_for_time(cursor + step * 0.5, seed_value)
		var flow := flow_for_gate(predicted_level, predicted_gate)
		predicted_level += (rain - flow * DRAIN_PER_FLOW) * step
		cursor += step
		if predicted_level >= 100.0:
			return cursor - current_time
		if predicted_gate >= 0 and predicted_level <= GATE_LEVELS[predicted_gate] + 1.0:
			predicted_gate = -1
	return -1.0

func _box(node_name: String, where: Vector3, dimensions: Vector3, color: Color, glowing: bool = false, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = where
	instance.material_override = _material(color, glowing)
	(parent if parent != null else world).add_child(instance)
	return instance

func _sloped_channel(node_name: String, start: Vector3, finish: Vector3, thickness: float, color: Color, glowing: bool = false) -> MeshInstance3D:
	var direction := finish - start
	var channel := _box(node_name, (start + finish) * 0.5, Vector3(direction.length(), thickness, thickness), color, glowing)
	channel.rotation.z = atan2(direction.y, direction.x)
	return channel

func _sphere(node_name: String, where: Vector3, radius: float, color: Color, glowing: bool = false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = where
	instance.material_override = _material(color, glowing)
	world.add_child(instance)
	return instance

func _sphere_on(parent: Node3D, where: Vector3, radius: float, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = where
	instance.material_override = _material(color, false)
	parent.add_child(instance)

func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glowing:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 0.75
	return material

func _overlay_label(from: Vector2, to: Vector2, content: String, color: Color, alignment: HorizontalAlignment, font_size: int) -> Label:
	var label := Label.new()
	label.position = from
	label.size = to - from
	label.text = content
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("173744"))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	return label

func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(7)
	return style
