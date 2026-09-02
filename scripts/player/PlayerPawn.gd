extends Node3D
class_name PlayerPawn

## PlayerPawn: 기존 사다리 보드 위에서 칸별로 이동하는 3D 캐릭터 말입니다.

@export var player_index: int = 0

var avatar_sprite: Sprite3D
var shadow_mesh: MeshInstance3D
var shadow_material: ShaderMaterial
var shield_visual: Node3D
var shield_shell: MeshInstance3D
var shield_ring_a: MeshInstance3D
var shield_ring_b: MeshInstance3D
var shield_shell_material: StandardMaterial3D
var shield_ring_material: StandardMaterial3D
var current_tile: int = 0
var move_tween: Tween
var animation_elapsed := 0.0
var idle_sprite_texture: Texture2D
var move_sprite_texture: Texture2D
var is_moving := false
var shield_elapsed := 0.0

# 원본 스프라이트 첫 프레임의 투명 여백(약 0.047)을 포함해 실제 발끝이
# 타일 윗면에 닿도록 맞춘 중심 높이입니다. 루트는 타일 윗면에 놓입니다.
const AVATAR_CENTER_HEIGHT := 0.315
const GROUND_SHADOW_OFFSET := 0.014
const GROUND_SHADOW_BASE_SCALE := 0.82
const GROUND_SHADOW_LIFT_SPREAD := 0.95
const GROUND_SHADOW_MAX_SCALE := 1.82

const IDLE_SPRITE_BY_ICON := {
	"res://assets/characters/eco_roster/captain_eco.png": "res://assets/characters/eco_roster/sprites/captain_eco_idle.png",
	"res://assets/characters/eco_roster/fairy_sparky.png": "res://assets/characters/eco_roster/sprites/fairy_sparky_idle.png",
	"res://assets/characters/eco_roster/water_popo.png": "res://assets/characters/eco_roster/sprites/water_popo_idle.png",
	"res://assets/characters/eco_roster/bear_pongi.png": "res://assets/characters/eco_roster/sprites/bear_pongi_idle.png",
	"res://assets/characters/eco_roster/solar_fox_sol.png": "res://assets/characters/eco_roster/sprites/solar_fox_sol_idle.png",
	"res://assets/characters/eco_roster/wind_rabbit_bori.png": "res://assets/characters/eco_roster/sprites/wind_rabbit_bori_idle.png",
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.png": "res://assets/characters/eco_roster/sprites/recycle_raccoon_ringo_idle.png",
	"res://assets/characters/eco_roster/earth_turtle_tori.png": "res://assets/characters/eco_roster/sprites/earth_turtle_tori_move_alpha.png",
	"res://assets/characters/eco_roster/lightning_bird_pika.png": "res://assets/characters/eco_roster/sprites/lightning_bird_pika_idle.png",
	"res://assets/characters/eco_roster/mushroom_cat_momo.png": "res://assets/characters/eco_roster/sprites/mushroom_cat_momo_idle.png"
}

const MOVE_SPRITE_BY_ICON := {
	"res://assets/characters/eco_roster/captain_eco.png": "res://assets/characters/eco_roster/sprites/captain_eco_move_alpha.png",
	"res://assets/characters/eco_roster/water_popo.png": "res://assets/characters/eco_roster/sprites/water_popo_move_alpha.png",
	"res://assets/characters/eco_roster/bear_pongi.png": "res://assets/characters/eco_roster/sprites/bear_pongi_move_alpha.png",
	"res://assets/characters/eco_roster/solar_fox_sol.png": "res://assets/characters/eco_roster/sprites/solar_fox_sol_move_alpha.png",
	"res://assets/characters/eco_roster/wind_rabbit_bori.png": "res://assets/characters/eco_roster/sprites/wind_rabbit_bori_move_alpha.png",
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.png": "res://assets/characters/eco_roster/sprites/recycle_raccoon_ringo_move_alpha.png",
	# 토리는 이동 중 3D 도약과 빠른 프레임 재생을 사용합니다. 투명 가장자리가 보존된 시트를 유지합니다.
	"res://assets/characters/eco_roster/earth_turtle_tori.png": "res://assets/characters/eco_roster/sprites/earth_turtle_tori_idle.png",
	"res://assets/characters/eco_roster/lightning_bird_pika.png": "res://assets/characters/eco_roster/sprites/lightning_bird_pika_move_alpha.png",
	"res://assets/characters/eco_roster/mushroom_cat_momo.png": "res://assets/characters/eco_roster/sprites/mushroom_cat_momo_move_alpha.png"
}

