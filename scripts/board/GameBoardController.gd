extends Node2D
class_name GameBoardController

## GameBoardController: 100칸 사다리 게임을 회전·확대 가능한 입체 쿼터뷰로 렌더링합니다.

const TileMarker3D = preload("res://scripts/board/TileMarker3D.gd")
const BoardItemPickup3D = preload("res://scripts/board/BoardItemPickup3D.gd")
const SpecialSkillEffect3D = preload("res://scripts/effects/SpecialSkillEffect3D.gd")
const EnergyFairyVillage3D = preload("res://scripts/board/EnergyFairyVillage3D.gd")

@onready var viewport: SubViewport = $ViewportContainer/SubViewport
@onready var viewport_container: SubViewportContainer = $ViewportContainer
@onready var world3d: Node3D = $ViewportContainer/SubViewport/World3D
@onready var camera3d: Camera3D = $ViewportContainer/SubViewport/World3D/Camera3D
@onready var world_environment: WorldEnvironment = $ViewportContainer/SubViewport/World3D/WorldEnvironment
@onready var pawns_container: Node3D = $ViewportContainer/SubViewport/World3D/PawnsContainer
@onready var tiles_container: Node3D = $ViewportContainer/SubViewport/World3D/TilesContainer
@onready var items_container: Node3D = $ViewportContainer/SubViewport/World3D/ItemsContainer
@onready var rails_container: Node3D = $ViewportContainer/SubViewport/World3D/RailsContainer
@onready var ui_layer: CanvasLayer = $UILayer
@onready var modals_layer: CanvasLayer = $Modals
@onready var hud: Control = $UILayer/HUD
@onready var quiz_modal: QuizUIController = $Modals/QuizModal

var player_pawns: Array[PlayerPawn] = []
var tile_markers: Array = []
var item_pickups: Dictionary = {}
var item_shadow_material: ShaderMaterial
var board_base_material: StandardMaterial3D
var renewable_landmarks: Node3D
var built_landmark_count := 0
var energy_fairy_village: EnergyFairyVillage3D
var hovered_tile_index: int = -1
var camera_focus := Vector3(0, 0.0, 0.4)
var camera_direction := Vector3(0.0, 13.0, 15.0).normalized()
var camera_distance := 32.0
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(41.0)
var camera_dragging := false
var camera_drag_button: int = MOUSE_BUTTON_NONE
var left_drag_pending := false
var left_drag_origin := Vector2.ZERO
var camera_zoom_tween: Tween
var camera_turn_focus_tween: Tween
var camera_follow_pawn: PlayerPawn
var camera_follow_active := false
var camera_follow_elapsed := 0.0
var camera_follow_duration := 0.0
var camera_follow_restore_focus := Vector3.ZERO
var camera_follow_restore_distance := 32.0
var camera_restore_active := false
var camera_restore_elapsed := 0.0
var camera_restore_start_focus := Vector3.ZERO
var camera_restore_start_distance := 32.0

## 이전 최대 확대(220%)보다 정확히 30% 더 가까운 거리 = 286% 확대입니다.
const CAMERA_MIN_DISTANCE := 6.53846
const CAMERA_MAX_DISTANCE := 46.0
const CAMERA_MIN_PITCH := 22.0
const CAMERA_MAX_PITCH := 72.0
const CAMERA_ORBIT_SENSITIVITY := 0.007
const CAMERA_DRAG_THRESHOLD := 6.0
# 100칸 보드 전체와 캐릭터 근접 화면을 모두 확인할 수 있는 확대 범위입니다.
const CAMERA_FOLLOW_DISTANCE := 12.0
const CAMERA_FOLLOW_HOLD_SECONDS := 1.25
const CAMERA_RESTORE_SECONDS := 0.48

