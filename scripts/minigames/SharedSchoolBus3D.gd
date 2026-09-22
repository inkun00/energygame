extends SubViewportContainer
class_name SharedSchoolBus3D

## 버스의 가속·제동·짧은 후진을 직접 조작합니다. 정류장과 학교에 정확히
## 멈추고 움직이는 학생을 태우며 1인당 운행 에너지를 확인합니다.
signal arcade_event(points: int, success: bool, message: String, count_correct: bool)

const BUS_MODEL = preload("res://assets/third_party/school_bus_run/schoolbus.glb")
const STUDENT_A = preload("res://assets/third_party/school_bus_run/character-a.glb")
const STUDENT_B = preload("res://assets/third_party/school_bus_run/character-b.glb")
const BUS_CAPACITY := 45
const SEGMENT_LENGTH := 60.0
const STOP_OFFSETS := [12.0, 29.0, 46.0]
const SCHOOL_OFFSET := 56.0
const SCHOOL_ENTRANCE_OFFSET := 3.5
const PICKUP_REACH := 1.15
const SCHOOL_REACH := 0.95
const STOP_SPEED_LIMIT := 0.35
const MAX_SPEED := 11.0
const REVERSE_SPEED := 6.0
const MAX_REVERSE_DISTANCE := 8.0
const ACCELERATION := 7.0
const REVERSE_ACCELERATION := 4.5
const BRAKE := 15.0
const COAST_DRAG := 1.3
const START_ENERGY := 3.0
const ENERGY_PER_DISTANCE := 0.15

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var bus: Node3D
var bus_door_left: Node3D
var bus_door_right: Node3D
var bus_door_open := 0.0
var segments: Dictionary = {}
var dropped_students: Array[Dictionary] = []
var passenger_label: Label
var efficiency_label: Label
var route_label: Label
var action_label: Label
var flash: ColorRect
var rng := RandomNumberGenerator.new()
var bus_x := 0.0
var furthest_x := 0.0
var bus_speed := 0.0
var route_distance := 0.0
var passengers := 0
var delivered_total := 0
var trip_index := 0
var elapsed := 0.0
var space_was_down := false
var flash_remaining := 0.0
var running := false
var notice := "D/A 길게 가속 · S 정차 · 정류장에서 Space"
var notice_remaining := 3.0

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(0, 286)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_overlay()
	set_process(true)

func setup(_player_data: Dictionary, game_seed: int) -> void:
	rng.seed = game_seed
	bus_x = 0.0
	furthest_x = 0.0
	bus_speed = 0.0
	bus_door_open = 0.0
	_set_bus_door_position()
	route_distance = 0.0
	passengers = 0
	delivered_total = 0
	trip_index = 0
	elapsed = 0.0
	space_was_down = false
	flash_remaining = 0.0
	notice = "D/A 길게 가속 · S 정차 · 정류장에서 Space"
	notice_remaining = 3.0
	for index in segments.keys():
		(segments[index] as Dictionary)["root"].queue_free()
	segments.clear()
	for record in dropped_students:
		if is_instance_valid(record["node"]):
			(record["node"] as Node3D).queue_free()
	dropped_students.clear()
	_ensure_segments()
	_animate_students(0.0)
	_update_visuals()
	running = true

func set_running(value: bool) -> void:
	running = value
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED

static func route_energy(distance: float) -> float:
	# 실제 kWh가 아닌 게임 수치: 운행 고정 비용 + 이동 거리 비용.
	return START_ENERGY + maxf(0.0, distance) * ENERGY_PER_DISTANCE

static func energy_per_person(passenger_count: int, distance: float) -> float:
	return route_energy(distance) / float(passenger_count) if passenger_count > 0 else 0.0

static func score_for_trip(passenger_count: int, distance: float) -> int:
	if passenger_count <= 0:
		return 0
	var per_person := energy_per_person(passenger_count, distance)
	# 45인 만차와 60초 반복 운행에서도 전체 점수 상한에 쉽게 닿지 않도록 조정합니다.
	return passenger_count * 12 + roundi(maxf(0.0, 3.0 - per_person) * 5.0 * float(passenger_count))

