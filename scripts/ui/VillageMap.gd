extends Control
class_name VillageMap

signal project_drop_requested(project_index: int, player_idx: int, map_position: Vector2)
signal project_drop_rejected(message: String)

# Kenney Starter Kit City Builder의 선택 커서/스냅 배치 흐름을 2D 마을 지도에 맞게 구현한다.
const BUILDING_SIZE := Vector2(76, 62)
const MAP_PADDING := Vector2(12, 12)
const RECOVERY_VISUAL_TARGET := 70.0
const MAP_TEXTURE: Texture2D = preload("res://assets/maps/energy_village_map.webp")
const TERRAIN_ZONES := {
	"wind_plain": {"label": "바람 초원", "rect": Rect2(0.08, 0.06, 0.33, 0.30), "color": Color("78d9ba")},
	"wind_coast": {"label": "바람 해안 절벽", "rect": Rect2(0.05, 0.28, 0.27, 0.34), "color": Color("58c4dd")},
	"solar_field": {"label": "햇빛 평야", "rect": Rect2(0.60, 0.06, 0.35, 0.29), "color": Color("ffd362")},
	"riverbank": {"label": "산골 강변", "rect": Rect2(0.42, 0.06, 0.19, 0.55), "color": Color("55bff2")},
	"eco_city": {"label": "친환경 마을", "rect": Rect2(0.62, 0.33, 0.31, 0.29), "color": Color("88d77b")},
	"grid_hub": {"label": "다리 옆 전력 광장", "rect": Rect2(0.39, 0.40, 0.23, 0.20), "color": Color("9aaeff")},
	"tidal_lagoon": {"label": "바닷가 조력 석호", "rect": Rect2(0.05, 0.63, 0.40, 0.32), "color": Color("35d8d0")},
	"nuclear_site": {"label": "안전 관리 고원", "rect": Rect2(0.37, 0.60, 0.28, 0.31), "color": Color("b9d3e6")},
	"geothermal_field": {"label": "화산 지열 산지", "rect": Rect2(0.66, 0.59, 0.30, 0.35), "color": Color("f2a567")}
}

# 작은 건물 크기에 맞춰 각 지형을 여러 개의 세부 건설 셀로 나눕니다. 드롭
# 위치는 가장 가까운 빈 셀로 스냅되어 길이나 강을 크게 덮지 않습니다.
const PLACEMENT_CELLS := {
	"wind_plain": [Vector2(0.18, 0.15), Vector2(0.31, 0.18), Vector2(0.20, 0.29), Vector2(0.34, 0.30)],
	"wind_coast": [Vector2(0.13, 0.37), Vector2(0.24, 0.42), Vector2(0.14, 0.54), Vector2(0.27, 0.56)],
	"solar_field": [Vector2(0.68, 0.15), Vector2(0.82, 0.16), Vector2(0.70, 0.28), Vector2(0.87, 0.28)],
	"riverbank": [Vector2(0.48, 0.17), Vector2(0.53, 0.31), Vector2(0.47, 0.45), Vector2(0.54, 0.56)],
	"eco_city": [Vector2(0.69, 0.40), Vector2(0.83, 0.40), Vector2(0.70, 0.53), Vector2(0.86, 0.54)],
	"grid_hub": [Vector2(0.44, 0.44), Vector2(0.56, 0.44), Vector2(0.45, 0.55), Vector2(0.57, 0.55)],
	"tidal_lagoon": [Vector2(0.14, 0.71), Vector2(0.29, 0.72), Vector2(0.16, 0.86), Vector2(0.34, 0.85)],
	"nuclear_site": [Vector2(0.43, 0.68), Vector2(0.57, 0.68), Vector2(0.44, 0.83), Vector2(0.58, 0.83)],
	"geothermal_field": [Vector2(0.73, 0.68), Vector2(0.87, 0.68), Vector2(0.73, 0.83), Vector2(0.87, 0.84)]
}

var environment_health_visual := 0.0
var placed_project_nodes: Dictionary = {}
var occupied_cell_ids: Dictionary = {}
var reserved_cell_ids: Dictionary = {}
var pending_project_cells: Dictionary = {}
var hovered_drop_position := Vector2(-1, -1)
var active_drag_project_index := -1
var hovered_drop_is_allowed := false
var health_tween: Tween
var drop_enabled := false
var build_preview: Control
var preview_shadow: Polygon2D
var preview_icon: TextureRect

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CAN_DROP
	_create_build_preview()
	queue_redraw()

