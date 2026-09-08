extends SubViewportContainer
class_name SolarPanelDash3D

## 저사양 노트북을 위한 경량 3D 자동 달리기 미니게임입니다.
## 햇빛을 향한 패널 차선을 고르고 구름 그림자를 뛰어넘으며 발전 원리를 익힙니다.

signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const SOLAR_PANEL_MODEL: PackedScene = preload("res://assets/third_party/kenney/solar_dash/solar-panel-landscape.glb")
const SOLAR_FARM_MODEL: PackedScene = preload("res://assets/third_party/kenney/solar_dash/solar-panel-landscape-group.glb")
const SOLAR_BUILDING_MODEL: PackedScene = preload("res://assets/third_party/kenney/solar_dash/building-a.glb")
const TREE_MODEL: PackedScene = preload("res://assets/third_party/kenney/solar_dash/tree_pineSmallA.glb")
const BUSH_MODEL: PackedScene = preload("res://assets/third_party/kenney/solar_dash/plant_bushLarge.glb")
const TERRAIN_MODEL_SPECS: Array[Dictionary] = [
	{"scene": preload("res://assets/third_party/kenney/solar_dash/rock_largeA.glb"), "name": "큰 바위", "scale": 1.55, "size": Vector3(1.45, 1.00, 1.15), "clearance": 0.68, "penalty": 24},
	{"scene": preload("res://assets/third_party/kenney/solar_dash/rock_largeC.glb"), "name": "뾰족 바위", "scale": 1.50, "size": Vector3(1.35, 1.12, 1.10), "clearance": 0.78, "penalty": 26},
	{"scene": preload("res://assets/third_party/kenney/solar_dash/log_large.glb"), "name": "쓰러진 통나무", "scale": 1.50, "size": Vector3(2.05, 0.70, 0.92), "clearance": 0.52, "penalty": 20},
	{"scene": preload("res://assets/third_party/kenney/solar_dash/stump_old.glb"), "name": "나무 그루터기", "scale": 1.45, "size": Vector3(1.15, 0.92, 1.08), "clearance": 0.64, "penalty": 22},
	{"scene": SOLAR_FARM_MODEL, "name": "태양광 발전 설비", "scale": 1.30, "size": Vector3(2.30, 1.20, 1.35), "clearance": 0.88, "penalty": 32},
]
const LANES: Array[float] = [-2.7, 0.0, 2.7]
const RUN_SPEED := 7.4
const STEER_SPEED := 6.8
const GROUND_Y := 0.02
const PLAYER_Z := 2.1
const GRAVITY := 15.5
const JUMP_FORCE := 6.4
const KNOCKBACK_SPEED := 8.8
const KNOCKBACK_SIDE_SPEED := 3.4
const KNOCKBACK_LIFT := 3.4
const FORWARD_SPRING := 18.0
const FORWARD_DAMPING := 4.2
const SUN_MOVE_INTERVAL := 5.0
const SUN_POSITIONS: Array[Vector3] = [
	Vector3(-6.2, 7.0, -18.0),
	Vector3(0.0, 8.0, -18.0),
	Vector3(6.2, 7.0, -18.0),
	Vector3(0.0, 8.0, -18.0),
]

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var hero: Node3D
var hero_body: CharacterBody3D
var sun: MeshInstance3D
var rng := RandomNumberGenerator.new()
var running := false
var jump_velocity := 0.0
var jump_height := 0.0
var spawn_elapsed := 0.0
var distance := 0.0
var sun_move_elapsed := 0.0
var sun_position_index := 0
var sun_move_tween: Tween
var panel_gates: Array[Dictionary] = []
var terrain_obstacles: Array[Dictionary] = []
var road_stripes: Array[MeshInstance3D] = []
var hit_cooldown := 0.0
var correct_material: StandardMaterial3D
var wrong_material: StandardMaterial3D
var panel_material: StandardMaterial3D
var energy_material: StandardMaterial3D
var overlay_label: Label
var score_rule_label: Label
var sun_timer_label: Label

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
	for gate_index in range(4):
		_spawn_panel_gate(-8.0 - float(gate_index) * 8.0)
	for obstacle_index in range(3):
		_spawn_terrain_obstacle(-13.0 - float(obstacle_index) * 12.0)
	running = true