func _build_world() -> void:
	viewport = SubViewport.new()
	viewport.name = "SharedSchoolBusViewport"
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
	environment.background_color = Color("a7d9ea")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("eef8ff")
	environment.ambient_light_energy = 0.84
	sky.environment = environment
	world.add_child(sky)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-50, -20, 0)
	sunlight.light_energy = 1.1
	sunlight.shadow_enabled = false
	world.add_child(sunlight)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	camera.current = true
	world.add_child(camera)
	bus = Node3D.new()
	bus.name = "SchoolBus"
	world.add_child(bus)
	var model := BUS_MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * 0.050
	model.rotation.y = PI * 0.5
	bus.add_child(model)
	_build_bus_door()
	_update_camera_and_bus()

func _build_bus_door() -> void:
	# 원본 CC BY 버스는 단일 메시라 문만 분리할 수 없습니다. 차체 옆에
	# 어두운 출입구와 두 장의 미닫이 패널을 얹어 개폐를 표현합니다.
	_box(bus, Vector3(1.08, 0.73, 0.83), Vector3(0.62, 1.03, 0.025), Color("263e48"))
	bus_door_left = Node3D.new()
	bus_door_right = Node3D.new()
	bus.add_child(bus_door_left)
	bus.add_child(bus_door_right)
	for panel in [bus_door_left, bus_door_right]:
		_box(panel, Vector3(0.0, 0.73, 0.87), Vector3(0.29, 1.01, 0.045), Color("ffe387"))
		_box(panel, Vector3(0.0, 1.00, 0.90), Vector3(0.22, 0.37, 0.012), Color("76bad0"))
	_set_bus_door_position()

func _set_bus_door_position() -> void:
	bus_door_left.position.x = 0.93 - 0.28 * bus_door_open
	bus_door_right.position.x = 1.23 + 0.28 * bus_door_open

func _is_at_service_point() -> bool:
	for segment in segments.values():
		var route := segment as Dictionary
		if absf(bus_x - float(route["school_x"])) <= SCHOOL_REACH:
			return true
		for stop in (route["stops"] as Array):
			if absf(bus_x - float(stop["x"])) <= PICKUP_REACH:
				return true
	return false

func _animate_bus_door(delta: float) -> void:
	var should_open := absf(bus_speed) <= STOP_SPEED_LIMIT and _is_at_service_point()
	bus_door_open = move_toward(bus_door_open, 1.0 if should_open else 0.0, delta * 2.5)
	_set_bus_door_position()

func _ensure_segments() -> void:
	var current_index := int(floorf(bus_x / SEGMENT_LENGTH))
	for index in range(maxi(0, current_index - 1), current_index + 2):
		if not segments.has(index):
			segments[index] = _build_segment(index)
	for index in segments.keys():
		if int(index) < current_index - 1:
			(segments[index] as Dictionary)["root"].queue_free()
			segments.erase(index)