const IDLE_SPRITE_FRAMES := 4
const MOVE_SPRITE_FRAMES := 4
const IDLE_SPRITE_FPS := 5.0
const MOVE_SPRITE_FPS := 10.0

const PAWN_OFFSETS_3D: Array[Vector3] = [
	Vector3(-0.50, 0.0, -0.50),
	Vector3(0.50, 0.0, -0.50),
	Vector3(-0.50, 0.0, 0.50),
	Vector3(0.50, 0.0, 0.50)
]

func _ready() -> void:
	_init_components()

func _process(delta: float) -> void:
	_update_shield_visual(delta)
	if avatar_sprite != null and avatar_sprite.hframes > 1:
		animation_elapsed += delta
		var animation_fps := MOVE_SPRITE_FPS if is_moving else IDLE_SPRITE_FPS
		avatar_sprite.frame = int(animation_elapsed * animation_fps) % avatar_sprite.hframes

func _init_components() -> void:
	if avatar_sprite != null:
		return

	# 1. 바닥에 닿는 부드러운 타원 그림자. 네온 원 대신 도약 높이에 맞춰 퍼지고 옅어집니다.
	shadow_mesh = MeshInstance3D.new()
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(0.86, 0.50)
	shadow_mesh.mesh = shadow_plane
	shadow_material = _create_soft_shadow_material(0.42)
	shadow_mesh.material_override = shadow_material
	add_child(shadow_mesh)

	# 2. 3D 빌보드 캐릭터 아바타 (Sprite3D)
	avatar_sprite = Sprite3D.new()
	avatar_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	avatar_sprite.pixel_size = 0.00068
	avatar_sprite.position = Vector3(0, AVATAR_CENTER_HEIGHT, 0)
	avatar_sprite.shaded = false
	avatar_sprite.double_sided = true
	add_child(avatar_sprite)

	# 3. 방패를 보유한 동안 캐릭터를 감싸는 반투명 에너지 보호막입니다.
	_create_shield_visual()

func setup_player(p_data: Dictionary) -> void:
	_init_components()
	player_index = p_data.get("index", 0)
	
	var icon_path = p_data.get("char_icon", "res://assets/images/char_captain_eco.jpg")
	var idle_sprite_path := str(IDLE_SPRITE_BY_ICON.get(icon_path, ""))
	var move_sprite_path := str(MOVE_SPRITE_BY_ICON.get(icon_path, ""))
	if avatar_sprite and not idle_sprite_path.is_empty() and ResourceLoader.exists(idle_sprite_path):
		idle_sprite_texture = load(idle_sprite_path)
		if not move_sprite_path.is_empty() and ResourceLoader.exists(move_sprite_path):
			move_sprite_texture = load(move_sprite_path)
		else:
			move_sprite_texture = idle_sprite_texture
		avatar_sprite.texture = idle_sprite_texture
		avatar_sprite.hframes = IDLE_SPRITE_FRAMES
		avatar_sprite.vframes = 1
		avatar_sprite.frame = 0
		# 생성된 시트의 프레임 높이에 맞춰 기존 말과 같은 보드상 크기를 유지합니다.
		avatar_sprite.pixel_size = 0.0010
	elif avatar_sprite and ResourceLoader.exists(icon_path):
		avatar_sprite.texture = load(icon_path)
		avatar_sprite.hframes = 1
		avatar_sprite.vframes = 1
		avatar_sprite.frame = 0
		avatar_sprite.pixel_size = 0.00068
	_set_avatar_animation_state(false)
	set_shield_active(bool(p_data.get("shield", false)))
		
	# 시작 위치를 타일 중심이 아닌 실제 윗면으로 계산합니다.
	_place_on_tile(0)