func set_board_active(is_active: bool) -> void:
	visible = is_active
	if is_instance_valid(ui_layer):
		ui_layer.visible = is_active
	if is_instance_valid(modals_layer):
		modals_layer.visible = is_active
	if is_instance_valid(viewport):
		viewport.get_parent().visible = is_active

func _ready() -> void:
	# CanvasLayer는 숨겨진 부모와 별개로 표시될 수 있으므로, 로비 단계에서는
	# 3D 보드·HUD·모달을 모두 명시적으로 끕니다.
	set_board_active(false)
	_configure_3d_camera()
	_build_energy_fairy_village_backdrop()
	_build_3d_board_base()
	_build_3d_path_guides()
	_spawn_3d_tile_markers()
	_build_3d_shortcut_rails()
	# 아이템과 텍스처도 로딩 화면이 떠 있는 초기화 단계에서 한 번 만들어 둡니다.
	# 게임 시작 버튼을 누른 뒤 98개 Sprite3D를 만드는 정지를 없앱니다.
	_reset_tile_item_pickups()
	viewport_container.gui_input.connect(_on_board_gui_input)
	if hud.has_signal("board_zoom_requested"):
		hud.connect("board_zoom_requested", _zoom_board)
	if hud.has_signal("special_skill_tile_targets_changed"):
		hud.connect("special_skill_tile_targets_changed", _on_special_skill_tile_targets_changed)
	
	if GameManager:
		GameManager.turn_changed.connect(_on_turn_changed)
		GameManager.player_moved.connect(_on_player_moved)
		GameManager.player_state_changed.connect(_on_player_state_changed)
		GameManager.quiz_requested.connect(_on_quiz_requested)
		GameManager.tile_item_collected.connect(_on_tile_item_collected)
		GameManager.special_skill_activated.connect(_on_special_skill_activated)
		GameManager.kingdom_progress_changed.connect(_on_kingdom_progress_changed)
		GameManager.village_construction_started.connect(_on_village_construction_started)

func _build_energy_fairy_village_backdrop() -> void:
	if is_instance_valid(energy_fairy_village):
		return
	energy_fairy_village = EnergyFairyVillage3D.new()
	world3d.add_child(energy_fairy_village)
	energy_fairy_village.build_village()

func _process(delta: float) -> void:
	if camera_follow_active and is_instance_valid(camera_follow_pawn):
		camera_follow_elapsed += delta
		var pawn_position := camera_follow_pawn.position
		var follow_target := Vector3(pawn_position.x, 0.0, pawn_position.z)
		var follow_weight := clampf(delta * 7.5, 0.0, 1.0)
		camera_focus = camera_focus.lerp(follow_target, follow_weight)
		_apply_camera_transform()
		if camera_follow_elapsed >= camera_follow_duration:
			_finish_camera_follow()
	elif camera_restore_active:
		camera_restore_elapsed += delta
		var restore_progress := clampf(camera_restore_elapsed / CAMERA_RESTORE_SECONDS, 0.0, 1.0)
		var eased_progress := smoothstep(0.0, 1.0, restore_progress)
		camera_focus = camera_restore_start_focus.lerp(camera_follow_restore_focus, eased_progress)
		camera_distance = lerpf(camera_restore_start_distance, camera_follow_restore_distance, eased_progress)
		_apply_camera_transform()
		if restore_progress >= 1.0:
			camera_restore_active = false

func _configure_3d_camera() -> void:
	camera3d.fov = 45.0
	camera3d.current = true
	_apply_camera_distance(camera_distance)

func _apply_camera_distance(distance_value: float) -> void:
	camera_distance = clampf(distance_value, CAMERA_MIN_DISTANCE, CAMERA_MAX_DISTANCE)
	_apply_camera_transform()

func _apply_camera_transform() -> void:
	var horizontal := cos(camera_pitch)
	camera_direction = Vector3(sin(camera_yaw) * horizontal, sin(camera_pitch), cos(camera_yaw) * horizontal).normalized()
	camera3d.position = camera_focus + camera_direction * camera_distance
	camera3d.look_at(camera_focus, Vector3.UP)

