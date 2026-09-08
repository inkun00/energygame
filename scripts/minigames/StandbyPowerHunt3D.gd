extends SubViewportContainer
class_name StandbyPowerHunt3D

## CC0 실내 모델로 구성한 횡스크롤 3D 대기전력 탐색 아케이드입니다.

signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const ASSET_ROOT := "res://assets/third_party/kenney/standby_house/"
const WALL = preload(ASSET_ROOT + "wall.glb")
const WALL_WINDOW = preload(ASSET_ROOT + "wallWindow.glb")
const WALL_DOOR = preload(ASSET_ROOT + "wallDoorwayWide.glb")
const FLOOR = preload(ASSET_ROOT + "floorFull.glb")
const DOOR = preload(ASSET_ROOT + "doorwayOpen.glb")
const SOFA = preload(ASSET_ROOT + "loungeSofa.glb")
const COFFEE_TABLE = preload(ASSET_ROOT + "tableCoffee.glb")
const TV_CABINET = preload(ASSET_ROOT + "cabinetTelevision.glb")
const FLOOR_LAMP = preload(ASSET_ROOT + "lampRoundFloor.glb")
const PLANT = preload(ASSET_ROOT + "pottedPlant.glb")
const BOOKCASE = preload(ASSET_ROOT + "bookcaseOpen.glb")
const KITCHEN_CABINET = preload(ASSET_ROOT + "kitchenCabinet.glb")
const BED = preload(ASSET_ROOT + "bedSingle.glb")
const SIDE_TABLE = preload(ASSET_ROOT + "sideTable.glb")
const TABLE_LAMP = preload(ASSET_ROOT + "lampRoundTable.glb")
const CEILING_FAN = preload(ASSET_ROOT + "ceilingFan.glb")

const DEVICE_SPECS: Array[Dictionary] = [
	{"x": 5.0, "room": "거실", "name": "TV", "scene": preload(ASSET_ROOT + "televisionModern.glb"), "standby": 3, "active": 55, "can_standby": true, "scale": 1.65, "tint": Color("334b61")},
	{"x": 9.0, "room": "거실", "name": "오디오", "scene": preload(ASSET_ROOT + "radio.glb"), "standby": 4, "active": 18, "can_standby": true, "scale": 1.55, "tint": Color("6c86a0")},
	{"x": 15.0, "room": "주방", "name": "냉장고", "scene": preload(ASSET_ROOT + "kitchenFridge.glb"), "standby": 0, "active": 45, "can_standby": false, "scale": 1.45, "tint": Color("a9d8dc")},
	{"x": 18.5, "room": "주방", "name": "전자레인지", "scene": preload(ASSET_ROOT + "kitchenMicrowave.glb"), "standby": 3, "active": 90, "can_standby": true, "scale": 1.65, "tint": Color("6e7d91")},
	{"x": 22.0, "room": "주방", "name": "커피머신", "scene": preload(ASSET_ROOT + "kitchenCoffeeMachine.glb"), "standby": 2, "active": 800, "can_standby": true, "scale": 1.75, "tint": Color("b06e45")},
	{"x": 28.0, "room": "침실", "name": "노트북", "scene": preload(ASSET_ROOT + "laptop.glb"), "standby": 2, "active": 35, "can_standby": true, "scale": 1.85, "tint": Color("547891")},
	{"x": 32.0, "room": "침실", "name": "모니터", "scene": preload(ASSET_ROOT + "computerScreen.glb"), "standby": 2, "active": 22, "can_standby": true, "scale": 1.55, "tint": Color("43596c")},
	{"x": 39.0, "room": "세탁실", "name": "세탁기", "scene": preload(ASSET_ROOT + "washer.glb"), "standby": 0, "active": 500, "can_standby": false, "scale": 1.35, "tint": Color("8bc3cc")},
	{"x": 43.0, "room": "세탁실", "name": "건조기", "scene": preload(ASSET_ROOT + "dryer.glb"), "standby": 0, "active": 900, "can_standby": false, "scale": 1.35, "tint": Color("9ba9b8")},
]

