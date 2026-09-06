extends Node3D
class_name EnergyFairyVillage3D

## 보드 바깥의 빈 월드를 에너지요정 마을로 채우는 경량 로우폴리 3D 배경입니다.

var animated_rotors: Array[Node3D] = []
var floating_lights: Array[Node3D] = []
var elapsed := 0.0

var grass_material: StandardMaterial3D
var path_material: StandardMaterial3D
var water_material: StandardMaterial3D
var wood_material: StandardMaterial3D
var leaf_materials: Array[StandardMaterial3D] = []
var glow_materials: Array[StandardMaterial3D] = []

func build_village() -> void:
	name = "EnergyFairyVillageBackdrop"
	_create_materials()
	_build_island_ground()
	_build_waterways_and_paths()
	_build_fairy_neighborhoods()
	_build_renewable_gardens()
	_build_forest_ring()
	_build_distant_hills()
	set_process(true)

func _process(delta: float) -> void:
	elapsed += delta
	for rotor_index in range(animated_rotors.size()):
		var rotor := animated_rotors[rotor_index]
		if is_instance_valid(rotor):
			rotor.rotation.z += delta * (0.72 + rotor_index * 0.08)
	for light_index in range(floating_lights.size()):
		var light := floating_lights[light_index]
		if is_instance_valid(light):
			var base_y := float(light.get_meta("base_y", light.position.y))
			light.position.y = base_y + sin(elapsed * 1.35 + light_index * 0.83) * 0.18
			light.rotation.y += delta * 0.34

func _create_materials() -> void:
	grass_material = _material(Color("204b35"), 0.92)
	path_material = _material(Color("a98c58"), 0.86)
	water_material = _material(Color("176f85"), 0.24, Color("12566d"), 0.22)
	wood_material = _material(Color("744b2b"), 0.82)
	leaf_materials = [
		_material(Color("2d8d52"), 0.9),
		_material(Color("49a85e"), 0.9),
		_material(Color("58b47a"), 0.88),
		_material(Color("6d9f4f"), 0.9)
	]
	glow_materials = [
		_material(Color("75f4cf"), 0.2, Color("45d8bd"), 0.3),
		_material(Color("ffe36d"), 0.2, Color("ffc83d"), 0.3),
		_material(Color("77d9ff"), 0.2, Color("39aee8"), 0.3),
		_material(Color("c89cff"), 0.2, Color("9c68e8"), 0.3)
	]

func _build_island_ground() -> void:
	_add_box(self, Vector3(0, -0.62, 0), Vector3(49.0, 0.62, 42.0), grass_material)
	var lower_soil := _material(Color("694b30"), 1.0)
	_add_box(self, Vector3(0, -1.14, 0), Vector3(46.5, 0.55, 39.5), lower_soil)
	# 보드와 마을 사이를 연결하는 밝은 석재 광장입니다.
	var plaza_material := _material(Color("769a78"), 0.92)
	_add_box(self, Vector3(0, -0.285, 0), Vector3(BoardGrid.BOARD_WIDTH_3D + 2.0, 0.08, BoardGrid.BOARD_DEPTH_3D + 2.0), plaza_material)

func _build_waterways_and_paths() -> void:
	# 보드 왼쪽의 큰 수로가 플레이어 근접 카메라에서 가장 넓게 보이는 빈 영역을 채웁니다.
	_add_box(self, Vector3(-15.0, -0.25, 0), Vector3(2.4, 0.12, 29.0), water_material)
	_add_box(self, Vector3(15.2, -0.25, 0), Vector3(1.4, 0.10, 29.0), water_material)
	_add_box(self, Vector3(0, -0.24, -10.7), Vector3(31.0, 0.10, 1.2), water_material)

	_add_box(self, Vector3(-18.4, -0.24, 0), Vector3(1.15, 0.10, 25.0), path_material)
	_add_box(self, Vector3(18.3, -0.24, 0), Vector3(1.10, 0.10, 25.0), path_material)
	_add_box(self, Vector3(0, -0.23, 9.0), Vector3(39.0, 0.11, 1.0), path_material)
	_add_box(self, Vector3(0, -0.23, -8.6), Vector3(39.0, 0.11, 1.0), path_material)

	for bridge_z in [-7.0, 0.0, 7.0]:
		_build_bridge(Vector3(-15.0, -0.05, bridge_z), 3.4)
	for bridge_z in [-5.2, 5.2]:
		_build_bridge(Vector3(15.2, -0.05, bridge_z), 2.3)

