extends Node3D
class_name EnergyFairyVillage3D

## 보드 바깥의 빈 월드를 에너지요정 마을로 채우는 경량 로우폴리 3D 배경입니다.

const MODELS = preload("res://scripts/board/VillageSceneryModel.gd")
const COTTAGES := ["cottage", "cottage_sage", "cottage_blue"]
const TREES := ["broadleaf", "broadleaf_sage", "broadleaf_lime"]
const TURBINE_BLADE = preload("res://assets/models/wind/turbine_blade.glb")
const FINISH_CRANE = preload("res://assets/models/board/finish_crane.glb")

var animated_rotors: Array[Node3D] = []
var floating_lights: Array[Node3D] = []
var elapsed := 0.0
var crane_jib: Node3D
var crane_cable: Node3D
var crane_hook: Node3D
var crane_rope_length := 0.0

var scenery_groups: Array[Node3D] = []
var cutaway_hidden_count := 0

func update_cutaway_view(camera_position: Vector3, focus_position: Vector3, enabled: bool) -> void:
	# Hide only tall decorative groups in the foreground sight corridor. A bool
	# cutaway works in the low-end Compatibility renderer without alpha overdraw,
	# extra viewports, raycasts, shadow maps or per-frame material duplication.
	var sight := focus_position - camera_position
	var distance := sight.length()
	var direction := sight / maxf(distance, 0.001)
	cutaway_hidden_count = 0
	for group in scenery_groups:
		if not is_instance_valid(group):
			continue
		var center := group.global_position + Vector3.UP * float(group.get_meta("cutaway_height", 1.1))
		var offset := center - camera_position
		var along := offset.dot(direction)
		var radius := float(group.get_meta("cutaway_radius", 1.5))
		var side_distance := (offset - direction * along).length()
		var in_sight_corridor := along > 0.0 and along < distance - 0.25 and side_distance < radius + 3.0
		var too_close := offset.length() < radius + 6.0
		group.visible = not (enabled and (in_sight_corridor or too_close))
		if not group.visible:
			cutaway_hidden_count += 1

func _register_scenery(group: Node3D, radius: float = 1.5, height: float = 1.1) -> void:
	group.set_meta("cutaway_radius", radius)
	group.set_meta("cutaway_height", height)
	scenery_groups.append(group)

func build_village() -> void:
	name = "EnergyFairyVillageBackdrop"
	_place("island", Vector3.ZERO)
	_build_waterways_and_paths()
	_build_fairy_neighborhoods()
	_build_renewable_gardens()
	_build_finish_crane()
	_build_forest_ring()
	_build_distant_hills()
	set_process(true)

func _process(delta: float) -> void:
	elapsed += delta
	if crane_jib and crane_jib.is_visible_in_tree():
		crane_jib.rotation.y = sin(elapsed * 0.39) * 0.14
		var payout := 0.82 + 0.18 * cos(elapsed * 0.83)
		crane_cable.scale.y = payout
		crane_hook.position.y = crane_cable.position.y - crane_rope_length * payout
	for rotor_index in range(animated_rotors.size()):
		var rotor := animated_rotors[rotor_index]
		if is_instance_valid(rotor):
			rotor.rotation.z -= delta * (0.72 + rotor_index * 0.08)
	for light_index in range(floating_lights.size()):
		var light := floating_lights[light_index]
		if is_instance_valid(light):
			var base_y := float(light.get_meta("base_y", light.position.y))
			light.position.y = base_y + sin(elapsed * 1.35 + light_index * 0.83) * float(light.get_meta("amplitude", 0.09))
			light.rotation.y += delta * 0.34

func _build_finish_crane() -> void:
	var crane := FINISH_CRANE.instantiate() as Node3D
	crane.name = "FinishConstructionCrane"
	var finish := BoardGrid.get_tile_position_3d(BoardGrid.LAST_TILE_INDEX)
	# The site stands on the plaza beyond the back-left corner of the finish.
	crane.position = Vector3(finish.x - 1.82, -0.245, finish.z - 1.87)
	crane.rotation.y = PI - 0.18
	add_child(crane)
	_register_scenery(crane, 1.4, 1.35)
	crane_jib = crane.get_node("Jib")
	crane_cable = crane_jib.get_node("HoistCable")
	crane_hook = crane_jib.get_node("HookBlock")
	crane_rope_length = crane_cable.position.y - crane_hook.position.y

