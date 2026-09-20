extends SubViewportContainer
class_name BatteryShuttle3D

## 햇빛이 많을 때 남는 전기를 배터리에 넣고, 흐릴 때 저장 전기를 도시로
## 옮기는 왕복 동작으로 '충전 후 방전'을 자연스럽게 익히는 30초 아케이드입니다.

signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const PHASE_SECONDS := 5.0
const BATTERY_CAPACITY := 4
const INITIAL_CHARGE := 1
const STORE_POINTS := 20
const SUPPLY_POINTS := 80
const RUN_SPEED := 6.8
const SOLAR_X := -4.3
const BATTERY_X := 0.0
const CITY_X := 4.3
const STATION_REACH := 0.42

var viewport: SubViewport
var world: Node3D
var hero: Node3D
var cargo_orb: MeshInstance3D
var sun: Node3D
var cloud: Node3D
var battery_cells: Array[MeshInstance3D] = []
var city_windows: Array[MeshInstance3D] = []
var solar_light: MeshInstance3D
var battery_light: MeshInstance3D
var city_light: MeshInstance3D
var phase_label: Label
var phase_timer_label: Label
var charge_label: Label
var cargo_label: Label
var instruction_label: Label
var flash: ColorRect
var charged_material: StandardMaterial3D
var empty_material: StandardMaterial3D
var solar_material: StandardMaterial3D
var stored_material: StandardMaterial3D
var city_on_material: StandardMaterial3D
var city_off_material: StandardMaterial3D
var elapsed := 0.0
var hero_x := 0.0
var battery_units := INITIAL_CHARGE
var cargo := 0 # 0: 없음, 1: 남는 태양광 전기, 2: 배터리에서 꺼낸 전기
var previous_phase := -1
var interaction_cooldown := 0.0
var visual_time := 0.0
var city_flash_remaining := 0.0
var flash_remaining := 0.0
var running := false
var notice := ""
var notice_remaining := 0.0

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 286)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_overlay()
	set_process(true)

func setup(player_data: Dictionary, _game_seed: int) -> void:
	elapsed = 0.0
	hero_x = 0.0
	battery_units = INITIAL_CHARGE
	cargo = 0
	previous_phase = -1
	interaction_cooldown = 0.0
	visual_time = 0.0
	city_flash_remaining = 0.0
	flash_remaining = 0.0
	notice = "햇빛이 많아요. 왼쪽에서 남는 전기를 가져오세요!"
	notice_remaining = 2.7
	_spawn_hero(player_data)
	_update_visuals()
	running = true

func set_running(value: bool) -> void:
	running = value
	if is_instance_valid(hero):
		hero.call("_set_avatar_animation_state", false)

static func is_sunny_at(seconds: float) -> bool:
	return int(floor(maxf(0.0, seconds) / PHASE_SECONDS)) % 2 == 0

func _build_world() -> void:
	viewport = SubViewport.new()
	viewport.name = "BatteryShuttleViewport"
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
	environment.background_color = Color("a9dbe9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("f0faff")
	environment.ambient_light_energy = 0.83
	sky.environment = environment
	world.add_child(sky)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-45, -22, 0)
	sunlight.light_energy = 1.05
	sunlight.shadow_enabled = false
	world.add_child(sunlight)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.3
	camera.position = Vector3(0, 5.1, 12.8)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0, 1.45, 0), Vector3.UP)
	charged_material = _material(Color("75f8bd"), true)
	empty_material = _material(Color("42616b"), false)
	solar_material = _material(Color("ffe477"), true)
	stored_material = _material(Color("8ee8ff"), true)
	city_on_material = _material(Color("ffe988"), true)
	city_off_material = _material(Color("61757b"), false)
	_box("Ground", world, Vector3(0, -0.18, 0), Vector3(12.5, 0.35, 6.0), Color("71a48a"))
	_box("Runway", world, Vector3(0, 0.02, 1.6), Vector3(10.3, 0.08, 1.45), Color("d0dbc3"))
	for mark in range(-3, 4):
		_box("PathMark%d" % mark, world, Vector3(float(mark) * 1.28, 0.08, 1.6), Vector3(0.45, 0.03, 0.06), Color("fff2b8"), true)
	_build_solar_station()
	_build_battery_station()
	_build_city_station()
	cargo_orb = _sphere("CarriedElectricity", world, Vector3(0, 2.5, 1.75), 0.25, Color("ffe477"), true)
	cargo_orb.visible = false