func _zoom_board(direction: float) -> void:
	_cancel_camera_follow()
	var target_distance := clampf(camera_distance - direction * 2.5, CAMERA_MIN_DISTANCE, CAMERA_MAX_DISTANCE)
	if is_equal_approx(target_distance, camera_distance):
		return
	if camera_zoom_tween and camera_zoom_tween.is_valid():
		camera_zoom_tween.kill()
	camera_zoom_tween = create_tween()
	camera_zoom_tween.tween_method(_apply_camera_distance, camera_distance, target_distance, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if hud and hud.has_method("show_zoom_level"):
		var zoom_percent := int(remap(target_distance, CAMERA_MAX_DISTANCE, CAMERA_MIN_DISTANCE, 70.0, 286.0))
		hud.show_zoom_level(zoom_percent)

func _orbit_camera(mouse_delta: Vector2) -> void:
	_cancel_camera_follow()
	if camera_zoom_tween and camera_zoom_tween.is_valid():
		camera_zoom_tween.kill()
	camera_yaw -= mouse_delta.x * CAMERA_ORBIT_SENSITIVITY
	camera_pitch = clampf(
		camera_pitch + mouse_delta.y * CAMERA_ORBIT_SENSITIVITY,
		deg_to_rad(CAMERA_MIN_PITCH),
		deg_to_rad(CAMERA_MAX_PITCH)
	)
	_apply_camera_transform()

func _pan_camera(mouse_delta: Vector2) -> void:
	_cancel_camera_follow()
	if camera_zoom_tween and camera_zoom_tween.is_valid():
		camera_zoom_tween.kill()
	# 현재 확대 배율에 맞춰 화면 픽셀을 3D 보드 평면의 이동량으로 변환합니다.
	var viewport_height := maxf(float(viewport.size.y), 1.0)
	var visible_world_height := 2.0 * camera_distance * tan(deg_to_rad(camera3d.fov * 0.5))
	var world_units_per_pixel := visible_world_height / viewport_height
	var camera_right := camera3d.global_transform.basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var camera_forward := Vector3(-camera_direction.x, 0.0, -camera_direction.z)
	if camera_forward.length_squared() < 0.001:
		camera_forward = Vector3.FORWARD
	else:
		camera_forward = camera_forward.normalized()

	var pan_delta := (-camera_right * mouse_delta.x + camera_forward * mouse_delta.y) * world_units_per_pixel
	camera_focus += pan_delta
	camera_focus.x = clampf(camera_focus.x, -BoardGrid.BOARD_WIDTH_3D * 0.5, BoardGrid.BOARD_WIDTH_3D * 0.5)
	camera_focus.z = clampf(camera_focus.z, -BoardGrid.BOARD_DEPTH_3D * 0.5, BoardGrid.BOARD_DEPTH_3D * 0.5)
	camera_focus.y = 0.0
	_apply_camera_transform()

func _start_camera_follow(pawn: PlayerPawn, from_tile: int, to_tile: int) -> void:
	if not is_instance_valid(pawn):
		return
	if not camera_follow_active and not camera_restore_active:
		camera_follow_restore_focus = camera_focus
		camera_follow_restore_distance = camera_distance
	camera_restore_active = false
	camera_follow_pawn = pawn
	camera_follow_active = true
	camera_follow_elapsed = 0.0
	camera_follow_duration = BoardGrid.get_movement_duration(from_tile, to_tile) + CAMERA_FOLLOW_HOLD_SECONDS
	var follow_distance := minf(camera_distance, CAMERA_FOLLOW_DISTANCE)
	if camera_zoom_tween and camera_zoom_tween.is_valid():
		camera_zoom_tween.kill()
	# 말이 출발하는 즉시 글자를 읽을 수 있는 근접 거리로 전환합니다.
	camera_distance = follow_distance
	_apply_camera_transform()

func _finish_camera_follow() -> void:
	if not camera_follow_active:
		return
	camera_follow_active = false
	camera_follow_pawn = null
	if camera_zoom_tween and camera_zoom_tween.is_valid():
		camera_zoom_tween.kill()
	camera_restore_start_focus = camera_focus
	camera_restore_start_distance = camera_distance
	camera_restore_elapsed = 0.0
	camera_restore_active = true

func _cancel_camera_follow() -> void:
	camera_follow_active = false
	camera_restore_active = false
	camera_follow_pawn = null
	if camera_turn_focus_tween and camera_turn_focus_tween.is_valid():
		camera_turn_focus_tween.kill()

func _on_turn_changed(player_idx: int) -> void:
	_focus_camera_on_player_turn(player_idx)

func _focus_camera_on_player_turn(player_idx: int) -> void:
	if player_idx < 0 or player_idx >= player_pawns.size():
		return
	var pawn := player_pawns[player_idx]
	if not is_instance_valid(pawn):
		return
	_cancel_camera_follow()
	if camera_zoom_tween and camera_zoom_tween.is_valid():
		camera_zoom_tween.kill()
	var start_focus := camera_focus
	var target_focus := Vector3(pawn.position.x, 0.0, pawn.position.z)
	var start_distance := camera_distance
	var target_distance := minf(camera_distance, CAMERA_FOLLOW_DISTANCE)
	camera_turn_focus_tween = create_tween()
	camera_turn_focus_tween.tween_method(
		_apply_turn_focus_transition.bind(start_focus, target_focus, start_distance, target_distance),
		0.0,
		1.0,
		0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _apply_turn_focus_transition(progress: float, start_focus: Vector3, target_focus: Vector3, start_distance: float, target_distance: float) -> void:
	camera_focus = start_focus.lerp(target_focus, progress)
	camera_distance = lerpf(start_distance, target_distance, progress)
	_apply_camera_transform()

func _set_camera_dragging(is_dragging: bool, button_index: int = MOUSE_BUTTON_NONE) -> void:
	camera_dragging = is_dragging
	camera_drag_button = button_index if is_dragging else MOUSE_BUTTON_NONE
	viewport_container.mouse_default_cursor_shape = Control.CURSOR_DRAG if is_dragging else Control.CURSOR_ARROW

func _build_3d_board_base() -> void:
	# 격자 전체를 받치는 낮은 입체 보드와 금속 테두리
	var base_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BoardGrid.BOARD_WIDTH_3D, 0.38, BoardGrid.BOARD_DEPTH_3D)
	base_mesh.mesh = box
	base_mesh.position = Vector3(0, -0.2, 0)
	
	board_base_material = StandardMaterial3D.new()
	board_base_material.albedo_color = Color("263136")
	board_base_material.roughness = 0.9
	board_base_material.metallic = 0.0
	base_mesh.material_override = board_base_material
	world3d.add_child(base_mesh)
	renewable_landmarks = Node3D.new()
	renewable_landmarks.name = "RenewableLandmarks"
	world3d.add_child(renewable_landmarks)

	var rim_mesh := MeshInstance3D.new()
	var rim_box := BoxMesh.new()
	rim_box.size = Vector3(BoardGrid.BOARD_WIDTH_3D + 0.5, 0.24, BoardGrid.BOARD_DEPTH_3D + 0.5)
	rim_mesh.mesh = rim_box
	rim_mesh.position = Vector3(0, -0.28, 0)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color("738476")
	rim_mat.metallic = 0.05
	rim_mat.roughness = 0.85
	rim_mesh.material_override = rim_mat
	world3d.add_child(rim_mesh)


func _build_3d_path_guides() -> void:
	var guide_material := StandardMaterial3D.new()
	guide_material.albedo_color = Color("689b8c")
	guide_material.emission_enabled = false
	guide_material.emission = Color(0.10, 0.58, 0.50) * 0.28
	for index in range(BoardGrid.TILE_POSITIONS_3D.size() - 1):
		var from_position := BoardGrid.get_tile_position_3d(index)
		var to_position := BoardGrid.get_tile_position_3d(index + 1)
		var difference := to_position - from_position
		var guide := MeshInstance3D.new()
		var guide_box := BoxMesh.new()
		guide_box.size = Vector3(0.24, 0.07, difference.length())
		guide.mesh = guide_box
		guide.material_override = guide_material
		world3d.add_child(guide)
		guide.position = (from_position + to_position) * 0.5 + Vector3(0, -0.08, 0)
		guide.look_at(to_position + Vector3(0, -0.08, 0), Vector3.UP)

func _spawn_3d_tile_markers() -> void:
	for i in range(BoardGrid.TILE_COUNT):
		var marker = TileMarker3D.new()
		tiles_container.add_child(marker)
		marker.setup_tile_3d(i)
		tile_markers.append(marker)

func _reset_tile_item_pickups() -> void:
	# 0번 출발 칸과 99번 도착 칸을 제외한 모든 칸에 재료 하나를 배치합니다.
	# 이미 만든 오브젝트는 재사용해 게임 시작 시 노드·텍스처 할당을 반복하지 않습니다.
	for tile_idx in range(1, BoardGrid.LAST_TILE_INDEX):
		var item_id := GameManager.get_tile_item_id(tile_idx)
		if item_id.is_empty():
			continue
		var existing = item_pickups.get(tile_idx)
		if is_instance_valid(existing):
			existing.reset_pickup()
			continue
		var pickup = BoardItemPickup3D.new()
		items_container.add_child(pickup)
		pickup.setup_pickup(tile_idx, item_id, GameManager.ITEM_DEFINITIONS[item_id], item_shadow_material)
		if item_shadow_material == null:
			item_shadow_material = pickup.shadow_material
		item_pickups[tile_idx] = pickup

func _on_tile_item_collected(tile_idx: int, _player_idx: int, _item_id: String) -> void:
	if not item_pickups.has(tile_idx):
		return
	var pickup = item_pickups[tile_idx]
	item_pickups.erase(tile_idx)
	if is_instance_valid(pickup):
		pickup.collect()

func _on_board_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		if left_drag_pending and motion_event.position.distance_to(left_drag_origin) >= CAMERA_DRAG_THRESHOLD:
			left_drag_pending = false
			_set_camera_dragging(true, MOUSE_BUTTON_LEFT)
			_set_hovered_tile(-1)
			_pan_camera(motion_event.relative)
			viewport_container.accept_event()
		elif camera_dragging:
			if camera_drag_button == MOUSE_BUTTON_LEFT:
				_pan_camera(motion_event.relative)
			else:
				_orbit_camera(motion_event.relative)
			viewport_container.accept_event()
		elif not left_drag_pending:
			_set_hovered_tile(_pick_tile_at_screen_position(motion_event.position))
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mouse_event.pressed:
				left_drag_pending = false
				_set_camera_dragging(true, mouse_event.button_index)
			elif camera_drag_button == mouse_event.button_index:
				_set_camera_dragging(false)
			viewport_container.accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_board(1.0)
			viewport_container.accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_board(-1.0)
			viewport_container.accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				left_drag_pending = true
				left_drag_origin = mouse_event.position
			else:
				var completed_camera_drag := camera_dragging and camera_drag_button == MOUSE_BUTTON_LEFT
				if completed_camera_drag:
					_set_camera_dragging(false)
				elif left_drag_pending:
					var tile_index := _pick_tile_at_screen_position(mouse_event.position)
					if tile_index >= 0:
						_activate_tile(tile_index)
				left_drag_pending = false
			viewport_container.accept_event()

func _pick_tile_at_screen_position(screen_position: Vector2) -> int:
	var closest_index := -1
	var closest_distance := 52.0
	for index in range(BoardGrid.TILE_POSITIONS_3D.size()):
		var world_position := BoardGrid.get_tile_position_3d(index) + Vector3(0, 0.34, 0)
		if camera3d.is_position_behind(world_position):
			continue
		var projected := camera3d.unproject_position(world_position)
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	return closest_index

func _set_hovered_tile(tile_index: int) -> void:
	if hovered_tile_index == tile_index:
		return
	if hovered_tile_index >= 0 and hovered_tile_index < tile_markers.size():
		tile_markers[hovered_tile_index].set_hovered(false)
	hovered_tile_index = tile_index
	if hovered_tile_index >= 0 and hovered_tile_index < tile_markers.size():
		tile_markers[hovered_tile_index].set_hovered(true)
		viewport_container.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		viewport_container.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _on_special_skill_tile_targets_changed(tile_indices: Array) -> void:
	for marker in tile_markers:
		if is_instance_valid(marker):
			marker.set_skill_targetable(false)
	for tile_index_variant in tile_indices:
		var tile_index := int(tile_index_variant)
		if tile_index >= 0 and tile_index < tile_markers.size() and is_instance_valid(tile_markers[tile_index]):
			tile_markers[tile_index].set_skill_targetable(true)

func _activate_tile(tile_index: int) -> void:
	if tile_index < 0 or tile_index >= tile_markers.size():
		return
	tile_markers[tile_index].play_click_feedback()
	# 특수기술 대상 지정 중에는 타일 정보 대신 기술 대상으로 전달합니다.
	if hud and hud.has_method("try_select_special_skill_tile") and hud.try_select_special_skill_tile(tile_index):
		return
	if hud and hud.has_method("show_tile_info"):
		hud.show_tile_info(BoardGrid.get_tile_data(tile_index))

func _build_3d_shortcut_rails() -> void:
	for tile in BoardGrid.TILE_DATA:
		var tile_type: int = tile["type"]
		var from_idx: int = tile["index"]
		var to_idx: int = tile.get("target", -1)
		
		if tile_type == BoardGrid.TileType.LADDER and to_idx != -1:
			_create_3d_arch_rail(from_idx, to_idx, Color(1.0, 0.82, 0.18), "ladder")
		elif tile_type == BoardGrid.TileType.SLIDE and to_idx != -1:
			_create_3d_arch_rail(from_idx, to_idx, Color(1.0, 0.28, 0.30), "slide")

func _create_3d_arch_rail(from_idx: int, to_idx: int, rail_color: Color, kind: String) -> void:
	var from_p: Vector3 = BoardGrid.get_tile_position_3d(from_idx)
	var to_p: Vector3 = BoardGrid.get_tile_position_3d(to_idx)
	
	# 3D 아치 곡선을 따르는 실린더/박스 마그넷 레일 생성
	var segments := 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = rail_color
	mat.emission_enabled = true
	mat.emission = rail_color * 0.4
	mat.roughness = 0.2
	mat.metallic = 0.6
	var travel := (to_p - from_p).normalized()
	var side := Vector3(-travel.z, 0, travel.x).normalized() * 0.15
	
	for s in range(segments):
		var t1 := float(s) / float(segments)
		var t2 := float(s + 1) / float(segments)
		var p1 := from_p.lerp(to_p, t1) + Vector3(0, sin(t1 * PI) * 0.9 + 0.18, 0)
		var p2 := from_p.lerp(to_p, t2) + Vector3(0, sin(t2 * PI) * 0.9 + 0.18, 0)

		if kind == "ladder":
			_add_rail_piece(p1 - side, p2 - side, mat, 0.075)
			_add_rail_piece(p1 + side, p2 + side, mat, 0.075)
			if s % 2 == 0:
				_add_rail_piece(p1 - side, p1 + side, mat, 0.07)
		else:
			_add_rail_piece(p1, p2, mat, 0.14)

func _add_rail_piece(from_position: Vector3, to_position: Vector3, material: Material, width: float) -> void:
	var difference := to_position - from_position
	if difference.length_squared() <= 0.001:
		return
	var piece := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, difference.length())
	piece.mesh = box
	piece.material_override = material
	rails_container.add_child(piece)
	piece.position = (from_position + to_position) * 0.5
	piece.look_at(to_position, Vector3.UP)

