extends Node3D
class_name BoardItemPickup3D

## 각 게임 칸에 놓이는 발전소 건설 재료입니다.

const TOKEN_MODELS = preload("res://assets/models/board/construction_tokens.glb")

static var token_meshes: Dictionary = {}

var tile_index := -1
var item_id := ""
var item_visual: GeometryInstance3D
var shadow_mesh: MeshInstance3D
var shadow_material: ShaderMaterial
var is_collected := false
var resting_height := 0.014
var collect_tween: Tween

static func _get_token_mesh(id: String) -> Mesh:
	if token_meshes.is_empty():
		var collection := TOKEN_MODELS.instantiate()
		for part in collection.get_children():
			if part is MeshInstance3D:
				token_meshes[String(part.name)] = part.mesh
		collection.free()
	return token_meshes.get(id)

func setup_pickup(tile_idx: int, pickup_item_id: String, item_data: Dictionary, pickup_shadow_material: ShaderMaterial = null) -> void:
	tile_index = tile_idx
	item_id = pickup_item_id
	var token := _get_token_mesh(item_id)
	if token:
		var model := MeshInstance3D.new()
		model.mesh = token
		item_visual = model
	else:
		var icon := Sprite3D.new()
		icon.texture = load(str(item_data["asset"]))
		icon.pixel_size = 0.00078
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		item_visual = icon
		resting_height = 0.5
	item_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item_visual)

	shadow_mesh = MeshInstance3D.new()
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(0.78, 0.46)
	shadow_mesh.mesh = shadow_plane
	shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow_material = pickup_shadow_material if pickup_shadow_material != null else _create_soft_shadow_material(0.28)
	shadow_mesh.material_override = shadow_material
	shadow_mesh.position.y = 0.011
	add_child(shadow_mesh)
	reset_pickup()

func reset_pickup() -> void:
	if collect_tween:
		collect_tween.kill()
	is_collected = false
	position = BoardGrid.get_tile_position_3d(tile_index)
	position.y = BoardGrid.get_tile_surface_height(tile_index)
	# Keep the back-left tile badge and the front number clear at the turn camera angle.
	position.x += 0.13
	item_visual.position.y = resting_height
	item_visual.scale = Vector3.ONE
	shadow_mesh.scale = Vector3.ONE
	visible = true

func collect() -> void:
	if is_collected:
		return
	is_collected = true
	collect_tween = create_tween().set_parallel(true)
	collect_tween.tween_property(item_visual, "position:y", resting_height + 0.55, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	collect_tween.tween_property(item_visual, "scale", Vector3.ONE * 1.45, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	collect_tween.tween_property(item_visual, "scale", Vector3.ZERO, 0.16).set_delay(0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	collect_tween.tween_property(shadow_mesh, "scale", Vector3(0.02, 1.0, 0.02), 0.36)
	collect_tween.chain().tween_callback(queue_free)

func _create_soft_shadow_material(alpha: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float shadow_alpha : hint_range(0.0, 1.0) = 0.28;
void fragment() {
	vec2 centered_uv = UV * 2.0 - vec2(1.0);
	float edge = length(centered_uv);
	float falloff = 1.0 - smoothstep(0.30, 1.0, edge);
	ALBEDO = vec3(0.008, 0.014, 0.018);
	ALPHA = falloff * shadow_alpha;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("shadow_alpha", alpha)
	return material
