extends Node

## GameManager: 4인 보드게임 핵심 세션 및 턴 상태 머신 (Singleton)

signal turn_changed(current_player_idx)
signal player_moved(player_idx, from_tile, to_tile)
signal player_state_changed(player_idx)
signal dice_rolled(player_idx, value)
signal dice_input_time_changed(player_idx, remaining_seconds)
signal quiz_requested(player_idx, quiz_data)
signal quiz_resolved(player_idx, is_correct)
signal spectator_quiz_bonus_resolved(observer_idx, target_idx, is_correct, bonus_score)
signal game_over(rankings)
signal status_message_posted(msg)
signal kingdom_progress_changed(projects_built, total_projects, kingdom_health)
signal player_inventory_changed(player_idx, inventory)
signal tile_item_collected(tile_index, player_idx, item_id)
signal special_skill_activated(player_idx, target_index, skill)
signal special_skill_completed(player_idx)
signal village_construction_started(inventory)
signal village_construction_changed(inventory, projects_built, kingdom_health)
signal game_time_changed(remaining_seconds, total_seconds)
signal lap_completed(player_idx, lap_number, rank, reward_count)
signal lap_reward_requested(player_idx, rank, reward_count)
signal lap_reward_completed(player_idx, selected_items)

enum TurnState {
	WAIT_ACTION,
	ROLLING_DICE,
	PLAYER_MOVING,
	TILE_EVENT,
	RESOLVING_QUIZ,
	TURN_END,
	GAME_OVER
}

const DICE_ROLL_ANIMATION_SECONDS := 1.10
const PLAYER_DICE_INPUT_SECONDS := 20.0
const AI_SPECIAL_SKILL_USE_CHANCE := 0.5
const AI_POST_SPECIAL_ACTION_DELAY_SECONDS := 1.0
const AI_VILLAGE_BUILD_DELAY_SECONDS := 0.75
# AI가 문제를 읽고 답을 고르는 시간을 기존 3.9초보다 5초 늘렸습니다.
const AI_QUIZ_THINK_SECONDS := 8.9
const MAX_PLAYER_COUNT := 4
const DEFAULT_GAME_DURATION_SECONDS := 600
const MIN_GAME_DURATION_SECONDS := 60
const REQUIRED_TEAM_QUIZ_CORRECT := 4
const VILLAGE_RECOVERY_TARGET := 70
const QUIZ_CORRECT_SCORE := 10
const SPECTATOR_QUIZ_BONUS_SCORE := QUIZ_CORRECT_SCORE / 2
# 게임 종료 시 누적 이동 거리 1~4위가 받는 일반 에너지입니다.
# 이 에너지는 최종 순위 계산 전에 지급되어 실제 순위에 반영됩니다.
const MOVEMENT_END_REWARDS: Array[int] = [120, 80, 40, 20]
const SPECIAL_SKILLS_BY_ICON := {
	"res://assets/characters/eco_roster/captain_eco.png": {"id": "eco_dash", "name": "자연의 돌진", "description": "자연의 길을 열어 앞쪽 1~5칸 타일로 즉시 이동합니다.", "cost": 3, "target_type": "tile", "effect": "move", "range": 5},
	"res://assets/characters/eco_roster/fairy_sparky.png": {"id": "starlight_charge", "name": "별빛 충전", "description": "자신의 일반 에너지를 3 충전합니다.", "cost": 3, "target_type": "self", "effect": "energy_boost", "amount": 3},
	"res://assets/characters/eco_roster/water_popo.png": {"id": "purifying_wave", "name": "정화의 물결", "description": "자신에게 방패와 일반 에너지 1을 부여합니다.", "cost": 3, "target_type": "self", "effect": "purify", "amount": 1},
	"res://assets/characters/eco_roster/bear_pongi.png": {"id": "forest_supply", "name": "숲의 보급", "description": "자신의 개인 보관함에 무작위 건설 재료 1개를 보급합니다.", "cost": 4, "target_type": "self", "effect": "material_supply", "amount": 1},
	"res://assets/characters/eco_roster/solar_fox_sol.png": {"id": "solar_charge", "name": "태양 충전", "description": "자신의 일반 에너지를 4 충전합니다.", "cost": 3, "target_type": "self", "effect": "energy_boost", "amount": 4},
	"res://assets/characters/eco_roster/wind_rabbit_bori.png": {"id": "wind_path", "name": "바람길 질주", "description": "바람길을 타고 앞쪽 1~7칸 타일로 즉시 이동합니다.", "cost": 3, "target_type": "tile", "effect": "move", "range": 7},
	"res://assets/characters/eco_roster/recycle_raccoon_ringo.png": {"id": "recycle_salvage", "name": "재활용 회수", "description": "선택한 미획득 타일의 건설 재료를 회수합니다.", "cost": 3, "target_type": "tile", "effect": "collect_material"},
	"res://assets/characters/eco_roster/earth_turtle_tori.png": {"id": "earth_barrier", "name": "대지 방벽", "description": "자신에게 다음 미끄럼틀이나 오답 후퇴를 막는 방패를 부여합니다.", "cost": 3, "target_type": "self", "effect": "shield"},
	"res://assets/characters/eco_roster/lightning_bird_pika.png": {"id": "lightning_leap", "name": "번개 도약", "description": "번개처럼 앞쪽 1~9칸 타일로 즉시 이동합니다.", "cost": 4, "target_type": "tile", "effect": "move", "range": 9},
	"res://assets/characters/eco_roster/mushroom_cat_momo.png": {"id": "mycelium_harvest", "name": "균사체 채집", "description": "선택한 미획득 타일의 건설 재료를 채집합니다.", "cost": 3, "target_type": "tile", "effect": "collect_material"}
}
const DEFAULT_SPECIAL_SKILL := {"id": "eco_dash", "name": "자연의 돌진", "description": "앞쪽 1~5칸 타일로 즉시 이동합니다.", "cost": 3, "target_type": "tile", "effect": "move", "range": 5}
const ITEM_DEFINITIONS := {
	"solar_panel": {"name": "태양광 패널", "icon": "☀️", "asset": "res://assets/items/solar_panel.png"},
	"wind_blade": {"name": "풍력 터빈 날개", "icon": "🌬️", "asset": "res://assets/items/wind_blade.png"},
	"battery": {"name": "에너지 저장 배터리", "icon": "🔋", "asset": "res://assets/items/battery.png"},
	"insulation": {"name": "고효율 단열재", "icon": "🏠", "asset": "res://assets/items/insulation.png"},
	"smart_grid": {"name": "스마트 그리드 코어", "icon": "🔌", "asset": "res://assets/items/smart_grid.png"},
	"hydro_turbine": {"name": "수력 터빈", "icon": "💧", "asset": "res://assets/items/hydro_turbine.png"},
	"geothermal_core": {"name": "지열 교환 코어", "icon": "♨️", "asset": "res://assets/items/geothermal_core.png"},
	"tidal_generator": {"name": "조력 발전 기어", "icon": "🌊", "asset": "res://assets/items/tidal_generator.png"},
	"reactor_control_core": {"name": "원자로 제어 코어", "icon": "⚛️", "asset": "res://assets/items/reactor_control_core.png"},
	"recycled_composite": {"name": "재생 복합소재", "icon": "♻️", "asset": "res://assets/items/recycled_composite.png"},
	"fast_charge_module": {"name": "고속 충전 모듈", "icon": "🔋", "asset": "res://assets/items/fast_charge_module.png"}
}
const CONSTRUCTION_PROJECTS := [
	{"name": "태양광 발전소", "image": "res://assets/buildings/solar_power_plant.png", "requirements": {"solar_panel": 2, "battery": 1}, "terrains": ["solar_field"], "terrain_label": "햇빛 초원", "health": 35, "message": "햇빛으로 전기를 만드는 태양광 발전소가 완공됐습니다!"},
	{"name": "풍력 발전단지", "image": "res://assets/buildings/wind_power_complex.png", "requirements": {"wind_blade": 2, "smart_grid": 1}, "terrains": ["wind_plain", "wind_coast"], "terrain_label": "바람 들판 또는 해안 절벽", "health": 35, "message": "맑은 바람을 전기로 바꾸는 풍력 발전단지가 돌아가기 시작했습니다!"},
	{"name": "에너지 절약 건물", "image": "res://assets/buildings/efficiency_building.png", "requirements": {"insulation": 2, "smart_grid": 1}, "terrains": ["eco_city"], "terrain_label": "친환경 도시", "health": 25, "message": "단열과 절전 설비를 갖춘 에너지 절약 건물이 늘어났습니다!"},
	{"name": "에너지 저장소", "image": "res://assets/buildings/energy_storage_facility.png", "requirements": {"battery": 2, "smart_grid": 1}, "terrains": ["grid_hub"], "terrain_label": "전력망 광장", "health": 25, "message": "남는 전기를 모아 쓰는 에너지 저장소가 완공됐습니다!"},
	{"name": "소수력 발전소", "image": "res://assets/buildings/small_hydro_plant.png", "requirements": {"hydro_turbine": 2, "smart_grid": 1}, "terrains": ["riverbank"], "terrain_label": "강변 수로", "health": 30, "message": "강물의 흐름을 살린 친환경 소수력 발전소가 완공됐습니다!"},
	{"name": "지열 발전소", "image": "res://assets/buildings/geothermal_power_plant.png", "requirements": {"geothermal_core": 2, "insulation": 1}, "terrains": ["geothermal_field"], "terrain_label": "지열 온천 지대", "health": 30, "message": "땅속 열을 안정적인 전기로 바꾸는 지열 발전소가 완공됐습니다!"},
	{"name": "조력 발전소", "image": "res://assets/buildings/tidal_power_plant.png", "requirements": {"tidal_generator": 2, "battery": 1}, "terrains": ["tidal_lagoon"], "terrain_label": "바닷가 조력 석호", "health": 30, "message": "밀물과 썰물의 힘을 이용하는 조력 발전소가 완공됐습니다!"},
	{"name": "원자력 발전소", "image": "res://assets/buildings/nuclear_power_plant.png", "requirements": {"reactor_control_core": 2, "smart_grid": 1}, "terrains": ["nuclear_site"], "terrain_label": "안전 관리 부지", "health": 40, "message": "안전 제어 설비를 갖춘 차세대 원자력 발전소가 안정적으로 전력을 공급합니다!"},
	{"name": "자원순환 생활센터", "category": "친환경 생활", "image": "res://assets/buildings/resource_circulation_center.png", "requirements": {"recycled_composite": 2, "smart_grid": 1}, "terrains": ["eco_city"], "terrain_label": "친환경 마을", "health": 20, "message": "수리·재사용·분리배출을 한곳에서 실천하는 자원순환 생활센터가 문을 열었습니다!"},
	{"name": "전기 대중교통 허브", "category": "친환경 생활", "image": "res://assets/buildings/electric_transit_hub.png", "requirements": {"fast_charge_module": 2, "battery": 1}, "terrains": ["grid_hub"], "terrain_label": "다리 옆 전력 광장", "health": 25, "message": "전기 셔틀과 자전거를 편리하게 이용하는 친환경 교통 거점이 완성됐습니다!"}
]
const MATERIAL_DRAW_BAG: Array[String] = [
	"solar_panel", "wind_blade", "battery", "insulation", "smart_grid", "hydro_turbine",
	"geothermal_core", "tidal_generator", "reactor_control_core", "recycled_composite", "fast_charge_module"
]