func start_board_game(player_configs: Array[Dictionary], duration_seconds: int = GameManager.DEFAULT_GAME_DURATION_SECONDS) -> void:
	set_board_active(true)
	_reset_kingdom_visuals()
	# 기존 말 정리
	for child in pawns_container.get_children():
		child.queue_free()
	player_pawns.clear()
	
	# 게임 매니저 세팅
	GameManager.setup_game(player_configs, duration_seconds)
	_refresh_random_shortcut_visuals()
	_reset_tile_item_pickups()
	
	# 4인 3D 플레이어 말 생성
	for p_data in GameManager.players:
		var pawn = PlayerPawn.new()
		pawns_container.add_child(pawn)
		pawn.setup_player(p_data)
		player_pawns.append(pawn)
		
	if hud and hud.has_method("initialize_hud"):
		hud.initialize_hud()
		
	get_tree().create_timer(0.1).timeout.connect(func():
		# 온라인 참가자는 방장이 전송하는 첫 턴 상태를 기다립니다.
		if not NetworkManager.is_online or NetworkManager.is_host:
			GameManager.start_first_turn()
	)

func _refresh_random_shortcut_visuals() -> void:
	# 타일 100개의 메시·라벨을 폐기하지 않고 바뀐 종류의 머티리얼만 갱신합니다.
	for marker in tile_markers:
		if is_instance_valid(marker):
			marker.refresh_tile_data()
	for child in rails_container.get_children():
		rails_container.remove_child(child)
		child.queue_free()
	_build_3d_shortcut_rails()

