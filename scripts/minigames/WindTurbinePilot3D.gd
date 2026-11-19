extends SubViewportContainer
class_name WindTurbinePilot3D

## 풍향에 터빈을 맞추고 위험 돌풍에서는 브레이크를 거는 경량 3D 아케이드입니다.

signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const MINIGAME_INPUT = preload("res://scripts/minigames/MiniGameInput.gd")
const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const VISUAL_STYLE = preload("res://scripts/minigames/MiniGameVisualStyle.gd")
const TURBINE_BLADE = preload("res://assets/models/wind/turbine_blade.glb")
const TURBINE_NACELLE = preload("res://assets/models/arcade/nacelle.glb")
const WIND_PHASE_SECONDS := 4.0
const YAW_LIMIT := 65.0
const YAW_SPEED := 72.0
const ALIGNMENT_FULL_SCORE_DEGREES := 11.0
const WIND_ANGLES: Array[float] = [-55.0, -28.0, 0.0, 28.0, 55.0]
const NORMAL_WIND_SPEEDS: Array[int] = [7, 11, 15, 19, 22]

var action_fx := preload("res://scripts/minigames/ArcadeMotionLayer.gd").new()
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
var rotor_speed := 0.0
var background_rotor_speed := 0.0
var brake_pads: Array[MeshInstance3D] = []
var pad_travel := 0.0

var rng := RandomNumberGenerator.new()
var visual_rng := RandomNumberGenerator.new()
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
var score_popup: Label
var score_popup_tween: Tween
var score_popup_success := false
var direction_gauge: Panel
var direction_caption: Label
var wind_pointer: ColorRect
var turbine_pointer: ColorRect
var direction_gauge_style: StyleBoxFlat
var power_caption: Label
var phase_caption: Label
var power_fill_style: StyleBoxFlat

func _init() -> void:
	add_child(action_fx)

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 286)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_viewport()
	_build_world()
	action_fx.attach(self, world, _draw_action_cue)
	_build_overlay()
	set_process(true)

func setup(player_data: Dictionary, game_seed: int) -> void:
	action_fx.clear()
	brake_was_down = false
	yaw_choice_made = false
	rng.seed = game_seed
	visual_rng.seed = game_seed ^ 0x71AD
	_spawn_hero(player_data)
	_start_next_wind_phase()
	running = true

func set_running(value: bool) -> void:
	running = value
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
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
	VISUAL_STYLE.add_environment(world)
	VISUAL_STYLE.add_key_light(world, Vector3(-48, -28, 0))

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
	aligned_head_material.emission_energy_multiplier = 0.62
	storm_head_material = _material(Color("ed5b53"), true)
	storm_head_material.emission_energy_multiplier = 0.62
	wind_material = _material(Color("a9f1ff"), true)
	wind_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wind_material.albedo_color.a = 0.66
	wind_material.emission_energy_multiplier = 0.55
	safe_material = _material(Color("72f3b1"), true)
	safe_material.emission_energy_multiplier = 0.62

