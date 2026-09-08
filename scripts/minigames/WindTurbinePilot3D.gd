extends SubViewportContainer
class_name WindTurbinePilot3D

## 풍향에 터빈을 맞추고 위험 돌풍에서는 브레이크를 거는 경량 3D 아케이드입니다.

signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const WIND_PHASE_SECONDS := 4.0
const YAW_LIMIT := 65.0
const YAW_SPEED := 72.0
const ALIGNMENT_FULL_SCORE_DEGREES := 11.0
const WIND_ANGLES: Array[float] = [-55.0, -28.0, 0.0, 28.0, 55.0]
const NORMAL_WIND_SPEEDS: Array[int] = [7, 11, 15, 19, 22]

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var hero: Node3D
var turbine_head: Node3D
var rotor: Node3D
var nacelle: MeshInstance3D
var wind_vane: Node3D
var wind_streaks: Array[MeshInstance3D] = []
var main_blades: Array[Node3D] = []
var background_rotors: Array[Node3D] = []

var rng := RandomNumberGenerator.new()
var running := false
var turbine_yaw := 0.0
var wind_angle := 0.0
var wind_speed := 11
var phase_elapsed := 0.0
var score_tick := 0.0
var phase_index := 0
var phase_scored := false
var storm_phase := false
var brake_active := false
var hero_adjusting := false
var rotor_broken := false
var repair_delay := 0.0
var visual_time := 0.0

var normal_head_material: StandardMaterial3D
var aligned_head_material: StandardMaterial3D
var storm_head_material: StandardMaterial3D
var blade_material: StandardMaterial3D
var wind_material: StandardMaterial3D
var safe_material: StandardMaterial3D

var instruction_label: Label
var wind_label: Label
var alignment_label: Label
var power_bar: ProgressBar
var phase_bar: ProgressBar
var storm_tint: ColorRect
var storm_border: Panel
var storm_banner: Panel
var storm_warning_label: Label
var storm_border_style: StyleBoxFlat
var storm_banner_style: StyleBoxFlat

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
	rng.seed = game_seed
	_spawn_hero(player_data)
	_start_next_wind_phase()
	running = true

func set_running(value: bool) -> void:
	running = value
	if is_instance_valid(hero) and hero.has_method("_set_avatar_animation_state"):
		hero.call("_set_avatar_animation_state", false)

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.name = "WindPilotViewport"
	viewport.size = Vector2i(960, 286)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	world.name = "WindPilotWorld"
	viewport.add_child(world)

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("76bfd1")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e5fbff")
	environment.ambient_light_energy = 0.82
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_color = Color("f6fff1")
	light.light_energy = 1.1
	light.shadow_enabled = false
	world.add_child(light)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 4.45, 10.8)
	camera.fov = 50.0
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 2.35, 0.0), Vector3.UP)

	_create_materials()
	_build_landscape()
	_build_main_turbine()
	_build_wind_vane()
	_build_wind_streaks()

func _create_materials() -> void:
	normal_head_material = _material(Color("d9eef0"), false)
	aligned_head_material = _material(Color("52e6ad"), true)
	aligned_head_material.emission_energy_multiplier = 1.25
	storm_head_material = _material(Color("ed5b53"), true)
	storm_head_material.emission_energy_multiplier = 1.25
	blade_material = _material(Color("edf7f2"), false)
	wind_material = _material(Color("a9f1ff"), true)
	wind_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wind_material.albedo_color.a = 0.66
	wind_material.emission_energy_multiplier = 1.25
	safe_material = _material(Color("72f3b1"), true)
	safe_material.emission_energy_multiplier = 1.8

func _build_landscape() -> void:
	var ground := MeshInstance3D.new()
	var ground_box := BoxMesh.new()
	ground_box.size = Vector3(24.0, 0.18, 20.0)
	ground.mesh = ground_box
	ground.position = Vector3(0.0, -0.12, -2.0)
	ground.material_override = _material(Color("5c9959"), false)
	world.add_child(ground)

	var service_pad := MeshInstance3D.new()
	var pad_cylinder := CylinderMesh.new()
	pad_cylinder.top_radius = 3.1
	pad_cylinder.bottom_radius = 3.35
	pad_cylinder.height = 0.22
	pad_cylinder.radial_segments = 32
	service_pad.mesh = pad_cylinder
	service_pad.position = Vector3(0.0, 0.03, 0.0)
	service_pad.material_override = _material(Color("365e62"), false)
	world.add_child(service_pad)

	for side in [-1, 1]:
		for z_index in range(3):
			_build_background_turbine(Vector3(float(side) * (5.2 + z_index), 0.0, -3.0 - z_index * 3.2), 0.52 - z_index * 0.07)