func animate_move_to_tile(to_tile_idx: int) -> void:
	var from_tile := current_tile
	current_tile = to_tile_idx
	var pawn_offset: Vector3 = PAWN_OFFSETS_3D[player_index % 4]
	
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	_set_avatar_animation_state(true)
	move_tween = create_tween().set_parallel(false)

	# 사다리/미끄럼틀 3D 아치형 점프 도약
	if BoardGrid.is_shortcut_transition(from_tile, to_tile_idx):
		var from_pos := position
		var to_pos := _get_tile_contact_position(to_tile_idx, pawn_offset)
		var jump_duration: float = BoardGrid.SHORTCUT_MOVE_SECONDS
		
		# 3D 포물선 도약 트윈
		move_tween.tween_method(
			_update_hop_position.bind(from_pos, to_pos, 2.2),
			0.0, 1.0, jump_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		move_tween.tween_callback(_place_on_tile.bind(to_tile_idx))
		move_tween.tween_callback(_set_avatar_animation_state.bind(false))
		return

	# 일반 칸 이동: 기존 사다리 경로를 따라 한 칸씩 통통 튀며 이동
	var direction := 1 if to_tile_idx > from_tile else -1
	var step_tile := from_tile + direction
	
	while step_tile != to_tile_idx + direction:
		var previous_tile := step_tile - direction
		var start_p := _get_tile_contact_position(previous_tile, pawn_offset)
		var target_p := _get_tile_contact_position(step_tile, pawn_offset)
		var step_dur: float = BoardGrid.MOVE_STEP_SECONDS
		
		move_tween.tween_method(
			_update_hop_position.bind(start_p, target_p, 0.68),
			0.0, 1.0, step_dur
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		step_tile += direction
	move_tween.tween_callback(_place_on_tile.bind(to_tile_idx))
	move_tween.tween_callback(_set_avatar_animation_state.bind(false))

func snap_to_tile(to_tile_idx: int) -> void:
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	current_tile = clampi(to_tile_idx, 0, BoardGrid.LAST_TILE_INDEX)
	_place_on_tile(current_tile)
	_set_avatar_animation_state(false)

func _set_avatar_animation_state(should_move: bool) -> void:
	is_moving = should_move
	animation_elapsed = 0.0
	if avatar_sprite == null:
		return
	var next_texture := move_sprite_texture if is_moving else idle_sprite_texture
	if next_texture != null:
		avatar_sprite.texture = next_texture
		avatar_sprite.hframes = MOVE_SPRITE_FRAMES if is_moving else IDLE_SPRITE_FRAMES
		avatar_sprite.vframes = 1
		avatar_sprite.frame = 0

func _update_hop_position(progress: float, from_position: Vector3, to_position: Vector3, hop_height: float) -> void:
	var ground := from_position.lerp(to_position, progress)
	var lift := sin(progress * PI) * hop_height
	position = ground + Vector3(0, lift, 0)
	_update_ground_shadow(ground.y, lift)

func _get_tile_contact_position(tile_index: int, pawn_offset: Vector3 = Vector3.ZERO) -> Vector3:
	var tile_position := BoardGrid.get_tile_position_3d(tile_index) + pawn_offset
	tile_position.y = BoardGrid.get_tile_surface_height(tile_index)
	return tile_position

func _place_on_tile(tile_index: int) -> void:
	current_tile = clampi(tile_index, 0, BoardGrid.LAST_TILE_INDEX)
	position = _get_tile_contact_position(current_tile, PAWN_OFFSETS_3D[player_index % 4])
	_update_ground_shadow(position.y, 0.0)

func _update_ground_shadow(surface_y: float, lift: float) -> void:
	if shadow_mesh == null:
		return
	shadow_mesh.position = Vector3(0, surface_y - position.y + GROUND_SHADOW_OFFSET, 0)
	# 캐릭터가 높이 뜰수록 빛이 넓게 퍼진 것처럼 그림자는 크게, 더 옅게 보입니다.
	# 기존 변화폭은 일반 한 칸 도약에서 10% 정도여서 거의 보이지 않았습니다.
	var spread := clampf(GROUND_SHADOW_BASE_SCALE + lift * GROUND_SHADOW_LIFT_SPREAD, GROUND_SHADOW_BASE_SCALE, GROUND_SHADOW_MAX_SCALE)
	shadow_mesh.scale = Vector3(spread, 1.0, spread)
	if shadow_material:
		shadow_material.set_shader_parameter("shadow_alpha", clampf(0.46 - lift * 0.28, 0.08, 0.46))

func _create_soft_shadow_material(alpha: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float shadow_alpha : hint_range(0.0, 1.0) = 0.42;
void fragment() {
	vec2 centered_uv = UV * 2.0 - vec2(1.0);
	float edge = length(centered_uv);
	float falloff = 1.0 - smoothstep(0.32, 1.0, edge);
	ALBEDO = vec3(0.008, 0.014, 0.018);
	ALPHA = falloff * shadow_alpha;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("shadow_alpha", alpha)
	return material

func _create_shield_visual() -> void:
	shield_visual = Node3D.new()
	shield_visual.name = "ShieldVisual"
	shield_visual.position = Vector3(0.0, 0.72, 0.0)
	shield_visual.visible = false
	add_child(shield_visual)

	shield_shell = MeshInstance3D.new()
	shield_shell.name = "ShieldShell"
	var sphere := SphereMesh.new()
	sphere.radius = 0.76
	sphere.height = 1.52
	sphere.radial_segments = 32
	sphere.rings = 16
	shield_shell.mesh = sphere
	shield_shell_material = StandardMaterial3D.new()
	shield_shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_shell_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_shell_material.albedo_color = Color(0.20, 0.82, 1.0, 0.13)
	shield_shell_material.emission_enabled = true
	shield_shell_material.emission = Color("62dfff")
	shield_shell_material.emission_energy_multiplier = 0.75
	shield_shell.material_override = shield_shell_material
	shield_visual.add_child(shield_shell)

	shield_ring_material = StandardMaterial3D.new()
	shield_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_ring_material.albedo_color = Color(0.55, 0.94, 1.0, 0.78)
	shield_ring_material.emission_enabled = true
	shield_ring_material.emission = Color("a2f4ff")
	shield_ring_material.emission_energy_multiplier = 1.8
	shield_ring_a = _create_shield_ring("ShieldRingA", Vector3(deg_to_rad(67.0), 0.0, deg_to_rad(18.0)))
	shield_ring_b = _create_shield_ring("ShieldRingB", Vector3(deg_to_rad(-58.0), deg_to_rad(28.0), deg_to_rad(-22.0)))

func _create_shield_ring(node_name: String, rotation_value: Vector3) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = node_name
	var torus := TorusMesh.new()
	torus.inner_radius = 0.745
	torus.outer_radius = 0.775
	torus.rings = 32
	torus.ring_segments = 10
	ring.mesh = torus
	ring.material_override = shield_ring_material
	ring.rotation = rotation_value
	shield_visual.add_child(ring)
	return ring

func set_shield_active(is_active: bool) -> void:
	_init_components()
	if shield_visual == null:
		return
	shield_visual.visible = is_active
	shield_elapsed = 0.0
	if is_active:
		shield_visual.scale = Vector3.ONE * 0.72
		var appear_tween := create_tween()
		appear_tween.tween_property(shield_visual, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_shield_visual(delta: float) -> void:
	if shield_visual == null or not shield_visual.visible:
		return
	shield_elapsed += delta
	var pulse := 1.0 + sin(shield_elapsed * 3.8) * 0.035
	shield_visual.scale = Vector3.ONE * pulse
	shield_visual.rotation.y = shield_elapsed * 0.48
	if shield_ring_a:
		shield_ring_a.rotation.z += delta * 0.72
	if shield_ring_b:
		shield_ring_b.rotation.x -= delta * 0.58
	if shield_shell_material:
		var glow := 0.11 + (sin(shield_elapsed * 3.8) + 1.0) * 0.025
		shield_shell_material.albedo_color = Color(0.20, 0.82, 1.0, glow)
