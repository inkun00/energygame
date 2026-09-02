extends Node3D
class_name TileMarker3D

## TileMarker3D: 기존 사다리 게임 칸을 입체 블록으로 표현합니다.

var tile_index: int = 0
var tile_data: Dictionary = {}
var block_mesh: MeshInstance3D
var num_label: Label3D
var border_mesh: MeshInstance3D
var hover_tween: Tween
var base_position: Vector3
var base_scale := Vector3.ONE

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
	border_material.albedo_color = Color(0.84, 0.69, 0.24)
	border_material.metallic = 0.72
	border_material.roughness = 0.24
	border_mesh.material_override = border_material
	add_child(border_mesh)
	move_child(border_mesh, 0)
	
	# 2. 타입별 3D 머티리얼 세팅
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.3
	mat.metallic = 0.2
	
	var t_type = tile_data.get("type", BoardGrid.TileType.QUIZ_OX)
	match t_type:
		BoardGrid.TileType.START:
			mat.albedo_color = Color(0.12, 0.58, 0.28) # 출발 에메랄드
			mat.emission_enabled = true
			mat.emission = Color(0.15, 0.65, 0.32) * 0.4
		BoardGrid.TileType.FINISH:
			mat.albedo_color = Color(0.85, 0.65, 0.12) # 골든 챔피언
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.85, 0.2) * 0.5
		BoardGrid.TileType.LADDER:
			mat.albedo_color = Color(0.88, 0.62, 0.10) # 황금 사다리
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.75, 0.15) * 0.35
		BoardGrid.TileType.SLIDE:
			mat.albedo_color = Color(0.78, 0.18, 0.20) # 낭비 미끄럼틀
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.2, 0.2) * 0.3
		BoardGrid.TileType.POWERPLANT:
			mat.albedo_color = Color(0.15, 0.52, 0.82) # 청정 발전소
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.6, 0.9) * 0.35
		BoardGrid.TileType.CHANCE_CARD:
			mat.albedo_color = Color(0.32, 0.45, 0.78)
		BoardGrid.TileType.REST_TURN:
			mat.albedo_color = Color(0.28, 0.48, 0.52)
		_:
			mat.albedo_color = Color(0.18, 0.26, 0.38) # 퀴즈 칸
				
	block_mesh.material_override = mat

	# 3. 게임판에는 칸 번호만 표시합니다. 재료 오브젝트가 중앙에 떠 있으므로
	# 번호는 앞쪽에 배치해 확대했을 때도 가리지 않게 합니다.
	num_label = Label3D.new()
	num_label.text = str(idx)
	num_label.font_size = 58
	num_label.outline_size = 12
	num_label.modulate = Color(1.0, 0.95, 0.6)
	num_label.outline_modulate = Color(0, 0, 0, 1)
	num_label.position = Vector3(0, tile_size.y * 0.5 + 0.025, 0.52)
	num_label.rotation_degrees = Vector3(-90, 0, 0)
	add_child(num_label)

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