var current_state: TurnState = TurnState.WAIT_ACTION
# 4인 플레이어 데이터 목록
var players: Array[Dictionary] = []
var current_turn_idx: int = 0
var total_turns: int = 0
var is_game_active: bool = false
var active_quiz_data: Dictionary = {}
var active_quiz_player_idx: int = -1
var active_spectator_quiz_attempts: Dictionary = {}
var game_session_id: int = 0
var projects_built := 0
var kingdom_health := 0
var kingdom_recovered := false
var team_quiz_correct := 0
var ai_fill_count := 0
var village_construction_active := false
var built_project_ids: Array[int] = []
var built_project_placements: Dictionary = {}
var built_project_owners: Dictionary = {}
var collected_item_tiles: Dictionary = {}
var special_skill_used_this_turn := false
var game_duration_seconds := DEFAULT_GAME_DURATION_SECONDS
var game_time_remaining := float(DEFAULT_GAME_DURATION_SECONDS)
var lap_finish_orders: Dictionary = {}
var pending_lap_reward: Dictionary = {}
var _last_emitted_time_seconds := -1
var dice_input_time_remaining := 0.0
var _last_emitted_dice_input_seconds := -1
var village_ai_builder_cursor := 0
var village_ai_construction_running := false

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if not is_game_active or village_construction_active or not pending_lap_reward.is_empty():
		return
	game_time_remaining = maxf(0.0, game_time_remaining - delta)
	var display_seconds := ceili(game_time_remaining)
	if display_seconds != _last_emitted_time_seconds:
		_last_emitted_time_seconds = display_seconds
		game_time_changed.emit(display_seconds, game_duration_seconds)
	if game_time_remaining <= 0.0:
		status_message_posted.emit("⏰ 설정한 플레이 시간이 끝났습니다. 모은 개인 재료로 친환경 마을을 건설합니다!")
		_start_village_construction_phase()
		return
	_update_player_dice_input_timer(delta)

