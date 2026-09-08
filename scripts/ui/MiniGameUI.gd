extends Control
class_name MiniGameUI

## 8종의 에너지 교육 미니게임을 하나의 동시 플레이 모달에서 운영합니다.

const UI = preload("res://scripts/ui/CommercialUI.gd")
const SOLAR_PANEL_DASH = preload("res://scripts/minigames/SolarPanelDash3D.gd")
const WIND_TURBINE_PILOT = preload("res://scripts/minigames/WindTurbinePilot3D.gd")
const SMART_GRID_BALANCE = preload("res://scripts/minigames/SmartGridBalance3D.gd")
const STANDBY_POWER_HUNT = preload("res://scripts/minigames/StandbyPowerHunt3D.gd")

const SORT_CARDS := [
	{"name": "태양광", "category": 0, "why": "햇빛은 자연에서 계속 얻을 수 있습니다."},
	{"name": "풍력", "category": 0, "why": "바람은 다시 생기는 재생 자원입니다."},
	{"name": "수력", "category": 0, "why": "순환하는 물의 흐름을 이용합니다."},
	{"name": "지열", "category": 0, "why": "땅속 열을 지속적으로 활용합니다."},
	{"name": "석탄", "category": 1, "why": "한정된 화석연료이며 연소할 때 탄소를 배출합니다."},
	{"name": "석유", "category": 1, "why": "오랜 시간 만들어져 빠르게 다시 생기지 않습니다."},
	{"name": "천연가스", "category": 1, "why": "석탄보다 배출이 적어도 화석연료입니다."},
	{"name": "LED 조명", "category": 2, "why": "같은 밝기를 더 적은 전기로 만듭니다."},
	{"name": "건물 단열", "category": 2, "why": "냉난방 에너지가 빠져나가는 것을 줄입니다."},
	{"name": "고효율 모터", "category": 2, "why": "같은 일을 더 적은 전력으로 수행합니다."}
]

const STANDBY_DEVICES := [
	{"name": "꺼진 TV", "watt": 3, "waste": true},
	{"name": "충전 끝난 어댑터", "watt": 2, "waste": true},
	{"name": "대기 중 게임기", "watt": 5, "waste": true},
	{"name": "사용 중 냉장고", "watt": 45, "waste": false},
	{"name": "작동 중 공기청정기", "watt": 28, "waste": false},
	{"name": "빈 방 셋톱박스", "watt": 6, "waste": true},
	{"name": "켜진 공부방 LED", "watt": 9, "waste": false},
	{"name": "절전 멀티탭", "watt": 0, "waste": false},
	{"name": "잠든 프린터", "watt": 4, "waste": true},
	{"name": "사용 중 노트북", "watt": 35, "waste": false},
	{"name": "예약만 된 전자레인지", "watt": 3, "waste": true},
	{"name": "충전 중 전기자전거", "watt": 80, "waste": false}
]

const COMMUTE_SCENARIOS := [
	{"prompt": "맑은 날 · 학교까지 800m · 가벼운 가방", "options": ["걷기", "자가용", "택시"], "answer": 0, "why": "가까운 거리는 걷기가 배출도 없고 건강에도 좋습니다."},
	{"prompt": "친구 3명 · 박물관까지 12km · 지하철 연결", "options": ["각자 승용차", "지하철", "택시 2대"], "answer": 1, "why": "여럿이 이용하는 대중교통은 1인당 배출량이 작습니다."},
	{"prompt": "도서관까지 3km · 자전거 도로 있음", "options": ["자전거", "대형 SUV", "택시"], "answer": 0, "why": "안전한 자전거 도로가 있는 가까운 거리는 자전거가 효율적입니다."},
	{"prompt": "폭우 · 병원까지 7km · 버스 바로 도착", "options": ["버스", "혼자 승용차", "비행기"], "answer": 0, "why": "걷기 어려운 날에는 연결된 대중교통이 현실적인 저탄소 선택입니다."},
	{"prompt": "서울에서 부산 · 장거리 이동", "options": ["혼자 승용차", "고속철도", "국내선 비행기"], "answer": 1, "why": "전기 철도는 장거리에서 1인당 에너지 사용을 줄일 수 있습니다."},
	{"prompt": "동네 공원까지 1.5km · 미세먼지 좋음", "options": ["전기자전거", "혼자 승용차", "택시"], "answer": 0, "why": "짧은 거리는 자전거류가 자동차보다 에너지를 훨씬 적게 씁니다."}
]