func _build_solar_station() -> void:
	_box("SolarBase", world, Vector3(SOLAR_X, 0.35, -0.8), Vector3(2.45, 0.7, 1.9), Color("66a778"))
	for panel_index in range(2):
		_box("SolarPole%d" % panel_index, world, Vector3(SOLAR_X + (float(panel_index) - 0.5) * 0.9, 1.1, -0.8), Vector3(0.12, 1.1, 0.12), Color("697f8b"))
		var panel := _box("SolarPanel%d" % panel_index, world, Vector3(SOLAR_X + (float(panel_index) - 0.5) * 0.9, 1.63, -0.8), Vector3(0.95, 0.60, 0.10), Color("337cbd"), true)
		panel.rotation_degrees.x = -25.0
	solar_light = _sphere("SolarPower", world, Vector3(SOLAR_X, 2.35, -0.2), 0.20, Color("ffe477"), true)
	_label3d("태양광\n남는 전기", Vector3(SOLAR_X, 2.88, 0.30), Color("fff0b8"))
	sun = Node3D.new()
	sun.position = Vector3(SOLAR_X, 4.05, -1.0)
	world.add_child(sun)
	_sphere("Sun", sun, Vector3.ZERO, 0.36, Color("ffe277"), true)
	for ray in range(8):
		var angle := float(ray) * TAU / 8.0
		var beam := _box("SunRay", sun, Vector3(cos(angle) * 0.57, sin(angle) * 0.57, 0), Vector3(0.24, 0.09, 0.08), Color("fff1aa"), true)
		beam.rotation.z = angle

func _build_battery_station() -> void:
	_box("BatteryPedestal", world, Vector3(0, 0.30, -0.85), Vector3(2.35, 0.60, 1.75), Color("889baa"))
	_box("BatteryBody", world, Vector3(0, 1.32, -0.9), Vector3(1.75, 1.70, 1.10), Color("374d62"))
	_box("BatteryCap", world, Vector3(0, 2.23, -0.9), Vector3(0.55, 0.20, 0.55), Color("bed7db"))
	for cell_index in range(BATTERY_CAPACITY):
		var cell := _box("ChargeCell%d" % cell_index, world, Vector3((float(cell_index) - 1.5) * 0.37, 1.38, -0.29), Vector3(0.27, 0.93, 0.06), Color("75f8bd"), true)
		battery_cells.append(cell)
	battery_light = _sphere("BatteryIndicator", world, Vector3(0, 2.56, -0.50), 0.16, Color("8ee8ff"), true)
	_box("StoragePad", world, Vector3(0, 0.06, 1.65), Vector3(1.45, 0.12, 1.20), Color("c7e2bf"), true)

func _build_city_station() -> void:
	_box("CityBase", world, Vector3(CITY_X, 0.32, -0.8), Vector3(2.55, 0.65, 1.9), Color("a4b4aa"))
	for house_index in range(2):
		var house_x := CITY_X + (float(house_index) - 0.5) * 0.95
		_box("House%d" % house_index, world, Vector3(house_x, 1.37, -0.95), Vector3(0.85, 1.60, 0.85), Color("e5d5b4"))
		for window_index in range(2):
			var pane := _box("Window%d_%d" % [house_index, window_index], world, Vector3(house_x + (float(window_index) - 0.5) * 0.30, 1.48, -0.49), Vector3(0.19, 0.31, 0.05), Color("61757b"))
			city_windows.append(pane)
	city_light = _sphere("CityLight", world, Vector3(CITY_X, 2.45, -0.4), 0.20, Color("61757b"))
	_label3d("도시\n전기가 필요해요", Vector3(CITY_X, 3.03, 0.30), Color("fff0ce"))
	cloud = Node3D.new()
	cloud.position = Vector3(CITY_X, 4.05, -1.0)
	world.add_child(cloud)
	for cloud_piece in range(3):
		_sphere("CloudPiece%d" % cloud_piece, cloud, Vector3((float(cloud_piece) - 1.0) * 0.37, float(cloud_piece % 2) * 0.16, 0), 0.36, Color("e6f0f1"))