# 게임 초기화 (로비에서 호출)
func setup_game(player_configs: Array[Dictionary], duration_seconds: int = DEFAULT_GAME_DURATION_SECONDS) -> void:
	game_session_id += 1
	players.clear()
	total_turns = 0
	current_turn_idx = 0
	projects_built = 0
	kingdom_health = 0
	kingdom_recovered = false
	team_quiz_correct = 0
	ai_fill_count = 0
	special_skill_used_this_turn = false
	village_construction_active = false
	built_project_ids.clear()
	built_project_placements.clear()
	built_project_owners.clear()
	collected_item_tiles.clear()
	active_spectator_quiz_attempts.clear()
	lap_finish_orders.clear()
	pending_lap_reward.clear()
	village_ai_builder_cursor = 0
	village_ai_construction_running = false
	game_duration_seconds = maxi(MIN_GAME_DURATION_SECONDS, duration_seconds)
	game_time_remaining = float(game_duration_seconds)
	_last_emitted_time_seconds = game_duration_seconds
	dice_input_time_remaining = 0.0
	_last_emitted_dice_input_seconds = -1
	BoardGrid.assign_random_shortcuts()
	
	# 싱글플레이와 인원 미달 파티 모두 최대 4인까지 AI 동료로 자동 채웁니다.
	var default_chars = [
		{"name": "캡틴 에코", "icon": "res://assets/characters/eco_roster/captain_eco.png", "color": Color(0.2, 0.8, 0.3)},
		{"name": "포포", "icon": "res://assets/characters/eco_roster/water_popo.png", "color": Color(0.2, 0.6, 0.95)},
		{"name": "퐁이", "icon": "res://assets/characters/eco_roster/bear_pongi.png", "color": Color(0.4, 0.9, 0.8)},
		{"name": "태양 여우 솔", "icon": "res://assets/characters/eco_roster/solar_fox_sol.png", "color": Color(1.0, 0.58, 0.12)}
	]
	
	for i in range(MAX_PLAYER_COUNT):
		var p_info: Dictionary = {}
		if i < player_configs.size():
			p_info = player_configs[i]
		else:
			p_info = {
				"name": default_chars[i]["name"] + " (AI)",
				"is_ai": true,
				"char_icon": default_chars[i]["icon"],
				"char_color": default_chars[i]["color"]
			}
		# 스파키는 이제 구조 대상이 아니라 왕국의 안내자이므로 플레이어 말로 선택하지 않습니다.
		if p_info.get("char_icon", "") == "res://assets/characters/eco_roster/fairy_sparky.png":
			p_info = p_info.duplicate(true)
			p_info["char_icon"] = default_chars[i]["icon"]
			p_info["char_color"] = default_chars[i]["color"]
			if "스파키" in str(p_info.get("name", "")):
				p_info["name"] = default_chars[i]["name"] + " (AI)"
			
		var player_data = {
			"index": i,
			"name": p_info.get("name", "플레이어 %d" % (i + 1)),
			"is_ai": p_info.get("is_ai", false),
			"char_icon": p_info.get("char_icon", default_chars[i]["icon"]),
			"char_color": p_info.get("char_color", default_chars[i]["color"]),
			"position": 0,
			"total_tiles_moved": 0,
			"movement_rank": 0,
			"movement_reward_energy": 0,
			"energy": 5, # 초기 에너지 5개
			"skill_energy": 0, # 퀴즈 정답으로만 모으는 특수기술 전용 에너지
			"quiz_correct": 0,
			"bonus_quiz_score": 0,
			"construction_contribution": 0,
			"inventory": _create_empty_inventory(),
			"project_completion_bonus": 0,
			"laps_completed": 0,
			"last_lap_rank": 0,
			"lap_reward_items": 0,
			"shield": false,
			"skip_turn": false,
			"badges": []
		}
		if player_data["is_ai"]:
			ai_fill_count += 1
		
		players.append(player_data)
		
	is_game_active = true
	active_quiz_data.clear()
	active_quiz_player_idx = -1
	active_spectator_quiz_attempts.clear()
	current_state = TurnState.WAIT_ACTION
	kingdom_progress_changed.emit(projects_built, CONSTRUCTION_PROJECTS.size(), kingdom_health)
	game_time_changed.emit(game_duration_seconds, game_duration_seconds)
	for player_idx in range(players.size()):
		player_inventory_changed.emit(player_idx, players[player_idx]["inventory"].duplicate(true))
	var party_message := "⚠️ 에너지요정 나라가 낭비와 화석연료 의존으로 위기에 빠졌습니다. 게임판을 탐험해 칸 위의 발전소 건설 자재를 모으세요!"
	if ai_fill_count > 0:
		party_message += " 빈 자리 %d곳은 AI 동료가 함께합니다." % ai_fill_count
	status_message_posted.emit(party_message)

func stop_game() -> void:
	game_session_id += 1
	is_game_active = false
	current_state = TurnState.WAIT_ACTION
	active_quiz_data.clear()
	active_quiz_player_idx = -1
	active_spectator_quiz_attempts.clear()
	pending_lap_reward.clear()
	game_time_remaining = 0.0
	dice_input_time_remaining = 0.0
	_last_emitted_dice_input_seconds = -1
	village_ai_construction_running = false

func start_first_turn() -> void:
	current_turn_idx = 0
	start_turn()

func start_turn() -> void:
	if not is_game_active:
		return
		
	var cur_p = players[current_turn_idx]
	current_state = TurnState.WAIT_ACTION
	special_skill_used_this_turn = false
	dice_input_time_remaining = 0.0
	_last_emitted_dice_input_seconds = -1
	turn_changed.emit(current_turn_idx)
	status_message_posted.emit("[%s] 님의 턴입니다." % cur_p["name"])
	
	# 휴식 턴 체크
	if cur_p["skip_turn"]:
		cur_p["skip_turn"] = false
		status_message_posted.emit("💤 [%s] 님은 에코 쉼터에서 쉬어갑니다." % cur_p["name"])
		end_turn()
		return
		
	# AI 봇인 경우 자동 액션
	if cur_p["is_ai"]:
		_schedule_game_action(1.2, _ai_execute_turn)
	else:
		dice_input_time_remaining = PLAYER_DICE_INPUT_SECONDS
		_last_emitted_dice_input_seconds = int(PLAYER_DICE_INPUT_SECONDS)
		dice_input_time_changed.emit(current_turn_idx, int(PLAYER_DICE_INPUT_SECONDS))

func _update_player_dice_input_timer(delta: float) -> void:
	if players.is_empty() or current_state != TurnState.WAIT_ACTION or dice_input_time_remaining <= 0.0:
		return
	var player_idx := current_turn_idx
	if player_idx < 0 or player_idx >= players.size() or bool(players[player_idx].get("is_ai", false)):
		return
	dice_input_time_remaining = maxf(0.0, dice_input_time_remaining - delta)
	var display_seconds := ceili(dice_input_time_remaining)
	if display_seconds != _last_emitted_dice_input_seconds:
		_last_emitted_dice_input_seconds = display_seconds
		dice_input_time_changed.emit(player_idx, display_seconds)
	if dice_input_time_remaining <= 0.0:
		status_message_posted.emit("⏱️ [%s] 주사위 선택 시간이 20초를 넘어 자동으로 굴립니다!" % players[player_idx]["name"])
		execute_roll_dice(player_idx)

func _ai_execute_turn() -> void:
	if current_state != TurnState.WAIT_ACTION:
		return
	var player_idx := current_turn_idx
	# SP가 충분한 AI는 절반의 확률로 캐릭터 고유 기술과 유효 대상을 무작위로
	# 고릅니다. 특수기술은 보너스 행동이므로 사용 후에도 주사위를 굴립니다.
	if can_use_special_skill(player_idx) and randf() < AI_SPECIAL_SKILL_USE_CHANCE:
		var skill := get_player_special_skill(player_idx)
		if _try_ai_use_random_special_skill(player_idx):
			if str(skill.get("effect", "")) == "move":
				return
			_schedule_game_action(AI_POST_SPECIAL_ACTION_DELAY_SECONDS, _ai_roll_after_special.bind(player_idx))
			return
	execute_roll_dice(player_idx)