func begin_render_warmup() -> void:
	# HTML 로딩 화면 뒤에서 실제 3D 보드를 몇 프레임 렌더링해 WebGL 셰이더를
	# 미리 컴파일합니다. HUD와 모달은 로비 위로 나타나지 않게 유지합니다.
	visible = true
	viewport_container.visible = true
	ui_layer.visible = false
	modals_layer.visible = false

func end_render_warmup() -> void:
	set_board_active(false)

func stop_board_game() -> void:
	_cancel_camera_follow()
	set_board_active(false)
	if quiz_modal:
		quiz_modal.cancel_quiz()

func _on_player_moved(player_idx: int, from_tile: int, to_tile: int) -> void:
	if player_idx < player_pawns.size():
		var pawn := player_pawns[player_idx]
		if to_tile == 0 and from_tile > 1 and GameManager.current_state == GameManager.TurnState.TURN_END:
			pawn.snap_to_tile(0)
			_focus_camera_on_player_turn(player_idx)
		else:
			pawn.animate_move_to_tile(to_tile)
			_start_camera_follow(pawn, from_tile, to_tile)

func _on_player_state_changed(player_idx: int) -> void:
	if player_idx < 0 or player_idx >= player_pawns.size() or player_idx >= GameManager.players.size():
		return
	player_pawns[player_idx].set_shield_active(bool(GameManager.players[player_idx].get("shield", false)))


