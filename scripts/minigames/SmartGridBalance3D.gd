extends SubViewportContainer
class_name SmartGridBalance3D

## 변화하는 도시 수요에 공급을 맞추는 경량 3D 스마트그리드 아케이드입니다.

signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const DEMAND_PHASE_SECONDS := 4.2
const SUPPLY_CHANGE_SPEED := 42.0
const BALANCE_TOLERANCE := 6.0
const DANGER_DIFFERENCE := 24.0
const DEMAND_EVENTS: Array[Dictionary] = [
	{"label": "학교 수업 시작", "delta": 18},
	{"label": "전기 버스 충전", "delta": 24},
	{"label": "가정의 저녁 활동", "delta": 16},
	{"label": "더운 날 냉방 증가", "delta": 20},
	{"label": "공장 교대 종료", "delta": -22},
	{"label": "점심시간 절전", "delta": -16},
	{"label": "LED 절전 실천", "delta": -18},
	{"label": "태양광 발전 설비 점검", "delta": 14},
]

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var hero: Node3D
var substation_core: MeshInstance3D
var city_buildings: Array[MeshInstance3D] = []
var city_windows: Array[MeshInstance3D] = []
var power_lines: Array[MeshInstance3D] = []
var power_pulses: Array[MeshInstance3D] = []

var rng := RandomNumberGenerator.new()
var running := false
var demand := 60.0
var demand_target := 60.0
var supply := 50.0
var phase_elapsed := 0.0
var score_tick := 0.0
var phase_index := 0
var phase_scored := false
var balance_combo := 0
var hero_adjusting := false
var visual_time := 0.0
var current_event := "도시 전력망 가동"
var gap_integral := 0.0
var measurement_time := 0.0

var normal_building_material: StandardMaterial3D
var balanced_building_material: StandardMaterial3D
var shortage_building_material: StandardMaterial3D
var overload_building_material: StandardMaterial3D
var normal_line_material: StandardMaterial3D
var balanced_line_material: StandardMaterial3D
var danger_line_material: StandardMaterial3D
var normal_window_material: StandardMaterial3D
var shortage_window_material: StandardMaterial3D
var overload_window_material: StandardMaterial3D

var event_label: Label
var demand_label: Label
var balance_label: Label
var help_label: Label
var supply_bar: ProgressBar
var demand_bar: ProgressBar
var phase_bar: ProgressBar
var danger_tint: ColorRect

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 286)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	rng.seed = 431
	_build_viewport()
	_build_world()
	_build_overlay()
	set_process(true)

func setup(player_data: Dictionary, game_seed: int) -> void:
	rng.seed = game_seed
	_spawn_hero(player_data)
	demand = float(rng.randi_range(5, 8) * 10)
	demand_target = demand
	supply = 50.0
	gap_integral = 0.0
	measurement_time = 0.0
	_start_demand_phase(true)
	running = true

func set_running(value: bool) -> void:
	running = value
	if is_instance_valid(hero) and hero.has_method("_set_avatar_animation_state"):
		hero.call("_set_avatar_animation_state", false)

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.name = "SmartGridViewport"
	viewport.size = Vector2i(960, 286)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	world.name = "SmartGridWorld"
	viewport.add_child(world)

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("102f4c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9deed")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -28, 0)
	light.light_color = Color("d8f5ff")
	light.light_energy = 1.15
	light.shadow_enabled = false
	world.add_child(light)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 6.1, 10.8)
	camera.fov = 49.0
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 1.25, -1.6), Vector3.UP)

	_create_materials()
	_build_city()
	_build_substation()
	_build_power_routes()

func _create_materials() -> void:
	normal_building_material = _material(Color("3f7084"), false)
	balanced_building_material = _material(Color("42dca3"), true)
	shortage_building_material = _material(Color("273e59"), false)
	overload_building_material = _material(Color("e05a45"), true)
	normal_line_material = _material(Color("54a9cb"), true)
	balanced_line_material = _material(Color("64f2b4"), true)
	danger_line_material = _material(Color("ff5c4f"), true)
	normal_window_material = _material(Color("f8dc70"), true)
	shortage_window_material = _material(Color("344754"), false)
	overload_window_material = _material(Color("ff7757"), true)