var dimmer: ColorRect
var card: PanelContainer
var title_label: Label
var mode_label: Label
var objective_label: Label
var timer_label: Label
var timer_bar: ProgressBar
var score_label: Label
var arena: VBoxContainer
var feedback_label: Label
var lesson_label: Label
var submission_label: Label

var active := false
var submitted := false
var game_data: Dictionary = {}
var game_id := ""
var round_id := -1
var duration := 30.0
var elapsed := 0.0
var score := 0
var correct := 0
var attempts := 0
var streak := 0
var best_streak := 0
var rng := RandomNumberGenerator.new()
var mode_tick := 0.0
var score_tick := 0.0

var primary_label: Label
var secondary_label: Label
var meter: ProgressBar
var solar_target := 0.5
var wind_lane := -1
var wind_window := 0.0
var grid_demand := 60
var grid_supply := 50
var hydro_target := 60
var hydro_flow := 30
var current_card: Dictionary = {}
var battery_state := 0
var current_scenario: Dictionary = {}
var solar_arcade: SubViewportContainer
var wind_arcade: SubViewportContainer
var grid_arcade: SubViewportContainer
var standby_arcade: SubViewportContainer

func _ready() -> void:
	_build_ui()
	visible = false
	set_process(true)
	if GameManager:
		GameManager.minigame_started.connect(_on_minigame_started)
		GameManager.minigame_submission_changed.connect(_on_submission_changed)
		GameManager.minigame_finished.connect(_on_minigame_finished)
		GameManager.turn_changed.connect(_on_turn_changed)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	dimmer = ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color("03151fe8")
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	card = PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -550
	card.offset_top = -330
	card.offset_right = 550
	card.offset_bottom = 330
	card.add_theme_stylebox_override("panel", UI.padded_panel(Color("0b2833fc"), Color("42d6b0"), 24.0, 24))
	add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	card.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 31)
	title_label.add_theme_color_override("font_color", Color("fff0a6"))
	header.add_child(title_label)
	mode_label = Label.new()
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mode_label.add_theme_font_size_override("font_size", 16)
	mode_label.add_theme_color_override("font_color", Color("8fffe0"))
	header.add_child(mode_label)

	objective_label = Label.new()
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_font_size_override("font_size", 18)
	objective_label.add_theme_color_override("font_color", Color("d9f7f0"))
	content.add_child(objective_label)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 14)
	content.add_child(status_row)
	timer_label = Label.new()
	timer_label.custom_minimum_size = Vector2(92, 34)
	timer_label.add_theme_font_size_override("font_size", 22)
	status_row.add_child(timer_label)
	timer_bar = ProgressBar.new()
	timer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_bar.custom_minimum_size = Vector2(0, 28)
	timer_bar.show_percentage = false
	timer_bar.max_value = 20.0
	status_row.add_child(timer_bar)
	score_label = Label.new()
	score_label.custom_minimum_size = Vector2(180, 34)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 23)
	score_label.add_theme_color_override("font_color", Color("ffe06b"))
	status_row.add_child(score_label)

	var arena_panel := PanelContainer.new()
	arena_panel.custom_minimum_size = Vector2(0, 300)
	arena_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var arena_style := StyleBoxFlat.new()
	arena_style.bg_color = Color("071e28")
	arena_style.border_color = Color("235366")
	arena_style.set_border_width_all(2)
	arena_style.set_corner_radius_all(16)
	arena_style.content_margin_left = 24
	arena_style.content_margin_right = 24
	arena_style.content_margin_top = 18
	arena_style.content_margin_bottom = 18
	arena_panel.add_theme_stylebox_override("panel", arena_style)
	content.add_child(arena_panel)
	arena = VBoxContainer.new()
	arena.alignment = BoxContainer.ALIGNMENT_CENTER
	arena.add_theme_constant_override("separation", 12)
	arena_panel.add_child(arena)

	feedback_label = Label.new()
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.custom_minimum_size = Vector2(0, 28)
	feedback_label.add_theme_font_size_override("font_size", 18)
	feedback_label.add_theme_color_override("font_color", Color("a8d8dd"))
	content.add_child(feedback_label)

	lesson_label = Label.new()
	lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lesson_label.add_theme_font_size_override("font_size", 15)
	lesson_label.add_theme_color_override("font_color", Color("a9c9cf"))
	content.add_child(lesson_label)

	submission_label = Label.new()
	submission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	submission_label.add_theme_font_size_override("font_size", 15)
	submission_label.add_theme_color_override("font_color", Color("72d9c1"))
	content.add_child(submission_label)