func _build_main_turbine() -> void:
	var tower := MeshInstance3D.new()
	var tower_mesh := CylinderMesh.new()
	tower_mesh.top_radius = 0.22
	tower_mesh.bottom_radius = 0.48
	tower_mesh.height = 4.8
	tower_mesh.radial_segments = 20
	tower.mesh = tower_mesh
	tower.position = Vector3(0.0, 2.42, 0.0)
	tower.material_override = _material(Color("d6e3df"), false)
	world.add_child(tower)

	turbine_head = Node3D.new()
	turbine_head.name = "TurbineHead"
	turbine_head.position = Vector3(0.0, 4.75, 0.0)
	world.add_child(turbine_head)

	nacelle = MeshInstance3D.new()
	var nacelle_box := BoxMesh.new()
	nacelle_box.size = Vector3(0.82, 0.62, 1.35)
	nacelle.mesh = nacelle_box
	nacelle.position.z = -0.20
	nacelle.material_override = normal_head_material
	turbine_head.add_child(nacelle)

	rotor = Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0.0, 0.0, 0.56)
	turbine_head.add_child(rotor)
	var hub := MeshInstance3D.new()
	var hub_sphere := SphereMesh.new()
	hub_sphere.radius = 0.28
	hub_sphere.height = 0.56
	hub.mesh = hub_sphere
	hub.material_override = _material(Color("3a7b8c"), true)
	rotor.add_child(hub)
	_build_rotor_blades()

func _build_rotor_blades() -> void:
	if not is_instance_valid(rotor) or not main_blades.is_empty():
		return
	for blade_index in range(3):
		var blade_root := Node3D.new()
		blade_root.name = "BladeRoot%d" % blade_index
		blade_root.rotation.z = deg_to_rad(float(blade_index) * 120.0)
		rotor.add_child(blade_root)
		var blade := MeshInstance3D.new()
		var blade_box := BoxMesh.new()
		blade_box.size = Vector3(0.16, 1.72, 0.09)
		blade.mesh = blade_box
		blade.position.y = 0.93
		blade.rotation.z = deg_to_rad(-7.0)
		blade.material_override = blade_material
		blade_root.add_child(blade)
		main_blades.append(blade_root)

func _build_background_turbine(base_position: Vector3, scale_value: float) -> void:
	var root_3d := Node3D.new()
	root_3d.position = base_position
	root_3d.scale = Vector3.ONE * scale_value
	world.add_child(root_3d)
	var tower := MeshInstance3D.new()
	var tower_mesh := CylinderMesh.new()
	tower_mesh.top_radius = 0.16
	tower_mesh.bottom_radius = 0.34
	tower_mesh.height = 4.0
	tower.mesh = tower_mesh
	tower.position.y = 2.0
	tower.material_override = _material(Color("c7d8d5"), false)
	root_3d.add_child(tower)
	var rotor_root := Node3D.new()
	rotor_root.position = Vector3(0.0, 4.0, 0.22)
	root_3d.add_child(rotor_root)
	background_rotors.append(rotor_root)
	for blade_index in range(3):
		var blade_root := Node3D.new()
		blade_root.rotation.z = deg_to_rad(float(blade_index) * 120.0)
		rotor_root.add_child(blade_root)
		var blade := MeshInstance3D.new()
		var blade_box := BoxMesh.new()
		blade_box.size = Vector3(0.10, 1.25, 0.06)
		blade.mesh = blade_box
		blade.position = Vector3(0.0, 0.68, 0.0)
		blade.material_override = blade_material
		blade_root.add_child(blade)

func _build_wind_vane() -> void:
	wind_vane = Node3D.new()
	wind_vane.name = "WindDirectionArrow"
	wind_vane.position = Vector3(0.0, 0.22, 0.0)
	world.add_child(wind_vane)
	var shaft := MeshInstance3D.new()
	var shaft_box := BoxMesh.new()
	shaft_box.size = Vector3(0.14, 0.06, 3.2)
	shaft.mesh = shaft_box
	shaft.position.z = 1.15
	shaft.material_override = wind_material
	wind_vane.add_child(shaft)
	var tip := MeshInstance3D.new()
	var tip_cone := CylinderMesh.new()
	tip_cone.top_radius = 0.0
	tip_cone.bottom_radius = 0.42
	tip_cone.height = 0.85
	tip_cone.radial_segments = 16
	tip.mesh = tip_cone
	tip.position.z = 2.85
	tip.rotation.x = deg_to_rad(90.0)
	tip.material_override = wind_material
	wind_vane.add_child(tip)

