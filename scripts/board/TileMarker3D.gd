extends Node3D
class_name TileMarker3D

## TileMarker3D: 기존 사다리 게임 칸을 입체 블록으로 표현합니다.

var tile_index: int = 0
var tile_data: Dictionary = {}
var block_mesh: MeshInstance3D
var num_label: Label3D
var border_mesh: MeshInstance3D
var block_material: StandardMaterial3D
var target_ring: MeshInstance3D
var target_ring_material: StandardMaterial3D
var hover_tween: Tween
var base_position: Vector3
var base_scale := Vector3.ONE
var skill_targetable := false
var target_pulse_elapsed := 0.0
var base_emission_enabled := false
var base_emission := Color.BLACK
var minigame_completed := false
var kind_badge: MeshInstance3D
var kind_label: Label3D
var kind_material: StandardMaterial3D
var route_ring: MeshInstance3D
var route_material: StandardMaterial3D
var route_current := false
var route_destination := false
var route_visible := false

func setup_tile_3d(idx: int) -> void:
	tile_index = idx
	tile_data = BoardGrid.get_tile_data(idx)
	var pos: Vector3 = BoardGrid.get_tile_position_3d(idx)
	position = pos
	base_position = pos

	var is_terminal := idx in [0, BoardGrid.LAST_TILE_INDEX]
	var tile_size := Vector3(1.76, 0.40, 1.76) if is_terminal else Vector3(1.66, 0.34, 1.66)
	
	# 1. 3D 베이스 블록 (입체 큐브)
	block_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = tile_size
	block_mesh.mesh = box
	add_child(block_mesh)

	# 블록 아래에 살짝 큰 금속 받침을 두어 입체적인 보드 피스처럼 보이게 합니다.
	border_mesh = MeshInstance3D.new()
	var border_box := BoxMesh.new()
	border_box.size = tile_size + Vector3(0.10, 0.05, 0.10)
	border_mesh.mesh = border_box
	border_mesh.position = Vector3(0, -0.055, 0)
	var border_material := StandardMaterial3D.new()
	border_material.albedo_color = Color("456d5c")
	border_material.metallic = 0.05
	border_material.roughness = 0.85
	border_mesh.material_override = border_material
	add_child(border_mesh)
	move_child(border_mesh, 0)
	
	# 2. 타입별 3D 머티리얼 세팅. 게임을 새로 시작할 때에는 메시와
	# 노드를 다시 만들지 않고 이 머티리얼만 갱신합니다.
	block_material = StandardMaterial3D.new()
	block_material.roughness = 0.85
	block_material.metallic = 0.0
	block_mesh.material_override = block_material
	_refresh_tile_style()
	_create_target_ring(tile_size.y)

	# 3. 게임판에는 칸 번호만 표시합니다. 재료 오브젝트가 중앙에 있으므로
	# 번호는 앞쪽에 배치해 확대했을 때도 가리지 않게 합니다.
	num_label = Label3D.new()
	num_label.text = str(idx)
	num_label.font_size = 58
	num_label.outline_size = 12
	num_label.modulate = Color("f4eddb")
	num_label.outline_modulate = Color(0, 0, 0, 1)
	num_label.position = Vector3(0, tile_size.y * 0.5 + 0.025, 0.52)
	num_label.rotation_degrees = Vector3(-90, 0, 0)
	add_child(num_label)
	_create_kind_badge(tile_size.y)
	_create_route_ring(tile_size.y)
	_refresh_kind_badge()

func refresh_tile_data() -> void:
	tile_data = BoardGrid.get_tile_data(tile_index)
	_refresh_tile_style()

func set_minigame_completed(is_completed: bool) -> void:
	minigame_completed = is_completed
	_refresh_tile_style()

func _refresh_tile_style() -> void:
	if block_material == null:
		return
	block_material.emission_enabled = false
	block_material.emission = Color.BLACK
	block_material.emission_energy_multiplier = 1.0
	var t_type = tile_data.get("type", BoardGrid.TileType.QUIZ_OX)
	match t_type:
		BoardGrid.TileType.START: block_material.albedo_color = Color("91c98a")
		BoardGrid.TileType.FINISH: block_material.albedo_color = Color("e7c878")
		BoardGrid.TileType.LADDER: block_material.albedo_color = Color("dbbe77")
		BoardGrid.TileType.SLIDE: block_material.albedo_color = Color("d99486")
		BoardGrid.TileType.POWERPLANT: block_material.albedo_color = Color("8fc4be")
		BoardGrid.TileType.CHANCE_CARD: block_material.albedo_color = Color("a6abd1")
		BoardGrid.TileType.REST_TURN: block_material.albedo_color = Color("a9bfa2")
		BoardGrid.TileType.MINIGAME:
			block_material.albedo_color = Color("84998c") if minigame_completed else Color("b29bd9")
			block_material.emission_enabled = not minigame_completed
			block_material.emission = Color("7a35aa") if not minigame_completed else Color.BLACK
			block_material.emission_energy_multiplier = 0.35
		_: block_material.albedo_color = Color("91b9b6")
	base_emission_enabled = block_material.emission_enabled
	base_emission = block_material.emission
	_refresh_kind_badge()

func _create_kind_badge(tile_height: float) -> void:
	# A small solid badge + Korean word remains readable without relying on hue.
	# Reuse these two nodes when shortcuts and completed minigames change.
	kind_badge = MeshInstance3D.new()
	kind_badge.name = "TileKindBadge"
	kind_badge.position = Vector3(-0.35, tile_height * 0.5 + 0.035, -0.50)
	kind_material = StandardMaterial3D.new()
	kind_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	kind_material.albedo_color = Color("153b43")
	kind_badge.material_override = kind_material
	add_child(kind_badge)
	kind_label = Label3D.new()
	kind_label.name = "TileKindLabel"
	kind_label.font_size = 47
	kind_label.pixel_size = 0.0045
	kind_label.outline_size = 5
	kind_label.modulate = Color("f6f4df")
	kind_label.outline_modulate = Color("17343b")
	kind_label.position = kind_badge.position + Vector3(0, 0.045, 0)
	kind_label.rotation_degrees.x = -90.0
	add_child(kind_label)