func reset_map() -> void:
	if health_tween and health_tween.is_valid():
		health_tween.kill()
	environment_health_visual = 0.0
	for project_node in placed_project_nodes.values():
		if is_instance_valid(project_node):
			project_node.queue_free()
	placed_project_nodes.clear()
	occupied_cell_ids.clear()
	reserved_cell_ids.clear()
	pending_project_cells.clear()
	_clear_drag_state()
	queue_redraw()

func set_drop_enabled(enabled: bool) -> void:
	drop_enabled = enabled
	mouse_default_cursor_shape = Control.CURSOR_CAN_DROP if enabled else Control.CURSOR_ARROW
	if not enabled:
		_clear_drag_state()
	queue_redraw()

func set_environment_health(health: int, animate: bool = true) -> void:
	var target := clampf(float(health), 0.0, 100.0)
	if not animate or not is_inside_tree():
		environment_health_visual = target
		queue_redraw()
		return
	if health_tween and health_tween.is_valid():
		health_tween.kill()
	health_tween = create_tween()
	health_tween.tween_method(_set_environment_health_visual, environment_health_visual, target, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func sync_projects(projects: Array, built_project_ids: Array[int], placements: Dictionary, owners: Dictionary, players: Array, health: int) -> void:
	for project_index in built_project_ids:
		if project_index < 0 or project_index >= projects.size() or placed_project_nodes.has(project_index):
			continue
		var project: Dictionary = projects[project_index]
		var requested_position: Vector2 = placements.get(project_index, Vector2(-1, -1))
		if requested_position.x < 0.0 or requested_position.y < 0.0:
			requested_position = _default_position(project_index)
		var cell_id := str(pending_project_cells.get(project_index, ""))
		if cell_id.is_empty():
			cell_id = _get_closest_cell_id(project_index, requested_position, true)
		if not cell_id.is_empty():
			occupied_cell_ids[cell_id] = project_index
			reserved_cell_ids.erase(cell_id)
			pending_project_cells.erase(project_index)
			requested_position = _get_cell_center_from_id(cell_id)
		var owner_index := int(owners.get(project_index, -1))
		var owner_data: Dictionary = players[owner_index] if owner_index >= 0 and owner_index < players.size() else {}
		_add_building(project_index, str(project.get("image", "")), str(project.get("name", "시설")), requested_position, owner_data)
	set_environment_health(health)
	queue_redraw()

func get_placed_project_count() -> int:
	return placed_project_nodes.size()

func create_drop_payload(project_index: int, player_idx: int) -> Dictionary:
	return {"kind": "village_project", "project_index": project_index, "player_idx": player_idx}

func get_terrain_center(terrain_id: String) -> Vector2:
	return _get_terrain_rect(terrain_id).get_center()

func get_terrain_build_cell_center(terrain_id: String, cell_index: int = 0) -> Vector2:
	var cells: Array = PLACEMENT_CELLS.get(terrain_id, [])
	if cell_index < 0 or cell_index >= cells.size():
		return get_terrain_center(terrain_id)
	return Vector2(cells[cell_index]) * size

func cancel_project_placement(project_index: int) -> void:
	var cell_id := str(pending_project_cells.get(project_index, ""))
	if not cell_id.is_empty():
		reserved_cell_ids.erase(cell_id)
	pending_project_cells.erase(project_index)
	queue_redraw()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not _has_valid_project_payload(data):
		_clear_drag_state()
		return false
	active_drag_project_index = int(data["project_index"])
	var candidate := _get_drop_candidate(active_drag_project_index, at_position)
	hovered_drop_position = candidate["position"]
	hovered_drop_is_allowed = candidate["allowed"]
	_update_build_preview(active_drag_project_index, hovered_drop_position, hovered_drop_is_allowed)
	queue_redraw()
	return hovered_drop_is_allowed

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _has_valid_project_payload(data):
		return
	var project_index := int(data["project_index"])
	var candidate := _get_drop_candidate(project_index, at_position)
	if not candidate["allowed"]:
		project_drop_rejected.emit(_get_project_terrain_label(project_index) + "의 비어 있는 건설 패드에만 지을 수 있습니다.")
		_clear_drag_state()
		return
	var cell_id := str(candidate["cell_id"])
	reserved_cell_ids[cell_id] = project_index
	pending_project_cells[project_index] = cell_id
	var snapped_position: Vector2 = candidate["position"]
	_clear_drag_state()
	project_drop_requested.emit(project_index, int(data["player_idx"]), snapped_position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drag_state()

func _set_environment_health_visual(value: float) -> void:
	environment_health_visual = value
	queue_redraw()

func _create_build_preview() -> void:
	if build_preview:
		return
	build_preview = _create_project_visual("BuildPreview", "", "", Color("6dffad"), true)
	build_preview.z_index = 12
	build_preview.visible = false
	add_child(build_preview)
	preview_shadow = build_preview.get_node("Shadow") as Polygon2D
	preview_icon = build_preview.get_node("Icon") as TextureRect

func _update_build_preview(project_index: int, center_position: Vector2, is_allowed: bool) -> void:
	if not build_preview:
		_create_build_preview()
	if project_index < 0 or project_index >= GameManager.CONSTRUCTION_PROJECTS.size() or center_position.x < 0.0:
		build_preview.visible = false
		return
	var preview_color := Color("6dffad") if is_allowed else Color("ff6b65")
	var project: Dictionary = GameManager.CONSTRUCTION_PROJECTS[project_index]
	var image_path := str(project.get("image", ""))
	preview_icon.texture = load(image_path) if ResourceLoader.exists(image_path) else null
	preview_icon.modulate = Color(1.0, 1.0, 1.0, 0.72) if is_allowed else Color(1.0, 0.54, 0.52, 0.64)
	preview_shadow.color = Color(preview_color, 0.48)
	build_preview.position = _clamp_icon_position(center_position - BUILDING_SIZE * 0.5)
	build_preview.visible = true

func _clear_drag_state() -> void:
	hovered_drop_position = Vector2(-1, -1)
	active_drag_project_index = -1
	hovered_drop_is_allowed = false
	if build_preview:
		build_preview.visible = false
	queue_redraw()

func _add_building(project_index: int, image_path: String, project_name: String, center_position: Vector2, owner_data: Dictionary = {}) -> void:
	var visual := _create_project_visual("PlacedProject%d" % project_index, image_path, project_name, Color("63dcb2"), false)
	visual.position = _clamp_icon_position(center_position - BUILDING_SIZE * 0.5)
	visual.z_index = 3
	add_child(visual)
	placed_project_nodes[project_index] = visual
	visual.pivot_offset = BUILDING_SIZE * 0.5
	visual.scale = Vector2(0.18, 0.18)
	visual.modulate = Color(1.20, 1.20, 0.88, 0.0)
	_add_owner_badge(visual, owner_data)
	var place_tween := create_tween().set_parallel(true)
	place_tween.tween_property(visual, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	place_tween.tween_property(visual, "modulate", Color.WHITE, 0.24)

func _add_owner_badge(visual: Control, owner_data: Dictionary) -> void:
	if owner_data.is_empty():
		return
	var owner_color := Color("dffff3")
	var configured_color: Variant = owner_data.get("char_color", null)
	if configured_color is Color:
		owner_color = configured_color.lightened(0.28)
	var badge := Label.new()
	badge.name = "OwnerBadge"
	badge.text = "◆ " + str(owner_data.get("name", "플레이어"))
	badge.position = Vector2(1, -12)
	badge.size = Vector2(BUILDING_SIZE.x - 2, 15)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 9)
	badge.add_theme_color_override("font_color", owner_color)
	badge.add_theme_color_override("font_outline_color", Color(0.01, 0.05, 0.06, 0.96))
	badge.add_theme_constant_override("outline_size", 4)
	badge.z_index = 2
	visual.add_child(badge)

func _create_project_visual(node_name: String, image_path: String, project_name: String, pad_color: Color, is_preview: bool) -> Control:
	var visual := Control.new()
	visual.name = node_name
	visual.custom_minimum_size = BUILDING_SIZE
	visual.size = BUILDING_SIZE
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.tooltip_text = project_name
	# 드래그 중에는 건설 가능 위치를 알려주는 패드가 필요하지만, 배치가 끝난
	# 시설에는 사각형처럼 보이는 인공 받침을 남기지 않습니다.
	if is_preview:
		var halo := Polygon2D.new()
		halo.name = "Halo"
		halo.polygon = PackedVector2Array([Vector2(7, 51), Vector2(38, 41), Vector2(70, 51), Vector2(38, 60)])
		halo.color = Color(pad_color, 0.20)
		visual.add_child(halo)
		var shadow := Polygon2D.new()
		shadow.name = "Shadow"
		shadow.polygon = PackedVector2Array([Vector2(11, 52), Vector2(38, 45), Vector2(66, 52), Vector2(38, 60)])
		shadow.color = Color(pad_color, 0.78)
		visual.add_child(shadow)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(0, -7)
	icon.size = BUILDING_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(image_path):
		icon.texture = load(image_path)
	visual.add_child(icon)
	return visual

func _default_position(project_index: int) -> Vector2:
	var cell_id := _get_closest_cell_id(project_index, size * 0.5, true)
	if not cell_id.is_empty():
		return _get_cell_center_from_id(cell_id)
	var terrains := _get_project_terrains(project_index)
	return get_terrain_center(str(terrains[0])) if not terrains.is_empty() else size * 0.5

func _has_valid_project_payload(data: Variant) -> bool:
	if not drop_enabled or not data is Dictionary or data.get("kind", "") != "village_project":
		return false
	var project_index := int(data.get("project_index", -1))
	return project_index >= 0 and project_index < GameManager.CONSTRUCTION_PROJECTS.size() and int(data.get("player_idx", -1)) >= 0 and not placed_project_nodes.has(project_index)

func _get_project_terrains(project_index: int) -> Array:
	if project_index < 0 or project_index >= GameManager.CONSTRUCTION_PROJECTS.size():
		return []
	return GameManager.CONSTRUCTION_PROJECTS[project_index].get("terrains", [])

func _get_project_terrain_label(project_index: int) -> String:
	if project_index < 0 or project_index >= GameManager.CONSTRUCTION_PROJECTS.size():
		return "적합한 지형"
	return str(GameManager.CONSTRUCTION_PROJECTS[project_index].get("terrain_label", "적합한 지형"))

func _get_terrain_rect(terrain_id: String) -> Rect2:
	var normalized_rect: Rect2 = TERRAIN_ZONES.get(terrain_id, {}).get("rect", Rect2())
	return Rect2(normalized_rect.position * size, normalized_rect.size * size)

func _get_drop_candidate(project_index: int, requested_position: Vector2) -> Dictionary:
	var requested := _clamp_center_position(requested_position)
	var allowed_terrains: Array[String] = []
	for terrain_id_variant in _get_project_terrains(project_index):
		var terrain_id := str(terrain_id_variant)
		if _get_terrain_rect(terrain_id).grow(6.0).has_point(requested):
			allowed_terrains.append(terrain_id)
	if allowed_terrains.is_empty():
		return {"allowed": false, "position": requested, "cell_id": ""}
	var cell_id := _get_closest_cell_id_from_terrains(allowed_terrains, requested, false)
	if cell_id.is_empty():
		return {"allowed": false, "position": requested, "cell_id": ""}
	return {"allowed": true, "position": _get_cell_center_from_id(cell_id), "cell_id": cell_id}

func _get_closest_cell_id(project_index: int, requested_position: Vector2, include_occupied: bool) -> String:
	var terrain_ids: Array[String] = []
	for terrain_id_variant in _get_project_terrains(project_index):
		terrain_ids.append(str(terrain_id_variant))
	return _get_closest_cell_id_from_terrains(terrain_ids, requested_position, include_occupied)

func _get_closest_cell_id_from_terrains(terrain_ids: Array[String], requested_position: Vector2, include_occupied: bool) -> String:
	var closest_cell_id := ""
	var closest_distance := INF
	for terrain_id in terrain_ids:
		var cells: Array = PLACEMENT_CELLS.get(terrain_id, [])
		for cell_index in range(cells.size()):
			var cell_id := _make_cell_id(terrain_id, cell_index)
			if not include_occupied and (occupied_cell_ids.has(cell_id) or reserved_cell_ids.has(cell_id)):
				continue
			var distance := requested_position.distance_squared_to(get_terrain_build_cell_center(terrain_id, cell_index))
			if distance < closest_distance:
				closest_distance = distance
				closest_cell_id = cell_id
	return closest_cell_id

func _make_cell_id(terrain_id: String, cell_index: int) -> String:
	return "%s:%d" % [terrain_id, cell_index]

func _get_cell_center_from_id(cell_id: String) -> Vector2:
	var parts := cell_id.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return size * 0.5
	return get_terrain_build_cell_center(parts[0], int(parts[1]))

func _clamp_center_position(center_position: Vector2) -> Vector2:
	return _clamp_icon_position(center_position - BUILDING_SIZE * 0.5) + BUILDING_SIZE * 0.5

func _clamp_icon_position(icon_position: Vector2) -> Vector2:
	var max_position := Vector2(maxf(MAP_PADDING.x, size.x - BUILDING_SIZE.x - MAP_PADDING.x), maxf(MAP_PADDING.y, size.y - BUILDING_SIZE.y - MAP_PADDING.y))
	return Vector2(clampf(icon_position.x, MAP_PADDING.x, max_position.x), clampf(icon_position.y, MAP_PADDING.y, max_position.y))

func _draw() -> void:
	var ratio := clampf(environment_health_visual / RECOVERY_VISUAL_TARGET, 0.0, 1.0)
	var map_rect := Rect2(Vector2.ZERO, size)
	draw_texture_rect(MAP_TEXTURE, map_rect, false)
	# 환경이 나쁠 때는 원본 지도를 탁한 스모그가 덮고, 시설이 늘수록 본래 색이 드러난다.
	var pollution_strength := 1.0 - ratio
	# 건설 시작 시에도 산·강·해안 같은 조건 지형을 읽을 수 있게 스모그를 과도하게 덮지 않는다.
	draw_rect(map_rect, Color(0.18, 0.12, 0.07, pollution_strength * 0.32))
	draw_rect(map_rect, Color(0.08, 0.12, 0.10, pollution_strength * 0.11))
	var pollution_alpha := pollution_strength * 0.20
	if pollution_alpha > 0.02:
		for cloud_ratio in [Vector2(0.15, 0.12), Vector2(0.73, 0.14), Vector2(0.86, 0.73), Vector2(0.28, 0.76)]:
			var cloud_position := Vector2(size.x * cloud_ratio.x, size.y * cloud_ratio.y)
			draw_circle(cloud_position, 25.0, Color(0.16, 0.15, 0.14, pollution_alpha))
			draw_circle(cloud_position + Vector2(23, 5), 19.0, Color(0.20, 0.18, 0.16, pollution_alpha * 0.82))
	if drop_enabled and active_drag_project_index >= 0:
		_draw_active_build_pads()
	draw_rect(map_rect, Color(0.08, 0.20, 0.17, 0.9), false, 3.0)

func _draw_active_build_pads() -> void:
	var font := ThemeDB.fallback_font
	var pad_color := Color("6dffad")
	for terrain_id_variant in _get_project_terrains(active_drag_project_index):
		var terrain_id := str(terrain_id_variant)
		var cells: Array = PLACEMENT_CELLS.get(terrain_id, [])
		for cell_index in range(cells.size()):
			var cell_id := _make_cell_id(terrain_id, cell_index)
			var center := get_terrain_build_cell_center(terrain_id, cell_index)
			var is_taken := occupied_cell_ids.has(cell_id) or reserved_cell_ids.has(cell_id)
			var color := Color("ff917e") if is_taken else pad_color
			var diamond := PackedVector2Array([center + Vector2(0, -18), center + Vector2(27, -2), center + Vector2(0, 15), center + Vector2(-27, -2)])
			draw_colored_polygon(diamond, Color(color, 0.24 if is_taken else 0.31))
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), color, 2.0, true)
			if not is_taken:
				draw_circle(center, 5.0, Color(color, 0.86))
	var requirement_text := _get_project_terrain_label(active_drag_project_index) + "의 빛나는 건설 패드에 놓으세요"
	draw_rect(Rect2(Vector2(10, 10), Vector2(size.x - 20, 30)), Color(0.02, 0.10, 0.11, 0.76), true)
	draw_string(font, Vector2(18, 31), requirement_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e5fff3"))