func _build_bridge(center: Vector3, width: float) -> void:
	_add_box(self, center, Vector3(width, 0.16, 1.0), wood_material)
	for offset_x in [-width * 0.42, width * 0.42]:
		_add_box(self, center + Vector3(offset_x, 0.35, -0.43), Vector3(0.10, 0.72, 0.10), wood_material)
		_add_box(self, center + Vector3(offset_x, 0.35, 0.43), Vector3(0.10, 0.72, 0.10), wood_material)

func _build_fairy_neighborhoods() -> void:
	var house_positions := [
		Vector3(-20.1, -0.2, -7.1), Vector3(-19.2, -0.2, -1.7), Vector3(-20.2, -0.2, 4.0), Vector3(-17.9, -0.2, 10.5),
		Vector3(20.1, -0.2, -7.5), Vector3(19.1, -0.2, -2.0), Vector3(20.0, -0.2, 4.5), Vector3(17.4, -0.2, 10.6),
		Vector3(-8.0, -0.2, 13.1), Vector3(0.2, -0.2, 13.2), Vector3(8.3, -0.2, 13.0),
		Vector3(-7.4, -0.2, -13.0), Vector3(1.0, -0.2, -13.1), Vector3(8.8, -0.2, -12.8)
	]
	var wall_colors := [Color("eff0bf"), Color("bfe8d2"), Color("c9ddff"), Color("e8c7f4"), Color("f2d0a6")]
	var roof_colors := [Color("e06752"), Color("437d6b"), Color("456fa5"), Color("8b5cad"), Color("d89b3d")]
	for house_index in range(house_positions.size()):
		_build_fairy_house(house_positions[house_index], wall_colors[house_index % wall_colors.size()], roof_colors[house_index % roof_colors.size()], house_index)
	# 턴 카메라가 보드 모서리를 확대했을 때도 주택이 보이도록 보드 바로 바깥에 작은 집을 둡니다.
	var nearby_houses := [Vector3(-12.7, -0.2, -3.7), Vector3(-12.7, -0.2, 3.3), Vector3(12.8, -0.2, -3.5), Vector3(12.8, -0.2, 3.5)]
	for nearby_index in range(nearby_houses.size()):
		_build_fairy_house(nearby_houses[nearby_index], wall_colors[(nearby_index + 1) % wall_colors.size()], roof_colors[(nearby_index + 2) % roof_colors.size()], house_positions.size() + nearby_index, 0.68)

	# 마을 입구의 에너지 관문
	_build_energy_gateway(Vector3(-12.8, -0.18, 9.0), PI * 0.5)
	_build_energy_gateway(Vector3(12.8, -0.18, -8.6), PI * 0.5)