func _try_ai_use_random_special_skill(player_idx: int) -> bool:
	if not can_use_special_skill(player_idx) or not bool(players[player_idx].get("is_ai", false)):
		return false
	var skill := get_player_special_skill(player_idx)
	var target_type := str(skill.get("target_type", "tile"))
	var effect := str(skill.get("effect", ""))
	var valid_targets: Array[int] = []
	if target_type == "self":
		valid_targets.append(player_idx)
	elif target_type == "player":
		for target_player_idx in range(players.size()):
			valid_targets.append(target_player_idx)
	elif effect == "move":
		var current_position := int(players[player_idx].get("position", 0))
		var furthest_target: int = mini(BoardGrid.LAST_TILE_INDEX - 1, current_position + int(skill.get("range", 1)))
		for target_tile in range(current_position + 1, furthest_target + 1):
			valid_targets.append(target_tile)
	else:
		for target_tile in range(1, BoardGrid.LAST_TILE_INDEX):
			if effect != "collect_material" or not collected_item_tiles.has(target_tile):
				valid_targets.append(target_tile)
	if valid_targets.is_empty():
		return false
	var selected_target := valid_targets[randi() % valid_targets.size()]
	return use_special_skill(player_idx, selected_target)

func _ai_roll_after_special(player_idx: int) -> void:
	if not is_game_active or current_turn_idx != player_idx or current_state != TurnState.WAIT_ACTION:
		return
	if not bool(players[player_idx].get("is_ai", false)):
		return
	execute_roll_dice(player_idx)

# 주사위 굴리기 실행
func execute_roll_dice(player_idx: int) -> void:
	if current_state != TurnState.WAIT_ACTION or player_idx != current_turn_idx:
		return
	dice_input_time_remaining = 0.0
	_last_emitted_dice_input_seconds = -1
	var roll_val = randi() % 6 + 1

	if NetworkManager.is_online and NetworkManager.is_host:
		NetworkManager.rpc_roll_dice.rpc(player_idx, roll_val)
	else:
		on_network_dice_rolled(player_idx, roll_val)

func on_network_dice_rolled(player_idx: int, dice_val: int) -> void:
	if not is_game_active or player_idx != current_turn_idx or current_state != TurnState.WAIT_ACTION:
		return
	dice_input_time_remaining = 0.0
	_last_emitted_dice_input_seconds = -1
	current_state = TurnState.ROLLING_DICE
	AudioManager.play_dice_sfx()
	status_message_posted.emit("🎲 [%s] 에너지 주사위를 굴리는 중..." % players[player_idx]["name"])
	dice_rolled.emit(player_idx, dice_val)
	_schedule_game_action(DICE_ROLL_ANIMATION_SECONDS, _finish_dice_roll.bind(player_idx, dice_val))

func _finish_dice_roll(player_idx: int, dice_val: int) -> void:
	if not is_game_active or player_idx != current_turn_idx or current_state != TurnState.ROLLING_DICE:
		return
	current_state = TurnState.PLAYER_MOVING
	var cur_p = players[player_idx]
	var old_pos = cur_p["position"]
	var target_pos = min(BoardGrid.LAST_TILE_INDEX, old_pos + dice_val)
	status_message_posted.emit("🎲 [%s] 주사위 [%d] 등장! %d번 칸으로 전진합니다." % [cur_p["name"], dice_val, target_pos])
	move_player_to(player_idx, target_pos)

# 플레이어 이동 및 타일 이벤트 처리
func move_player_to(player_idx: int, target_tile: int, shortcut_history: Array[int] = []) -> void:
	var cur_p = players[player_idx]
	var from_tile = cur_p["position"]
	cur_p["position"] = target_tile
	_record_player_movement(player_idx, from_tile, target_tile)
	player_moved.emit(player_idx, from_tile, target_tile)
	AudioManager.play_move_sfx()
	
	# 격자 칸별 이동 애니메이션이 끝난 뒤에만 도착 이벤트를 처리합니다.
	var movement_duration := BoardGrid.get_movement_duration(from_tile, target_tile)
	_schedule_game_action(movement_duration + 0.08, _resolve_tile_event.bind(player_idx, target_tile, shortcut_history.duplicate()))

func _resolve_tile_event(player_idx: int, tile_idx: int, shortcut_history: Array[int] = []) -> void:
	var cur_p = players[player_idx]
	var tile = BoardGrid.get_tile_data(tile_idx)
	status_message_posted.emit("📍 [%s] %s 도착! (%s)" % [cur_p["name"], tile["name"], tile["desc"]])
	_collect_tile_item(player_idx, tile_idx)
	
	# 마지막 칸은 게임 종료 지점이 아니라 한 바퀴 완주 지점입니다.
	if tile_idx >= BoardGrid.LAST_TILE_INDEX:
		_handle_lap_completion(player_idx)
		return
		
	match tile["type"]:
		BoardGrid.TileType.LADDER:
			AudioManager.play_ladder_sfx()
			_follow_shortcut(player_idx, tile_idx, int(tile["target"]), shortcut_history, "🪜 [황금 사다리 발동!] %d번 칸으로 지름길 도약!" % tile["target"])
			return
			
		BoardGrid.TileType.SLIDE:
			if cur_p["shield"]:
				cur_p["shield"] = false
				player_state_changed.emit(player_idx)
				status_message_posted.emit("🛡️ [%s] 특수기술 방패로 미끄럼틀 함정을 방어했습니다!" % cur_p["name"])
				end_turn()
			else:
				AudioManager.play_slide_sfx()
				_follow_shortcut(player_idx, tile_idx, int(tile["target"]), shortcut_history, "🛝 [낭비 미끄럼틀!] %d번 칸으로 후퇴합니다..." % tile["target"])
			return
			
		BoardGrid.TileType.POWERPLANT:
			AudioManager.play_correct_sfx()
			var reward_energy: int = tile.get("reward_energy", 2)
			cur_p["energy"] += reward_energy
			player_state_changed.emit(player_idx)
			status_message_posted.emit("⚡ 친환경 발전소 현장 조사 성공! (에너지 +%d)" % reward_energy)
			end_turn()
			
		BoardGrid.TileType.CHANCE_CARD:
			var bonus_item_id := MATERIAL_DRAW_BAG[randi() % MATERIAL_DRAW_BAG.size()]
			var inventory: Dictionary = cur_p["inventory"]
			inventory[bonus_item_id] = int(inventory.get(bonus_item_id, 0)) + 1
			player_inventory_changed.emit(player_idx, inventory.duplicate(true))
			player_state_changed.emit(player_idx)
			status_message_posted.emit("🎁 보너스 건설재료 [%s] 1개를 획득했습니다!" % ITEM_DEFINITIONS[bonus_item_id]["name"])
			end_turn()
			
		BoardGrid.TileType.REST_TURN:
			cur_p["skip_turn"] = true
			player_state_changed.emit(player_idx)
			status_message_posted.emit("☕ 다음 턴에 1회 쉬어갑니다.")
			end_turn()
			
		BoardGrid.TileType.QUIZ_CHOSUNG, BoardGrid.TileType.QUIZ_OX, BoardGrid.TileType.QUIZ_CHOICE:
			current_state = TurnState.RESOLVING_QUIZ
			# 게임판에 남아 있는 세 종류의 퀴즈 칸은 모두 4지선다 문제를 출제합니다.
			var quiz = QuizDatabase.get_random_quiz()
			active_quiz_data = quiz
			active_quiz_player_idx = player_idx
			active_spectator_quiz_attempts.clear()
			quiz_requested.emit(player_idx, quiz)
			if cur_p["is_ai"]:
				# AI 봇 85% 확률 정답
				_schedule_game_action(AI_QUIZ_THINK_SECONDS, resolve_ai_quiz_if_pending.bind(player_idx))
				
		_:
			end_turn()