func _process(delta: float) -> void:
	if not active or submitted:
		return
	elapsed += delta
	var remaining := maxf(0.0, duration - elapsed)
	timer_label.text = "%02d초" % ceili(remaining)
	timer_bar.value = remaining
	if remaining <= 5.0:
		timer_label.add_theme_color_override("font_color", Color("ff826e"))
	else:
		timer_label.add_theme_color_override("font_color", Color("f5f7da"))
	_update_mode(delta)
	if elapsed >= duration:
		_submit_score()

func _on_minigame_started(data: Dictionary) -> void:
	game_data = data.duplicate(true)
	game_id = str(game_data.get("id", "solar_align"))
	round_id = int(game_data.get("round_id", -1))
	duration = float(game_data.get("duration", 30.0))
	elapsed = 0.0
	score = 0
	correct = 0
	attempts = 0
	streak = 0
	best_streak = 0
	mode_tick = 0.0
	score_tick = 0.0
	submitted = false
	active = true
	rng.seed = int(game_data.get("seed", 1)) + _local_player_index() * 104729
	visible = true
	title_label.text = "%s  %s" % [game_data.get("icon", "🎮"), game_data.get("title", "에너지 미니게임")]
	mode_label.text = "전원 동시 플레이  ·  %s" % game_data.get("input_hint", "빠른 도전")
	objective_label.text = "목표  |  " + str(game_data.get("objective", "제한시간 안에 최고 점수에 도전하세요."))
	lesson_label.text = "에너지 원리  |  " + str(game_data.get("lesson", ""))
	timer_bar.max_value = duration
	timer_bar.value = duration
	feedback_label.text = "준비 완료! 바로 시작하세요."
	submission_label.text = "내 점수는 종료 즉시 비공개로 제출됩니다."
	_refresh_score()
	_build_mode()

func _on_submission_changed(state: Dictionary) -> void:
	if not visible or int((state.get("game", {}) as Dictionary).get("round_id", -2)) != round_id:
		return
	submission_label.text = "점수 제출 %d / %d명%s" % [int(state.get("submitted_count", 0)), int(state.get("player_count", 4)), "  ·  내 점수 제출 완료" if submitted else ""]

func _on_minigame_finished(results: Array) -> void:
	if not visible:
		return
	active = false
	submitted = true
	_build_results(results)
	timer_label.text = "종료"
	timer_bar.value = 0
	feedback_label.text = "순위에 따라 에너지가 즉시 지급되었습니다."
	submission_label.text = "잠시 후 보드 게임이 이어집니다."
	var finished_round := round_id
	get_tree().create_timer(GameManager.MINIGAME_RESULTS_SECONDS - 0.2).timeout.connect(func():
		if round_id == finished_round and not active:
			visible = false
	)

func _on_turn_changed(_player_idx: int) -> void:
	if not active:
		visible = false

