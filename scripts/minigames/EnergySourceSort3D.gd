extends SubViewportContainer
class_name EnergySourceSort3D

## 햇빛·바람·흐르는 물은 다시 얻고, 화석연료는 캐서 쓰는 자원임을
## 두 배송장 사이를 실제로 달리며 분류하는 30초짜리 3D 아케이드입니다.

signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const PLAYER_PAWN = preload("res://scripts/player/PlayerPawn.gd")
const SOURCES := [
	{"name": "햇빛", "kind": 0, "shape": "sun", "reason": "햇빛은 다음 날에도 다시 비춰요."},
	{"name": "바람", "kind": 0, "shape": "wind", "reason": "바람은 자연에서 다시 불어요."},
	{"name": "흐르는 물", "kind": 0, "shape": "water", "reason": "물은 자연에서 순환하며 다시 흘러요."},
	{"name": "석탄", "kind": 1, "shape": "coal", "reason": "석탄은 땅에서 캐서 쓰는 연료예요."},
	{"name": "석유", "kind": 1, "shape": "oil", "reason": "석유는 땅에서 꺼내 쓰는 연료예요."},
	{"name": "천연가스", "kind": 1, "shape": "gas", "reason": "천연가스도 땅에서 꺼내 쓰는 연료예요."},
]
const RUN_SPEED := 7.0
const DELIVERY_X := 4.25
const CORRECT_POINTS := 90
const WRONG_PENALTY := 30

var viewport: SubViewport
var world: Node3D
var hero: Node3D
var icon_anchor: Node3D
var left_light: MeshInstance3D
var right_light: MeshInstance3D
var item_label: Label
var hint_label: Label
var round_label: Label
var flash: ColorRect
var rng_seed := 0
var item_step := 0
var current_source: Dictionary = {}
var hero_x := 0.0
var visual_time := 0.0
var cooldown := 0.0
var waiting_for_release := false
var running := false
var flash_remaining := 0.0
var left_material: StandardMaterial3D
var right_material: StandardMaterial3D
var idle_light_material: StandardMaterial3D

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 286)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_overlay()
	set_process(true)

func setup(player_data: Dictionary, game_seed: int) -> void:
	rng_seed = game_seed
	item_step = 0
	hero_x = 0.0
	visual_time = 0.0
	cooldown = 0.0
	waiting_for_release = false
	flash_remaining = 0.0
	_spawn_hero(player_data)
	_next_item()
	running = true

func set_running(value: bool) -> void:
	running = value
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	if is_instance_valid(hero):
		hero.call("_set_avatar_animation_state", false)

static func source_for_step(game_seed: int, step: int) -> Dictionary:
	# 6종을 한 번씩 보여준 뒤 다음 묶음을 섞어 모든 원천을 고르게 만납니다.
	var bag: Array[int] = [0, 1, 2, 3, 4, 5]
	var source_rng := RandomNumberGenerator.new()
	source_rng.seed = game_seed + int(step / SOURCES.size()) * 65537
	for index in range(bag.size() - 1, 0, -1):
		var other := source_rng.randi_range(0, index)
		var saved := bag[index]
		bag[index] = bag[other]
		bag[other] = saved
	return SOURCES[bag[posmod(step, bag.size())]]

func _build_world() -> void:
	viewport = SubViewport.new()
	viewport.name = "EnergySourceSortViewport"
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
	environment.background_color = Color("a5d7e3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e9f8ee")
	environment.ambient_light_energy = 0.85
	sky.environment = environment
	world.add_child(sky)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -24, 0)
	light.light_energy = 1.2
	light.shadow_enabled = false
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.3
	camera.position = Vector3(0, 5.0, 12.0)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0, 1.25, 0), Vector3.UP)
	left_material = _material(Color("70e8ac"), true)
	right_material = _material(Color("e8b779"), true)
	idle_light_material = _material(Color("718590"), false)
	_box("SortingFloor", world, Vector3(0, -0.17, 0), Vector3(12.0, 0.35, 6.0), Color("658e83"))
	_box("Runway", world, Vector3(0, 0.02, 1.2), Vector3(9.0, 0.07, 2.0), Color("c6d9c2"))
	for mark in range(-3, 4):
		_box("RunwayDash%d" % mark, world, Vector3(float(mark) * 1.1, 0.065, 1.2), Vector3(0.4, 0.03, 0.08), Color("f8f6d9"), true)
	_make_bin(-4.65, Color("33aa76"), 0)
	_make_bin(4.65, Color("8e6255"), 1)
	_box("CenterPickup", world, Vector3(0, 0.09, 0.0), Vector3(1.6, 0.13, 1.15), Color("edf6a8"), true)
	icon_anchor = Node3D.new()
	icon_anchor.name = "CarriedEnergySource"
	world.add_child(icon_anchor)

