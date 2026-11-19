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
var animation_phase := 0.0
var idle_sprite_texture: Texture2D
var move_sprite_texture: Texture2D
var back_run_sprite_texture: Texture2D
var side_run_sprite_texture: Texture2D
var is_moving := false
var use_back_run_sprite := false
var use_side_run_sprite := false
var shield_elapsed := 0.0
var last_animation_position := Vector3.ZERO
var animation_speed := 0.0
var animation_position_ready := false
var board_presentation_enabled := false
var board_current_turn := false
var board_display_name := ""
var board_is_local := false
var board_turn_ring: MeshInstance3D
var board_turn_label: Label3D
var board_face: Sprite3D
var board_turn_material: StandardMaterial3D
var player_icon_path := ""
var board_model: Node3D
var board_animator: AnimationPlayer
var board_target_yaw := 0.0
var board_shortcut_jump := false
var board_stride_length := LEGACY_BOARD_STRIDE_LENGTH
var arcade_stride_length := LEGACY_BOARD_STRIDE_LENGTH
var board_pose_time := 0.0
enum ArcadePose { NONE, SIDE, RUNNER, CONTROL }
var arcade_pose := ArcadePose.NONE
var course_speed := 0.0
var arcade_lift := 0.0
var peak_lift := 0.0
var descending := false

const BOARD_AVATAR_SCALE := 1.35
const BOARD_ACTIVE_AVATAR_SCALE := 1.60
const BOARD_MODEL_DIR := "res://assets/models/board_pawns/"
const LEGACY_CAPTAIN_ICON := "res://assets/images/char_captain_eco.webp"
const LEGACY_BOARD_STRIDE_LENGTH := 0.42

# 원본 스프라이트 첫 프레임의 투명 여백(약 0.047)을 포함해 실제 발끝이
# 타일 윗면에 닿도록 맞춘 중심 높이입니다. 루트는 타일 윗면에 놓입니다.
const AVATAR_CENTER_HEIGHT := 0.315
const GROUND_SHADOW_OFFSET := 0.014
const GROUND_SHADOW_BASE_SCALE := 0.82
const GROUND_SHADOW_LIFT_SPREAD := 0.95
const GROUND_SHADOW_MAX_SCALE := 1.82

const IDLE_SPRITE_BY_ICON := {
	"res://assets/characters/eco_roster/captain_eco.webp": "res://assets/characters/eco_roster/sprites/captain_eco_idle.webp",
	"res://assets/characters/eco_roster/fairy_sparky.webp": "res://assets/characters/eco_roster/sprites/fairy_sparky_idle.webp",
	"res://assets/characters/eco_roster/water_popo.webp": "res://assets/characters/eco_roster/sprites/water_popo_idle.webp",
	"res://assets/characters/eco_roster/bear_pongi.webp": "res://assets/characters/eco_roster/sprites/bear_pongi_idle.webp",
	"res://assets/characters/eco_roster/solar_fox_sol.webp": "res://assets/characters/eco_roster/sprites/solar_fox_sol_idle.webp",
	"res://assets/characters/eco_roster/wind_rabbit_bori.webp": "res://assets/characters/eco_roster/sprites/wind_rabbit_bori_idle.webp",
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.webp": "res://assets/characters/eco_roster/sprites/recycle_raccoon_ringo_idle.webp",
	"res://assets/characters/eco_roster/earth_turtle_tori.webp": "res://assets/characters/eco_roster/sprites/earth_turtle_tori_move_alpha.webp",
	"res://assets/characters/eco_roster/lightning_bird_pika.webp": "res://assets/characters/eco_roster/sprites/lightning_bird_pika_idle.webp",
	"res://assets/characters/eco_roster/mushroom_cat_momo.webp": "res://assets/characters/eco_roster/sprites/mushroom_cat_momo_idle.webp"
}