func set_running(value: bool) -> void:
	running = value
	if is_instance_valid(hero) and hero.has_method("_set_avatar_animation_state"):
		hero.call("_set_avatar_animation_state", value)

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.name = "SolarDashViewport"
	viewport.size = Vector2i(960, 286)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	world.name = "SolarDashWorld"
	viewport.add_child(world)

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("69b9d0")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dff7ff")
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -35, 0)
	light.light_color = Color("fff1b2")
	light.light_energy = 1.15
	light.shadow_enabled = false
	world.add_child(light)

	camera = Camera3D.new()
	camera.position = Vector3(0, 5.2, 8.6)
	camera.fov = 53.0
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.8, -7.8), Vector3.UP)

	_build_ground()
	_build_sun()
	_build_horizon()
	_create_materials()

func _build_ground() -> void:
	var road := MeshInstance3D.new()
	var road_box := BoxMesh.new()
	road_box.size = Vector3(9.7, 0.20, 46.0)
	road.mesh = road_box
	road.position = Vector3(0, -0.12, -13.5)
	road.material_override = _material(Color("315b57"), false)
	world.add_child(road)
	var road_body := StaticBody3D.new()
	road_body.position = road.position
	var road_collision := CollisionShape3D.new()
	var road_shape := BoxShape3D.new()
	road_shape.size = road_box.size
	road_collision.shape = road_shape
	road_body.add_child(road_collision)
	world.add_child(road_body)

	for side in [-1, 1]:
		var field := MeshInstance3D.new()
		var field_box := BoxMesh.new()
		field_box.size = Vector3(16.0, 0.12, 46.0)
		field.mesh = field_box
		field.position = Vector3(float(side) * 12.8, -0.17, -13.5)
		field.material_override = _material(Color("6f9d55"), false)
		world.add_child(field)

	for lane_separator in [-1.35, 1.35]:
		for stripe_index in range(10):
			var stripe := MeshInstance3D.new()
			var stripe_box := BoxMesh.new()
			stripe_box.size = Vector3(0.07, 0.025, 1.8)
			stripe.mesh = stripe_box
			stripe.position = Vector3(lane_separator, 0.015, 5.0 - float(stripe_index) * 4.5)
			stripe.material_override = _material(Color("b8e3ba"), true)
			world.add_child(stripe)
			road_stripes.append(stripe)

func _build_sun() -> void:
	sun = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.78
	sphere.height = 1.56
	sun.mesh = sphere
	sun.position = SUN_POSITIONS[0]
	var sun_material := _material(Color("ffd957"), true)
	sun_material.emission_energy_multiplier = 2.4
	sun.material_override = sun_material
	world.add_child(sun)

func _build_horizon() -> void:
	for x in [-7.2, 7.2]:
		for z_index in range(5):
			_spawn_static_asset(TREE_MODEL, Vector3(x + rng.randf_range(-1.0, 1.0), 0.0, -3.0 - z_index * 7.0), Vector3.ONE * rng.randf_range(1.45, 1.85), float(z_index * 31))
			if z_index % 2 == 0:
				_spawn_static_asset(BUSH_MODEL, Vector3(x * 0.82, 0.0, -5.0 - z_index * 7.0), Vector3.ONE * 1.2, float(z_index * 47))
	for side in [-1, 1]:
		_spawn_static_asset(SOLAR_FARM_MODEL, Vector3(float(side) * 6.0, 0.0, -8.0), Vector3.ONE * 2.0, 180.0)
	_spawn_static_asset(SOLAR_BUILDING_MODEL, Vector3(-6.4, 0.0, -20.0), Vector3.ONE, 18.0)

func _spawn_static_asset(scene: PackedScene, position_value: Vector3, scale_value: Vector3, yaw_degrees: float) -> Node3D:
	var instance := scene.instantiate() as Node3D
	instance.position = position_value
	instance.scale = scale_value
	instance.rotation_degrees.y = yaw_degrees
	world.add_child(instance)
	return instance