func cancel_minigame() -> void:
	if is_instance_valid(solar_arcade) and solar_arcade.has_method("set_running"):
		solar_arcade.call("set_running", false)
	if is_instance_valid(wind_arcade) and wind_arcade.has_method("set_running"):
		wind_arcade.call("set_running", false)
	if is_instance_valid(grid_arcade) and grid_arcade.has_method("set_running"):
		grid_arcade.call("set_running", false)
	if is_instance_valid(standby_arcade) and standby_arcade.has_method("set_running"):
		standby_arcade.call("set_running", false)
	active = false
	submitted = false
	visible = false

func _build_mode() -> void:
	_clear_arena()
	match game_id:
		"solar_align": _build_solar_align()
		"wind_rhythm": _build_wind_rhythm()
		"grid_balance": _build_grid_balance()
		"standby_hunt": _build_standby_hunt()
		"hydro_gate": _build_hydro_gate()
		"energy_sort": _build_energy_sort()
		"battery_relay": _build_battery_relay()
		"eco_commute": _build_eco_commute()
		_: _build_solar_align()

func _clear_arena() -> void:
	if is_instance_valid(solar_arcade) and solar_arcade.has_method("set_running"):
		solar_arcade.call("set_running", false)
	if is_instance_valid(wind_arcade) and wind_arcade.has_method("set_running"):
		wind_arcade.call("set_running", false)
	if is_instance_valid(grid_arcade) and grid_arcade.has_method("set_running"):
		grid_arcade.call("set_running", false)
	if is_instance_valid(standby_arcade) and standby_arcade.has_method("set_running"):
		standby_arcade.call("set_running", false)
	solar_arcade = null
	wind_arcade = null
	grid_arcade = null
	standby_arcade = null
	for child in arena.get_children():
		arena.remove_child(child)
		child.queue_free()
	primary_label = null
	secondary_label = null
	meter = null