const MOVE_SPRITE_BY_ICON := {
	"res://assets/characters/eco_roster/captain_eco.webp": "res://assets/characters/eco_roster/sprites/captain_eco_move_alpha.webp",
	"res://assets/characters/eco_roster/water_popo.webp": "res://assets/characters/eco_roster/sprites/water_popo_move_alpha.webp",
	"res://assets/characters/eco_roster/bear_pongi.webp": "res://assets/characters/eco_roster/sprites/bear_pongi_move_alpha.webp",
	"res://assets/characters/eco_roster/solar_fox_sol.webp": "res://assets/characters/eco_roster/sprites/solar_fox_sol_move_alpha.webp",
	"res://assets/characters/eco_roster/wind_rabbit_bori.webp": "res://assets/characters/eco_roster/sprites/wind_rabbit_bori_move_alpha.webp",
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.webp": "res://assets/characters/eco_roster/sprites/recycle_raccoon_ringo_move_alpha.webp",
	# 토리는 이동 중 3D 도약과 빠른 프레임 재생을 사용합니다. 투명 가장자리가 보존된 시트를 유지합니다.
	"res://assets/characters/eco_roster/earth_turtle_tori.webp": "res://assets/characters/eco_roster/sprites/earth_turtle_tori_idle.webp",
	"res://assets/characters/eco_roster/lightning_bird_pika.webp": "res://assets/characters/eco_roster/sprites/lightning_bird_pika_move_alpha.webp",
	"res://assets/characters/eco_roster/mushroom_cat_momo.webp": "res://assets/characters/eco_roster/sprites/mushroom_cat_momo_move_alpha.webp"
}

const BACK_RUN_SPRITE_BY_ICON := {
	"res://assets/characters/eco_roster/captain_eco.webp": "res://assets/characters/eco_roster/sprites/back_run/captain_eco_back_run.png",
	"res://assets/characters/eco_roster/fairy_sparky.webp": "res://assets/characters/eco_roster/sprites/back_run/fairy_sparky_back_run.png",
	"res://assets/characters/eco_roster/water_popo.webp": "res://assets/characters/eco_roster/sprites/back_run/water_popo_back_run.png",
	"res://assets/characters/eco_roster/bear_pongi.webp": "res://assets/characters/eco_roster/sprites/back_run/bear_pongi_back_run.png",
	"res://assets/characters/eco_roster/solar_fox_sol.webp": "res://assets/characters/eco_roster/sprites/back_run/solar_fox_sol_back_run.png",
	"res://assets/characters/eco_roster/wind_rabbit_bori.webp": "res://assets/characters/eco_roster/sprites/back_run/wind_rabbit_bori_back_run.png",
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.webp": "res://assets/characters/eco_roster/sprites/back_run/recycle_raccoon_ringo_back_run.png",
	"res://assets/characters/eco_roster/earth_turtle_tori.webp": "res://assets/characters/eco_roster/sprites/back_run/earth_turtle_tori_back_run.png",
	"res://assets/characters/eco_roster/lightning_bird_pika.webp": "res://assets/characters/eco_roster/sprites/back_run/lightning_bird_pika_back_run.png",
	"res://assets/characters/eco_roster/mushroom_cat_momo.webp": "res://assets/characters/eco_roster/sprites/back_run/mushroom_cat_momo_back_run.png"
}