func _create_materials() -> void:
	panel_material = _material(Color("23589a"), true)
	panel_material.emission = Color("123f78")
	panel_material.emission_energy_multiplier = 0.45
	correct_material = _material(Color("48e58d"), true)
	correct_material.emission_energy_multiplier = 1.4
	wrong_material = _material(Color("e65f58"), true)
	wrong_material.emission_energy_multiplier = 1.1
	energy_material = _material(Color("ffe66b"), true)
	energy_material.emission_energy_multiplier = 1.8

func _build_overlay() -> void:
	overlay_label = Label.new()
	overlay_label.position = Vector2(14, 12)
	overlay_label.text = "A / D  차선 이동       SPACE  점프       발전 설비와 지형물 충돌을 피하세요!"
	overlay_label.add_theme_font_size_override("font_size", 16)
	overlay_label.add_theme_color_override("font_color", Color("fff7c2"))
	overlay_label.add_theme_color_override("font_outline_color", Color("12313b"))
	overlay_label.add_theme_constant_override("outline_size", 5)
	add_child(overlay_label)

	score_rule_label = Label.new()
	score_rule_label.position = Vector2(14, 40)
	score_rule_label.text = "☀ 햇빛을 보는 패널  +100점     🪨 지형물 회피  +30점     충돌 시 뒤로 밀림"
	score_rule_label.add_theme_font_size_override("font_size", 15)
	score_rule_label.add_theme_color_override("font_color", Color("ffe66b"))
	score_rule_label.add_theme_color_override("font_outline_color", Color("12313b"))
	score_rule_label.add_theme_constant_override("outline_size", 5)
	add_child(score_rule_label)

	sun_timer_label = Label.new()
	sun_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sun_timer_label.offset_left = -240.0
	sun_timer_label.offset_top = 12.0
	sun_timer_label.offset_right = -14.0
	sun_timer_label.offset_bottom = 45.0
	sun_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sun_timer_label.text = "태양 이동까지 5초"
	sun_timer_label.add_theme_font_size_override("font_size", 16)
	sun_timer_label.add_theme_color_override("font_color", Color("ffe66b"))
	sun_timer_label.add_theme_color_override("font_outline_color", Color("12313b"))
	sun_timer_label.add_theme_constant_override("outline_size", 5)
	add_child(sun_timer_label)

func _spawn_hero(player_data: Dictionary) -> void:
	if is_instance_valid(hero_body):
		hero_body.queue_free()
	hero_body = CharacterBody3D.new()
	hero_body.name = "SolarRunnerBody"
	hero_body.position = Vector3(0, GROUND_Y + 0.04, PLAYER_Z)
	hero_body.floor_snap_length = 0.18
	hero_body.floor_max_angle = deg_to_rad(50.0)
	var collision_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.05
	collision_shape.shape = capsule
	collision_shape.position.y = 0.54
	hero_body.add_child(collision_shape)
	world.add_child(hero_body)
	hero = PLAYER_PAWN.new()
	hero_body.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_player", hero_data)
	hero.call("set_back_run_enabled", true)
	hero.position = Vector3.ZERO
	hero.scale = Vector3.ONE * 2.15
	hero.call("_set_avatar_animation_state", true)

func _spawn_panel_gate(start_z: float = -30.0) -> void:
	var gate := Node3D.new()
	gate.position.z = start_z
	world.add_child(gate)
	var correct_lane := _correct_lane_for_current_sun()
	var panels: Array[Node3D] = []
	for lane_index in range(3):
		var station := Node3D.new()
		station.position.x = LANES[lane_index]
		gate.add_child(station)
		var panel := SOLAR_PANEL_MODEL.instantiate() as Node3D
		panel.name = "KenneySolarPanel%d" % lane_index
		panel.scale = Vector3.ONE * 1.65
		panel.rotation_degrees.y = 180.0
		# Kenney 모델의 지면 기준점보다 높여 지지 기둥과 받침이 모두 보이게 합니다.
		panel.position.y = 0.68
		station.add_child(panel)
		panels.append(panel)
	panel_gates.append({
		"node": gate,
		"correct_lane": correct_lane,
		"resolved": false,
		"meshes": panels,
	})
	_update_panel_gate_for_sun(panel_gates[panel_gates.size() - 1])