func _spawn_hero(player_data: Dictionary) -> void:
	if is_instance_valid(hero):
		hero.queue_free()
	hero = PLAYER_PAWN.new()
	world.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_player", hero_data)
	hero.call("set_side_run_enabled", true)
	hero.scale = Vector3.ONE * 2.15
	hero.position = Vector3(0, 0.13, 1.7)
	if hero.shadow_mesh:
		hero.shadow_mesh.visible = false
	hero.call("_set_avatar_animation_state", false)

func _build_overlay() -> void:
	phase_label = _overlay_label(Vector2(290, 7), Vector2(670, 40), "햇빛 많음 · 남는 전기", Color("ffe386"), 23)
	phase_timer_label = _overlay_label(Vector2(352, 40), Vector2(608, 68), "구름까지 5초", Color("effff7"), 17)
	charge_label = _overlay_label(Vector2(348, 79), Vector2(612, 109), "배터리 1/4칸", Color("a4ffe0"), 18)
	cargo_label = _overlay_label(Vector2(30, 204), Vector2(320, 233), "운반 중: 없음", Color("fff3bc"), 17)
	instruction_label = _overlay_label(Vector2(90, 260), Vector2(870, 285), "A/D로 달리기 · 태양광 → 배터리 → 도시", Color("fff1ac"), 16)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color.TRANSPARENT
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

func _process(delta: float) -> void:
	visual_time += delta
	flash_remaining = maxf(0.0, flash_remaining - delta)
	city_flash_remaining = maxf(0.0, city_flash_remaining - delta)
	if flash_remaining <= 0.0:
		flash.color = Color.TRANSPARENT
	if is_instance_valid(cargo_orb):
		cargo_orb.position = Vector3(hero_x, 2.43 + sin(visual_time * 6.0) * 0.10, 1.72)
	if is_instance_valid(sun):
		sun.rotation.z += delta * 0.4
	if not running:
		return
	elapsed += delta
	interaction_cooldown = maxf(0.0, interaction_cooldown - delta)
	notice_remaining = maxf(0.0, notice_remaining - delta)
	var new_phase := int(floor(elapsed / PHASE_SECONDS)) % 2
	if new_phase != previous_phase:
		previous_phase = new_phase
		notice = "햇빛이 많아요! 남는 전기를 배터리에 저장해요." if new_phase == 0 else "구름이 꼈어요! 배터리 전기를 도시로 보내요."
		notice_remaining = 2.3
	var axis := float(int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)))
	hero_x = clampf(hero_x + axis * RUN_SPEED * delta, SOLAR_X, CITY_X)
	if is_instance_valid(hero):
		hero.position.x = hero_x
		if hero.is_moving != (axis != 0.0):
			hero.call("_set_avatar_animation_state", axis != 0.0)
		if axis != 0.0 and hero.avatar_sprite:
			hero.avatar_sprite.flip_h = axis < 0.0
	if interaction_cooldown <= 0.0:
		_try_station_action()
	_update_visuals()