func _build_solar_align() -> void:
	solar_arcade = SOLAR_PANEL_DASH.new()
	solar_arcade.arcade_event.connect(_on_solar_arcade_event)
	arena.add_child(solar_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	solar_arcade.call("setup", player_data, int(game_data.get("seed", 1)) + local_idx * 104729)

func _on_solar_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	attempts += 1
	if success:
		_register_success(points, message, count_correct)
	else:
		_register_miss(points, message)

func _on_solar_pressed() -> void:
	if not _can_play(): return
	attempts += 1
	var position := _solar_position()
	var error := absf(position - solar_target)
	if error <= 0.07:
		_register_success(120 if error <= 0.025 else 85, "최적 각도! 태양광 발전 효율 최고")
		solar_target = rng.randf_range(0.15, 0.85)
		primary_label.text = "패널 최적 각도: %d°" % int(solar_target * 90.0)
	else:
		_register_miss(18, "각도가 빗나갔어요. 빛을 정면으로 받아 보세요.")

func _solar_position() -> float:
	var wave := fmod(elapsed * 0.72, 2.0)
	return wave if wave <= 1.0 else 2.0 - wave

func _build_wind_rhythm() -> void:
	wind_arcade = WIND_TURBINE_PILOT.new()
	wind_arcade.arcade_event.connect(_on_wind_arcade_event)
	arena.add_child(wind_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	wind_arcade.call("setup", player_data, int(game_data.get("seed", 1)) + local_idx * 104729)

func _on_wind_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	attempts += 1
	if success:
		_register_success(points, message, count_correct)
	else:
		_register_miss(points, message)

func _spawn_wind_cue() -> void:
	wind_lane = rng.randi_range(0, 2)
	wind_window = 0.95
	mode_tick = 0.0
	if primary_label:
		primary_label.text = "돌풍 방향  %s" % ["↙ 서쪽", "↑ 중앙", "↘ 동쪽"][wind_lane]

func _on_wind_lane_pressed(lane: int) -> void:
	if not _can_play(): return
	attempts += 1
	if lane == wind_lane and wind_window > 0.0:
		var speed_bonus := int(wind_window * 45.0)
		_register_success(65 + speed_bonus, "돌풍 포착! 바람이 강할 때 발전량이 커집니다.")
		wind_lane = -1
		mode_tick = -0.35
		primary_label.text = "좋아요! 다음 돌풍 준비…"
	else:
		_register_miss(22, "바람 방향을 놓쳤어요. 풍향 표시를 확인하세요.")

func _build_grid_balance() -> void:
	grid_arcade = SMART_GRID_BALANCE.new()
	grid_arcade.arcade_event.connect(_on_grid_arcade_event)
	arena.add_child(grid_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	grid_arcade.call("setup", player_data, int(game_data.get("seed", 1)) + local_idx * 104729)

func _on_grid_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	attempts += 1
	if success:
		_register_success(points, message, count_correct)
	else:
		_register_miss(points, message)

func _change_grid_supply(change: int) -> void:
	if not _can_play(): return
	grid_supply = clampi(grid_supply + change, 10, 100)
	attempts += 1
	_refresh_grid_labels()

func _refresh_grid_labels() -> void:
	if primary_label:
		primary_label.text = "도시 수요 %d MW  |  현재 공급 %d MW" % [grid_demand, grid_supply]
	if meter:
		meter.value = grid_supply

func _build_standby_hunt() -> void:
	standby_arcade = STANDBY_POWER_HUNT.new()
	standby_arcade.arcade_event.connect(_on_standby_arcade_event)
	arena.add_child(standby_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	standby_arcade.call("setup", player_data, int(game_data.get("seed", 1)) + local_idx * 104729)

func _on_standby_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	attempts += 1
	if success:
		_register_success(points, message, count_correct)
	else:
		_register_miss(points, message)

func _spawn_standby_grid() -> void:
	var old_grid := arena.get_node_or_null("DeviceGrid")
	if old_grid:
		arena.remove_child(old_grid)
		old_grid.queue_free()
	var grid := GridContainer.new()
	grid.name = "DeviceGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	arena.add_child(grid)
	var choices := STANDBY_DEVICES.duplicate(true)
	choices.shuffle()
	for i in range(9):
		var device: Dictionary = choices[i]
		var button := _make_button("%s\n%d W" % [device["name"], device["watt"]], Color("8f5338") if device["waste"] else Color("315967"))
		button.custom_minimum_size = Vector2(300, 54)
		button.pressed.connect(_on_device_pressed.bind(button, device))
		grid.add_child(button)

func _on_device_pressed(button: Button, device: Dictionary) -> void:
	if not _can_play() or button.disabled: return
	attempts += 1
	button.disabled = true
	if bool(device.get("waste", false)):
		button.text = "✅ 차단 · " + str(device["name"])
		_register_success(90, "%s의 대기전력을 차단했습니다." % device["name"])
	else:
		button.text = "⚠ 사용 중 · " + str(device["name"])
		_register_miss(35, "사용 중인 기기는 대기전력이 아닙니다.")

func _build_hydro_gate() -> void:
	hydro_target = rng.randi_range(3, 9) * 10
	hydro_flow = rng.randi_range(2, 6) * 10
	primary_label = _arena_label("요청 유량 %d ㎥/s  |  수문 유량 %d ㎥/s" % [hydro_target, hydro_flow], 25, Color("64c7ff"))
	secondary_label = _arena_label("유량이 너무 크면 하류 생태계에 부담을 줄 수 있어요.", 17)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	arena.add_child(row)
	for spec in [["−10 닫기", -10], ["＋10 열기", 10], ["✓ 유량 확정", 0]]:
		var button := _make_button(spec[0], Color("287ca8") if spec[1] != 0 else Color("2a9b70"))
		button.pressed.connect(_on_hydro_action.bind(int(spec[1])))
		row.add_child(button)

func _on_hydro_action(change: int) -> void:
	if not _can_play(): return
	if change != 0:
		hydro_flow = clampi(hydro_flow + change, 10, 100)
		primary_label.text = "요청 유량 %d ㎥/s  |  수문 유량 %d ㎥/s" % [hydro_target, hydro_flow]
		return
	attempts += 1
	var error := absi(hydro_flow - hydro_target)
	if error == 0:
		_register_success(125, "정확한 유량! 물의 힘과 생태 안전을 함께 지켰어요.")
	else:
		_register_miss(mini(45, error), "요청과 %d만큼 차이 납니다." % error)
	hydro_target = rng.randi_range(3, 9) * 10
	primary_label.text = "요청 유량 %d ㎥/s  |  수문 유량 %d ㎥/s" % [hydro_target, hydro_flow]

func _build_energy_sort() -> void:
	primary_label = _arena_label("", 31, Color("b6f58e"))
	secondary_label = _arena_label("카드가 어느 범주인지 고르세요.", 17)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	arena.add_child(row)
	for category in range(3):
		var button := _make_button(["🌱 재생에너지", "🪨 비재생에너지", "💡 효율 기술"][category], [Color("28885d"), Color("80584c"), Color("aa8b2e")][category])
		button.custom_minimum_size = Vector2(270, 66)
		button.pressed.connect(_on_sort_pressed.bind(category))
		row.add_child(button)
	_next_sort_card()

func _next_sort_card() -> void:
	current_card = (SORT_CARDS[rng.randi_range(0, SORT_CARDS.size() - 1)] as Dictionary).duplicate(true)
	if primary_label:
		primary_label.text = "에너지 카드  |  %s" % current_card["name"]

func _on_sort_pressed(category: int) -> void:
	if not _can_play(): return
	attempts += 1
	if category == int(current_card.get("category", -1)):
		_register_success(100, "정답! " + str(current_card["why"]))
	else:
		_register_miss(28, "다시 분류해 볼까요? " + str(current_card["why"]))
	_next_sort_card()

func _build_battery_relay() -> void:
	primary_label = _arena_label("", 28, Color("d4ff76"))
	secondary_label = _arena_label("계통 상태를 보고 저장장치 행동을 선택하세요.", 17)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	arena.add_child(row)
	for action in range(3):
		var button := _make_button(["⬇ 잉여 전력 충전", "⬆ 부족 전력 방전", "⏸ 균형 유지"][action], Color("688a2e"))
		button.custom_minimum_size = Vector2(275, 62)
		button.pressed.connect(_on_battery_action.bind(action))
		row.add_child(button)
	_spawn_battery_state()

func _spawn_battery_state() -> void:
	battery_state = rng.randi_range(0, 2)
	mode_tick = 0.0
	if primary_label:
		primary_label.text = ["☀️ 발전 +35 MW · 전력이 남아요", "🏙️ 수요 +30 MW · 전력이 부족해요", "⚖️ 생산과 소비가 같아요"][battery_state]

func _on_battery_action(action: int) -> void:
	if not _can_play(): return
	attempts += 1
	if action == battery_state:
		_register_success(95, ["남는 전기를 저장했어요.", "저장 전기를 필요한 곳에 공급했어요.", "불필요한 충·방전을 피했어요."][action])
	else:
		_register_miss(30, "저장장치는 잉여일 때 충전하고 부족할 때 방전합니다.")
	_spawn_battery_state()

func _build_eco_commute() -> void:
	primary_label = _arena_label("", 24, Color("72ebb0"))
	secondary_label = _arena_label("무조건 한 수단이 아니라 상황에 맞는 저탄소 선택이 중요해요.", 16)
	var row := HBoxContainer.new()
	row.name = "CommuteButtons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	arena.add_child(row)
	_next_commute_scenario()

func _next_commute_scenario() -> void:
	current_scenario = (COMMUTE_SCENARIOS[rng.randi_range(0, COMMUTE_SCENARIOS.size() - 1)] as Dictionary).duplicate(true)
	primary_label.text = str(current_scenario["prompt"])
	var row := arena.get_node_or_null("CommuteButtons") as HBoxContainer
	if not row: return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var options: Array = current_scenario["options"]
	for option_idx in range(options.size()):
		var button := _make_button(str(options[option_idx]), Color("26865f"))
		button.custom_minimum_size = Vector2(265, 62)
		button.pressed.connect(_on_commute_pressed.bind(option_idx))
		row.add_child(button)

func _on_commute_pressed(option_idx: int) -> void:
	if not _can_play(): return
	attempts += 1
	if option_idx == int(current_scenario.get("answer", -1)):
		_register_success(105, "좋은 선택! " + str(current_scenario["why"]))
	else:
		_register_miss(30, "더 적은 에너지를 쓰는 방법이 있어요. " + str(current_scenario["why"]))
	_next_commute_scenario()

func _update_mode(delta: float) -> void:
	match game_id:
		"solar_align":
			pass
		"wind_rhythm":
			pass
		"grid_balance":
			pass
		"battery_relay":
			mode_tick += delta
			if mode_tick >= 2.2:
				mode_tick = 0.0
				streak = 0
				_spawn_battery_state()

func _register_success(points: int, message: String, count_correct: bool = true) -> void:
	score = mini(GameManager.MINIGAME_SCORE_LIMIT, score + points)
	streak += 1
	best_streak = maxi(best_streak, streak)
	if count_correct:
		correct += 1
	feedback_label.text = "✅ %s  ·  +%d점%s" % [message, points, "  ·  콤보 ×%d" % streak if streak >= 2 else ""]
	feedback_label.add_theme_color_override("font_color", Color("83f2b6"))
	_refresh_score()

func _register_miss(penalty: int, message: String) -> void:
	score = maxi(0, score - penalty)
	streak = 0
	feedback_label.text = "💡 %s  ·  -%d점" % [message, penalty]
	feedback_label.add_theme_color_override("font_color", Color("ffb28e"))
	_refresh_score()

func _refresh_score() -> void:
	if score_label:
		score_label.text = "점수  %04d" % score

func _submit_score() -> void:
	if submitted:
		return
	submitted = true
	active = false
	if is_instance_valid(solar_arcade) and solar_arcade.has_method("set_running"):
		solar_arcade.call("set_running", false)
	if is_instance_valid(wind_arcade) and wind_arcade.has_method("set_running"):
		wind_arcade.call("set_running", false)
	if is_instance_valid(grid_arcade) and grid_arcade.has_method("set_running"):
		grid_arcade.call("set_running", false)
	if is_instance_valid(standby_arcade) and standby_arcade.has_method("set_running"):
		standby_arcade.call("set_running", false)
	feedback_label.text = "⏱️ 도전 종료! 점수를 제출했습니다."
	feedback_label.add_theme_color_override("font_color", Color("ffe083"))
	submission_label.text = "다른 플레이어의 도전이 끝나기를 기다리는 중…"
	GameManager.submit_minigame_score(_local_player_index(), score, {"correct": correct, "attempts": attempts, "best_streak": best_streak})

func _build_results(results: Array) -> void:
	_clear_arena()
	var heading := _arena_label("에너지 챌린지 최종 순위", 28, Color("ffe06b"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for result_variant in results:
		var result: Dictionary = result_variant
		var row := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("173743") if int(result.get("player_idx", -1)) == _local_player_index() else Color("102a34")
		style.set_corner_radius_all(10)
		style.content_margin_left = 18
		style.content_margin_right = 18
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		row.add_theme_stylebox_override("panel", style)
		arena.add_child(row)
		var label := Label.new()
		label.text = "%d위   %-10s    %4d점                         ⚡ 에너지 +%d" % [int(result["rank"]), str(result["name"]), int(result["score"]), int(result["reward"])]
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color("fff0a6") if int(result["rank"]) == 1 else Color("d7edf0"))
		row.add_child(label)

func _arena_label(text_value: String, font_size: int, color: Color = Color("d9eef2")) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	arena.add_child(label)
	return label

func _make_button(text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(220, 58)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.25)
	normal.border_color = color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate()
	hover.bg_color = color.darkened(0.08)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.40)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	return button

func _can_play() -> bool:
	return active and not submitted

func _local_player_index() -> int:
	if NetworkManager and NetworkManager.is_online:
		return NetworkManager.get_local_player_index()
	return 0