const COURSE_END := 47.0
const RUN_SPEED := 6.4
const RUN_ACCELERATION := 18.0
const INTERACTION_DISTANCE := 1.65
const PASS_DISTANCE := 1.95

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var course_root: Node3D
var hero: Node3D
var rng := RandomNumberGenerator.new()
var running := false
var run_velocity := 0.0
var lap_index := 1
var visual_time := 0.0
var space_was_down := false
var device_records: Array[Dictionary] = []

var neutral_material: StandardMaterial3D
var active_material: StandardMaterial3D
var safe_material: StandardMaterial3D
var danger_material: StandardMaterial3D
var floor_glow_material: StandardMaterial3D

var room_label: Label
var progress_label: Label
var action_label: Label
var flash: ColorRect

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 286)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	rng.seed = 7321
	_build_viewport()
	_build_world()
	_build_overlay()
	set_process(true)

func setup(player_data: Dictionary, game_seed: int) -> void:
	rng.seed = game_seed
	_spawn_hero(player_data)
	_build_house_course()
	running = true

func set_running(value: bool) -> void:
	running = value
	if is_instance_valid(hero) and hero.has_method("_set_avatar_animation_state"):
		hero.call("_set_avatar_animation_state", value and absf(run_velocity) > 0.1)

func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.name = "StandbySideScrollViewport"
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
	environment.background_color = Color("94c7d3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff3da")
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -18, 0)
	light.light_color = Color("fff0d1")
	light.light_energy = 1.35
	light.shadow_enabled = false
	world.add_child(light)
	neutral_material = _material(Color("f5e5c7"), false)
	active_material = _material(Color("5ee6c0"), true)
	safe_material = _material(Color("71ed9f"), true)
	danger_material = _material(Color("ff6358"), true)
	floor_glow_material = _material(Color("ffc85a"), true)
	floor_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_glow_material.albedo_color.a = 0.38
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.2
	camera.position = Vector3(4.3, 3.45, 12.0)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(4.3, 2.25, 0.0), Vector3.UP)

func _spawn_hero(player_data: Dictionary) -> void:
	hero = PLAYER_PAWN.new()
	world.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_player", hero_data)
	hero.call("set_side_run_enabled", true)
	hero.position = Vector3(1.0, 0.04, 1.0)
	hero.scale = Vector3.ONE * 2.8
	hero.call("_set_avatar_animation_state", false)

func _build_house_course() -> void:
	if is_instance_valid(course_root):
		course_root.queue_free()
	device_records.clear()
	course_root = Node3D.new()
	course_root.name = "KenneyHouseLap%d" % lap_index
	world.add_child(course_root)
	_build_house_shell()
	_build_room_decor()
	for device_index in range(DEVICE_SPECS.size()):
		_build_device(device_index, DEVICE_SPECS[device_index])

func _build_house_shell() -> void:
	for tile_x in range(48):
		_place_model(FLOOR, Vector3(float(tile_x) + 0.5, -0.02, 0.0), 1.02, 0.0, "Floor")
	for wall_x in range(0, 48, 2):
		var wall_scene: PackedScene = WALL_WINDOW if wall_x % 12 == 4 else WALL
		_place_model(wall_scene, Vector3(float(wall_x) + 1.0, 0.0, -1.35), 1.0, 0.0, "Wall")
	for boundary in [0.0, 12.0, 24.0, 36.0, 48.0]:
		_place_model(WALL_DOOR, Vector3(boundary, 0.0, -0.65), 1.0, 90.0, "RoomDivider")
	for room_index in range(4):
		var room_center := 6.0 + float(room_index) * 12.0
		var label := Label3D.new()
		label.position = Vector3(room_center, 4.75, -0.8)
		label.text = ["거실", "주방", "침실", "세탁실"][room_index]
		label.font_size = 48
		label.pixel_size = 0.007
		label.outline_size = 8
		label.modulate = Color("fff1bf")
		course_root.add_child(label)