func _build_city() -> void:
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(16.0, 0.18, 12.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.13, -2.0)
	ground.material_override = _material(Color("1b4956"), false)
	world.add_child(ground)

	for row in range(3):
		for side in [-1, 1]:
			for column in range(2):
				var building := MeshInstance3D.new()
				var box := BoxMesh.new()
				var height := 1.05 + float((row + column) % 3) * 0.48
				box.size = Vector3(1.15, height, 1.05)
				building.mesh = box
				building.position = Vector3(float(side) * (2.9 + float(column) * 1.55), height * 0.5, -1.3 - float(row) * 1.7)
				building.material_override = normal_building_material
				world.add_child(building)
				city_buildings.append(building)
				_build_windows(building, height)

func _build_windows(building: MeshInstance3D, height: float) -> void:
	for floor_index in range(2):
		var window := MeshInstance3D.new()
		var window_box := BoxMesh.new()
		window_box.size = Vector3(0.72, 0.16, 0.035)
		window.mesh = window_box
		window.position = building.position + Vector3(0.0, minf(height - 0.18, 0.36 + float(floor_index) * 0.42), 0.545)
		window.material_override = normal_window_material
		world.add_child(window)
		city_windows.append(window)

func _build_substation() -> void:
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.25
	base_mesh.bottom_radius = 1.45
	base_mesh.height = 0.28
	base_mesh.radial_segments = 24
	base.mesh = base_mesh
	base.position = Vector3(0.0, 0.04, 0.45)
	base.material_override = _material(Color("243f50"), false)
	world.add_child(base)

	for side in [-1, 1]:
		var mast := MeshInstance3D.new()
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.08
		mast_mesh.bottom_radius = 0.12
		mast_mesh.height = 1.8
		mast.mesh = mast_mesh
		mast.position = Vector3(float(side) * 0.62, 0.95, 0.45)
		mast.material_override = _material(Color("a9c8cf"), false)
		world.add_child(mast)

	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.42
	core_mesh.height = 0.84
	substation_core = MeshInstance3D.new()
	substation_core.mesh = core_mesh
	substation_core.position = Vector3(0.0, 1.22, 0.45)
	substation_core.material_override = normal_line_material
	world.add_child(substation_core)

func _build_power_routes() -> void:
	for lane in [-1, 0, 1]:
		var line := MeshInstance3D.new()
		var line_box := BoxMesh.new()
		line_box.size = Vector3(0.075, 0.055, 6.5)
		line.mesh = line_box
		line.position = Vector3(float(lane) * 3.15, 0.12, -2.0)
		line.material_override = normal_line_material
		world.add_child(line)
		power_lines.append(line)
		for pulse_index in range(4):
			var pulse := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.105
			sphere.height = 0.21
			pulse.mesh = sphere
			pulse.position = Vector3(float(lane) * 3.15, 0.22, 1.1 - float(pulse_index) * 1.55)
			pulse.material_override = balanced_line_material
			pulse.set_meta("route_offset", float(pulse_index) * 1.55 + float(lane + 1) * 0.37)
			world.add_child(pulse)
			power_pulses.append(pulse)