func _build_wind_streaks() -> void:
	for streak_index in range(14):
		var streak := MeshInstance3D.new()
		var streak_box := BoxMesh.new()
		streak_box.size = Vector3(0.045, 0.045, rng.randf_range(0.75, 1.65))
		streak.mesh = streak_box
		streak.position = Vector3(rng.randf_range(-5.8, 5.8), rng.randf_range(0.7, 5.8), rng.randf_range(-5.0, 5.0))
		streak.material_override = wind_material
		world.add_child(streak)
		wind_streaks.append(streak)

func _build_overlay() -> void:
	storm_tint = ColorRect.new()
	storm_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	storm_tint.color = Color(0.72, 0.02, 0.02, 0.18)
	storm_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storm_tint.visible = false
	add_child(storm_tint)

	instruction_label = Label.new()
	instruction_label.position = Vector2(14, 10)
	instruction_label.text = "A / D  터빈 회전       풍향 화살표와 터빈을 맞추세요"
	instruction_label.add_theme_font_size_override("font_size", 16)
	instruction_label.add_theme_color_override("font_color", Color("f2fff8"))
	instruction_label.add_theme_color_override("font_outline_color", Color("12313b"))
	instruction_label.add_theme_constant_override("outline_size", 5)
	add_child(instruction_label)

	wind_label = Label.new()
	wind_label.position = Vector2(14, 40)
	wind_label.add_theme_font_size_override("font_size", 22)
	wind_label.add_theme_color_override("font_color", Color("9deeff"))
	wind_label.add_theme_color_override("font_outline_color", Color("12313b"))
	wind_label.add_theme_constant_override("outline_size", 6)
	add_child(wind_label)

	alignment_label = Label.new()
	alignment_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	alignment_label.offset_left = -330.0
	alignment_label.offset_top = 10.0
	alignment_label.offset_right = -14.0
	alignment_label.offset_bottom = 42.0
	alignment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	alignment_label.add_theme_font_size_override("font_size", 18)
	alignment_label.add_theme_color_override("font_color", Color("ffe67b"))
	alignment_label.add_theme_color_override("font_outline_color", Color("12313b"))
	alignment_label.add_theme_constant_override("outline_size", 5)
	add_child(alignment_label)

	power_bar = ProgressBar.new()
	power_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	power_bar.offset_left = 120.0
	power_bar.offset_top = -42.0
	power_bar.offset_right = -120.0
	power_bar.offset_bottom = -20.0
	power_bar.min_value = 0.0
	power_bar.max_value = 100.0
	power_bar.show_percentage = false
	add_child(power_bar)

	phase_bar = ProgressBar.new()
	phase_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	phase_bar.offset_left = 120.0
	phase_bar.offset_top = -17.0
	phase_bar.offset_right = -120.0
	phase_bar.offset_bottom = -10.0
	phase_bar.max_value = WIND_PHASE_SECONDS
	phase_bar.show_percentage = false
	add_child(phase_bar)

	storm_border = Panel.new()
	storm_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	storm_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storm_border_style = StyleBoxFlat.new()
	storm_border_style.bg_color = Color(0.22, 0.0, 0.0, 0.08)
	storm_border_style.border_color = Color("ff3028")
	storm_border_style.set_border_width_all(8)
	storm_border_style.set_corner_radius_all(10)
	storm_border.add_theme_stylebox_override("panel", storm_border_style)
	storm_border.visible = false
	add_child(storm_border)

	storm_banner = Panel.new()
	storm_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	storm_banner.offset_left = -330.0
	storm_banner.offset_top = 66.0
	storm_banner.offset_right = 330.0
	storm_banner.offset_bottom = 140.0
	storm_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storm_banner_style = StyleBoxFlat.new()
	storm_banner_style.bg_color = Color(0.42, 0.015, 0.015, 0.94)
	storm_banner_style.border_color = Color("ff5148")
	storm_banner_style.set_border_width_all(4)
	storm_banner_style.set_corner_radius_all(14)
	storm_banner_style.shadow_color = Color(0.08, 0.0, 0.0, 0.65)
	storm_banner_style.shadow_size = 8
	storm_banner.add_theme_stylebox_override("panel", storm_banner_style)
	storm_banner.visible = false
	add_child(storm_banner)

	storm_warning_label = Label.new()
	storm_warning_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	storm_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	storm_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	storm_warning_label.add_theme_font_size_override("font_size", 25)
	storm_warning_label.add_theme_color_override("font_color", Color("fff1bf"))
	storm_warning_label.add_theme_color_override("font_outline_color", Color("400000"))
	storm_warning_label.add_theme_constant_override("outline_size", 5)
	storm_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storm_banner.add_child(storm_warning_label)