func resolve_ai_quiz_if_pending(player_idx: int) -> void:
	# 예약 콜백과 관전 UI 안전장치가 같은 진입점을 사용합니다. 먼저 도착한 호출만
	# 결과를 확정하고, 뒤늦은 중복 호출은 현재 상태 검사에서 안전하게 무시됩니다.
	if not is_game_active or current_state != TurnState.RESOLVING_QUIZ or player_idx != active_quiz_player_idx:
		return
	if player_idx < 0 or player_idx >= players.size() or not bool(players[player_idx].get("is_ai", false)):
		return
	on_network_quiz_resolved(player_idx, randf() < 0.85)

func submit_spectator_quiz_guess(observer_idx: int, target_idx: int, choice: String) -> Dictionary:
	var result := {"accepted": false, "is_correct": false, "bonus_score": 0}
	if not is_game_active or current_state != TurnState.RESOLVING_QUIZ or target_idx != active_quiz_player_idx:
		return result
	if observer_idx < 0 or observer_idx >= players.size() or target_idx < 0 or target_idx >= players.size():
		return result
	if observer_idx == target_idx or bool(players[observer_idx].get("is_ai", false)):
		return result
	if active_spectator_quiz_attempts.has(observer_idx):
		return result

	active_spectator_quiz_attempts[observer_idx] = choice
	var is_correct := choice == str(active_quiz_data.get("answer", ""))
	var bonus_score := SPECTATOR_QUIZ_BONUS_SCORE if is_correct else 0
	if is_correct:
		players[observer_idx]["bonus_quiz_score"] = int(players[observer_idx].get("bonus_quiz_score", 0)) + bonus_score
		player_state_changed.emit(observer_idx)
		status_message_posted.emit("⚡ [%s] 선행 정답 성공! 관전 보너스 +%d점" % [players[observer_idx]["name"], bonus_score])
	else:
		status_message_posted.emit("💭 [%s] 선행 답안은 아쉽게 빗나갔습니다. 보너스 점수는 없습니다." % players[observer_idx]["name"])
	spectator_quiz_bonus_resolved.emit(observer_idx, target_idx, is_correct, bonus_score)
	result["accepted"] = true
	result["is_correct"] = is_correct
	result["bonus_score"] = bonus_score
	return result

func _follow_shortcut(player_idx: int, from_tile: int, target_tile: int, shortcut_history: Array[int], message: String) -> void:
	var updated_history := shortcut_history.duplicate()
	if from_tile not in updated_history:
		updated_history.append(from_tile)
	if target_tile in updated_history or updated_history.size() >= BoardGrid.TILE_COUNT:
		status_message_posted.emit("⚠️ 사다리·미끄럼틀 반복 구간을 감지해 현재 칸에서 이동을 멈춥니다.")
		end_turn()
		return
	status_message_posted.emit(message)
	_schedule_game_action(0.8, move_player_to.bind(player_idx, target_tile, updated_history))

# 퀴즈 결과 처리
func on_network_quiz_resolved(player_idx: int, is_correct: bool) -> void:
	if not is_game_active or current_state != TurnState.RESOLVING_QUIZ or player_idx != active_quiz_player_idx:
		return
	var cur_p = players[player_idx]
	quiz_resolved.emit(player_idx, is_correct)
	if is_correct:
		var reward_energy: int = active_quiz_data.get("reward_energy", 2)
		cur_p["energy"] += reward_energy
		cur_p["skill_energy"] += reward_energy
		cur_p["quiz_correct"] += 1
		team_quiz_correct += 1
		kingdom_progress_changed.emit(projects_built, CONSTRUCTION_PROJECTS.size(), kingdom_health)
		AudioManager.play_correct_sfx()
		status_message_posted.emit("✨ 정답입니다! 에너지 보상과 개인 퀴즈 점수를 획득했습니다. (개인 퀴즈 점수 +%d)" % QUIZ_CORRECT_SCORE)
	else:
		AudioManager.play_wrong_sfx()
		if cur_p["shield"]:
			cur_p["shield"] = false
			status_message_posted.emit("🛡️ 오답이지만 방패 쉴드로 후퇴를 방어했습니다!")
		else:
			var prev_pos = max(0, cur_p["position"] - 1)
			var penalty_from_pos := int(cur_p["position"])
			cur_p["position"] = prev_pos
			_record_player_movement(player_idx, penalty_from_pos, prev_pos)
			player_moved.emit(player_idx, penalty_from_pos, prev_pos)
			status_message_posted.emit("❌ 아쉽습니다! 오답 페널티로 1칸 뒤로 물러납니다.")
	player_state_changed.emit(player_idx)
	active_quiz_data.clear()
	active_quiz_player_idx = -1
	active_spectator_quiz_attempts.clear()
	_schedule_game_action(1.0, end_turn)

# 턴 종료 및 다음 플레이어 전환
func end_turn() -> void:
	if not is_game_active:
		return
	dice_input_time_remaining = 0.0
	_last_emitted_dice_input_seconds = -1
	total_turns += 1
	current_turn_idx = (current_turn_idx + 1) % players.size()
	current_state = TurnState.WAIT_ACTION
	_schedule_game_action(0.6, start_turn)

func _handle_lap_completion(player_idx: int) -> void:
	if not is_game_active or player_idx < 0 or player_idx >= players.size():
		return
	var player: Dictionary = players[player_idx]
	var lap_number := int(player.get("laps_completed", 0)) + 1
	var finish_order: Array = lap_finish_orders.get(lap_number, [])
	if player_idx in finish_order:
		return
	finish_order.append(player_idx)
	lap_finish_orders[lap_number] = finish_order
	var rank := finish_order.size()
	var reward_count := maxi(0, 4 - rank)
	player["laps_completed"] = lap_number
	player["last_lap_rank"] = rank
	player_state_changed.emit(player_idx)
	lap_completed.emit(player_idx, lap_number, rank, reward_count)
	status_message_posted.emit("🏁 [%s] %d바퀴 %d등 완주! 원하는 발전소 부품 %d개를 받습니다." % [player["name"], lap_number, rank, reward_count])
	if reward_count <= 0:
		_complete_lap_reward(player_idx, [])
		return
	pending_lap_reward = {
		"player_idx": player_idx,
		"rank": rank,
		"remaining": reward_count,
		"total": reward_count,
		"selected_items": []
	}
	current_state = TurnState.TILE_EVENT
	if player.get("is_ai", false):
		for _reward_index in range(reward_count):
			_grant_lap_reward_item(player_idx, _choose_ai_lap_reward_item(player_idx))
	else:
		lap_reward_requested.emit(player_idx, rank, reward_count)

func claim_lap_reward(player_idx: int, item_id: String) -> bool:
	if pending_lap_reward.is_empty() or int(pending_lap_reward.get("player_idx", -1)) != player_idx:
		return false
	if not ITEM_DEFINITIONS.has(item_id) or int(pending_lap_reward.get("remaining", 0)) <= 0:
		return false
	_grant_lap_reward_item(player_idx, item_id)
	return true