func _build_room_decor() -> void:
	_place_model(SOFA, Vector3(2.4, 0, -0.45), 1.3, 180, "Sofa")
	_place_model(COFFEE_TABLE, Vector3(6.8, 0, -0.2), 1.15, 0, "CoffeeTable")
	_place_model(TV_CABINET, Vector3(4.9, 0, -0.7), 1.2, 0, "TvCabinet")
	_place_model(FLOOR_LAMP, Vector3(10.6, 0, -0.65), 1.35, 0, "LivingLamp")
	_place_model(PLANT, Vector3(0.8, 0, -0.65), 1.35, 0, "LivingPlant")
	for x_pos in [13.0, 16.7, 20.5, 23.0]:
		_place_model(KITCHEN_CABINET, Vector3(x_pos, 0, -0.65), 1.2, 0, "KitchenCabinet")
	_place_model(BED, Vector3(25.8, 0, -0.55), 1.25, 90, "Bed")
	_place_model(SIDE_TABLE, Vector3(30.0, 0, -0.55), 1.25, 0, "SideTable")
	_place_model(TABLE_LAMP, Vector3(30.0, 1.0, -0.55), 1.1, 0, "BedLamp")
	_place_model(BOOKCASE, Vector3(34.4, 0, -0.65), 1.3, 0, "Bookcase")
	_place_model(CEILING_FAN, Vector3(33.0, 5.1, -0.2), 1.35, 0, "CeilingFan")
	_place_model(DOOR, Vector3(46.2, 0, -0.6), 1.25, 0, "ExitDoor")

func _build_device(device_index: int, spec: Dictionary) -> void:
	var station := Node3D.new()
	station.position = Vector3(float(spec["x"]), 0.0, 0.22)
	station.name = "Device_%s" % str(spec["name"])
	course_root.add_child(station)
	var model := (spec["scene"] as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * float(spec["scale"])
	model.rotation_degrees.y = 180.0
	station.add_child(model)
	_apply_model_tint(model, spec["tint"] as Color)
	var can_standby := bool(spec["can_standby"])
	var is_waste := can_standby and (device_index == 0 or rng.randf() < 0.58)
	var watts := int(spec["standby"] if is_waste else spec["active"])
	var plug := MeshInstance3D.new()
	plug.name = "Plug"
	var plug_mesh := BoxMesh.new()
	plug_mesh.size = Vector3(0.25, 0.32, 0.12)
	plug.mesh = plug_mesh
	plug.position = Vector3(0.72, 0.34, 0.45)
	plug.material_override = neutral_material
	station.add_child(plug)
	var status := Label3D.new()
	status.name = "StatusLabel"
	status.position = Vector3(0, 2.45, 0.15)
	status.text = "%s\n%s · %d W" % [str(spec["name"]), "화면 꺼짐" if is_waste else "사용 중", watts]
	status.font_size = 46
	status.pixel_size = 0.006
	status.outline_size = 10
	status.modulate = Color("fff1d4")
	status.no_depth_test = true
	station.add_child(status)
	if not is_waste:
		var activity := MeshInstance3D.new()
		activity.name = "ActivityGlow"
		var sphere := SphereMesh.new()
		sphere.radius = 0.13
		sphere.height = 0.26
		sphere.radial_segments = 10
		activity.mesh = sphere
		activity.position = Vector3(-0.72, 0.45, 0.5)
		activity.material_override = active_material
		station.add_child(activity)
	device_records.append({"node": station, "x": float(spec["x"]), "name": str(spec["name"]), "room": str(spec["room"]), "waste": is_waste, "watt": watts, "resolved": false, "label": status, "plug": plug})

func _process(delta: float) -> void:
	visual_time += delta
	_animate_scene()
	if not running or not is_instance_valid(hero):
		return
	var direction := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A): direction -= 1.0
	if Input.is_key_pressed(KEY_D): direction += 1.0
	direction = clampf(direction, -1.0, 1.0)
	run_velocity = move_toward(run_velocity, direction * RUN_SPEED, RUN_ACCELERATION * delta)
	hero.position.x = clampf(hero.position.x + run_velocity * delta, 0.6, COURSE_END)
	if hero.has_method("_set_avatar_animation_state"):
		hero.call("_set_avatar_animation_state", absf(run_velocity) > 0.18)
	if hero.avatar_sprite:
		hero.avatar_sprite.flip_h = run_velocity < -0.1
	var look_x := clampf(hero.position.x + 2.3, 4.3, COURSE_END - 4.3)
	camera.position.x = lerpf(camera.position.x, look_x, 1.0 - exp(-delta * 5.5))
	camera.look_at(Vector3(camera.position.x, 2.25, 0.0), Vector3.UP)
	_update_device_passes()
	_update_hud()
	var space_down := Input.is_key_pressed(KEY_SPACE)
	if space_down and not space_was_down:
		_try_disconnect()
	space_was_down = space_down
	if hero.position.x >= COURSE_END - 0.1 and run_velocity > 0.0:
		_start_new_lap()