func _build_segment(index: int) -> Dictionary:
	var start_x := float(index) * SEGMENT_LENGTH
	var group := Node3D.new()
	group.name = "RouteSegment%d" % index
	world.add_child(group)
	_box(group, Vector3(start_x + SEGMENT_LENGTH * 0.5, -0.22, -1.1), Vector3(SEGMENT_LENGTH, 0.34, 6.0), Color("79bf90"))
	_box(group, Vector3(start_x + SEGMENT_LENGTH * 0.5, -0.03, 1.1), Vector3(SEGMENT_LENGTH, 0.10, 2.45), Color("667886"))
	if index == 0:
		# 시작 위치 뒤쪽도 같은 길로 채워 첫 화면에서 도로가 끊겨 보이지 않게 합니다.
		_box(group, Vector3(-10.0, -0.22, -1.1), Vector3(20.0, 0.34, 6.0), Color("79bf90"))
		_box(group, Vector3(-10.0, -0.03, 1.1), Vector3(20.0, 0.10, 2.45), Color("667886"))
		for back_mark in range(17):
			_box(group, Vector3(-19.4 + float(back_mark) * 1.2, 0.03, 1.1), Vector3(0.52, 0.03, 0.08), Color("e9e9d1"), true)
	for mark in range(50):
		_box(group, Vector3(start_x + 0.6 + float(mark) * 1.2, 0.03, 1.1), Vector3(0.52, 0.03, 0.08), Color("e9e9d1"), true)
	var stops: Array[Dictionary] = []
	for stop_index in range(STOP_OFFSETS.size()):
		var stop_x: float = start_x + float(STOP_OFFSETS[stop_index])
		var count: int = rng.randi_range(15, 19) if index > 0 else int([17, 18, 16][stop_index])
		var late_count: int = rng.randi_range(5, mini(11, count - 5)) if index > 0 else int([7, 10, 8][stop_index])
		var stop_root := Node3D.new()
		group.add_child(stop_root)
		_box(stop_root, Vector3(stop_x, 0.13, -1.0), Vector3(4.8, 0.25, 1.7), Color("e2e3b0"))
		_box(stop_root, Vector3(stop_x, 1.22, -1.4), Vector3(0.12, 1.9, 0.12), Color("739094"))
		_box(stop_root, Vector3(stop_x, 2.14, -1.4), Vector3(4.7, 0.16, 1.6), Color("6fb5c9"))
		var student_nodes: Array[Node3D] = []
		var student_states: Array[Dictionary] = []
		for student_index in range(count):
			var column := student_index % 7
			var row := student_index / 7
			var base_x := stop_x + (float(column) - 3.0) * 0.48
			var base_z := -0.18 - float(row) * 0.38
			var is_late: bool = student_index >= count - late_count
			var late_order: int = student_index - (count - late_count) if is_late else -1
			student_states.append({"node": null, "animator": null, "base_x": base_x, "base_z": base_z, "late": is_late, "late_order": late_order, "approaching": false, "arrived": not is_late, "boarded": false, "phase": rng.randf_range(0.0, TAU), "run_speed": 1.4 + float(late_order % 4) * 0.30 if is_late else 0.0, "variant": (stop_index + student_index) % 2})
		var ready_count: int = count - late_count
		var label := _label3d(group, "대기 %d명 · 뛰는 중 %d명" % [ready_count, late_count], Vector3(stop_x, 2.72, -0.45), Color("ffc288"))
		stops.append({"x": stop_x, "waiting": ready_count, "students": student_nodes, "states": student_states, "label": label, "root": stop_root, "active": false, "retired": false})
	var school_x := start_x + SCHOOL_OFFSET
	var entrance_x := school_x + SCHOOL_ENTRANCE_OFFSET
	_box(group, Vector3(entrance_x, 1.10, -2.0), Vector3(2.35, 2.18, 1.55), Color("ead5b1"))
	_box(group, Vector3(entrance_x, 2.31, -2.0), Vector3(2.55, 0.24, 1.8), Color("b5796b"))
	_box(group, Vector3(entrance_x, 0.58, -1.17), Vector3(0.54, 1.12, 0.07), Color("617d8a"))
	var school_door_left := _box(group, Vector3(entrance_x - 0.13, 0.58, -1.10), Vector3(0.25, 1.08, 0.045), Color("c4e6d8"))
	var school_door_right := _box(group, Vector3(entrance_x + 0.13, 0.58, -1.10), Vector3(0.25, 1.08, 0.045), Color("c4e6d8"))
	_label3d(group, "학교 · 노란 구역에 정차", Vector3(entrance_x, 2.95, -0.8), Color("fff2c6"))
	_box(group, Vector3(school_x, 0.055, 1.1), Vector3(2.0, 0.07, 2.45), Color("e5d98c"), true)
	return {"root": group, "stops": stops, "school_x": school_x, "entrance_x": entrance_x, "school_served": false, "school_missed_notice": false, "school_door_left": school_door_left, "school_door_right": school_door_right, "school_door_open": 0.0}

func _build_overlay() -> void:
	passenger_label = _overlay_label(Vector2(24, 8), Vector2(300, 39), "승객 0 / 45명", Color("fff2b8"), 22)
	efficiency_label = _overlay_label(Vector2(305, 8), Vector2(655, 39), "1인당 에너지 --", Color("d7ffed"), 20)
	route_label = _overlay_label(Vector2(668, 8), Vector2(935, 39), "속도 0 · 에너지 3.0", Color("fff0b7"), 17)
	action_label = _overlay_label(Vector2(85, 255), Vector2(875, 282), "D/A 길게 가속 · S 정차 · 정류장에서 Space", Color("fff4bd"), 17)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color.TRANSPARENT
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