func _build_fairy_house(position_value: Vector3, wall_color: Color, roof_color: Color, house_index: int, scale_value: float = 1.0) -> void:
	var house := Node3D.new()
	house.position = position_value
	house.rotation.y = (house_index % 4) * PI * 0.5
	house.scale = Vector3.ONE * scale_value
	add_child(house)
	var wall_material := _material(wall_color, 0.8)
	var roof_material := _material(roof_color, 0.72)
	_add_cylinder(house, Vector3(0, 0.88, 0), 1.05, 1.05, 1.7, wall_material, 10)
	_add_cylinder(house, Vector3(0, 2.0, 0), 0.0, 1.42, 1.25, roof_material, 10)
	_add_box(house, Vector3(0, 0.55, 1.0), Vector3(0.52, 0.92, 0.10), wood_material)
	var window_material := glow_materials[house_index % glow_materials.size()]
	_add_sphere(house, Vector3(-0.56, 1.0, 0.86), 0.24, window_material, 10)
	_add_sphere(house, Vector3(0.56, 1.0, 0.86), 0.24, window_material, 10)
	var chimney := _add_cylinder(house, Vector3(0.62, 2.18, -0.18), 0.12, 0.16, 0.72, wood_material, 8)
	chimney.rotation.z = -0.08
	_build_floating_orb(house, Vector3(0, 3.05, 0), window_material, house_index)

func _build_energy_gateway(position_value: Vector3, yaw: float) -> void:
	var gateway := Node3D.new()
	gateway.position = position_value
	gateway.rotation.y = yaw
	add_child(gateway)
	var stone := _material(Color("b8c7a3"), 0.8)
	_add_box(gateway, Vector3(-1.0, 1.05, 0), Vector3(0.38, 2.3, 0.55), stone)
	_add_box(gateway, Vector3(1.0, 1.05, 0), Vector3(0.38, 2.3, 0.55), stone)
	_add_box(gateway, Vector3(0, 2.15, 0), Vector3(2.35, 0.34, 0.55), stone)
	_build_floating_orb(gateway, Vector3(0, 2.72, 0), glow_materials[0], floating_lights.size())

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

func _build_wind_turbine(position_value: Vector3, yaw: float) -> void:
	var turbine := Node3D.new()
	turbine.position = position_value
	turbine.rotation.y = yaw
	add_child(turbine)
	var metal := _material(Color("d9ece4"), 0.5)
	_add_cylinder(turbine, Vector3(0, 2.25, 0), 0.11, 0.24, 4.5, metal, 10)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 4.45, 0.12)
	turbine.add_child(rotor)
	_add_sphere(rotor, Vector3.ZERO, 0.25, glow_materials[2], 10)
	for blade_index in range(3):
		var blade_root := Node3D.new()
		blade_root.rotation.z = blade_index * TAU / 3.0
		rotor.add_child(blade_root)
		var blade := _add_box(blade_root, Vector3(0, 1.02, 0), Vector3(0.22, 1.72, 0.10), metal)
		blade.rotation.z = -0.10
	animated_rotors.append(rotor)

func _build_solar_panel(position_value: Vector3, yaw: float) -> void:
	var panel_root := Node3D.new()
	panel_root.position = position_value
	panel_root.rotation.y = yaw
	add_child(panel_root)
	var frame := _material(Color("a7c2c4"), 0.35)
	var cells := _material(Color("17599a"), 0.25, Color("164f89"), 0.32)
	_add_cylinder(panel_root, Vector3(0, 0.38, 0), 0.07, 0.09, 0.75, frame, 8)
	var panel := _add_box(panel_root, Vector3(0, 0.85, 0), Vector3(1.65, 0.10, 1.0), cells)
	panel.rotation.x = deg_to_rad(18.0)
	for line_x in [-0.42, 0.0, 0.42]:
		_add_box(panel_root, Vector3(line_x, 0.91, -0.03), Vector3(0.025, 0.025, 0.92), frame).rotation.x = deg_to_rad(18.0)

func _build_crystal_cluster(position_value: Vector3, crystal_index: int) -> void:
	var cluster := Node3D.new()
	cluster.position = position_value
	cluster.scale = Vector3.ONE * 0.72
	add_child(cluster)
	var glow := glow_materials[crystal_index % glow_materials.size()]
	for crystal_data in [[Vector3(-0.28, 0.55, 0.05), 0.22, 1.25], [Vector3(0.18, 0.78, 0), 0.28, 1.7], [Vector3(0.48, 0.43, 0.12), 0.18, 0.95]]:
		var crystal := _add_cylinder(cluster, crystal_data[0], 0.0, float(crystal_data[1]), float(crystal_data[2]), glow, 6)
		crystal.rotation.z = float(crystal_data[0].x) * 0.24
	_build_floating_orb(cluster, Vector3(0.08, 2.05, 0), glow, crystal_index)

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