func _build_landscape() -> void:
	var ground := MeshInstance3D.new()
	var ground_box := BoxMesh.new()
	ground_box.size = Vector3(24.0, 0.18, 20.0)
	ground.mesh = ground_box
	ground.position = Vector3(0.0, -0.12, -2.0)
	ground.material_override = _material(VISUAL_STYLE.FIELD, false)
	world.add_child(ground)

	var service_pad := MeshInstance3D.new()
	var pad_cylinder := CylinderMesh.new()
	pad_cylinder.top_radius = 3.1
	pad_cylinder.bottom_radius = 3.35
	pad_cylinder.height = 0.22
	pad_cylinder.radial_segments = 32
	service_pad.mesh = pad_cylinder
	service_pad.position = Vector3(0.0, 0.03, 0.0)
	service_pad.material_override = _material(VISUAL_STYLE.ROAD, false)
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
	nacelle_box.size = Vector3(0.36, 0.10, 0.04)
	nacelle.mesh = nacelle_box
	nacelle.position = Vector3(0.0, 0.17, 0.47)
	nacelle.material_override = normal_head_material
	turbine_head.add_child(nacelle)
	var housing := VISUAL_STYLE.place_prop(turbine_head, TURBINE_NACELLE, Vector3(0, -0.31, -0.20), Vector3(1.38, 0.70, 0.85))
	housing.rotation.y = PI * 0.5

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
	var brake_disc := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.41
	disc.bottom_radius = 0.41
	disc.height = 0.13
	disc.radial_segments = 20
	brake_disc.mesh = disc
	brake_disc.rotation.x = PI * 0.5
	brake_disc.position.z = 0.48
	brake_disc.material_override = _material(Color("526a71"), false)
	turbine_head.add_child(brake_disc)
	var shoe := BoxMesh.new()
	shoe.size = Vector3(0.16, 0.39, 0.25)
	var enamel := _material(Color("ffbe69"), false)
	for side in [-1.0, 1.0]:
		var pad := MeshInstance3D.new()
		pad.mesh = shoe
		pad.position = Vector3(side * 0.63, 0, 0.50)
		pad.material_override = enamel
		turbine_head.add_child(pad)
		brake_pads.append(pad)
	_build_rotor_blades()

func _build_rotor_blades() -> void:
	if not is_instance_valid(rotor) or not main_blades.is_empty():
		return
	for blade_index in range(3):
		var blade_root := TURBINE_BLADE.instantiate() as Node3D
		blade_root.name = "BladeRoot%d" % blade_index
		blade_root.rotation.z = blade_index * TAU / 3.0
		rotor.add_child(blade_root)
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
	var housing := VISUAL_STYLE.place_prop(root_3d, TURBINE_NACELLE, Vector3(0, 3.80, -0.17), Vector3(0.90, 0.48, 0.58))
	housing.rotation.y = PI * 0.5
	var rotor_root := Node3D.new()
	rotor_root.position = Vector3(0.0, 4.0, 0.24)
	rotor_root.rotation.z = base_position.x * 0.7
	root_3d.add_child(rotor_root)
	background_rotors.append(rotor_root)
	var hub := MeshInstance3D.new()
	var hub_mesh := SphereMesh.new()
	hub_mesh.radius = 0.19
	hub_mesh.height = 0.38
	hub_mesh.radial_segments = 12
	hub_mesh.rings = 5
	hub.mesh = hub_mesh
	hub.material_override = normal_head_material
	rotor_root.add_child(hub)
	for blade_index in range(3):
		var blade := TURBINE_BLADE.instantiate() as Node3D
		blade.rotation.z = blade_index * TAU / 3.0
		blade.scale = Vector3.ONE * 0.72
		rotor_root.add_child(blade)

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
		streak_box.size = Vector3(0.045, 0.045, visual_rng.randf_range(0.75, 1.65))
		streak.mesh = streak_box
		streak.position = Vector3(visual_rng.randf_range(-5.8, 5.8), visual_rng.randf_range(0.7, 5.8), visual_rng.randf_range(-5.0, 5.0))
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
	instruction_label.text = MINIGAME_INPUT.hint("wind_rhythm", "A / D  터빈 회전       풍향 화살표와 터빈을 맞추세요")
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
	power_fill_style = _style_meter(power_bar, Color("74e0b2"))
	power_caption = _comparison_label("발전 출력", Vector2.ZERO, 106, self)
	power_caption.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	power_caption.offset_left = 8.0
	power_caption.offset_right = 114.0
	power_caption.offset_top = -45.0
	power_caption.offset_bottom = -19.0
	power_caption.add_theme_font_size_override("font_size", 16)

	phase_bar = ProgressBar.new()
	phase_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	phase_bar.offset_left = 120.0
	phase_bar.offset_top = -17.0
	phase_bar.offset_right = -120.0
	phase_bar.offset_bottom = -10.0
	phase_bar.max_value = WIND_PHASE_SECONDS
	phase_bar.show_percentage = false
	add_child(phase_bar)
	_style_meter(phase_bar, Color("7dd6ed"))
	phase_caption = _comparison_label("", Vector2.ZERO, 120, self)
	phase_caption.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	phase_caption.offset_left = -116.0
	phase_caption.offset_right = -8.0
	phase_caption.offset_top = -45.0
	phase_caption.offset_bottom = -19.0
	phase_caption.add_theme_font_size_override("font_size", 15)

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
	# The old centered banner covered the main hub, hiding the very rotation
	# the learner needs to stop. Reserve the left sky, not the working turbine.
	storm_banner.set_anchors_preset(Control.PRESET_TOP_LEFT)
	storm_banner.offset_left = 14.0
	storm_banner.offset_top = 78.0
	storm_banner.offset_right = 340.0
	storm_banner.offset_bottom = 158.0
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
	storm_warning_label.add_theme_font_size_override("font_size", 21)
	storm_warning_label.add_theme_color_override("font_color", Color("fff1bf"))
	storm_warning_label.add_theme_color_override("font_outline_color", Color("400000"))
	storm_warning_label.add_theme_constant_override("outline_size", 5)
	storm_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storm_banner.add_child(storm_warning_label)
	_build_direction_gauge()