func _process(delta: float) -> void:
	flash_remaining = maxf(0.0, flash_remaining - delta)
	if flash_remaining <= 0.0:
		flash.color = Color.TRANSPARENT
	_animate_dropoff_students(delta)
	_animate_school_doors(delta)
	if not running:
		return
	elapsed += delta
	notice_remaining = maxf(0.0, notice_remaining - delta)
	_step_vehicle(delta, Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT), Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN), Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	_ensure_segments()
	_animate_students(delta)
	_animate_bus_door(delta)
	_update_camera_and_bus()
	var space_down := Input.is_key_pressed(KEY_SPACE)
	if space_down and not space_was_down:
		_attempt_pickup()
	space_was_down = space_down
	_check_school_stop()
	_update_visuals()

func _step_vehicle(delta: float, accelerate: bool, brake: bool, reverse: bool) -> void:
	if brake:
		bus_speed = move_toward(bus_speed, 0.0, BRAKE * delta)
	elif reverse:
		bus_speed = move_toward(bus_speed, -REVERSE_SPEED, BRAKE * delta if bus_speed > 0.0 else REVERSE_ACCELERATION * delta)
	elif accelerate:
		bus_speed = move_toward(bus_speed, MAX_SPEED, ACCELERATION * delta)
	else:
		bus_speed = move_toward(bus_speed, 0.0, COAST_DRAG * delta)
	var previous_x := bus_x
	bus_x = maxf(maxf(0.0, furthest_x - MAX_REVERSE_DISTANCE), bus_x + bus_speed * delta)
	furthest_x = maxf(furthest_x, bus_x)
	if bus_x <= maxf(0.0, furthest_x - MAX_REVERSE_DISTANCE) and bus_speed < 0.0:
		bus_speed = 0.0
	route_distance += absf(bus_x - previous_x)

func _activate_stop(stop: Dictionary) -> void:
	if bool(stop["active"]) or bool(stop["retired"]):
		return
	stop["active"] = true
	var stop_x := float(stop["x"])
	for state in (stop["states"] as Array):
		var student_scene: PackedScene = STUDENT_A if int(state["variant"]) == 0 else STUDENT_B
		var student := student_scene.instantiate() as Node3D
		student.name = "WaitingStudent"
		var start_x := stop_x + 3.4 + float(int(state["late_order"]) % 6) * 0.85 if bool(state["late"]) else float(state["base_x"])
		student.position = Vector3(start_x, 0.72, float(state["base_z"]))
		student.scale = Vector3.ONE * 0.42
		(stop["root"] as Node3D).add_child(student)
		(stop["students"] as Array).append(student)
		var animator := student.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animator:
			animator.play("idle" if bool(state["late"]) else "walk")
		state["node"] = student
		state["animator"] = animator

func _retire_stop(stop: Dictionary) -> void:
	for state in (stop["states"] as Array):
		if is_instance_valid(state["node"]):
			(state["node"] as Node3D).queue_free()
		state["node"] = null
		state["animator"] = null
	(stop["students"] as Array).clear()
	stop["active"] = false
	stop["retired"] = true