func _build_tree(position_value: Vector3, scale_value: float, tree_index: int) -> void:
	var tree := Node3D.new()
	tree.position = position_value
	tree.scale = Vector3.ONE * scale_value
	add_child(tree)
	_add_cylinder(tree, Vector3(0, 0.72, 0), 0.20, 0.28, 1.45, wood_material, 8)
	var leaves := leaf_materials[tree_index % leaf_materials.size()]
	_add_sphere(tree, Vector3(0, 1.75, 0), 0.82, leaves, 10)
	_add_sphere(tree, Vector3(-0.48, 1.48, 0.08), 0.55, leaves, 9)
	_add_sphere(tree, Vector3(0.46, 1.48, -0.04), 0.58, leaves, 9)
	if tree_index % 3 == 0:
		_build_floating_orb(tree, Vector3(0.1, 2.48, 0), glow_materials[tree_index % glow_materials.size()], tree_index)

func _build_lantern(position_value: Vector3, light_index: int) -> void:
	var lantern := Node3D.new()
	lantern.position = position_value
	add_child(lantern)
	var metal := _material(Color("45625e"), 0.55)
	_add_cylinder(lantern, Vector3(0, 0.62, 0), 0.06, 0.09, 1.22, metal, 8)
	_build_floating_orb(lantern, Vector3(0, 1.38, 0), glow_materials[light_index % glow_materials.size()], light_index)

func _build_floating_orb(parent: Node3D, local_position: Vector3, material: StandardMaterial3D, light_index: int) -> void:
	var orb_root := Node3D.new()
	orb_root.position = local_position
	orb_root.set_meta("base_y", local_position.y)
	parent.add_child(orb_root)
	_add_sphere(orb_root, Vector3.ZERO, 0.18 if parent != self else 0.22, material, 10)
	var ring := _add_cylinder(orb_root, Vector3.ZERO, 0.31, 0.31, 0.025, material, 16)
	ring.rotation.x = PI * 0.5
	ring.rotation.z = light_index * 0.27
	floating_lights.append(orb_root)

func _build_distant_hills() -> void:
	var hill_materials := [_material(Color("365b43"), 1.0), _material(Color("3f684a"), 1.0), _material(Color("526f50"), 1.0)]
	var hill_positions := [Vector3(-23.5, -0.5, -13.5), Vector3(-15.0, -0.5, -16.0), Vector3(-5.0, -0.5, -16.7), Vector3(6.0, -0.5, -16.5), Vector3(16.0, -0.5, -15.5), Vector3(23.0, -0.5, -12.8), Vector3(-23.5, -0.5, 13.2), Vector3(23.5, -0.5, 13.0)]
	for hill_index in range(hill_positions.size()):
		_add_cylinder(self, hill_positions[hill_index] + Vector3(0, 1.1 + (hill_index % 2) * 0.4, 0), 0.3, 3.2 + (hill_index % 3) * 0.7, 3.7 + (hill_index % 2), hill_materials[hill_index % hill_materials.size()], 9)

func _material(color: Color, roughness: float, emission_color: Color = Color.TRANSPARENT, emission_strength: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = emission_strength
	return material

func _add_box(parent: Node3D, position_value: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _add_cylinder(parent: Node3D, position_value: Vector3, top_radius: float, bottom_radius: float, height: float, material: Material, segments: int) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _add_sphere(parent: Node3D, position_value: Vector3, radius: float, material: Material, segments: int) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(4, segments / 2)
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
	return instance