func _grant_lap_reward_item(player_idx: int, item_id: String) -> void:
	if pending_lap_reward.is_empty() or not ITEM_DEFINITIONS.has(item_id):
		return
	var inventory: Dictionary = players[player_idx]["inventory"]
	inventory[item_id] = int(inventory.get(item_id, 0)) + 1
	players[player_idx]["construction_contribution"] += 1
	players[player_idx]["lap_reward_items"] += 1
	var selected_items: Array = pending_lap_reward.get("selected_items", [])
	selected_items.append(item_id)
	pending_lap_reward["selected_items"] = selected_items
	pending_lap_reward["remaining"] = int(pending_lap_reward.get("remaining", 0)) - 1
	player_inventory_changed.emit(player_idx, inventory.duplicate(true))
	player_state_changed.emit(player_idx)
	status_message_posted.emit("🎁 [%s] 완주 보상으로 %s을(를) 선택했습니다. (%d개 남음)" % [players[player_idx]["name"], ITEM_DEFINITIONS[item_id]["name"], int(pending_lap_reward["remaining"])])
	if int(pending_lap_reward["remaining"]) <= 0:
		_complete_lap_reward(player_idx, selected_items)

func _choose_ai_lap_reward_item(player_idx: int) -> String:
	var inventory: Dictionary = players[player_idx].get("inventory", {})
	var best_item := MATERIAL_DRAW_BAG[0]
	var best_missing := 999
	for project in CONSTRUCTION_PROJECTS:
		var requirements: Dictionary = project["requirements"]
		var missing_total := 0
		var missing_item := ""
		for requirement_id_variant in requirements:
			var requirement_id := str(requirement_id_variant)
			var missing := maxi(0, int(requirements[requirement_id]) - int(inventory.get(requirement_id, 0)))
			missing_total += missing
			if missing > 0 and missing_item.is_empty():
				missing_item = requirement_id
		if missing_total > 0 and missing_total < best_missing:
			best_missing = missing_total
			best_item = missing_item
	return best_item

func _complete_lap_reward(player_idx: int, selected_items: Array) -> void:
	if player_idx < 0 or player_idx >= players.size():
		return
	pending_lap_reward.clear()
	current_state = TurnState.TURN_END
	var from_tile := int(players[player_idx].get("position", BoardGrid.LAST_TILE_INDEX))
	players[player_idx]["position"] = 0
	player_moved.emit(player_idx, from_tile, 0)
	player_state_changed.emit(player_idx)
	lap_reward_completed.emit(player_idx, selected_items.duplicate())
	status_message_posted.emit("🔄 [%s] 님이 출발 칸으로 돌아와 다음 바퀴를 준비합니다." % players[player_idx]["name"])
	end_turn()

func _schedule_game_action(delay_seconds: float, callback: Callable) -> void:
	var scheduled_session := game_session_id
	get_tree().create_timer(delay_seconds).timeout.connect(func():
		if is_game_active and scheduled_session == game_session_id:
			callback.call()
	)

func get_player_special_skill(player_idx: int) -> Dictionary:
	if player_idx < 0 or player_idx >= players.size():
		return DEFAULT_SPECIAL_SKILL.duplicate(true)
	var icon_path := str(players[player_idx].get("char_icon", ""))
	return (SPECIAL_SKILLS_BY_ICON.get(icon_path, DEFAULT_SPECIAL_SKILL) as Dictionary).duplicate(true)

func can_use_special_skill(player_idx: int) -> bool:
	if not is_game_active or village_construction_active or player_idx < 0 or player_idx >= players.size():
		return false
	if current_state != TurnState.WAIT_ACTION or current_turn_idx != player_idx:
		return false
	if special_skill_used_this_turn:
		return false
	var skill := get_player_special_skill(player_idx)
	return int(players[player_idx].get("skill_energy", 0)) >= int(skill.get("cost", 0))

func use_special_skill(player_idx: int, target_index: int) -> bool:
	if not can_use_special_skill(player_idx):
		status_message_posted.emit("⚠️ 특수기술은 자신의 턴에, 퀴즈 특수 에너지가 충분할 때만 사용할 수 있습니다.")
		return false
	var skill := get_player_special_skill(player_idx)
	var target_type := str(skill.get("target_type", "tile"))
	var effect := str(skill.get("effect", ""))
	if not _is_valid_special_skill_target(player_idx, target_index, target_type, effect, skill):
		return false

	var player: Dictionary = players[player_idx]
	player["skill_energy"] = int(player.get("skill_energy", 0)) - int(skill.get("cost", 0))
	special_skill_used_this_turn = true
	if effect == "move":
		current_state = TurnState.PLAYER_MOVING
	player_state_changed.emit(player_idx)
	AudioManager.play_special_skill_sfx(str(skill.get("id", "eco_dash")))
	special_skill_activated.emit(player_idx, target_index, skill.duplicate(true))
	status_message_posted.emit("⚡ [%s] %s 발동!" % [player["name"], skill["name"]])

	match effect:
		"move":
			_move_player_with_special_skill(player_idx, target_index)
			return true
		"energy_boost":
			players[target_index]["energy"] += int(skill.get("amount", 0))
			player_state_changed.emit(target_index)
			status_message_posted.emit("☀️ [%s] 님이 일반 에너지 +%d를 받았습니다." % [players[target_index]["name"], int(skill.get("amount", 0))])
		"purify":
			players[target_index]["shield"] = true
			players[target_index]["energy"] += int(skill.get("amount", 0))
			player_state_changed.emit(target_index)
			status_message_posted.emit("💧 [%s] 님이 정화 방패와 일반 에너지 +%d를 받았습니다." % [players[target_index]["name"], int(skill.get("amount", 0))])
		"shield":
			players[target_index]["shield"] = true
			player_state_changed.emit(target_index)
			status_message_posted.emit("🛡️ [%s] 님에게 대지 방벽이 생겼습니다." % players[target_index]["name"])
		"material_supply":
			var supply_item_id := MATERIAL_DRAW_BAG[randi() % MATERIAL_DRAW_BAG.size()]
			var target_inventory: Dictionary = players[target_index]["inventory"]
			target_inventory[supply_item_id] = int(target_inventory.get(supply_item_id, 0)) + int(skill.get("amount", 1))
			player_inventory_changed.emit(target_index, target_inventory.duplicate(true))
			player_state_changed.emit(target_index)
			status_message_posted.emit("🌲 [%s] 님이 %s을(를) 보급받았습니다." % [players[target_index]["name"], ITEM_DEFINITIONS[supply_item_id]["name"]])
		"collect_material":
			_collect_tile_item(player_idx, target_index)

	# 특수기술은 주사위와 별개의 턴당 1회 보너스 행동입니다.
	special_skill_completed.emit(player_idx)
	status_message_posted.emit("특수기술 완료 · 이어서 중앙 주사위를 굴릴 수 있습니다.")
	return true


func _move_player_with_special_skill(player_idx: int, target_tile: int) -> void:
	var player: Dictionary = players[player_idx]
	var from_tile := int(player.get("position", 0))
	player["position"] = target_tile
	_record_player_movement(player_idx, from_tile, target_tile)
	player_moved.emit(player_idx, from_tile, target_tile)
	AudioManager.play_move_sfx()
	var movement_duration := BoardGrid.get_movement_duration(from_tile, target_tile)
	_schedule_game_action(movement_duration + 0.08, _finish_special_skill_move.bind(player_idx, target_tile))