func _animate_students(delta: float) -> void:
	for segment in segments.values():
		for stop in (segment as Dictionary)["stops"]:
			var stop_x := float(stop["x"])
			if not bool(stop["active"]) and absf(bus_x - stop_x) <= 18.0:
				_activate_stop(stop)
			if not bool(stop["active"]):
				continue
			if bus_x > stop_x + 10.0:
				_retire_stop(stop)
				continue
			var ready_count := 0
			var running_count := 0
			for state in (stop["states"] as Array):
				if bool(state["boarded"]):
					continue
				var student := state["node"] as Node3D
				var animator := state["animator"] as AnimationPlayer
				if bool(state["late"]) and not bool(state["arrived"]):
					running_count += 1
					if bus_x >= stop_x - 9.0:
						state["approaching"] = true
					if bool(state["approaching"]):
						student.position.x = move_toward(student.position.x, float(state["base_x"]), float(state["run_speed"]) * delta)
						if animator and animator.current_animation != "sprint":
							animator.play("sprint")
						if absf(student.position.x - float(state["base_x"])) < 0.05:
							state["arrived"] = true
							running_count -= 1
					elif animator and animator.current_animation != "idle":
						animator.play("idle")
				if bool(state["arrived"]):
					ready_count += 1
					student.position.x = float(state["base_x"]) + sin(elapsed * 1.7 + float(state["phase"])) * 0.10
					student.position.z = float(state["base_z"]) + sin(elapsed * 1.15 + float(state["phase"])) * 0.05
					if animator and animator.current_animation != "walk":
						animator.play("walk")
			stop["waiting"] = ready_count
			(stop["label"] as Label3D).text = "대기 %d명%s" % [ready_count, " · 뛰는 중 %d명" % running_count if running_count > 0 else ""]
			(stop["label"] as Label3D).modulate = Color("ffc288") if running_count > 0 else Color("fff3c4")

func _attempt_pickup() -> void:
	if not running:
		return
	var closest: Dictionary = {}
	var closest_gap := PICKUP_REACH
	for segment in segments.values():
		for stop in (segment as Dictionary)["stops"]:
			var gap := absf(bus_x - float(stop["x"]))
			if gap <= closest_gap:
				closest = stop
				closest_gap = gap
	if closest.is_empty():
		_notice("정류장 표시 안에 정확히 멈춰 Space를 누르세요.")
		return
	if absf(bus_speed) > STOP_SPEED_LIMIT:
		_notice("학생을 태우려면 먼저 S로 버스를 멈추세요!")
		return
	if passengers >= BUS_CAPACITY:
		_notice("버스가 가득 찼어요! 앞으로 가면 학교에 도착해요.")
		return
	var boarding := 0
	for state in (closest["states"] as Array):
		if bool(state["arrived"]) and not bool(state["boarded"]) and passengers + boarding < BUS_CAPACITY:
			state["boarded"] = true
			(state["node"] as Node3D).visible = false
			boarding += 1
	if boarding <= 0:
		_notice("학생이 아직 정류장으로 뛰어오고 있어요. 잠시 기다리세요!")
		return
	passengers += boarding
	closest["waiting"] = maxi(0, int(closest["waiting"]) - boarding)
	var late_remaining := 0
	for state in (closest["states"] as Array):
		if not bool(state["arrived"]) and not bool(state["boarded"]):
			late_remaining += 1
	if late_remaining > 0 and passengers < BUS_CAPACITY:
		_notice("%d명 탑승 · %d명 뛰어오는 중! 기다려 Space 또는 출발" % [boarding, late_remaining])
	else:
		_notice("학생 %d명 탑승! 함께 탈수록 1인당 에너지가 줄어요." % boarding)
	arcade_event.emit(0, true, "학생 %d명 탑승 · 앞으로 달리세요" % boarding, false)
	flash.color = Color("8de9b236")
	flash_remaining = 0.20
	_update_visuals()

func _check_school_stop() -> void:
	for segment in segments.values():
		var record := segment as Dictionary
		var school_x := float(record["school_x"])
		if not bool(record["school_served"]) and absf(bus_x - school_x) <= SCHOOL_REACH and absf(bus_speed) <= STOP_SPEED_LIMIT:
			record["school_served"] = true
			_unload_at_school(school_x)
		elif not bool(record["school_served"]) and not bool(record["school_missed_notice"]) and bus_x > school_x + SCHOOL_REACH:
			record["school_missed_notice"] = true
			_notice("학교를 지나쳤어요! S로 멈추고 A로 조금 후진하세요.")

func _unload_at_school(school_x: float) -> void:
	if passengers > 0:
		var per_person := energy_per_person(passengers, route_distance)
		var earned := score_for_trip(passengers, route_distance)
		_spawn_dropoff_students(school_x, passengers)
		delivered_total += passengers
		arcade_event.emit(earned, true, "학생 %d명 도착 · 1인당 에너지 %.1f" % [passengers, per_person], true)
		_notice("학교 도착! 함께 탄 %d명의 1인당 에너지 %.1f" % [passengers, per_person])
		flash.color = Color("ffe77e42")
		flash_remaining = 0.25
	else:
		_notice("빈 버스로 학교에 왔어요. 다음 정류장에서 학생을 태워 보세요!")
	passengers = 0
	route_distance = 0.0
	trip_index += 1