func _style_meter(bar: ProgressBar, color: Color) -> StyleBoxFlat:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("203f47")
	background.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	return fill

func _build_direction_gauge() -> void:
	direction_gauge = Panel.new()
	direction_gauge.name = "WindTurbineComparison"
	direction_gauge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	direction_gauge.offset_left = -270.0
	direction_gauge.offset_top = -164.0
	direction_gauge.offset_right = -14.0
	direction_gauge.offset_bottom = -52.0
	direction_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direction_gauge_style = StyleBoxFlat.new()
	direction_gauge_style.bg_color = Color("12343bef")
	direction_gauge_style.border_color = Color("82c6d4")
	direction_gauge_style.set_border_width_all(2)
	direction_gauge_style.set_corner_radius_all(9)
	direction_gauge.add_theme_stylebox_override("panel", direction_gauge_style)
	add_child(direction_gauge)
	direction_caption = _comparison_label("바람과 터빈을 겹쳐요", Vector2(8, 5), 240, direction_gauge)
	var track := ColorRect.new()
	track.position = Vector2(22, 63)
	track.size = Vector2(212, 2)
	track.color = Color("b8d1cf")
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direction_gauge.add_child(track)
	wind_pointer = ColorRect.new()
	wind_pointer.size = Vector2(4, 20)
	wind_pointer.position.y = 44.0
	wind_pointer.color = Color("ffd977")
	wind_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direction_gauge.add_child(wind_pointer)
	_comparison_label("바람", Vector2(-25, -17), 54, wind_pointer)
	turbine_pointer = ColorRect.new()
	turbine_pointer.size = Vector2(4, 20)
	turbine_pointer.position.y = 64.0
	turbine_pointer.color = Color("8de8ff")
	turbine_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direction_gauge.add_child(turbine_pointer)
	_comparison_label("터빈", Vector2(-25, 19), 54, turbine_pointer)

func _comparison_label(value: String, where: Vector2, width: float, parent: Control) -> Label:
	var label := Label.new()
	label.text = value
	label.position = where
	label.size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("f1fff5"))
	label.add_theme_color_override("font_outline_color", Color("12313b"))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _spawn_hero(player_data: Dictionary) -> void:
	if is_instance_valid(hero):
		hero.queue_free()
	hero = PLAYER_PAWN.new()
	world.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_arcade_player", hero_data, PLAYER_PAWN.ArcadePose.CONTROL)
	hero.position = Vector3(0.0, 0.14, 3.2)
	hero.scale = Vector3.ONE * 1.75
	hero_adjusting = false
	hero.call("_set_avatar_animation_state", false)
	VISUAL_STYLE.style_hero(hero)