func _spawn_terrain_obstacle(start_z: float = -32.0, forced_spec_index: int = -1) -> void:
	var spec_index := forced_spec_index if forced_spec_index >= 0 else rng.randi_range(0, TERRAIN_MODEL_SPECS.size() - 1)
	var spec: Dictionary = TERRAIN_MODEL_SPECS[clampi(spec_index, 0, TERRAIN_MODEL_SPECS.size() - 1)]
	var obstacle := AnimatableBody3D.new()
	obstacle.name = "KenneyHazard_%s" % str(spec["name"])
	obstacle.position = Vector3(LANES[rng.randi_range(0, 2)], 0.0, start_z)
	obstacle.sync_to_physics = true
	obstacle.set_meta("solar_dash_hazard", true)
	world.add_child(obstacle)
	var visual := (spec["scene"] as PackedScene).instantiate() as Node3D
	visual.scale = Vector3.ONE * float(spec["scale"])
	visual.rotation_degrees.y = rng.randf_range(-18.0, 18.0)
	obstacle.add_child(visual)
	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	var collision_size: Vector3 = spec["size"]
	box_shape.size = collision_size
	collision_shape.shape = box_shape
	collision_shape.position.y = collision_size.y * 0.5
	obstacle.add_child(collision_shape)
	var record := {
		"node": obstacle,
		"resolved": false,
		"name": str(spec["name"]),
		"clearance": float(spec["clearance"]),
		"penalty": int(spec["penalty"]),
	}
	terrain_obstacles.append(record)

func _physics_process(delta: float) -> void:
	if not running or not is_instance_valid(hero_body):
		return
	hit_cooldown = maxf(0.0, hit_cooldown - delta)
	_update_hero_physics(delta)
	_update_course(delta)
	_update_spawning(delta)
	distance += RUN_SPEED * delta
	if is_instance_valid(sun):
		sun.rotation.y += delta * 0.18
	_update_sun(delta)

func _update_hero_physics(delta: float) -> void:
	var direction := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction += 1.0
	var velocity := hero_body.velocity
	velocity.x = move_toward(velocity.x, direction * STEER_SPEED, STEER_SPEED * 12.0 * delta)
	if not hero_body.is_on_floor():
		velocity.y -= GRAVITY * delta
	if (Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) and hero_body.is_on_floor():
		velocity.y = JUMP_FORCE
	# 충돌로 뒤로 밀린 뒤 감쇠되는 속도와 원래 달리기 위치로 향하는 복원력을 적용합니다.
	velocity.z += (PLAYER_Z - hero_body.position.z) * FORWARD_SPRING * delta
	velocity.z *= exp(-FORWARD_DAMPING * delta)
	hero_body.velocity = velocity
	hero_body.move_and_slide()
	hero_body.position.x = clampf(hero_body.position.x, LANES[0], LANES[2])
	jump_velocity = hero_body.velocity.y
	jump_height = maxf(0.0, hero_body.position.y - GROUND_Y)
	_handle_physical_collisions()
	# 좌우 이동과 점프가 스프라이트만 움직이는 느낌이 들지 않도록 살짝 기울입니다.
	hero.rotation.z = lerpf(hero.rotation.z, -direction * 0.12, clampf(delta * 8.0, 0.0, 1.0))

func _handle_physical_collisions() -> void:
	if hit_cooldown > 0.0:
		return
	for collision_index in range(hero_body.get_slide_collision_count()):
		var collision := hero_body.get_slide_collision(collision_index)
		var collider := collision.get_collider() as Node3D
		if is_instance_valid(collider) and bool(collider.get_meta("solar_dash_hazard", false)):
			_resolve_hazard_collision(collider)
			return