func _spawn_dropoff_students(school_x: float, count: int) -> void:
	# 한 명씩 버스 문에서 나와 학교 입구로 걸어가게 하고 동시 모델 수도 제한합니다.
	for student_index in range(count):
		var local_index := student_index % 9
		var start_x := school_x + 1.1 + (float(local_index % 3) - 1.0) * 0.16
		dropped_students.append({"node": null, "age": 0.0, "delay": float(student_index) * 0.075, "start_x": start_x, "school_x": school_x, "entrance_x": school_x + SCHOOL_ENTRANCE_OFFSET, "variant": student_index % 2})

func _animate_dropoff_students(delta: float) -> void:
	for index in range(dropped_students.size() - 1, -1, -1):
		var record: Dictionary = dropped_students[index]
		record["age"] = float(record["age"]) + delta
		if float(record["age"]) < float(record["delay"]):
			continue
		if not is_instance_valid(record["node"]):
			var student_scene: PackedScene = STUDENT_A if int(record["variant"]) == 0 else STUDENT_B
			var new_student := student_scene.instantiate() as Node3D
			new_student.scale = Vector3.ONE * 0.42
			new_student.position = Vector3(float(record["start_x"]), 0.55, 2.4)
			new_student.rotation.y = PI
			world.add_child(new_student)
			var animator := new_student.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if animator:
				animator.play("walk")
			record["node"] = new_student
		var student := record["node"] as Node3D
		var progress := clampf((float(record["age"]) - float(record["delay"])) / 2.2, 0.0, 1.0)
		student.position.z = lerpf(2.4, -1.36, progress)
		student.position.x = lerpf(float(record["start_x"]), float(record["entrance_x"]), progress)
		if progress >= 1.0:
			student.queue_free()
			dropped_students.remove_at(index)

func _animate_school_doors(delta: float) -> void:
	for segment in segments.values():
		var route := segment as Dictionary
		var school_x := float(route["school_x"])
		var entrance_x := float(route["entrance_x"])
		var entering := false
		for student in dropped_students:
			if is_equal_approx(float(student["school_x"]), school_x):
				entering = true
				break
		var open_amount := move_toward(float(route["school_door_open"]), 1.0 if entering else 0.0, delta * 2.5)
		route["school_door_open"] = open_amount
		(route["school_door_left"] as Node3D).position.x = entrance_x - 0.13 - 0.28 * open_amount
		(route["school_door_right"] as Node3D).position.x = entrance_x + 0.13 + 0.28 * open_amount

func _notice(message: String) -> void:
	notice = message
	notice_remaining = 1.9

func _update_visuals() -> void:
	passenger_label.text = "승객  %d / %d명" % [passengers, BUS_CAPACITY]
	efficiency_label.text = "1인당 에너지  %.1f" % energy_per_person(passengers, route_distance) if passengers > 0 else "1인당 에너지  --"
	var direction := "후진" if bus_speed < -STOP_SPEED_LIMIT else "전진" if bus_speed > STOP_SPEED_LIMIT else "정차"
	route_label.text = "%s %.1f · 에너지 %.1f" % [direction, absf(bus_speed), route_energy(route_distance)]
	action_label.text = notice if notice_remaining > 0.0 else "D/A 길게 가속 · S 정차 · 정류장 Space · 학교 정차 시 하차"

func _update_camera_and_bus() -> void:
	bus.position = Vector3(bus_x, 0.12, 1.1)
	camera.position = Vector3(bus_x + 5.0, 5.4, 12.5)
	camera.look_at(Vector3(bus_x + 5.0, 1.30, 0), Vector3.UP)

func _box(parent: Node3D, where: Vector3, dimensions: Vector3, color: Color, glowing: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = where
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.74
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.65
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _label3d(parent: Node3D, content: String, where: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.position = where
	label.text = content
	label.modulate = color
	label.font_size = 42
	label.pixel_size = 0.008
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