func _finish_special_skill_move(player_idx: int, target_tile: int) -> void:
	if not is_game_active or current_turn_idx != player_idx or current_state != TurnState.PLAYER_MOVING:
		return
	# 보너스 이동으로 도착한 칸에서는 개인 재료만 획득하고, 칸 이벤트와 턴 종료는
	# 이어서 굴릴 주사위 이동이 처리하도록 남겨 둡니다.
	_collect_tile_item(player_idx, target_tile)
	current_state = TurnState.WAIT_ACTION
	player_state_changed.emit(player_idx)
	special_skill_completed.emit(player_idx)
	status_message_posted.emit("특수 이동 완료 · 이제 중앙 주사위를 굴릴 수 있습니다.")
	if bool(players[player_idx].get("is_ai", false)):
		_schedule_game_action(AI_POST_SPECIAL_ACTION_DELAY_SECONDS, _ai_roll_after_special.bind(player_idx))

func _is_valid_special_skill_target(player_idx: int, target_index: int, target_type: String, effect: String, skill: Dictionary) -> bool:
	if target_type == "self":
		if target_index != player_idx:
			status_message_posted.emit("⚠️ 이 특수기술은 자신에게만 사용할 수 있습니다.")
			return false
		return true
	if target_type == "player":
		if target_index < 0 or target_index >= players.size():
			status_message_posted.emit("⚠️ 특수기술을 받을 플레이어를 선택하세요.")
			return false
		return true
	if target_index <= 0 or target_index >= BoardGrid.LAST_TILE_INDEX:
		status_message_posted.emit("⚠️ 출발·도착 칸을 제외한 게임판 타일을 선택하세요.")
		return false
	if effect == "move":
		var current_position := int(players[player_idx].get("position", 0))
		var max_target: int = mini(BoardGrid.LAST_TILE_INDEX, current_position + int(skill.get("range", 1)))
		if target_index <= current_position or target_index > max_target:
			status_message_posted.emit("⚠️ %s: 현재 위치보다 앞의 %d칸 이내 타일을 선택하세요." % [skill["name"], int(skill.get("range", 1))])
			return false
	elif effect == "collect_material" and collected_item_tiles.has(target_index):
		status_message_posted.emit("⚠️ 이 타일의 건설 재료는 이미 다른 플레이어가 획득했습니다.")
		return false
	return true

func get_tile_item_id(tile_idx: int) -> String:
	# 출발·도착 칸을 제외한 1~98번 칸에 모든 건설 재료를 최대한 고르게 배치합니다.
	if tile_idx <= 0 or tile_idx >= BoardGrid.LAST_TILE_INDEX:
		return ""
	return MATERIAL_DRAW_BAG[(tile_idx - 1) % MATERIAL_DRAW_BAG.size()]

func _collect_tile_item(player_idx: int, tile_idx: int) -> bool:
	if not is_game_active or village_construction_active or kingdom_recovered:
		return false
	if player_idx < 0 or player_idx >= players.size() or collected_item_tiles.has(tile_idx):
		return false
	var item_id := get_tile_item_id(tile_idx)
	if item_id.is_empty():
		return false
	# 획득 상태를 먼저 기록해 같은 프레임에 여러 플레이어가 도착해도 중복 지급되지 않게 합니다.
	collected_item_tiles[tile_idx] = player_idx
	var item_data: Dictionary = ITEM_DEFINITIONS[item_id]
	var inventory: Dictionary = players[player_idx]["inventory"]
	inventory[item_id] = int(inventory.get(item_id, 0)) + 1
	players[player_idx]["construction_contribution"] += 1
	player_inventory_changed.emit(player_idx, inventory.duplicate(true))
	player_state_changed.emit(player_idx)
	tile_item_collected.emit(tile_idx, player_idx, item_id)
	status_message_posted.emit("%s %s 획득! [%s] 님의 건설 공헌 +1" % [item_data["icon"], item_data["name"], players[player_idx]["name"]])
	return true

func _create_empty_inventory() -> Dictionary:
	var inventory := {}
	for item_id in ITEM_DEFINITIONS:
		inventory[item_id] = 0
	return inventory

func get_player_inventories() -> Array[Dictionary]:
	var inventories: Array[Dictionary] = []
	for player in players:
		inventories.append(player.get("inventory", _create_empty_inventory()).duplicate(true))
	return inventories

func _start_village_construction_phase() -> void:
	if village_construction_active or kingdom_recovered:
		return
	pending_lap_reward.clear()
	village_construction_active = true
	is_game_active = false
	current_state = TurnState.GAME_OVER
	status_message_posted.emit("🏘️ 마을 건설 단계: 재료를 골라 친환경 건물을 짓고 공동 친환경 에너지 지수 %d를 목표로 도전하세요." % VILLAGE_RECOVERY_TARGET)
	village_construction_started.emit(get_player_inventories())
	# 사람과 함께 플레이한 AI도 자기 재료로 시설을 선택해 순서대로 건설합니다.
	_schedule_village_ai_construction()

func can_build_village_project(project_index: int, player_idx: int = -1) -> bool:
	if not village_construction_active or project_index < 0 or project_index >= CONSTRUCTION_PROJECTS.size() or project_index in built_project_ids:
		return false
	if player_idx < 0:
		return not get_project_builder_indices(project_index).is_empty()
	if player_idx >= players.size():
		return false
	var requirements: Dictionary = CONSTRUCTION_PROJECTS[project_index]["requirements"]
	var inventory: Dictionary = players[player_idx].get("inventory", {})
	for requirement_item_id in requirements:
		var item_id := str(requirement_item_id)
		if inventory.get(item_id, 0) < int(requirements[item_id]):
			return false
	return true

func get_project_builder_indices(project_index: int) -> Array[int]:
	var builders: Array[int] = []
	for player_idx in range(players.size()):
		if can_build_village_project(project_index, player_idx):
			builders.append(player_idx)
	return builders

func build_village_project(project_index: int, player_idx: int = -1, map_position: Vector2 = Vector2(-1, -1)) -> bool:
	if player_idx < 0:
		var builders := get_project_builder_indices(project_index)
		if builders.is_empty():
			return false
		player_idx = builders[0]
	if not can_build_village_project(project_index, player_idx):
		return false
	var project: Dictionary = CONSTRUCTION_PROJECTS[project_index]
	var inventory: Dictionary = players[player_idx]["inventory"]
	for requirement_item_id in project["requirements"]:
		var item_id := str(requirement_item_id)
		inventory[item_id] -= int(project["requirements"][item_id])
	built_project_ids.append(project_index)
	if map_position.x >= 0.0 and map_position.y >= 0.0:
		built_project_placements[project_index] = map_position
	built_project_owners[project_index] = player_idx
	players[player_idx]["project_completion_bonus"] += 1
	projects_built = built_project_ids.size()
	kingdom_health = mini(100, kingdom_health + int(project["health"]))
	player_inventory_changed.emit(player_idx, inventory.duplicate(true))
	player_state_changed.emit(player_idx)
	kingdom_progress_changed.emit(projects_built, CONSTRUCTION_PROJECTS.size(), kingdom_health)
	village_construction_changed.emit(get_player_inventories(), projects_built, kingdom_health)
	status_message_posted.emit("🏗️ [%s] 님의 개인 재료로 %s 완공! %s" % [players[player_idx]["name"], project["name"], project["message"]])
	# 왕국 복원 조건을 만족하면 별도의 '완성도 확인' 버튼을 누르지 않아도 즉시 엔딩을 엽니다.
	if kingdom_health >= VILLAGE_RECOVERY_TARGET:
		status_message_posted.emit("✨ 친환경 에너지 지수가 목표에 도달했습니다. 왕국 복원 엔딩을 시작합니다!")
		evaluate_village(true)
	return true