func _animate_scene() -> void:
	for record in device_records:
		var node := record["node"] as Node3D
		if not is_instance_valid(node): continue
		var glow := node.get_node_or_null("ActivityGlow") as MeshInstance3D
		if glow:
			glow.scale = Vector3.ONE * (0.82 + sin(visual_time * 6.0 + float(record["x"])) * 0.18)

func _update_device_passes() -> void:
	if run_velocity <= 0.1:
		return
	for record in device_records:
		if bool(record["resolved"]): continue
		if hero.position.x > float(record["x"]) + PASS_DISTANCE:
			_resolve_device(record, false)

func _nearest_unresolved_device() -> Dictionary:
	var nearest: Dictionary = {}
	var best_distance := INF
	for record in device_records:
		if bool(record["resolved"]): continue
		var distance := absf(hero.position.x - float(record["x"]))
		if distance <= INTERACTION_DISTANCE and distance < best_distance:
			nearest = record
			best_distance = distance
	return nearest

func _try_disconnect() -> void:
	var record := _nearest_unresolved_device()
	if record.is_empty():
		arcade_event.emit(8, false, "전자기기 가까이에서 플러그를 차단하세요.", false)
		_flash(Color("ffb15a3d"))
		return
	_resolve_device(record, true)

func _resolve_device(record: Dictionary, disconnect: bool) -> void:
	if bool(record.get("resolved", false)):
		return
	record["resolved"] = true
	var is_waste := bool(record["waste"])
	var device_name := str(record["name"])
	var watts := int(record["watt"])
	var status := record["label"] as Label3D
	var plug := record["plug"] as MeshInstance3D
	if disconnect:
		if is_instance_valid(plug):
			plug.material_override = safe_material if is_waste else danger_material
			var tween := create_tween().set_parallel(true)
			tween.tween_property(plug, "position:y", plug.position.y + 0.8, 0.32).set_trans(Tween.TRANS_BACK)
			tween.tween_property(plug, "rotation_degrees:z", 45.0, 0.32)
		if is_waste:
			var points := 95 + watts * 3
			status.text = "%s\n차단 완료 · 0 W" % device_name
			status.modulate = Color("79efaa")
			arcade_event.emit(points, true, "%s의 대기전력 %d W를 차단했어요." % [device_name, watts], true)
			_flash(Color("55e79c35"))
		else:
			status.text = "%s\n사용 중 전원 차단!" % device_name
			status.modulate = Color("ff6c60")
			arcade_event.emit(48, false, "%s은 지금 사용 중이에요." % device_name, false)
			_flash(Color("ff493f50"))
	else:
		if is_waste:
			status.text = "%s\n대기전력 놓침 · %d W" % [device_name, watts]
			status.modulate = Color("ff8167")
			arcade_event.emit(24, false, "%s은 꺼져 보여도 %d W를 쓰고 있어요." % [device_name, watts], false)
		else:
			status.text = "%s\n사용 유지 · 안전" % device_name
			status.modulate = Color("84eab7")
			arcade_event.emit(14, true, "%s의 작동을 유지했어요." % device_name, false)

