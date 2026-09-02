extends Button
class_name ConstructionDragCard

var project_index := -1
var player_idx := -1
var building_texture: Texture2D

func configure(new_project_index: int, new_player_idx: int, texture: Texture2D, can_drag: bool) -> void:
	project_index = new_project_index
	player_idx = new_player_idx
	building_texture = texture
	disabled = not can_drag
	mouse_default_cursor_shape = Control.CURSOR_DRAG if can_drag else Control.CURSOR_FORBIDDEN

func create_drag_payload() -> Dictionary:
	if disabled or project_index < 0 or player_idx < 0:
		return {}
	return {"kind": "village_project", "project_index": project_index, "player_idx": player_idx}

func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload := create_drag_payload()
	if payload.is_empty():
		return null
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(116, 96)
	preview.size = Vector2(116, 96)
	preview.texture = building_texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1.15, 1.15, 1.0, 0.92)
	set_drag_preview(preview)
	return payload