func _spawn_hero(player_data: Dictionary) -> void:
	if is_instance_valid(hero):
		hero.queue_free()
	hero = PLAYER_PAWN.new()
	world.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_player", hero_data)
	hero.call("set_back_run_enabled", true)
	hero.position = Vector3(0.0, 0.14, 3.2)
	hero.scale = Vector3.ONE * 1.75
	hero_adjusting = false
	hero.call("_set_avatar_animation_state", false)

func _process(delta: float) -> void:
	if not running or not is_instance_valid(turbine_head):
		return
	visual_time += delta
	phase_elapsed += delta
	if rotor_broken:
		repair_delay -= delta
		if repair_delay <= 0.0:
			rotor_broken = false
			_build_rotor_blades()
	var input_direction := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_direction -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_direction += 1.0
	turbine_yaw = clampf(turbine_yaw + input_direction * YAW_SPEED * delta, -YAW_LIMIT, YAW_LIMIT)
	turbine_head.rotation.y = deg_to_rad(turbine_yaw)
	wind_vane.rotation.y = deg_to_rad(wind_angle)
	if is_instance_valid(hero):
		hero.position.x = lerpf(hero.position.x, turbine_yaw / YAW_LIMIT * 1.45, clampf(delta * 5.5, 0.0, 1.0))
		var should_animate := not is_zero_approx(input_direction)
		if should_animate != hero_adjusting:
			hero_adjusting = should_animate
			hero.call("_set_avatar_animation_state", should_animate)

	var alignment := _alignment_efficiency()
	var generated_power := _generated_power_percent(alignment)
	if storm_phase:
		generated_power = 0.0
		if Input.is_key_pressed(KEY_SPACE) and not phase_scored:
			_engage_storm_brake()
	else:
		_score_aligned_generation(delta, alignment)
	_update_rotor(delta, generated_power)
	_update_wind_streaks(delta)
	_update_hud(alignment, generated_power)
	if phase_elapsed >= WIND_PHASE_SECONDS:
		_finish_wind_phase()

func _alignment_efficiency() -> float:
	var angular_error := absf(wrapf(turbine_yaw - wind_angle, -180.0, 180.0))
	return clampf(1.0 - angular_error / 55.0, 0.0, 1.0)

func _generated_power_percent(alignment: float) -> float:
	# 같은 정렬 상태에서도 풍속이 높을수록 더 큰 발전량을 보여 줍니다.
	var speed_factor := clampf(float(wind_speed) / 22.0, 0.0, 1.0)
	return alignment * alignment * speed_factor * 100.0

func _score_aligned_generation(delta: float, alignment: float) -> void:
	if absf(wrapf(turbine_yaw - wind_angle, -180.0, 180.0)) > ALIGNMENT_FULL_SCORE_DEGREES:
		score_tick = 0.0
		return
	score_tick += delta
	if score_tick < 0.34:
		return
	score_tick = 0.0
	var points := 7 + int(round(float(wind_speed) * 0.85))
	var first_capture := not phase_scored
	phase_scored = true
	_show_score_popup(points, true, "%d m/s 발전" % wind_speed)
	arcade_event.emit(points, true, "풍향 정렬! %d m/s 바람으로 발전 중" % wind_speed, first_capture)

func _engage_storm_brake() -> void:
	phase_scored = true
	brake_active = true
	if is_instance_valid(nacelle):
		nacelle.material_override = safe_material
	_set_storm_overlay(true, true)
	_show_score_popup(75, true, "위험 돌풍 안전 정지!")
	arcade_event.emit(75, true, "강풍에서는 터빈을 멈춰 장비를 보호합니다.", true)