func _process(delta: float) -> void:
	if not running or not is_instance_valid(turbine_head):
		return
	action_fx.advance(delta)
	visual_time += delta
	phase_elapsed += delta
	if rotor_broken:
		repair_delay -= delta
		if repair_delay <= 0.0:
			rotor_broken = false
			_build_rotor_blades()
	var input_direction := 0.0
	if MINIGAME_INPUT.is_pressed(KEY_A) or MINIGAME_INPUT.is_pressed(KEY_LEFT):
		input_direction -= 1.0
	if MINIGAME_INPUT.is_pressed(KEY_D) or MINIGAME_INPUT.is_pressed(KEY_RIGHT):
		input_direction += 1.0
	_apply_yaw_input(input_direction, delta)
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
	_update_brake_input(MINIGAME_INPUT.is_pressed(KEY_SPACE))
	if storm_phase:
		generated_power = 0.0
	else:
		if brake_active or rotor_broken:
			generated_power = 0.0
		else:
			_score_aligned_generation(delta, alignment)
	_update_rotor(delta, generated_power)
	_update_wind_streaks(delta)
	_update_hud(alignment, generated_power)
	if phase_elapsed >= WIND_PHASE_SECONDS:
		var remainder := phase_elapsed - WIND_PHASE_SECONDS
		_finish_wind_phase()
		phase_elapsed = remainder

func _alignment_efficiency() -> float:
	var angular_error := absf(wrapf(turbine_yaw - wind_angle, -180.0, 180.0))
	return clampf(1.0 - angular_error / 55.0, 0.0, 1.0)

func _generated_power_percent(alignment: float) -> float:
	# 같은 정렬 상태에서도 풍속이 높을수록 더 큰 발전량을 보여 줍니다.
	var speed_factor := clampf(float(wind_speed) / 22.0, 0.0, 1.0)
	return alignment * alignment * speed_factor * 100.0

func _score_aligned_generation(delta: float, alignment: float) -> void:
	if brake_active or rotor_broken or not yaw_choice_made:
		score_tick = 0.0
		return
	if absf(wrapf(turbine_yaw - wind_angle, -180.0, 180.0)) > ALIGNMENT_FULL_SCORE_DEGREES:
		score_tick = 0.0
		return
	score_tick += delta
	# Keep every complete generation interval and its remainder. Resetting the
	# clock on each award unfairly loses more electricity at a lower frame rate.
	while score_tick + 0.000001 >= 0.34:
		score_tick = maxf(0.0, score_tick - 0.34)
		var points := 7 + int(round(float(wind_speed) * 0.85))
		var first_capture := not phase_scored
		phase_scored = true
		if first_capture:
			action_fx.play_cue(&"generate", 1.15)
			_show_score_popup(points, true, "풍향 정렬 · 발전 시작")
		arcade_event.emit(points, true, "풍향 정렬! %d m/s 바람으로 발전 중" % wind_speed, first_capture)

var brake_was_down := false
var yaw_choice_made := false

func _apply_yaw_input(direction: float, delta: float) -> void:
	var previous := turbine_yaw
	turbine_yaw = clampf(turbine_yaw + direction * YAW_SPEED * delta, -YAW_LIMIT, YAW_LIMIT)
	yaw_choice_made = yaw_choice_made or not is_equal_approx(previous, turbine_yaw)

func _update_brake_input(down: bool) -> void:
	var new_press := down and not brake_was_down
	brake_was_down = down
	if storm_phase:
		if down and not brake_active:
			_engage_storm_brake(new_press)
	else:
		brake_active = down
		if down and is_instance_valid(instruction_label):
			instruction_label.text = "보통 바람에서는 브레이크를 놓아야 발전해요."