func _start_new_lap() -> void:
	lap_index += 1
	hero.position.x = 0.8
	run_velocity = 1.0
	camera.position.x = 4.3
	_build_house_course()
	arcade_event.emit(35, true, "집 안 점검 %d회차를 시작합니다." % lap_index, false)

func _update_hud() -> void:
	var room_index := clampi(int(hero.position.x / 12.0), 0, 3)
	room_label.text = "현재 위치  %s" % ["거실", "주방", "침실", "세탁실"][room_index]
	progress_label.text = "집 안 점검 %d회차  ·  %d%%" % [lap_index, int(hero.position.x / COURSE_END * 100.0)]
	var nearest := _nearest_unresolved_device()
	if nearest.is_empty():
		action_label.text = "A/D로 집 안을 이동하세요"
	else:
		action_label.text = "[SPACE] %s 플러그 확인" % str(nearest["name"])
		action_label.modulate.a = 0.78 + sin(visual_time * 7.0) * 0.20

func _build_overlay() -> void:
	var help := Label.new()
	help.position = Vector2(14, 9)
	help.text = "A/D 좌우 달리기    SPACE 가까운 플러그 차단    화면은 꺼졌는데 W가 표시되면 대기전력!"
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", Color("fff0b3"))
	help.add_theme_color_override("font_outline_color", Color("18343d"))
	help.add_theme_constant_override("outline_size", 5)
	add_child(help)
	room_label = _overlay_label(Vector2(14, 39), Vector2(300, 70), "현재 위치  거실", HORIZONTAL_ALIGNMENT_LEFT, Color("8bf2d1"))
	progress_label = _overlay_label(Vector2(650, 9), Vector2(946, 40), "집 안 점검 1회차", HORIZONTAL_ALIGNMENT_RIGHT, Color("fff0b3"))
	action_label = _overlay_label(Vector2(320, 246), Vector2(640, 278), "A/D로 집 안을 이동하세요", HORIZONTAL_ALIGNMENT_CENTER, Color("ffd367"))
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color.TRANSPARENT
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

func _overlay_label(from: Vector2, to: Vector2, text_value: String, alignment: HorizontalAlignment, color: Color) -> Label:
	var label := Label.new()
	label.position = from
	label.size = to - from
	label.text = text_value
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("18343d"))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	return label

func _flash(color: Color) -> void:
	flash.color = color
	create_tween().tween_property(flash, "color:a", 0.0, 0.30)

func _place_model(scene: PackedScene, position_value: Vector3, scale_value: float, yaw: float, node_name: String) -> Node3D:
	var model := scene.instantiate() as Node3D
	model.name = node_name
	model.position = position_value
	model.scale = Vector3.ONE * scale_value
	model.rotation_degrees.y = yaw
	course_root.add_child(model)
	var tint := Color.WHITE
	match node_name:
		"Floor": tint = Color("c39a6b")
		"Wall", "RoomDivider": tint = Color("ecd6ad")
		"Sofa": tint = Color("4d91a5")
		"CoffeeTable", "TvCabinet", "SideTable", "Bookcase": tint = Color("956a49")
		"KitchenCabinet": tint = Color("ddb878")
		"Bed": tint = Color("89b6c7")
		"LivingLamp", "BedLamp": tint = Color("f2cf67")
		"LivingPlant": tint = Color("62a55c")
		_: pass
	if tint != Color.WHITE:
		_apply_model_tint(model, tint)
	return model

func _apply_model_tint(model_root: Node3D, tint: Color) -> void:
	var meshes: Array[Node] = []
	if model_root is MeshInstance3D:
		meshes.append(model_root)
	meshes.append_array(model_root.find_children("*", "MeshInstance3D", true, false))
	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null: continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.get_active_material(surface_index)
			var material := source.duplicate() as StandardMaterial3D if source is StandardMaterial3D else StandardMaterial3D.new()
			material.albedo_color *= tint
			mesh_instance.set_surface_override_material(surface_index, material)

func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.2
	return material