func _resolve_hazard_collision(obstacle: Node3D) -> void:
	for obstacle_index in range(terrain_obstacles.size()):
		var record: Dictionary = terrain_obstacles[obstacle_index]
		if record.get("node") != obstacle or bool(record.get("resolved", false)):
			continue
		record["resolved"] = true
		hit_cooldown = 0.5
		var side_direction := signf(hero_body.position.x - obstacle.position.x)
		if is_zero_approx(side_direction):
			side_direction = -1.0 if rng.randf() < 0.5 else 1.0
		hero_body.velocity.z = KNOCKBACK_SPEED
		hero_body.velocity.x = side_direction * KNOCKBACK_SIDE_SPEED
		hero_body.velocity.y = maxf(hero_body.velocity.y, KNOCKBACK_LIFT)
		var penalty := int(record.get("penalty", 22))
		var obstacle_name := str(record.get("name", "장애물"))
		_show_collision_flash()
		_show_score_popup(penalty, false, "%s 충돌 · 뒤로 밀림" % obstacle_name)
		arcade_event.emit(penalty, false, "%s에 부딪혀 충격량만큼 뒤로 밀려났어요." % obstacle_name, false)
		return

func _update_course(delta: float) -> void:
	for stripe in road_stripes:
		stripe.position.z += RUN_SPEED * delta
		if stripe.position.z > 7.0:
			stripe.position.z -= 45.0

	for gate_index in range(panel_gates.size() - 1, -1, -1):
		var record: Dictionary = panel_gates[gate_index]
		var gate := record.get("node") as Node3D
		if not is_instance_valid(gate):
			panel_gates.remove_at(gate_index)
			continue
		gate.position.z += RUN_SPEED * delta
		if not bool(record.get("resolved", false)) and gate.position.z >= PLAYER_Z - 0.2:
			record["resolved"] = true
			_resolve_panel_gate(record)
		if gate.position.z > 8.5:
			gate.queue_free()
			panel_gates.remove_at(gate_index)
		elif not bool(record.get("resolved", false)):
			_update_panel_gate_for_sun(record)

	for obstacle_index in range(terrain_obstacles.size() - 1, -1, -1):
		var record: Dictionary = terrain_obstacles[obstacle_index]
		var obstacle := record.get("node") as AnimatableBody3D
		if not is_instance_valid(obstacle):
			terrain_obstacles.remove_at(obstacle_index)
			continue
		obstacle.position.z += RUN_SPEED * delta
		if not bool(record.get("resolved", false)) and obstacle.position.z >= hero_body.position.z - 0.20:
			record["resolved"] = true
			var same_lane := absf(hero_body.position.x - obstacle.position.x) < 0.92
			if same_lane and jump_height >= float(record.get("clearance", 0.6)):
				_show_score_popup(30, true, "%s 회피 성공!" % str(record.get("name", "지형물")))
				arcade_event.emit(30, true, "지형물을 뛰어넘어 태양광 발전 경로를 지켰어요!", false)
			elif same_lane:
				record["resolved"] = false
				_resolve_hazard_collision(obstacle)
		if obstacle.position.z > 8.5:
			obstacle.queue_free()
			terrain_obstacles.remove_at(obstacle_index)

func _update_spawning(delta: float) -> void:
	spawn_elapsed += delta
	if spawn_elapsed < 2.15:
		return
	spawn_elapsed = 0.0
	_spawn_panel_gate()
	if rng.randf() < 0.74:
		_spawn_terrain_obstacle(-35.0)

func _resolve_panel_gate(record: Dictionary) -> void:
	# 태양 이동 트윈과 게이트 통과가 같은 프레임에 겹쳐도 현재 위치 기준으로 판정합니다.
	_update_panel_gate_for_sun(record)
	var selected_lane := _nearest_lane(hero_body.position.x)
	var correct_lane := int(record.get("correct_lane", 1))
	var panels: Array = record.get("meshes", [])
	if selected_lane >= 0 and selected_lane < panels.size():
		_tint_model(panels[selected_lane] as Node3D, correct_material if selected_lane == correct_lane else wrong_material)
	if selected_lane == correct_lane:
		_spawn_energy_burst(hero_body.position + Vector3(0, 1.1, -0.2))
		_show_score_popup(100, true, "태양광 발전 성공!")
		arcade_event.emit(100, true, "햇빛을 향한 패널을 통과해 발전 성공!", true)
	else:
		_show_score_popup(25, false, "햇빛이 부족해요")
		arcade_event.emit(25, false, "반대쪽 패널은 햇빛을 적게 받아요.", false)