func evaluate_village(allow_during_ai_construction: bool = false) -> void:
	if not village_construction_active:
		return
	if village_ai_construction_running and not allow_during_ai_construction:
		status_message_posted.emit("🤖 AI 플레이어가 발전소를 선택하고 있습니다. 잠시 후 마을 완성도를 확인하세요.")
		return
	kingdom_recovered = kingdom_health >= VILLAGE_RECOVERY_TARGET
	village_construction_active = false
	village_ai_construction_running = false
	_award_movement_end_rewards()
	var rankings = players.duplicate(true)
	for p in rankings:
		# 일반 에너지가 최종 순위를 결정합니다. 기존 활동 점수는 에너지가
		# 같은 플레이어 사이에서만 사용하는 동점 판정값으로 남깁니다.
		p["final_score"] = int(p.get("energy", 0))
		p["ranking_tiebreak_score"] = int(p.get("laps_completed", 0)) * 30 + int(p.get("quiz_correct", 0)) * QUIZ_CORRECT_SCORE + int(p.get("bonus_quiz_score", 0)) + int(p.get("construction_contribution", 0)) * 8
	rankings.sort_custom(func(a, b):
		var energy_a := int(a.get("energy", 0))
		var energy_b := int(b.get("energy", 0))
		if energy_a != energy_b:
			return energy_a > energy_b
		var tiebreak_a := int(a.get("ranking_tiebreak_score", 0))
		var tiebreak_b := int(b.get("ranking_tiebreak_score", 0))
		if tiebreak_a != tiebreak_b:
			return tiebreak_a > tiebreak_b
		return int(a.get("index", 0)) < int(b.get("index", 0))
	)
	game_over.emit(rankings)
	if kingdom_recovered:
		status_message_posted.emit("🌍 목표 달성! 친환경 시설이 화력발전소를 대신하며 왕국이 건강한 미래를 되찾았습니다!")
	else:
		status_message_posted.emit("🌧️ 공동 친환경 에너지 지수가 아직 %d / %d입니다. 왕국 복원은 다음 도전으로 이어집니다." % [kingdom_health, VILLAGE_RECOVERY_TARGET])

func _record_player_movement(player_idx: int, from_tile: int, to_tile: int) -> void:
	if player_idx < 0 or player_idx >= players.size():
		return
	# 미끄럼틀과 오답 후퇴는 이동 경쟁에 이득이 되지 않도록 전진한 칸만 셉니다.
	players[player_idx]["total_tiles_moved"] = int(players[player_idx].get("total_tiles_moved", 0)) + maxi(0, to_tile - from_tile)

func _award_movement_end_rewards() -> void:
	var movement_order: Array[int] = []
	for player_idx in range(players.size()):
		movement_order.append(player_idx)
	movement_order.sort_custom(func(a, b):
		var distance_a := int(players[a].get("total_tiles_moved", 0))
		var distance_b := int(players[b].get("total_tiles_moved", 0))
		if distance_a != distance_b:
			return distance_a > distance_b
		return a < b
	)

	var previous_distance := -1
	var movement_rank := 0
	for order_index in range(movement_order.size()):
		var player_idx := movement_order[order_index]
		var distance := int(players[player_idx].get("total_tiles_moved", 0))
		if distance != previous_distance:
			movement_rank = order_index + 1
			previous_distance = distance
		var reward_index := mini(movement_rank - 1, MOVEMENT_END_REWARDS.size() - 1)
		var reward_energy := MOVEMENT_END_REWARDS[reward_index] if distance > 0 else 0
		players[player_idx]["movement_rank"] = movement_rank
		players[player_idx]["movement_reward_energy"] = reward_energy
		players[player_idx]["energy"] = int(players[player_idx].get("energy", 0)) + reward_energy
		player_state_changed.emit(player_idx)

	if not movement_order.is_empty():
		var champion_idx := movement_order[0]
		status_message_posted.emit("🏃 이동왕 [%s] · 총 %d칸 이동 · 순위 에너지 +%d!" % [players[champion_idx]["name"], players[champion_idx].get("total_tiles_moved", 0), players[champion_idx].get("movement_reward_energy", 0)])

func _schedule_village_ai_construction() -> void:
	if village_ai_construction_running or not village_construction_active or not _has_ai_players():
		return
	village_ai_construction_running = true
	_schedule_next_village_ai_construction(AI_VILLAGE_BUILD_DELAY_SECONDS)

func _schedule_next_village_ai_construction(delay_seconds: float) -> void:
	var scheduled_session := game_session_id
	get_tree().create_timer(delay_seconds).timeout.connect(func():
		if scheduled_session != game_session_id or not village_construction_active:
			village_ai_construction_running = false
			return
		if _run_one_ai_village_construction():
			if village_construction_active:
				_schedule_next_village_ai_construction(AI_VILLAGE_BUILD_DELAY_SECONDS)
			return
		village_ai_construction_running = false
		if _all_players_are_ai():
			evaluate_village(true)
	)

func _run_one_ai_village_construction() -> bool:
	if not village_construction_active or players.is_empty():
		return false
	for offset in range(players.size()):
		var player_idx := (village_ai_builder_cursor + offset) % players.size()
		if not bool(players[player_idx].get("is_ai", false)):
			continue
		var project_index := _choose_ai_village_project(player_idx)
		if project_index < 0:
			continue
		village_ai_builder_cursor = (player_idx + 1) % players.size()
		status_message_posted.emit("🤖 [%s] 님이 보유 재료를 분석해 %s 건설을 선택했습니다." % [players[player_idx]["name"], CONSTRUCTION_PROJECTS[project_index]["name"]])
		return build_village_project(project_index, player_idx)
	return false

func _choose_ai_village_project(player_idx: int) -> int:
	var candidates: Array[int] = []
	for project_index in range(CONSTRUCTION_PROJECTS.size()):
		if can_build_village_project(project_index, player_idx):
			candidates.append(project_index)
	if candidates.is_empty():
		return -1
	# 같은 조건에서는 선택이 매번 달라질 수 있게 먼저 섞고, 공동 지수를 많이
	# 올리는 시설부터 고려해 AI가 의미 있는 건설 결정을 내리게 합니다.
	candidates.shuffle()
	candidates.sort_custom(func(a: int, b: int):
		return int(CONSTRUCTION_PROJECTS[a].get("health", 0)) > int(CONSTRUCTION_PROJECTS[b].get("health", 0))
	)
	return candidates[0]

func _all_players_are_ai() -> bool:
	if players.is_empty():
		return false
	for player in players:
		if not bool(player.get("is_ai", false)):
			return false
	return true

func _has_ai_players() -> bool:
	for player in players:
		if bool(player.get("is_ai", false)):
			return true
	return false