func _place(model_id: String, point: Vector3) -> MeshInstance3D:
	var model := MODELS.make(model_id)
	model.position = point
	add_child(model)
	return model

func _build_waterways_and_paths() -> void:
	for bridge_z in [-7.0, 0.0, 7.0]:
		_place("footbridge", Vector3(-15.0, -0.26, bridge_z))
	for bridge_z in [-5.2, 5.2]:
		var bridge := _place("footbridge", Vector3(15.2, -0.26, bridge_z))
		bridge.scale.x = 0.74

func _build_fairy_neighborhoods() -> void:
	var house_positions := [
		Vector3(-20.1, -0.2, -7.1), Vector3(-19.2, -0.2, -1.7), Vector3(-20.2, -0.2, 4.0), Vector3(-17.9, -0.2, 10.5),
		Vector3(20.1, -0.2, -7.5), Vector3(19.1, -0.2, -2.0), Vector3(20.0, -0.2, 4.5), Vector3(17.4, -0.2, 10.6),
		Vector3(-8.0, -0.2, 13.1), Vector3(0.2, -0.2, 13.2), Vector3(8.3, -0.2, 13.0),
		Vector3(-7.4, -0.2, -13.0), Vector3(1.0, -0.2, -13.1), Vector3(8.8, -0.2, -12.8)
	]
	for house_index in range(house_positions.size()):
		_build_fairy_house(house_positions[house_index], house_index)
	# 턴 카메라가 보드 모서리를 확대했을 때도 주택이 보이도록 보드 바로 바깥에 작은 집을 둡니다.
	var nearby_houses := [Vector3(-12.7, -0.2, -3.7), Vector3(-12.7, -0.2, 3.3), Vector3(12.8, -0.2, -3.5), Vector3(12.8, -0.2, 3.5)]
	for nearby_index in range(nearby_houses.size()):
		_build_fairy_house(nearby_houses[nearby_index], house_positions.size() + nearby_index, 0.68)

	# 마을 입구의 에너지 관문
	_build_energy_gateway(Vector3(-12.8, -0.18, 9.0), PI * 0.5)
	_build_energy_gateway(Vector3(12.8, -0.18, -8.6), PI * 0.5)

func _build_fairy_house(point: Vector3, house_index: int, scale_value: float = 1.0) -> void:
	var house := _place(COTTAGES[house_index % COTTAGES.size()], Vector3(point.x, -0.27, point.z))
	# Inward-facing porches keep the doors visible from the board.
	house.rotation.y = atan2(-point.x, -point.z) + 0.12 * sin(house_index * 1.6)
	house.scale = Vector3.ONE * scale_value
	_register_scenery(house, 1.5 * scale_value, 1.3 * scale_value)
	_build_floating_orb(house, Vector3(0.0, 2.88, 0.0), house_index)

func _build_energy_gateway(point: Vector3, yaw: float) -> void:
	var gateway := _place("gateway", Vector3(point.x, -0.27, point.z))
	gateway.rotation.y = yaw
	_register_scenery(gateway, 1.5, 1.4)
	_build_floating_orb(gateway, Vector3(0.0, 2.83, 0.0), 0)

func _build_renewable_gardens() -> void:
	# 왼쪽 수로 너머의 풍력 언덕
	for turbine_data in [[Vector3(-22.0, 0, -11.0), 0.0], [Vector3(-18.6, 0, -12.7), 0.2], [Vector3(-21.5, 0, 10.8), -0.18]]:
		_build_wind_turbine(turbine_data[0], float(turbine_data[1]))
	# 오른쪽의 태양광 정원
	for x_offset in range(3):
		for z_offset in range(2):
			_build_solar_panel(Vector3(14.0 + x_offset * 2.0, 0.0, 10.8 + z_offset * 1.45), -0.10 + x_offset * 0.05)
	# 수로를 따라 빛나는 에너지 수정
	var crystal_positions := [Vector3(-13.1, 0, -10.0), Vector3(-13.2, 0, -3.5), Vector3(-13.0, 0, 3.7), Vector3(-12.8, 0, 10.4), Vector3(13.1, 0, -10.0), Vector3(13.0, 0, 10.2)]
	for crystal_index in range(crystal_positions.size()):
		_build_crystal_cluster(crystal_positions[crystal_index], crystal_index)