func _build_overlay() -> void:
	danger_tint = ColorRect.new()
	danger_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	danger_tint.color = Color(0.65, 0.04, 0.02, 0.0)
	danger_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(danger_tint)

	help_label = _overlay_label("W/S 또는 ↑/↓  공급량 조절", Vector2(14, 8), 16, Color("eafff8"))
	event_label = _overlay_label("", Vector2(14, 36), 21, Color("ffe47d"))

	demand_label = Label.new()
	demand_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	demand_label.offset_left = -390.0
	demand_label.offset_top = 8.0
	demand_label.offset_right = -14.0
	demand_label.offset_bottom = 42.0
	demand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	demand_label.add_theme_font_size_override("font_size", 20)
	demand_label.add_theme_color_override("font_color", Color("c7f4ff"))
	demand_label.add_theme_color_override("font_outline_color", Color("071c28"))
	demand_label.add_theme_constant_override("outline_size", 5)
	add_child(demand_label)

	balance_label = Label.new()
	balance_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	balance_label.offset_left = -330.0
	balance_label.offset_top = 62.0
	balance_label.offset_right = 330.0
	balance_label.offset_bottom = 102.0
	balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance_label.add_theme_font_size_override("font_size", 26)
	balance_label.add_theme_color_override("font_outline_color", Color("071c28"))
	balance_label.add_theme_constant_override("outline_size", 7)
	add_child(balance_label)

	var supply_caption := _overlay_label("공급", Vector2(18, 228), 15, Color("72efb6"))
	supply_caption.custom_minimum_size.x = 70.0
	var demand_caption := _overlay_label("수요", Vector2(18, 254), 15, Color("ffcf78"))
	demand_caption.custom_minimum_size.x = 70.0

	supply_bar = ProgressBar.new()
	supply_bar.position = Vector2(88, 230)
	supply_bar.size = Vector2(740, 17)
	supply_bar.max_value = 120.0
	supply_bar.show_percentage = false
	_style_progress_bar(supply_bar, Color("55e6a6"), Color("183743"))
	add_child(supply_bar)
	demand_bar = ProgressBar.new()
	demand_bar.position = Vector2(88, 256)
	demand_bar.size = Vector2(740, 17)
	demand_bar.max_value = 120.0
	demand_bar.show_percentage = false
	_style_progress_bar(demand_bar, Color("ffd36e"), Color("183743"))
	add_child(demand_bar)
	phase_bar = ProgressBar.new()
	phase_bar.position = Vector2(844, 230)
	phase_bar.size = Vector2(96, 43)
	phase_bar.max_value = DEMAND_PHASE_SECONDS
	phase_bar.show_percentage = false
	_style_progress_bar(phase_bar, Color("72cfff"), Color("183743"))
	add_child(phase_bar)