func _refresh_kind_badge() -> void:
	if kind_badge == null or kind_label == null:
		return
	var type: int = tile_data.get("type", BoardGrid.TileType.QUIZ_OX)
	var word := "퀴즈"
	var sides := 16
	var color := Color("315f72")
	match type:
		BoardGrid.TileType.START:
			word = "출발"
			color = Color("306f58")
		BoardGrid.TileType.FINISH:
			word = "완주"
			color = Color("a26e26")
		BoardGrid.TileType.LADDER:
			word = "상승"
			sides = 3
			color = Color("9a762e")
		BoardGrid.TileType.SLIDE:
			word = "하강"
			sides = 3
			color = Color("a34f48")
		BoardGrid.TileType.POWERPLANT:
			word = "발전"
			sides = 6
			color = Color("2d7373")
		BoardGrid.TileType.CHANCE_CARD:
			word = "보너스"
			sides = 4
			color = Color("6b558a")
		BoardGrid.TileType.REST_TURN:
			word = "쉼"
			sides = 4
			color = Color("607264")
		BoardGrid.TileType.MINIGAME:
			word = "완료" if minigame_completed else "미니"
			sides = 6
			color = Color("455d61") if minigame_completed else Color("744e91")
	kind_label.text = word
	kind_label.modulate = Color("c0d6cd") if type == BoardGrid.TileType.MINIGAME and minigame_completed else Color("fff5d8")
	kind_material.albedo_color = color
	var mesh := kind_badge.mesh as CylinderMesh
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = 0.34
		mesh.bottom_radius = 0.34
		mesh.height = 0.025
		mesh.rings = 1
		kind_badge.mesh = mesh
	mesh.radial_segments = sides
	kind_badge.scale = Vector3(1.24 if word.length() > 2 else 1.0, 1.0, 0.64)
	kind_badge.rotation.y = PI if type == BoardGrid.TileType.SLIDE else 0.0

func _create_route_ring(tile_height: float) -> void:
	route_ring = MeshInstance3D.new()
	route_ring.name = "MovementRouteRing"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.74
	ring.outer_radius = 0.80
	ring.rings = 20
	ring.ring_segments = 4
	route_ring.mesh = ring
	route_ring.position.y = tile_height * 0.5 + 0.065
	route_material = StandardMaterial3D.new()
	route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	route_ring.material_override = route_material
	route_ring.visible = false
	add_child(route_ring)

func set_route_state(is_current: bool, is_destination: bool, on_route: bool) -> void:
	route_current = is_current
	route_destination = is_destination
	route_visible = is_current or is_destination or on_route
	if route_ring:
		route_ring.visible = route_visible
		route_material.albedo_color = Color("ffd166") if is_current or is_destination else Color("77dece")
		route_ring.scale = Vector3.ONE * (1.05 if is_destination else 1.0)

func _process(delta: float) -> void:
	if not skill_targetable or target_ring == null:
		return
	target_pulse_elapsed += delta
	var pulse := 1.0 + sin(target_pulse_elapsed * 5.2) * 0.11
	target_ring.scale = Vector3.ONE * pulse
	target_ring.rotation.y += delta * 0.85
	if target_ring_material:
		target_ring_material.emission_energy_multiplier = 1.8 + (sin(target_pulse_elapsed * 5.2) + 1.0) * 0.55

func _create_target_ring(tile_height: float) -> void:
	target_ring = MeshInstance3D.new()
	target_ring.name = "SkillTargetRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.66
	torus.outer_radius = 0.79
	torus.rings = 32
	torus.ring_segments = 10
	target_ring.mesh = torus
	target_ring.position = Vector3(0.0, tile_height * 0.5 + 0.08, 0.0)
	target_ring_material = StandardMaterial3D.new()
	target_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_ring_material.albedo_color = Color(0.25, 1.0, 0.72, 0.92)
	target_ring_material.emission_enabled = true
	target_ring_material.emission = Color("55ffd0")
	target_ring_material.emission_energy_multiplier = 2.2
	target_ring.material_override = target_ring_material
	target_ring.visible = false
	add_child(target_ring)

func set_skill_targetable(is_targetable: bool) -> void:
	skill_targetable = is_targetable
	target_pulse_elapsed = 0.0
	if target_ring:
		target_ring.visible = is_targetable
		target_ring.scale = Vector3.ONE
	if block_material:
		if is_targetable:
			block_material.emission_enabled = true
			block_material.emission = Color("3dffc5")
			block_material.emission_energy_multiplier = 0.95
		else:
			block_material.emission_enabled = base_emission_enabled
			block_material.emission = base_emission
			block_material.emission_energy_multiplier = 1.0

func set_hovered(is_hovered: bool) -> void:
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()
	hover_tween = create_tween().set_parallel(true)
	var target_scale := Vector3(1.08, 1.08, 1.08) if is_hovered else base_scale
	var target_position := base_position + Vector3(0, 0.14, 0) if is_hovered else base_position
	hover_tween.tween_property(self, "scale", target_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "position", target_position, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func play_click_feedback() -> void:
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.tween_property(self, "scale", Vector3(0.94, 1.16, 0.94), 0.08).set_trans(Tween.TRANS_QUAD)
	hover_tween.tween_property(self, "scale", Vector3(1.08, 1.08, 1.08), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