func _make_bin(x: float, color: Color, index: int) -> void:
	_box("CollectionBin%d" % index, world, Vector3(x, 0.65, -0.65), Vector3(2.2, 1.3, 1.5), color)
	_box("BinRim%d" % index, world, Vector3(x, 1.35, -0.65), Vector3(2.35, 0.18, 1.65), color.lightened(0.28), true)
	var lamp := _sphere("DeliveryLamp%d" % index, world, Vector3(x, 2.15, 0.0), 0.20, Color("718590"))
	if index == 0:
		left_light = lamp
	else:
		right_light = lamp
	var label := Label3D.new()
	label.position = Vector3(x, 1.18, 0.17)
	label.text = "다시 얻음" if index == 0 else "땅속 연료"
	label.font_size = 44
	label.pixel_size = 0.009
	label.outline_size = 9
	label.no_depth_test = true
	world.add_child(label)

func _spawn_hero(player_data: Dictionary) -> void:
	if is_instance_valid(hero):
		hero.queue_free()
	hero = PLAYER_PAWN.new()
	world.add_child(hero)
	var hero_data := player_data.duplicate(true)
	hero_data["index"] = 0
	hero.call("setup_player", hero_data)
	hero.call("set_side_run_enabled", true)
	hero.scale = Vector3.ONE * 2.3
	hero.position = Vector3(0, 0.10, 1.45)
	if hero.shadow_mesh:
		hero.shadow_mesh.visible = false
	hero.call("_set_avatar_animation_state", false)

func _build_overlay() -> void:
	item_label = _overlay_label(Vector2(330, 7), Vector2(630, 48), "이번 에너지는?", Color("fff1a5"), 28)
	round_label = _overlay_label(Vector2(340, 45), Vector2(620, 72), "배송 1번째", Color("e7f8ff"), 17)
	_overlay_label(Vector2(10, 96), Vector2(345, 127), "← 자연에서 다시 얻어요", Color("b6ffcb"), 20)
	_overlay_label(Vector2(18, 124), Vector2(338, 148), "햇빛 · 바람 · 흐르는 물", Color("e7fff1"), 16)
	_overlay_label(Vector2(615, 96), Vector2(950, 127), "땅에서 꺼내 써요 →", Color("ffe0b2"), 20)
	_overlay_label(Vector2(622, 124), Vector2(942, 148), "석탄 · 석유 · 천연가스", Color("fff1dc"), 16)
	hint_label = _overlay_label(Vector2(145, 259), Vector2(815, 285), "A/← 왼쪽  ·  D/→ 오른쪽  ·  중앙에서 다음 물건 받기", Color("fff1a5"), 16)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color.TRANSPARENT
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

func _next_item() -> void:
	current_source = source_for_step(rng_seed, item_step).duplicate(true)
	item_label.text = "운반: %s" % current_source["name"]
	round_label.text = "%d번째 물건" % (item_step + 1)
	for child in icon_anchor.get_children():
		icon_anchor.remove_child(child)
		child.queue_free()
	_build_source_shape(str(current_source["shape"]))
	icon_anchor.position = Vector3(hero_x, 2.45, 1.55)