func _update_sun(delta: float) -> void:
	sun_move_elapsed += delta
	var seconds_left := ceili(maxf(0.0, SUN_MOVE_INTERVAL - sun_move_elapsed))
	if is_instance_valid(sun_timer_label):
		sun_timer_label.text = "태양 이동까지 %d초" % seconds_left
	if sun_move_elapsed < SUN_MOVE_INTERVAL:
		return
	sun_move_elapsed = 0.0
	sun_position_index = (sun_position_index + 1) % SUN_POSITIONS.size()
	if sun_move_tween and sun_move_tween.is_valid():
		sun_move_tween.kill()
	sun_move_tween = create_tween()
	sun_move_tween.tween_property(sun, "position", SUN_POSITIONS[sun_position_index], 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _update_panel_gate_for_sun(record: Dictionary) -> void:
	var gate := record.get("node") as Node3D
	var panels: Array = record.get("meshes", [])
	if not is_instance_valid(gate):
		return
	var correct_lane := _correct_lane_for_current_sun()
	record["correct_lane"] = correct_lane
	for lane_index in range(panels.size()):
		var panel := panels[lane_index] as Node3D
		if not is_instance_valid(panel):
			continue
		# 수평 거리와 높이 차로 실제 태양 고도각을 계산합니다. Kenney 모델을
		# Y축으로 180도 돌린 현재 배치에서는 Z축 +회전이 오른쪽을 향합니다.
		var horizontal_to_sun := sun.global_position.x - panel.global_position.x
		var vertical_to_sun := maxf(1.0, sun.global_position.y - panel.global_position.y)
		var facing_angle := clampf(rad_to_deg(atan2(horizontal_to_sun, vertical_to_sun)), -42.0, 42.0)
		if lane_index == correct_lane:
			panel.rotation_degrees.z = facing_angle
		else:
			# 오답 패널은 각 패널이 태양을 향할 때 필요한 각도의 반대편으로 둡니다.
			panel.rotation_degrees.z = -36.0 if facing_angle >= 0.0 else 36.0

func _correct_lane_for_current_sun() -> int:
	if not is_instance_valid(sun):
		return 1
	var nearest_lane := 0
	var nearest_distance := INF
	for lane_index in range(LANES.size()):
		var lane_distance := absf(sun.global_position.x - LANES[lane_index])
		if lane_distance < nearest_distance:
			nearest_distance = lane_distance
			nearest_lane = lane_index
	return nearest_lane

func _tint_model(model_root: Node3D, material: StandardMaterial3D) -> void:
	if model_root is MeshInstance3D:
		(model_root as MeshInstance3D).material_override = material
	for child in model_root.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = material

func _show_collision_flash() -> void:
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.18, 0.08, 0.30)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(flash.queue_free)

func _show_score_popup(points: int, success: bool, message: String) -> void:
	var popup := Label.new()
	popup.set_anchors_preset(Control.PRESET_CENTER_TOP)
	popup.offset_left = -260.0
	popup.offset_top = 70.0
	popup.offset_right = 260.0
	popup.offset_bottom = 116.0
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.text = "%s%d점  %s" % ["+" if success else "−", points, message]
	popup.add_theme_font_size_override("font_size", 27)
	popup.add_theme_color_override("font_color", Color("6effaa") if success else Color("ff766d"))
	popup.add_theme_color_override("font_outline_color", Color("08202a"))
	popup.add_theme_constant_override("outline_size", 7)
	add_child(popup)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 34.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tween.chain().tween_callback(popup.queue_free)

func _nearest_lane(x_position: float) -> int:
	var nearest := 0
	var nearest_distance := INF
	for lane_index in range(LANES.size()):
		var lane_distance := absf(x_position - LANES[lane_index])
		if lane_distance < nearest_distance:
			nearest_distance = lane_distance
			nearest = lane_index
	return nearest

func _spawn_energy_burst(burst_position: Vector3) -> void:
	var burst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	burst.mesh = sphere
	burst.position = burst_position
	burst.material_override = energy_material
	world.add_child(burst)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(burst, "scale", Vector3.ONE * 3.2, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(burst, "position:y", burst.position.y + 1.1, 0.38)
	tween.tween_property(burst, "transparency", 1.0, 0.38)
	tween.chain().tween_callback(burst.queue_free)

func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.76
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.7
	return material