func _on_special_skill_activated(player_idx: int, target_index: int, skill: Dictionary) -> void:
	if player_idx < 0 or player_idx >= player_pawns.size() or not is_instance_valid(world3d):
		return
	var source_pawn: PlayerPawn = player_pawns[player_idx]
	var source_position := world3d.to_local(source_pawn.global_position)
	var target_position := source_position
	if str(skill.get("target_type", "tile")) in ["player", "self"]:
		if target_index >= 0 and target_index < player_pawns.size():
			target_position = world3d.to_local(player_pawns[target_index].global_position)
	else:
		target_position = BoardGrid.get_tile_position_3d(target_index)
		target_position.y = BoardGrid.get_tile_surface_height(target_index)
	var effect := SpecialSkillEffect3D.new()
	effect.name = "SpecialSkillEffect3D"
	world3d.add_child(effect)
	effect.play(skill, source_position, target_position)
	if hud and hud.has_method("play_special_skill_cinematic"):
		var target_global := world3d.to_global(target_position + Vector3.UP * 0.8)
		var target_screen := camera3d.unproject_position(target_global)
		hud.play_special_skill_cinematic(player_idx, skill, target_screen)

func _on_quiz_requested(player_idx: int, quiz_data: Dictionary) -> void:
	if quiz_modal:
		quiz_modal.display_quiz(player_idx, quiz_data)

