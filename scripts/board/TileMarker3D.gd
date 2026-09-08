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
	border_material.albedo_color = Color("657568")
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
		BoardGrid.TileType.START: block_material.albedo_color = Color("51876a")
		BoardGrid.TileType.FINISH: block_material.albedo_color = Color("b69852")
		BoardGrid.TileType.LADDER: block_material.albedo_color = Color("b79d64")
		BoardGrid.TileType.SLIDE: block_material.albedo_color = Color("aa6460")
		BoardGrid.TileType.POWERPLANT: block_material.albedo_color = Color("508b91")
		BoardGrid.TileType.CHANCE_CARD: block_material.albedo_color = Color("7b789b")
		BoardGrid.TileType.REST_TURN: block_material.albedo_color = Color("73877b")
		BoardGrid.TileType.MINIGAME:
			block_material.albedo_color = Color("59676b") if minigame_completed else Color("9b5fc0")
			block_material.emission_enabled = not minigame_completed
			block_material.emission = Color("7a35aa") if not minigame_completed else Color.BLACK
			block_material.emission_energy_multiplier = 0.35
		_: block_material.albedo_color = Color("4f6a80")
	base_emission_enabled = block_material.emission_enabled
	base_emission = block_material.emission

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