const SIDE_RUN_SPRITE_BY_ICON := {
	"res://assets/characters/eco_roster/captain_eco.webp": "res://assets/characters/eco_roster/sprites/side_run/captain_eco_side_run.png",
	"res://assets/characters/eco_roster/fairy_sparky.webp": "res://assets/characters/eco_roster/sprites/side_run/fairy_sparky_side_run.png",
	"res://assets/characters/eco_roster/water_popo.webp": "res://assets/characters/eco_roster/sprites/side_run/water_popo_side_run.png",
	"res://assets/characters/eco_roster/bear_pongi.webp": "res://assets/characters/eco_roster/sprites/side_run/bear_pongi_side_run.png",
	"res://assets/characters/eco_roster/solar_fox_sol.webp": "res://assets/characters/eco_roster/sprites/side_run/solar_fox_sol_side_run.png",
	"res://assets/characters/eco_roster/wind_rabbit_bori.webp": "res://assets/characters/eco_roster/sprites/side_run/wind_rabbit_bori_side_run.png",
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.webp": "res://assets/characters/eco_roster/sprites/side_run/recycle_raccoon_ringo_side_run.png",
	"res://assets/characters/eco_roster/earth_turtle_tori.webp": "res://assets/characters/eco_roster/sprites/side_run/earth_turtle_tori_side_run.png",
	"res://assets/characters/eco_roster/lightning_bird_pika.webp": "res://assets/characters/eco_roster/sprites/side_run/lightning_bird_pika_side_run.png",
	"res://assets/characters/eco_roster/mushroom_cat_momo.webp": "res://assets/characters/eco_roster/sprites/side_run/mushroom_cat_momo_side_run.png"
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
	if board_model:
		if arcade_pose != ArcadePose.NONE:
			_advance_arcade_pose(delta)
			return
		board_model.rotation.y = rotate_toward(board_model.rotation.y, board_target_yaw, delta * 12.0)
		if board_animator.current_animation == &"idle":
			board_animator.advance(delta)
		elif not is_equal_approx(board_animator.current_animation_position, board_pose_time):
			board_animator.seek(board_pose_time, true)
		return
	if not animation_position_ready:
		last_animation_position = position
		animation_position_ready = true
	var movement := position - last_animation_position
	last_animation_position = position
	var horizontal_speed := Vector2(movement.x, movement.z).length() / maxf(delta, 0.001)
	animation_speed = lerpf(animation_speed, horizontal_speed, minf(1.0, delta * 12.0))
	if avatar_sprite != null and avatar_sprite.hframes > 1:
		if (use_back_run_sprite or use_side_run_sprite) and not is_moving:
			avatar_sprite.frame = 0
			return
		animation_elapsed += delta
		var animation_fps := clampf(6.0 + animation_speed * 0.85, 6.0, 15.0) if is_moving else IDLE_SPRITE_FPS
		animation_phase += delta * animation_fps
		avatar_sprite.frame = int(animation_phase) % avatar_sprite.hframes

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

func setup_arcade_player(p_data: Dictionary, view: ArcadePose, forward_speed: float = 0.0) -> void:
	arcade_pose = view
	course_speed = forward_speed
	board_target_yaw = 1.25 if view == ArcadePose.SIDE else PI
	setup_player(p_data)
	animation_position_ready = false

func setup_player(p_data: Dictionary) -> void:
	_init_components()
	player_index = p_data.get("index", 0)
	player_icon_path = str(p_data.get("char_icon", LEGACY_CAPTAIN_ICON))
	if player_icon_path.is_empty():
		player_icon_path = LEGACY_CAPTAIN_ICON
	_configure_avatar()
	if board_face:
		board_face.texture = preload("res://scripts/ui/HeroFace.gd").for_portrait(player_icon_path)
	_set_avatar_animation_state(false)
	set_shield_active(bool(p_data.get("shield", false)))
	_place_on_tile(0)

func _configure_avatar() -> void:
	if player_icon_path.is_empty():
		return
	var model_path := ""
	var roster_icon := player_icon_path.replace("res://assets/images/char_", "res://assets/characters/eco_roster/")
	if (board_presentation_enabled or arcade_pose != ArcadePose.NONE) and roster_icon in IDLE_SPRITE_BY_ICON:
		var slug := roster_icon.get_file().get_basename()
		if slug == "fairy_sparky":
			slug = "captain_eco"
		model_path = BOARD_MODEL_DIR + slug + ".glb"
	if board_model:
		if board_model.scene_file_path == model_path:
			return
		board_model.free()
		board_model = null
		board_animator = null
	if not model_path.is_empty() and ResourceLoader.exists(model_path, "PackedScene"):
		var scene := load(model_path) as PackedScene
		board_model = scene.instantiate() as Node3D
		add_child(board_model)
		board_model.rotation.y = board_target_yaw
		board_animator = board_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if board_animator and board_animator.has_animation(&"idle") and board_animator.has_animation(&"walk"):
			board_stride_length = _read_stride(board_model, &"board_stride_length", LEGACY_BOARD_STRIDE_LENGTH)
			arcade_stride_length = _read_stride(board_model, &"arcade_stride_length", board_stride_length)
			board_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			for clip_name in [&"idle", &"walk"]:
				board_animator.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
			for clip_name in [&"run", &"operate"]:
				if board_animator.has_animation(clip_name):
					board_animator.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
			if board_animator.has_animation(&"jump"):
				board_animator.get_animation(&"jump").loop_mode = Animation.LOOP_NONE
			avatar_sprite.hide()
			_apply_avatar_contact_scale()
			_set_avatar_animation_state(is_moving)
			return
		board_model.free()
		board_model = null
		board_animator = null
	avatar_sprite.show()
	_load_sprite_textures(player_icon_path)
	_set_avatar_animation_state(is_moving)

func _read_stride(model: Node3D, key: StringName, fallback: float) -> float:
	# Imported glTF node extras carry the authored travel for one complete loop.
	for node: Node in [model] + model.find_children("*", "", true, false):
		var extras: Dictionary = node.get_meta(&"extras", {})
		var length := float(extras.get(key, 0.0))
		if is_finite(length) and length > 0.0:
			return length
	return fallback

func _load_sprite_textures(icon_path: String) -> void:
	idle_sprite_texture = null
	move_sprite_texture = null
	back_run_sprite_texture = null
	side_run_sprite_texture = null
	var idle_sprite_path := str(IDLE_SPRITE_BY_ICON.get(icon_path, ""))
	var move_sprite_path := str(MOVE_SPRITE_BY_ICON.get(icon_path, ""))
	var back_run_sprite_path := str(BACK_RUN_SPRITE_BY_ICON.get(icon_path, ""))
	var side_run_sprite_path := str(SIDE_RUN_SPRITE_BY_ICON.get(icon_path, ""))
	if avatar_sprite and not idle_sprite_path.is_empty() and ResourceLoader.exists(idle_sprite_path):
		idle_sprite_texture = load(idle_sprite_path)
		if not move_sprite_path.is_empty() and ResourceLoader.exists(move_sprite_path):
			move_sprite_texture = load(move_sprite_path)
		else:
			move_sprite_texture = idle_sprite_texture
		if not back_run_sprite_path.is_empty() and ResourceLoader.exists(back_run_sprite_path):
			back_run_sprite_texture = load(back_run_sprite_path)
		else:
			back_run_sprite_texture = move_sprite_texture
		if not side_run_sprite_path.is_empty() and ResourceLoader.exists(side_run_sprite_path):
			side_run_sprite_texture = load(side_run_sprite_path)
		else:
			side_run_sprite_texture = move_sprite_texture
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

func set_board_presentation(enabled: bool, display_name: String = "", is_local: bool = false) -> void:
	# Arcade pawns deliberately keep their original contact size and prompts.
	board_presentation_enabled = enabled
	board_display_name = display_name
	board_is_local = is_local
	_configure_avatar()
	if enabled and board_turn_ring == null:
		board_turn_ring = MeshInstance3D.new()
		board_turn_ring.name = "ActivePlayerRing"
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.37
		mesh.outer_radius = 0.45
		mesh.rings = 24
		mesh.ring_segments = 4
		board_turn_ring.mesh = mesh
		board_turn_ring.position.y = 0.035
		board_turn_material = StandardMaterial3D.new()
		board_turn_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		board_turn_material.albedo_color = Color("ffd166")
		board_turn_ring.material_override = board_turn_material
		add_child(board_turn_ring)
		board_face = Sprite3D.new()
		board_face.name = "ActiveHeroFace"
		board_face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		board_face.shaded = false
		board_face.no_depth_test = true
		board_face.render_priority = 10
		board_face.pixel_size = 0.0042
		board_face.position.y = 1.49
		board_face.texture = preload("res://scripts/ui/HeroFace.gd").for_portrait(player_icon_path)
		add_child(board_face)
		board_turn_label = Label3D.new()
		board_turn_label.name = "ActivePlayerName"
		board_turn_label.font_size = 42
		board_turn_label.pixel_size = 0.006
		board_turn_label.outline_size = 8
		board_turn_label.modulate = Color("fff1b6")
		board_turn_label.outline_modulate = Color("14333c")
		board_turn_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		board_turn_label.no_depth_test = true
		add_child(board_turn_label)
	set_board_current_turn(board_current_turn)

func set_board_current_turn(active: bool) -> void:
	board_current_turn = active and board_presentation_enabled
	if board_turn_ring:
		board_turn_ring.visible = board_current_turn
	if board_face:
		board_face.visible = board_current_turn
	if board_turn_label:
		board_turn_label.visible = board_current_turn
		board_turn_label.text = ("내 캐릭터 · " if board_is_local else "진행 중 · ") + board_display_name.left(12)
		board_turn_label.position.y = 1.95
	if avatar_sprite:
		avatar_sprite.no_depth_test = board_current_turn
		_apply_avatar_contact_scale()

func _board_avatar_scale() -> float:
	if not board_presentation_enabled:
		return 1.0
	return BOARD_ACTIVE_AVATAR_SCALE if board_current_turn else BOARD_AVATAR_SCALE

func _apply_avatar_contact_scale(stretch_y: float = 1.0) -> void:
	if board_model:
		board_model.scale = Vector3.ONE * _board_avatar_scale()
		return
	if avatar_sprite:
		var visual_scale := _board_avatar_scale()
		avatar_sprite.scale = Vector3(visual_scale / sqrt(stretch_y), visual_scale * stretch_y, 1.0)
		avatar_sprite.position.y = AVATAR_CENTER_HEIGHT * visual_scale * stretch_y

func _face_board_step(from_position: Vector3, to_position: Vector3) -> void:
	if not board_presentation_enabled:
		return
	var direction := to_position - from_position
	if board_model:
		board_target_yaw = atan2(direction.x, direction.z)
		return
	use_side_run_sprite = absf(direction.x) > absf(direction.z)
	use_back_run_sprite = not use_side_run_sprite and direction.z < 0.0
	avatar_sprite.flip_h = use_side_run_sprite and direction.x < 0.0
	_set_avatar_animation_state(true)

func animate_move_to_tile(to_tile_idx: int) -> void:
	var from_tile := current_tile
	current_tile = to_tile_idx
	var pawn_offset: Vector3 = PAWN_OFFSETS_3D[player_index % 4]
	
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	board_shortcut_jump = BoardGrid.is_shortcut_transition(from_tile, to_tile_idx)
	_set_avatar_animation_state(true)
	move_tween = create_tween().set_parallel(false)

	# 사다리/미끄럼틀 3D 아치형 점프 도약
	if board_shortcut_jump:
		var from_pos := position
		var to_pos := _get_tile_contact_position(to_tile_idx, pawn_offset)
		var jump_duration: float = BoardGrid.SHORTCUT_MOVE_SECONDS
		
		# 3D 포물선 도약 트윈
		_face_board_step(from_pos, to_pos)
		move_tween.tween_method(
			_update_hop_position.bind(from_pos, to_pos, 2.2),
			0.0, 1.0, jump_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		move_tween.tween_callback(_place_on_tile.bind(to_tile_idx))
		move_tween.tween_callback(_set_avatar_animation_state.bind(false))
		return

	# 입체 말은 칸 사이를 걸어서 이동하고 스프라이트 말은 칸마다 도약합니다.
	var direction := 1 if to_tile_idx > from_tile else -1
	var step_tile := from_tile + direction
	
	while step_tile != to_tile_idx + direction:
		var previous_tile := step_tile - direction
		var start_p := _get_tile_contact_position(previous_tile, pawn_offset)
		var target_p := _get_tile_contact_position(step_tile, pawn_offset)
		var step_dur: float = BoardGrid.MOVE_STEP_SECONDS
		move_tween.tween_callback(_face_board_step.bind(start_p, target_p))
		if board_model:
			var exit_direction := Vector3.ZERO
			if step_tile != to_tile_idx:
				exit_direction = _get_tile_contact_position(step_tile + direction, pawn_offset) - target_p
			move_tween.tween_method(_advance_board_step.bind(start_p, target_p, exit_direction), 0.0, 1.0, step_dur)
		else:
			move_tween.tween_method(_update_hop_position.bind(start_p, target_p, 0.68), 0.0, 1.0, step_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
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
	if board_animator:
		is_moving = should_move
		var clip_name := &"walk" if should_move else &"idle"
		if (arcade_lift > 0.07 or (should_move and board_shortcut_jump)) and board_animator.has_animation(&"jump"):
			clip_name = &"jump"
		elif should_move and arcade_pose == ArcadePose.CONTROL and board_animator.has_animation(&"operate"):
			clip_name = &"operate"
		elif should_move and arcade_pose != ArcadePose.NONE and board_animator.has_animation(&"run"):
			clip_name = &"run"
		if board_animator.current_animation != clip_name:
			var initial_pose := board_animator.assigned_animation.is_empty()
			board_pose_time = 0.0
			board_animator.play(clip_name, 0.12 if clip_name == &"idle" else 0.0)
			if initial_pose:
				board_animator.seek(board_animator.current_animation_length * fmod(player_index * 0.27, 1.0), true)
		return
	if avatar_sprite == null:
		is_moving = should_move
		return
	var next_texture := side_run_sprite_texture if use_side_run_sprite else (back_run_sprite_texture if use_back_run_sprite else idle_sprite_texture)
	if should_move and not use_back_run_sprite and not use_side_run_sprite:
		next_texture = move_sprite_texture
	# Arcade controllers report the movement state every frame. Do not restart
	# the sheet on each report, otherwise a running character freezes at frame 0.
	if is_moving == should_move and avatar_sprite.texture == next_texture and next_texture != null:
		return
	is_moving = should_move
	animation_elapsed = 0.0
	animation_phase = 0.0
	if next_texture != null:
		avatar_sprite.texture = next_texture
		avatar_sprite.hframes = MOVE_SPRITE_FRAMES if is_moving or use_back_run_sprite or use_side_run_sprite else IDLE_SPRITE_FRAMES
		avatar_sprite.vframes = 1
		avatar_sprite.frame = 0

func set_arcade_lift(lift: float) -> void:
	var was_airborne := arcade_lift > 0.07
	if lift > 0.07:
		peak_lift = maxf(peak_lift, lift)
		if lift < arcade_lift - 0.001:
			descending = true
	else:
		peak_lift = 0.0
		descending = false
	arcade_lift = lift
	if was_airborne != (lift > 0.07):
		_set_avatar_animation_state(is_moving)

func _advance_arcade_pose(delta: float) -> void:
	var distance_x := position.x - last_animation_position.x if animation_position_ready else 0.0
	last_animation_position = position
	animation_position_ready = true
	if arcade_pose == ArcadePose.SIDE and absf(distance_x) > 0.0001:
		board_target_yaw = signf(distance_x) * 1.25
	board_model.rotation.y = rotate_toward(board_model.rotation.y, board_target_yaw, 14.0 * delta)
	match board_animator.current_animation:
		&"walk", &"run":
			# The auto-runner's road moves under the hero. Side-view games move
			# the pawn directly, including a blocked step or a return to centre.
			var travel := course_speed * delta if arcade_pose == ArcadePose.RUNNER else absf(distance_x)
			var stride := arcade_stride_length * absf(scale.x)
			var length := board_animator.current_animation_length
			_set_board_motion_time(fposmod(board_pose_time + travel * length / maxf(0.01, stride), length))
		&"jump":
			var fraction := 0.16 + 0.34 * clampf(arcade_lift / maxf(0.1, scale.y * 0.48), 0, 1)
			if descending:
				fraction = 0.88 - 0.38 * clampf(arcade_lift / maxf(peak_lift, 0.1), 0, 1)
			_set_board_motion_time(board_animator.current_animation_length * fraction)
		_:
			board_animator.advance(delta)

func set_back_run_enabled(enabled: bool) -> void:
	use_back_run_sprite = enabled
	if enabled:
		use_side_run_sprite = false
	_set_avatar_animation_state(is_moving)

func set_side_run_enabled(enabled: bool) -> void:
	use_side_run_sprite = enabled
	if enabled:
		use_back_run_sprite = false
	_set_avatar_animation_state(is_moving)

func _advance_board_step(progress: float, from_position: Vector3, to_position: Vector3, exit_direction: Vector3) -> void:
	var previous_position := position
	position = from_position.lerp(to_position, progress)
	_update_ground_shadow(position.y, 0.0)
	var distance := Vector2(position.x - previous_position.x, position.z - previous_position.z).length()
	var cycles := distance / (_board_avatar_scale() * board_stride_length)
	var loop_length := board_animator.current_animation_length
	_set_board_motion_time(fposmod(board_pose_time + cycles * loop_length, loop_length))
	if exit_direction != Vector3.ZERO:
		var heading := to_position - from_position
		var turn := 0.5 * smoothstep(0.80, 1.0, progress)
		board_target_yaw = lerp_angle(atan2(heading.x, heading.z), atan2(exit_direction.x, exit_direction.z), turn)

func _set_board_motion_time(time: float) -> void:
	board_pose_time = time
	# Movement continues behind overlays. Sample the skeleton again when visible.
	if is_processing():
		board_animator.seek(board_pose_time, true)

func _update_hop_position(progress: float, from_position: Vector3, to_position: Vector3, hop_height: float) -> void:
	var ground := from_position.lerp(to_position, progress)
	var lift := sin(progress * PI) * hop_height
	position = ground + Vector3(0, lift, 0)
	_update_ground_shadow(ground.y, lift)
	if board_model and board_shortcut_jump:
		var phase := progress
		if board_animator.current_animation != &"jump":
			# Older models can still tuck their feet using the travel clip.
			phase = lerpf(0.0, 0.5, smoothstep(0.0, 1.0, progress))
			board_model.rotation.x = sin(progress * TAU) * 0.10
		_set_board_motion_time(board_animator.current_animation_length * phase)
	elif avatar_sprite:
		var stretch_y := 1.0 + sin(progress * TAU) * 0.07
		_apply_avatar_contact_scale(stretch_y)

func _get_tile_contact_position(tile_index: int, pawn_offset: Vector3 = Vector3.ZERO) -> Vector3:
	var tile_position := BoardGrid.get_tile_position_3d(tile_index) + pawn_offset
	tile_position.y = BoardGrid.get_tile_surface_height(tile_index)
	return tile_position

func _place_on_tile(tile_index: int) -> void:
	current_tile = clampi(tile_index, 0, BoardGrid.LAST_TILE_INDEX)
	position = _get_tile_contact_position(current_tile, PAWN_OFFSETS_3D[player_index % 4])
	last_animation_position = position
	animation_speed = 0.0
	board_shortcut_jump = false
	if board_model:
		board_model.rotation.x = 0.0
	_update_ground_shadow(position.y, 0.0)
	if avatar_sprite:
		_apply_avatar_contact_scale()

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