func _engage_storm_brake(award: bool = true) -> void:
	action_fx.play_cue(&"brake", 1.30)
	phase_scored = true
	brake_active = true
	if is_instance_valid(nacelle):
		nacelle.material_override = safe_material
	_set_storm_overlay(true, true)
	# The storm banner already shows the success; a second popup covers it.
	arcade_event.emit(75 if award else 0, true, "돌풍을 보고 멈추면 장비를 지켜요." if award else "계속 멈추면 발전도 멈춰요. 보통 바람에는 브레이크를 놓아 보세요.", award)

func _finish_wind_phase() -> void:
	if storm_phase and not phase_scored:
		_break_turbine_blades()
		_show_score_popup(35, false, "강풍 브레이크를 놓쳤어요")
		arcade_event.emit(35, false, "너무 강한 바람에서는 터빈을 멈춰야 고장을 막습니다.", false)
	_start_next_wind_phase()

func _start_next_wind_phase() -> void:
	# A previous phase's generation message must not cover a new storm alert
	# or claim that generation is still running after the situation changes.
	if score_popup_success:
		_clear_score_popup()
	phase_index += 1
	phase_elapsed = 0.0
	score_tick = 0.0
	phase_scored = false
	brake_active = false
	storm_phase = phase_index % 4 == 0
	wind_angle = WIND_ANGLES[rng.randi_range(0, WIND_ANGLES.size() - 1)]
	if storm_phase:
		action_fx.play_cue(&"gust", 1.22)
		wind_speed = rng.randi_range(27, 32)
		_set_wind_visual_color(Color("ff5148"))
		_set_storm_overlay(true, false)
		if is_instance_valid(nacelle):
			nacelle.material_override = storm_head_material
		if is_instance_valid(instruction_label):
			instruction_label.text = MINIGAME_INPUT.hint("wind_rhythm", "위험 돌풍!  SPACE를 눌러 터빈 브레이크")
	else:
		wind_speed = NORMAL_WIND_SPEEDS[rng.randi_range(0, NORMAL_WIND_SPEEDS.size() - 1)]
		_set_wind_visual_color(Color("a9f1ff"))
		_set_storm_overlay(false, false)
		if is_instance_valid(nacelle):
			nacelle.material_override = normal_head_material
		if is_instance_valid(instruction_label):
			instruction_label.text = MINIGAME_INPUT.hint("wind_rhythm", "A / D  터빈 회전       풍향 화살표와 터빈을 맞추세요")

func _update_rotor(delta: float, power_percent: float) -> void:
	if not is_instance_valid(rotor):
		return
	# 실제 풍속을 애니메이션 속도에 직접 연결합니다. 정렬이 나빠도 바람은 불지만
	# 발전 효율은 낮고, 위험 돌풍에서는 브레이크 전까지 가장 빠르게 회전합니다.
	var wind_factor := clampf((float(wind_speed) - 7.0) / 25.0, 0.0, 1.0)
	var capture_factor := 1.0 if storm_phase else 0.38 + clampf(power_percent / 100.0, 0.0, 1.0) * 0.62
	var target_speed := 0.0 if brake_active or rotor_broken else lerpf(1.35, 7.2, wind_factor) * capture_factor
	pad_travel = move_toward(pad_travel, 1.0 if brake_active else 0.0, delta * 5.5)
	for i in range(brake_pads.size()):
		var spacing := lerpf(0.63, 0.455, smoothstep(0.0, 1.0, pad_travel))
		brake_pads[i].position.x = spacing * (-1.0 if i == 0 else 1.0)
	var previous_speed := rotor_speed
	rotor_speed = move_toward(rotor_speed, target_speed, delta * (24.0 if brake_active else 5.0))
	rotor.rotation.z -= delta * (previous_speed + rotor_speed) * 0.5
	var farm_target := 0.0 if storm_phase else lerpf(0.8, 4.6, wind_factor)
	var previous_farm_speed := background_rotor_speed
	background_rotor_speed = move_toward(background_rotor_speed, farm_target, delta * (16.0 if storm_phase else 3.0))
	var farm_step := delta * (previous_farm_speed + background_rotor_speed) * 0.5
	for background_rotor in background_rotors:
		background_rotor.rotation.z -= farm_step
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
			streak.position = Vector3(visual_rng.randf_range(-5.5, 5.5), visual_rng.randf_range(0.7, 5.8), visual_rng.randf_range(-5.5, -3.5))