func _style_progress_bar(bar: ProgressBar, fill_color: Color, background_color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = background_color
	background.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("fill", fill)

func _overlay_label(text_value: String, position_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("071c28"))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	return label

func _spawn_hero(player_data: Dictionary) -> void:
	if is_instance_valid(hero):
		hero.queue_free()
	hero = PLAYER_PAWN.new()
	world.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_player", hero_data)
	hero.call("set_back_run_enabled", true)
	hero.position = Vector3(0.0, 0.14, 2.75)
	hero.scale = Vector3.ONE * 1.65
	hero.call("_set_avatar_animation_state", false)

func _process(delta: float) -> void:
	if not running:
		return
	visual_time += delta
	phase_elapsed += delta
	var input_direction := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_direction += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_direction -= 1.0
	supply = clampf(supply + input_direction * SUPPLY_CHANGE_SPEED * delta, 20.0, 120.0)
	# 수요는 목표값으로 순간 이동하지 않고 실제 계기판처럼 연속적으로 움직입니다.
	var demand_blend := 1.0 - exp(-delta * 1.15)
	demand = lerpf(demand, demand_target, demand_blend)
	if is_instance_valid(hero):
		hero.position.x = lerpf(hero.position.x, input_direction * 0.72, clampf(delta * 7.0, 0.0, 1.0))
		var adjusting := not is_zero_approx(input_direction)
		if adjusting != hero_adjusting:
			hero_adjusting = adjusting
			hero.call("_set_avatar_animation_state", adjusting)

	var difference := supply - demand
	var balanced := absf(difference) <= BALANCE_TOLERANCE
	var gap := absf(difference)
	gap_integral += gap * delta
	measurement_time += delta
	# 오차 0 MW일 때 최대점, 오차가 커질수록 연속적으로 점수가 감소합니다.
	# 따라서 30초 동안 평균 간격을 더 작게 유지한 플레이어가 반드시 유리합니다.
	var synchronization := clampf(1.0 - gap / 60.0, 0.0, 1.0)
	score_tick += delta
	if score_tick >= 0.20:
		score_tick = 0.0
		var points := roundi(32.0 * synchronization * synchronization)
		if synchronization >= 0.90:
			balance_combo += 1
		else:
			balance_combo = 0
		if points > 0:
			var first_precise_sync := synchronization >= 0.90 and not phase_scored
			if first_precise_sync:
				phase_scored = true
			arcade_event.emit(points, true, "동기화 %d%% · 간격이 작을수록 점수가 커집니다." % roundi(synchronization * 100.0), first_precise_sync)

	_update_city_visuals(delta, difference, balanced)
	_update_hud(difference, balanced)
	if phase_elapsed >= DEMAND_PHASE_SECONDS:
		_start_demand_phase(false)

func _start_demand_phase(initial: bool) -> void:
	phase_index += 1
	phase_elapsed = 0.0
	phase_scored = false
	if initial:
		current_event = "도시 전력망 가동"
		return
	var event: Dictionary = DEMAND_EVENTS[rng.randi_range(0, DEMAND_EVENTS.size() - 1)]
	var previous_target := demand_target
	demand_target = clampf(demand_target + float(event["delta"]), 30.0, 110.0)
	if is_equal_approx(previous_target, demand_target):
		demand_target = clampf(demand_target - float(event["delta"]), 30.0, 110.0)
	var actual_change := roundi(demand_target - previous_target)
	current_event = "%s  %s%d MW" % [str(event["label"]), "+" if actual_change >= 0 else "", actual_change]

func _update_city_visuals(delta: float, difference: float, balanced: bool) -> void:
	var state_material := balanced_building_material
	var line_material := balanced_line_material
	if not balanced and difference < 0.0:
		state_material = shortage_building_material
		line_material = normal_line_material
	elif not balanced:
		state_material = overload_building_material
		line_material = danger_line_material
	for building in city_buildings:
		building.material_override = state_material
	var window_material := normal_window_material
	if not balanced and difference < 0.0:
		window_material = shortage_window_material
	elif not balanced:
		window_material = overload_window_material
	for window in city_windows:
		window.material_override = window_material
	for line in power_lines:
		line.material_override = line_material
	var flow_speed := lerpf(1.5, 5.5, clampf(supply / 120.0, 0.0, 1.0))
	for pulse in power_pulses:
		var offset := float(pulse.get_meta("route_offset", 0.0))
		pulse.position.z = 1.15 - fmod(visual_time * flow_speed + offset, 6.5)
		pulse.material_override = line_material
		pulse.visible = difference >= -DANGER_DIFFERENCE
	if is_instance_valid(substation_core):
		substation_core.material_override = line_material
		var beat := 1.0 + sin(visual_time * (3.0 + supply * 0.035)) * 0.08
		substation_core.scale = Vector3.ONE * beat
	var target_alpha := 0.13 if absf(difference) >= DANGER_DIFFERENCE else 0.0
	danger_tint.color.a = lerpf(danger_tint.color.a, target_alpha, clampf(delta * 7.0, 0.0, 1.0))

func _update_hud(difference: float, balanced: bool) -> void:
	supply_bar.value = supply
	demand_bar.value = demand
	phase_bar.value = DEMAND_PHASE_SECONDS - phase_elapsed
	event_label.text = "도시 변화  |  " + current_event
	var gap := absf(difference)
	var synchronization := clampf(1.0 - gap / 60.0, 0.0, 1.0) * 100.0
	var average_gap := gap_integral / maxf(measurement_time, 0.001)
	demand_label.text = "수요 %d MW  ·  공급 %d MW  ·  평균 오차 %.1f" % [roundi(demand), roundi(supply), average_gap]
	if balanced:
		balance_label.text = "✅ 동기화 %d%%  ·  간격 %.1f MW" % [roundi(synchronization), gap]
		balance_label.add_theme_color_override("font_color", Color("65f2b3"))
	elif difference < 0.0:
		balance_label.text = "동기화 %d%%  ·  공급 부족 %.1f MW  ·  W/↑" % [roundi(synchronization), gap]
		balance_label.add_theme_color_override("font_color", Color("8ed8ff"))
	else:
		balance_label.text = "동기화 %d%%  ·  공급 과잉 %.1f MW  ·  S/↓" % [roundi(synchronization), gap]
		balance_label.add_theme_color_override("font_color", Color("ff796d"))

func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.8
	return material