func _try_station_action() -> void:
	if hero_x <= SOLAR_X + STATION_REACH and cargo == 0 and is_sunny_at(elapsed) and battery_units < BATTERY_CAPACITY:
		cargo = 1
		notice = "발전소의 남는 전기를 받았어요. 가운데 배터리로!"
		notice_remaining = 1.5
		interaction_cooldown = 0.23
	elif absf(hero_x - BATTERY_X) <= STATION_REACH and cargo == 1:
		cargo = 0
		battery_units += 1
		arcade_event.emit(STORE_POINTS, true, "남는 전기 1칸을 배터리에 저장", true)
		_flash(Color("67f7b145"))
		interaction_cooldown = 0.23
	elif absf(hero_x - BATTERY_X) <= STATION_REACH and cargo == 0 and not is_sunny_at(elapsed) and battery_units > 0:
		cargo = 2
		battery_units -= 1
		notice = "배터리의 저장 전기를 꺼냈어요. 오른쪽 도시로!"
		notice_remaining = 1.5
		interaction_cooldown = 0.23
	elif hero_x >= CITY_X - STATION_REACH and cargo == 2:
		cargo = 0
		city_flash_remaining = 1.1
		arcade_event.emit(SUPPLY_POINTS, true, "저장 전기로 도시의 불을 켰어요", true)
		_flash(Color("ffe77b45"))
		interaction_cooldown = 0.23

func _flash(color: Color) -> void:
	flash.color = color
	flash_remaining = 0.20

func _update_visuals() -> void:
	if not is_instance_valid(cargo_orb):
		return
	var sunny := is_sunny_at(elapsed)
	sun.visible = sunny
	cloud.visible = not sunny
	solar_light.visible = sunny and battery_units < BATTERY_CAPACITY
	for cell_index in range(battery_cells.size()):
		battery_cells[cell_index].material_override = charged_material if cell_index < battery_units else empty_material
	battery_light.material_override = charged_material if battery_units > 0 else empty_material
	var city_lit := city_flash_remaining > 0.0 or sunny
	for pane in city_windows:
		pane.material_override = city_on_material if city_lit else city_off_material
	city_light.material_override = city_on_material if city_lit else city_off_material
	cargo_orb.visible = cargo != 0
	if cargo != 0:
		cargo_orb.material_override = solar_material if cargo == 1 else stored_material
	phase_label.text = "햇빛 많음 · 남는 전기" if sunny else "구름 많음 · 전기 부족"
	phase_label.add_theme_color_override("font_color", Color("ffe386") if sunny else Color("b8ecff"))
	phase_timer_label.text = "%s까지 %.1f초" % ["구름" if sunny else "햇빛", PHASE_SECONDS - fposmod(elapsed, PHASE_SECONDS)]
	charge_label.text = "배터리  %d / %d칸" % [battery_units, BATTERY_CAPACITY]
	cargo_label.text = "운반 중: %s" % ("남는 전기 → 배터리" if cargo == 1 else ("저장 전기 → 도시" if cargo == 2 else "없음"))
	if notice_remaining > 0.0:
		instruction_label.text = notice
	elif cargo == 1:
		instruction_label.text = "A/D 이동 · 가운데 배터리에 남는 전기를 넣으세요"
	elif cargo == 2:
		instruction_label.text = "A/D 이동 · 오른쪽 도시로 저장 전기를 보내세요"
	elif sunny:
		instruction_label.text = "배터리가 가득 찼어요. 구름이 올 때까지 기다리세요" if battery_units >= BATTERY_CAPACITY else "A/D 이동 · 왼쪽 태양광에서 남는 전기를 가져오세요"
	else:
		instruction_label.text = "배터리가 비었어요. 다음 햇빛 때 전기를 저장하세요" if battery_units <= 0 else "A/D 이동 · 가운데 배터리에서 전기를 꺼내세요"

func _box(node_name: String, parent: Node3D, where: Vector3, dimensions: Vector3, color: Color, glowing: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = where
	instance.material_override = _material(color, glowing)
	parent.add_child(instance)
	return instance

func _sphere(node_name: String, parent: Node3D, where: Vector3, radius: float, color: Color, glowing: bool = false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = where
	instance.material_override = _material(color, glowing)
	parent.add_child(instance)
	return instance

func _label3d(content: String, where: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.position = where
	label.text = content
	label.modulate = color
	label.font_size = 42
	label.pixel_size = 0.009
	label.outline_size = 8
	label.no_depth_test = true
	world.add_child(label)

func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.7
	return material

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