func _break_turbine_blades() -> void:
	if rotor_broken or main_blades.is_empty():
		return
	rotor_broken = true
	repair_delay = 1.15
	var detached_blades := main_blades.duplicate()
	main_blades.clear()
	for blade in detached_blades:
		# After separation the blade tumbles around its mass centre, carrying
		# its tangential velocity from the hub into a falling arc.
		var fragment := Node3D.new()
		world.add_child(fragment)
		fragment.global_transform = blade.global_transform.translated_local(Vector3.UP * 0.85)
		blade.reparent(fragment, true)
		var initial_position := fragment.position
		var velocity := fragment.basis.x * rotor_speed * 0.85 + fragment.basis.z * 1.2
		var flight_time := (velocity.y + sqrt(velocity.y * velocity.y + 19.6 * initial_position.y)) / 9.8
		var spin := Vector3(visual_rng.randf_range(-2.0, 2.0), visual_rng.randf_range(-1.5, 1.5), -rotor_speed)
		var tween := fragment.create_tween().set_parallel(true)
		tween.tween_method(func(t: float) -> void:
			fragment.position = initial_position + velocity * t + Vector3.DOWN * 4.9 * t * t
		, 0.0, flight_time, flight_time)
		tween.tween_property(fragment, "rotation", fragment.rotation + spin * flight_time, flight_time)
		tween.tween_property(fragment, "scale", Vector3.ONE * 0.05, 0.14).set_delay(flight_time - 0.14)
		tween.chain().tween_callback(fragment.queue_free)
	rotor_speed = 0.0
	if is_instance_valid(camera):
		var base_position := camera.position
		var shake := create_tween()
		shake.tween_property(camera, "position", base_position + Vector3(0.16, 0.08, 0.0), 0.06)
		shake.tween_property(camera, "position", base_position + Vector3(-0.13, -0.05, 0.0), 0.07)
		shake.tween_property(camera, "position", base_position, 0.08)