func _finish_wind_phase() -> void:
	if storm_phase and not phase_scored:
		_break_turbine_blades()
		_show_score_popup(35, false, "강풍 브레이크를 놓쳤어요")
		arcade_event.emit(35, false, "너무 강한 바람에서는 터빈을 멈춰야 고장을 막습니다.", false)
	_start_next_wind_phase()

func _start_next_wind_phase() -> void:
	phase_index += 1
	phase_elapsed = 0.0
	score_tick = 0.0
	phase_scored = false
	brake_active = false
	storm_phase = phase_index % 4 == 0
	wind_angle = WIND_ANGLES[rng.randi_range(0, WIND_ANGLES.size() - 1)]
	if storm_phase:
		wind_speed = rng.randi_range(27, 32)
		_set_wind_visual_color(Color("ff5148"))
		_set_storm_overlay(true, false)
		if is_instance_valid(nacelle):
			nacelle.material_override = storm_head_material
		if is_instance_valid(instruction_label):
			instruction_label.text = "위험 돌풍!  SPACE를 눌러 터빈 브레이크"
	else:
		wind_speed = NORMAL_WIND_SPEEDS[rng.randi_range(0, NORMAL_WIND_SPEEDS.size() - 1)]
		_set_wind_visual_color(Color("a9f1ff"))
		_set_storm_overlay(false, false)
		if is_instance_valid(nacelle):
			nacelle.material_override = normal_head_material
		if is_instance_valid(instruction_label):
			instruction_label.text = "A / D  터빈 회전       풍향 화살표와 터빈을 맞추세요"

func _update_rotor(delta: float, power_percent: float) -> void:
	if not is_instance_valid(rotor):
		return
	# 실제 풍속을 애니메이션 속도에 직접 연결합니다. 정렬이 나빠도 바람은 불지만
	# 발전 효율은 낮고, 위험 돌풍에서는 브레이크 전까지 가장 빠르게 회전합니다.
	var wind_factor := clampf((float(wind_speed) - 7.0) / 25.0, 0.0, 1.0)
	var capture_factor := 1.0 if storm_phase else 0.38 + clampf(power_percent / 100.0, 0.0, 1.0) * 0.62
	var spin_speed := 0.10 if brake_active else lerpf(1.35, 7.2, wind_factor) * capture_factor
	rotor.rotation.z -= delta * spin_speed
	for background_rotor in background_rotors:
		if is_instance_valid(background_rotor):
			background_rotor.rotation.z -= delta * lerpf(0.8, 4.6, wind_factor)
	if is_instance_valid(nacelle) and not storm_phase:
		nacelle.material_override = aligned_head_material if power_percent >= 72.0 else normal_head_material

func _update_wind_streaks(delta: float) -> void:
	var radians := deg_to_rad(wind_angle)
	var direction := Vector3(sin(radians), 0.0, cos(radians)).normalized()
	var wind_factor := clampf((float(wind_speed) - 7.0) / 25.0, 0.0, 1.0)
	var movement := direction * delta * lerpf(2.4, 10.5, wind_factor)
	for streak_index in range(wind_streaks.size()):
		var streak := wind_streaks[streak_index]
		streak.position += movement
		if storm_phase and not brake_active:
			streak.position.y += sin(visual_time * 11.0 + float(streak_index) * 1.7) * delta * 1.6
		streak.rotation.y = radians
		streak.scale.z = lerpf(0.75, 2.2, wind_factor)
		if absf(streak.position.x) > 6.5 or absf(streak.position.z) > 6.5:
			streak.position = Vector3(rng.randf_range(-5.5, 5.5), rng.randf_range(0.7, 5.8), rng.randf_range(-5.5, -3.5))