func _build_source_shape(shape: String) -> void:
	match shape:
		"sun":
			_sphere("Sun", icon_anchor, Vector3.ZERO, 0.37, Color("ffd651"), true)
			for ray in range(8):
				var angle := float(ray) * TAU / 8.0
				var beam := _box("SunRay", icon_anchor, Vector3(cos(angle) * 0.59, sin(angle) * 0.59, 0), Vector3(0.30, 0.11, 0.10), Color("ffef92"), true)
				beam.rotation.z = angle
		"wind":
			_sphere("WindHub", icon_anchor, Vector3.ZERO, 0.15, Color("d8faff"))
			for blade in range(3):
				var angle := float(blade) * TAU / 3.0
				var vane := _box("WindBlade", icon_anchor, Vector3(sin(angle) * 0.39, cos(angle) * 0.39, 0), Vector3(0.16, 0.69, 0.10), Color("f3fcff"), true)
				vane.rotation.z = -angle
		"water":
			var drop := _sphere("WaterDrop", icon_anchor, Vector3(0, -0.08, 0), 0.36, Color("5dbcf1"), true)
			drop.scale = Vector3(0.9, 1.1, 0.9)
			_cylinder("WaterTip", icon_anchor, Vector3(0, 0.27, 0), 0.26, 0.42, Color("5dbcf1"))
		"coal":
			for rock in range(3):
				_sphere("CoalRock", icon_anchor, Vector3((float(rock) - 1.0) * 0.25, -0.14 + float(rock % 2) * 0.21, 0), 0.26, Color("303c46"))
		"oil":
			_cylinder("OilBarrel", icon_anchor, Vector3.ZERO, 0.37, 0.83, Color("333a46"))
			_cylinder("BarrelTop", icon_anchor, Vector3(0, 0.43, 0), 0.39, 0.08, Color("cd9d61"))
		"gas":
			_cylinder("GasTank", icon_anchor, Vector3.ZERO, 0.33, 0.85, Color("96b7c4"))
			_sphere("GasFlame", icon_anchor, Vector3(0, 0.57, 0), 0.18, Color("7edaf7"), true)

func _process(delta: float) -> void:
	visual_time += delta
	flash_remaining = maxf(0.0, flash_remaining - delta)
	if flash_remaining <= 0.0:
		flash.color = Color.TRANSPARENT
	if not is_instance_valid(icon_anchor):
		return
	icon_anchor.position = Vector3(hero_x, 2.45 + sin(visual_time * 5.0) * 0.09, 1.55)
	icon_anchor.rotation.y += delta * 0.7
	if not running:
		return
	if cooldown > 0.0:
		cooldown -= delta
		return
	var left_down := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right_down := Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	if waiting_for_release:
		if not left_down and not right_down:
			waiting_for_release = false
		return
	var axis := float(int(right_down) - int(left_down))
	hero_x = clampf(hero_x + axis * RUN_SPEED * delta, -DELIVERY_X, DELIVERY_X)
	if is_instance_valid(hero):
		hero.position.x = hero_x
		if hero.is_moving != (axis != 0.0):
			hero.call("_set_avatar_animation_state", axis != 0.0)
		if axis != 0.0 and hero.avatar_sprite:
			hero.avatar_sprite.flip_h = axis < 0.0
	if absf(hero_x) >= DELIVERY_X:
		_deliver(0 if hero_x < 0.0 else 1)

func _deliver(bin_kind: int) -> void:
	var correct := bin_kind == int(current_source["kind"])
	var message := "%s → %s · %s" % [current_source["name"], "다시 얻는 곳" if bin_kind == 0 else "꺼내 쓰는 곳", current_source["reason"]]
	arcade_event.emit(CORRECT_POINTS if correct else WRONG_PENALTY, correct, message, correct)
	left_light.material_override = left_material if bin_kind == 0 and correct else idle_light_material
	right_light.material_override = right_material if bin_kind == 1 and correct else idle_light_material
	flash.color = Color("62ed9b32") if correct else Color("f071633f")
	flash_remaining = 0.22
	hero_x = 0.0
	if is_instance_valid(hero):
		hero.position.x = 0.0
		hero.call("_set_avatar_animation_state", false)
	item_step += 1
	_next_item()
	cooldown = 0.20
	waiting_for_release = true

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

func _cylinder(node_name: String, parent: Node3D, where: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.7
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = where
	instance.material_override = _material(color, false)
	parent.add_child(instance)
	return instance

func _material(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
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