func _update_hud(alignment: float, power_percent: float) -> void:
	_update_direction_feedback(alignment, power_percent)
	if is_instance_valid(phase_bar):
		phase_bar.value = WIND_PHASE_SECONDS - phase_elapsed
	if is_instance_valid(power_bar):
		power_bar.value = power_percent
		power_fill_style.bg_color = Color("819ca0") if brake_active or rotor_broken or storm_phase else Color("74e0b2")
		power_caption.text = "발전 멈춤" if brake_active or rotor_broken or storm_phase else "발전 출력"
		phase_caption.text = "바람 %.1f초" % maxf(0.0, WIND_PHASE_SECONDS - phase_elapsed)
	var direction_text := "정면"
	if wind_angle < -8.0:
		direction_text = "← 왼쪽"
	elif wind_angle > 8.0:
		direction_text = "오른쪽 →"
	if is_instance_valid(wind_label):
		wind_label.text = "%s풍향 %s · %d m/s" % ["주의! " if storm_phase else "", direction_text, wind_speed]
		wind_label.add_theme_color_override("font_color", Color("ff756d") if storm_phase else Color("9deeff"))
	if is_instance_valid(alignment_label):
		if storm_phase:
			alignment_label.text = "발전 0% · 안전 정지" if brake_active else "과속 위험 · 발전 중단"
		elif not yaw_choice_made:
			alignment_label.text = "정렬도 %d%% · 예상 발전 %d%%" % [roundi(alignment * 100.0), roundi(power_percent)]
		else:
			alignment_label.text = "정렬도 %d%%  ·  발전 %d%%" % [roundi(alignment * 100.0), roundi(power_percent)]
	if is_instance_valid(instruction_label) and storm_phase:
		instruction_label.text = "멈추면 돌풍에서 날개를 지킬 수 있어요"
	elif is_instance_valid(instruction_label):
		if rotor_broken:
			instruction_label.text = MINIGAME_INPUT.hint("wind_rhythm", "터빈 수리 중 · 잠깐 뒤 A/D로 풍향을 맞춰요")
		elif brake_active:
			instruction_label.text = MINIGAME_INPUT.hint("wind_rhythm", "보통 바람에는 SPACE를 놓아 발전을 이어가요")
		elif not yaw_choice_made:
			instruction_label.text = MINIGAME_INPUT.hint("wind_rhythm", "A/D로 한 번 조절해 시작 · 풍향에 맞추면 점수가 쌓여요")
		else:
			instruction_label.text = MINIGAME_INPUT.hint("wind_rhythm", "A/D 방향 조절 · SPACE 브레이크")
		if phase_index % 4 == 3 and phase_elapsed >= WIND_PHASE_SECONDS - 1.0:
			instruction_label.text = MINIGAME_INPUT.hint("wind_rhythm", "돌풍 접근! 다음 바람에서는 SPACE로 터빈을 멈춰요")
	if storm_phase and is_instance_valid(storm_warning_label):
		if brake_active:
			storm_warning_label.text = "안전 정지 완료!\n돌풍에서 날개를 지켰어요"
			storm_border.modulate.a = 1.0
			storm_banner.modulate.a = 1.0
			storm_tint.modulate.a = 0.45
		else:
			var remaining := maxf(0.0, WIND_PHASE_SECONDS - phase_elapsed)
			storm_warning_label.text = MINIGAME_INPUT.hint("wind_rhythm", "위험 돌풍  %d m/s\nSPACE 브레이크!  %.1f초") % [wind_speed, remaining]
			var pulse := 0.80 + sin(phase_elapsed * 3.5) * 0.20
			storm_border.modulate.a = pulse
			storm_banner.modulate.a = 0.86 + pulse * 0.14
			storm_tint.modulate.a = 0.48 + pulse * 0.32

func _update_direction_feedback(alignment: float, _power_percent: float) -> void:
	if not is_instance_valid(direction_gauge):
		return
	# The large storm banner is the only central stop instruction. Do not add a
	# second empty comparison card while direction no longer matters.
	direction_gauge.visible = not storm_phase
	# The upper wind pin and lower turbine pin share the SAME angle scale.
	# Their positions convey the cause, while the rotor/output show the result.
	wind_pointer.position.x = 20.0 + inverse_lerp(-YAW_LIMIT, YAW_LIMIT, wind_angle) * 212.0
	turbine_pointer.position.x = 20.0 + inverse_lerp(-YAW_LIMIT, YAW_LIMIT, turbine_yaw) * 212.0
	wind_pointer.visible = not storm_phase and not rotor_broken
	turbine_pointer.visible = wind_pointer.visible
	var safe_stop := storm_phase and brake_active
	direction_gauge_style.border_color = Color("70f1b2") if safe_stop or alignment >= 0.8 else Color("82c6d4")
	if storm_phase:
		direction_gauge_style.border_color = Color("70f1b2") if safe_stop else Color("ff8071")
		direction_caption.text = "브레이크 → 안전 정지" if safe_stop else MINIGAME_INPUT.hint("wind_rhythm", "SPACE → 회전을 멈춰요")
	elif rotor_broken:
		direction_caption.text = "날개 수리 중 · 발전 멈춤"
	elif brake_active:
		direction_caption.text = MINIGAME_INPUT.hint("wind_rhythm", "SPACE 놓기 → 다시 발전")
	elif not yaw_choice_made:
		direction_caption.text = "바람과 터빈 방향 비교"
	else:
		direction_caption.text = "바람과 터빈 방향 비교"

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
	_clear_score_popup()
	var popup := Label.new()
	popup.set_anchors_preset(Control.PRESET_CENTER_TOP)
	popup.offset_left = -280.0
	popup.offset_top = 184.0
	popup.offset_right = 280.0
	popup.offset_bottom = 232.0
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.text = "%s%d점  %s" % ["+" if success else "−", points, message]
	popup.add_theme_font_size_override("font_size", 25)
	popup.add_theme_color_override("font_color", Color("c2ffdd") if success else Color("ffe0d7"))
	popup.add_theme_color_override("font_outline_color", Color("041019"))
	popup.add_theme_constant_override("outline_size", 9)
	add_child(popup)
	score_popup = popup
	score_popup_success = success
	var tween := create_tween().bind_node(popup).set_parallel(true)
	score_popup_tween = tween
	tween.tween_property(popup, "position:y", popup.position.y - 10.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.65).set_delay(0.7)
	tween.chain().tween_callback(popup.queue_free)