func _break_turbine_blades() -> void:
	if rotor_broken or main_blades.is_empty():
		return
	rotor_broken = true
	repair_delay = 1.15
	var detached_blades := main_blades.duplicate()
	main_blades.clear()
	for blade_index in range(detached_blades.size()):
		var blade: Node3D = detached_blades[blade_index]
		var preserved_transform := blade.global_transform
		rotor.remove_child(blade)
		world.add_child(blade)
		blade.global_transform = preserved_transform
		var side := -1.0 if blade_index == 0 else (1.0 if blade_index == 1 else 0.35)
		var target := blade.position + Vector3(side * rng.randf_range(3.6, 5.4), rng.randf_range(2.0, 4.2), rng.randf_range(1.2, 3.8))
		var target_rotation := blade.rotation + Vector3(rng.randf_range(2.5, 5.0), rng.randf_range(2.0, 4.5), side * rng.randf_range(5.5, 9.0))
		var tween := create_tween().set_parallel(true)
		tween.tween_property(blade, "position", target, 1.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(blade, "rotation", target_rotation, 1.05).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(blade, "scale", Vector3.ONE * 0.35, 1.05).set_delay(0.45)
		tween.chain().tween_callback(blade.queue_free)
	if is_instance_valid(camera):
		var base_position := camera.position
		var shake := create_tween()
		shake.tween_property(camera, "position", base_position + Vector3(0.16, 0.08, 0.0), 0.06)
		shake.tween_property(camera, "position", base_position + Vector3(-0.13, -0.05, 0.0), 0.07)
		shake.tween_property(camera, "position", base_position, 0.08)

func _update_hud(alignment: float, power_percent: float) -> void:
	if is_instance_valid(phase_bar):
		phase_bar.value = WIND_PHASE_SECONDS - phase_elapsed
	if is_instance_valid(power_bar):
		power_bar.value = power_percent
	var direction_text := "정면"
	if wind_angle < -8.0:
		direction_text = "← 왼쪽"
	elif wind_angle > 8.0:
		direction_text = "오른쪽 →"
	if is_instance_valid(wind_label):
		wind_label.text = "%s  풍향 %s · %d m/s" % ["⚠ 위험" if storm_phase else "🌬", direction_text, wind_speed]
		wind_label.add_theme_color_override("font_color", Color("ff756d") if storm_phase else Color("9deeff"))
	if is_instance_valid(alignment_label):
		if storm_phase:
			alignment_label.text = "SPACE 브레이크  %s" % ("안전 정지 완료" if brake_active else "지금 누르세요!")
		else:
			alignment_label.text = "정렬도 %d%%  ·  발전 %d%%" % [roundi(alignment * 100.0), roundi(power_percent)]
	if storm_phase and is_instance_valid(storm_warning_label):
		if brake_active:
			storm_warning_label.text = "✅ 브레이크 성공 · 터빈 안전 정지"
			storm_border.modulate.a = 1.0
			storm_banner.modulate.a = 1.0
			storm_tint.modulate.a = 0.45
		else:
			var remaining := maxf(0.0, WIND_PHASE_SECONDS - phase_elapsed)
			storm_warning_label.text = "⚠ 위험 돌풍  %d m/s\nSPACE 브레이크!  %.1f초" % [wind_speed, remaining]
			var pulse := 0.72 + sin(phase_elapsed * 12.0) * 0.28
			storm_border.modulate.a = pulse
			storm_banner.modulate.a = 0.86 + pulse * 0.14
			storm_tint.modulate.a = 0.48 + pulse * 0.32

func _set_storm_overlay(active: bool, safe: bool) -> void:
	if not is_instance_valid(storm_tint):
		return
	storm_tint.visible = active
	storm_border.visible = active
	storm_banner.visible = active
	if not active:
		return
	var accent := Color("54efaa") if safe else Color("ff3028")
	storm_border_style.border_color = accent
	storm_banner_style.border_color = accent
	storm_banner_style.bg_color = Color(0.015, 0.28, 0.17, 0.94) if safe else Color(0.42, 0.015, 0.015, 0.94)
	storm_warning_label.add_theme_color_override("font_color", Color("d8ffec") if safe else Color("fff1bf"))

func _set_wind_visual_color(color: Color) -> void:
	if not is_instance_valid(wind_material):
		return
	wind_material.albedo_color = Color(color.r, color.g, color.b, 0.72)
	wind_material.emission = color

func _show_score_popup(points: int, success: bool, message: String) -> void:
	var popup := Label.new()
	popup.set_anchors_preset(Control.PRESET_CENTER_TOP)
	popup.offset_left = -280.0
	popup.offset_top = 64.0
	popup.offset_right = 280.0
	popup.offset_bottom = 112.0
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.text = "%s%d점  %s" % ["+" if success else "−", points, message]
	popup.add_theme_font_size_override("font_size", 25)
	popup.add_theme_color_override("font_color", Color("70ffb5") if success else Color("ff766d"))
	popup.add_theme_color_override("font_outline_color", Color("08202a"))
	popup.add_theme_constant_override("outline_size", 7)
	add_child(popup)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 30.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tween.chain().tween_callback(popup.queue_free)

func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.72
	return material
