extends Node3D
class_name BoardItemPickup3D

## 각 게임 칸 위에 떠 있는 발전소 건설 재료입니다.

var tile_index: int = -1
var item_id := ""
var item_sprite: Sprite3D
var shadow_mesh: MeshInstance3D
var shadow_material: ShaderMaterial
var elapsed := 0.0
var base_height := 0.0
var ground_height := 0.0
var is_collected := false

func setup_pickup(tile_idx: int, pickup_item_id: String, item_data: Dictionary) -> void:
	tile_index = tile_idx
	item_id = pickup_item_id
	ground_height = BoardGrid.get_tile_surface_height(tile_idx)
	position = BoardGrid.get_tile_position_3d(tile_idx) + Vector3(0, ground_height - BoardGrid.get_tile_position_3d(tile_idx).y + 0.52, 0)
	base_height = position.y

	shadow_mesh = MeshInstance3D.new()
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(0.78, 0.46)
	shadow_mesh.mesh = shadow_plane
	shadow_material = _create_soft_shadow_material(0.28)
	shadow_mesh.material_override = shadow_material
	add_child(shadow_mesh)
	# 첫 렌더 프레임부터 그림자가 타일 상단에 붙어 있도록 초기 위치를 계산합니다.
	_update_ground_shadow()

	item_sprite = Sprite3D.new()
	item_sprite.texture = load(str(item_data.get("asset", "")))
	item_sprite.pixel_size = 0.00078
	item_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	item_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	item_sprite.position = Vector3(0, -0.02, 0)
	add_child(item_sprite)

func _process(delta: float) -> void:
	if is_collected:
		return
	elapsed += delta
	position.y = base_height + sin(elapsed * 2.4 + float(tile_index) * 0.37) * 0.09
	rotation.y = sin(elapsed * 0.7 + float(tile_index)) * 0.12
	_update_ground_shadow()

func collect() -> void:
	if is_collected:
		return
	is_collected = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y + 0.55, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3(1.45, 1.45, 1.45), 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.16).set_delay(0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)

func _update_ground_shadow() -> void:
	if shadow_mesh == null:
		return
	var hover_height := maxf(position.y - ground_height, 0.0)
	shadow_mesh.position = Vector3(0, ground_height - position.y + 0.012, 0)
	var spread := 1.0 + hover_height * 0.22
	shadow_mesh.scale = Vector3(spread, 1.0, spread)
	if shadow_material:
		shadow_material.set_shader_parameter("shadow_alpha", clampf(0.30 - hover_height * 0.16, 0.10, 0.30))

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