func _clear_score_popup() -> void:
	if is_instance_valid(score_popup_tween):
		score_popup_tween.kill()
	if is_instance_valid(score_popup):
		score_popup.visible = false
		score_popup.queue_free()
	score_popup = null
	score_popup_tween = null
	score_popup_success = false

func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	return VISUAL_STYLE.material(color, glowing)

func _draw_action_cue(_layer: Control, kind: StringName, _from: Vector2, _to: Vector2, t: float, alpha: float, _amount: float) -> void:
	var tint := Color(1.0, 1.0, 1.0, alpha)
	var hub := action_fx.project(rotor.global_position)
	var wing_span := hub.distance_to(action_fx.project(rotor.global_position + camera.global_basis.x * 1.6))
	if kind == &"generate":
		var foot := action_fx.project(Vector3(0, 0.24, 0.0))
		for i in range(3):
			var u := clampf(t * 1.65 - 0.15 * i, 0, 1)
			if u > 0 and u < 1:
				var mid := hub.lerp(foot, u)
				var half_width := 10.5
				action_fx.stroke([mid + Vector2(-half_width, -4), mid + Vector2(0, 4), mid + Vector2(half_width, -4)], Color("b3ffcd") * tint, 3.8)
		for i in range(3):
			var start := TAU * i / 3.0 + t * 0.85
			action_fx.arc(hub, wing_span * (0.53 + 0.16 * t), start, start + 0.85, Color("a1f7dd") * tint, 3.4)
		return
	if kind == &"gust":
		# Three waves approach from the reported side; each front points
		# into the hub and sweeps past it once rather than flashing the view.
		var side := 1.0 if wind_angle >= 0 else -1.0
		for i in range(3):
			var y := (i - 1.0) * 17.0
			var front := hub + Vector2(side * lerpf(wing_span * 1.7, wing_span * 0.34, t), y)
			action_fx.stroke([front + Vector2(side * 26, -6), front, front + Vector2(side * 20, 6)], Color("ffaa6e") * tint, 3.2)
		return
	# Caliper jaws close from opposite sides and hold; two square brake bars
	# identify a stop independently of colour or the wind direction.
	var settle := smoothstep(0.0, 0.45, t)
	var radius := lerpf(wing_span * 0.83, wing_span * 0.32, settle)
	for side in [-1.0, 1.0]:
		var angle := 0.0 if side > 0 else PI
		action_fx.arc(hub, radius, angle - 0.64, angle + 0.64, Color("92f3c9") * tint, 5.6)
		if t > 0.25:
			var mid := hub + Vector2(side * 4.5, 0)
			action_fx.stroke([mid + Vector2.UP * 8, mid + Vector2.DOWN * 8], Color("fff5c1") * tint, 3.8)