func _build_wind_turbine(point: Vector3, yaw: float) -> void:
	var turbine := _place("turbine_mast", Vector3(point.x, -0.28, point.z))
	turbine.rotation.y = yaw
	_register_scenery(turbine, 1.7, 3.0)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 4.45, 0.29)
	rotor.rotation.z = yaw * 2.0
	turbine.add_child(rotor)
	var cap := MODELS.make("beacon2")
	cap.scale = Vector3(0.76, 0.76, 1.1)
	cap.rotation.x = PI * 0.5
	rotor.add_child(cap)
	for blade_index in range(3):
		var blade := TURBINE_BLADE.instantiate() as Node3D
		blade.rotation.z = blade_index * TAU / 3.0
		rotor.add_child(blade)
	animated_rotors.append(rotor)

func _build_solar_panel(point: Vector3, yaw: float) -> void:
	var panel := _place("solar_array", Vector3(point.x, -0.27, point.z))
	panel.rotation.y = yaw

func _build_crystal_cluster(point: Vector3, index: int) -> void:
	var cluster := _place("crystal%d" % (index % 4), Vector3(point.x, -0.27, point.z))
	cluster.scale = Vector3.ONE * 0.8
	cluster.rotation.y = index * 0.73
	_register_scenery(cluster, 0.8, 0.9)
	_build_floating_orb(cluster, Vector3(0.08, 1.96, 0), index)

func _build_forest_ring() -> void:
	var tree_positions := [
		Vector3(-22.0, 0, -4.2), Vector3(-22.2, 0, 1.1), Vector3(-21.7, 0, 7.4), Vector3(-17.1, 0, -10.8), Vector3(-11.0, 0, -12.8),
		Vector3(-3.8, 0, -13.7), Vector3(5.0, 0, -13.6), Vector3(12.8, 0, -13.0), Vector3(20.8, 0, -10.5), Vector3(22.0, 0, -4.6),
		Vector3(22.1, 0, 1.0), Vector3(21.8, 0, 7.2), Vector3(12.6, 0, 13.1), Vector3(4.5, 0, 14.0), Vector3(-4.2, 0, 14.0), Vector3(-12.8, 0, 13.0)
	]
	for tree_index in range(tree_positions.size()):
		_build_tree(tree_positions[tree_index], 0.85 + (tree_index % 3) * 0.12, tree_index)
	# 수로와 집 사이의 작은 마법 등불
	for z_value in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_build_lantern(Vector3(-16.9, 0, z_value), int(z_value + 8.0))
		_build_lantern(Vector3(16.9, 0, z_value), int(z_value + 13.0))

func _build_tree(point: Vector3, scale_value: float, index: int) -> void:
	var tree := _place(TREES[index % TREES.size()], Vector3(point.x, -0.28, point.z))
	tree.rotation.y = index * 1.22
	tree.scale = Vector3.ONE * scale_value
	_register_scenery(tree, 1.25 * scale_value, 1.4 * scale_value)
	if index % 3 == 0:
		_build_floating_orb(tree, Vector3(0.1, 2.98, 0), index)

func _build_lantern(point: Vector3, index: int) -> void:
	var lantern := _place("lantern_post", Vector3(point.x, -0.27, point.z))
	var light := _build_floating_orb(lantern, Vector3(0, 1.55, 0), index)
	light.set_meta("amplitude", 0.035)

func _build_floating_orb(parent: Node3D, point: Vector3, index: int) -> Node3D:
	var light := MODELS.make("beacon%d" % posmod(index, 4))
	light.position = point
	light.set_meta("base_y", point.y)
	parent.add_child(light)
	floating_lights.append(light)
	return light

func _build_distant_hills() -> void:
	# Both low ridgelines are fitted in island coordinates, tapering below the grass.
	_place("hill", Vector3.ZERO)
	_place("hill_east", Vector3.ZERO)