func _on_village_construction_started(_inventories: Array) -> void:
	# 건설 결과와 저장 이미지는 말 위치가 아니라 마을 전체가 보이는 시점으로 남깁니다.
	_cancel_camera_follow()
	camera_restore_active = false
	camera_focus = Vector3(0, 0.0, 0.4)
	camera_yaw = 0.0
	camera_pitch = deg_to_rad(41.0)
	_apply_camera_distance(32.0)

func _reset_kingdom_visuals() -> void:
	built_landmark_count = 0
	if renewable_landmarks:
		for landmark in renewable_landmarks.get_children():
			landmark.queue_free()
	if board_base_material:
		board_base_material.albedo_color = Color("263136")
		board_base_material.emission_enabled = false
	if world_environment and world_environment.environment:
		world_environment.environment.ambient_light_color = Color("5d6972")
		world_environment.environment.ambient_light_energy = 0.55

func _on_kingdom_progress_changed(projects_built: int, total_projects: int, health: int) -> void:
	var recovery := clampf(float(health) / 100.0, 0.0, 1.0)
	if board_base_material:
		board_base_material.albedo_color = Color("263136").lerp(Color("126b50"), recovery)
		board_base_material.emission_enabled = recovery > 0.0
		board_base_material.emission = Color("1fbf80") * recovery * 0.32
	if world_environment and world_environment.environment:
		world_environment.environment.ambient_light_color = Color("5d6972").lerp(Color("8fe2b7"), recovery)
		world_environment.environment.ambient_light_energy = lerpf(0.55, 1.05, recovery)
	while built_landmark_count < projects_built and built_landmark_count < total_projects:
		_add_renewable_landmark(built_landmark_count)
		built_landmark_count += 1

func _add_renewable_landmark(stage_index: int) -> void:
	if renewable_landmarks == null:
		return
	var positions := [Vector3(-9.5, 0.35, -4.7), Vector3(9.5, 0.35, -4.7), Vector3(-9.5, 0.35, 4.7), Vector3(9.5, 0.35, 4.7)]
	var landmark := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	var landmark_colors: Array[Color] = [Color("ffd84e"), Color("78d9f4"), Color("9ce77c"), Color("8ce8bf")]
	material.albedo_color = landmark_colors[stage_index]
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.35
	if stage_index == 1:
		var turbine := CylinderMesh.new()
		turbine.top_radius = 0.10
		turbine.bottom_radius = 0.16
		turbine.height = 2.2
		landmark.mesh = turbine
		landmark.position = positions[stage_index] + Vector3(0, 1.1, 0)
	else:
		var building := BoxMesh.new()
		building.size = Vector3(1.4, 1.2 + stage_index * 0.25, 1.4)
		landmark.mesh = building
		landmark.position = positions[stage_index] + Vector3(0, building.size.y * 0.5, 0)
	landmark.material_override = material
	renewable_landmarks.add_child(landmark)
