extends Control
class_name MiniGameUI

## 에너지 교육 미니게임을 하나의 동시 플레이 모달에서 운영합니다.

signal standalone_replay_requested
signal standalone_menu_requested

const UI = preload("res://scripts/ui/CommercialUI.gd")
const SOLAR_PANEL_DASH = preload("res://scripts/minigames/SolarPanelDash3D.gd")
const WIND_TURBINE_PILOT = preload("res://scripts/minigames/WindTurbinePilot3D.gd")
const SMART_GRID_BALANCE = preload("res://scripts/minigames/SmartGridBalance3D.gd")
const STANDBY_POWER_HUNT = preload("res://scripts/minigames/StandbyPowerHunt3D.gd")
const HYDRO_GATE_RUN = preload("res://scripts/minigames/HydroGateRun3D.gd")
const ENERGY_SOURCE_SORT = preload("res://scripts/minigames/EnergySourceSort3D.gd")
const BATTERY_SHUTTLE = preload("res://scripts/minigames/BatteryShuttle3D.gd")
const SHARED_SCHOOL_BUS = preload("res://scripts/minigames/SharedSchoolBus3D.gd")
const HEAT_LEAK_DASH = preload("res://scripts/minigames/HeatLeakDash3D.gd")
const LEARNING_FEEDBACK = preload("res://scripts/minigames/MiniGameLearningFeedback.gd")

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

var dimmer: ColorRect
var card: PanelContainer
var standalone_mode := false
var standalone_actions: HBoxContainer
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

var guide_panel: PanelContainer
var guide_open := false
var round_started_locally := false
var guide_title_label: Label
var guide_badge_label: Label
var guide_objective_label: Label
var guide_controls_container: VBoxContainer
var guide_lesson_label: Label
var guide_tip_label: Label
var guide_rewards_label: Label
var guide_start_button: Button

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
var learning_counts: Dictionary = {}
var learning_snapshot: Dictionary = {}
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
var solar_arcade: SubViewportContainer
var wind_arcade: SubViewportContainer
var grid_arcade: SubViewportContainer
var standby_arcade: SubViewportContainer
var hydro_arcade: SubViewportContainer
var sort_arcade: SubViewportContainer
var battery_arcade: SubViewportContainer
var commute_arcade: SubViewportContainer
var heat_arcade: SubViewportContainer

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
	content.name = "ContentBox"
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
	if standalone_mode:
		standalone_actions = HBoxContainer.new()
		standalone_actions.alignment = BoxContainer.ALIGNMENT_CENTER
		standalone_actions.add_theme_constant_override("separation", 16)
		standalone_actions.visible = false
		content.add_child(standalone_actions)
		var replay_button := _make_button("↻ 다시 플레이", Color("2a9b70"))
		replay_button.custom_minimum_size = Vector2(220, 48)
		replay_button.pressed.connect(func(): standalone_replay_requested.emit())
		standalone_actions.add_child(replay_button)
		var menu_button := _make_button("다른 미니게임", Color("287ca8"))
		menu_button.custom_minimum_size = Vector2(220, 48)
		menu_button.pressed.connect(func(): standalone_menu_requested.emit())
		standalone_actions.add_child(menu_button)
	_build_guide_ui()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_guide_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			dismiss_guide()

func _process(delta: float) -> void:
	if not active or submitted or not round_started_locally:
		return
	elapsed += delta
	if not standalone_mode and NetworkManager.is_online and NetworkManager.is_host:
		elapsed = maxf(elapsed, duration - clampf(GameManager.minigame_time_remaining - GameManager.MINIGAME_SUBMISSION_GRACE_SECONDS, 0.0, duration))
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
	learning_counts.clear()
	learning_snapshot.clear()
	round_started_locally = false
	mode_tick = 0.0
	score_tick = 0.0
	submitted = false
	active = true
	if is_instance_valid(standalone_actions):
		standalone_actions.visible = false
	# 순위 경쟁은 같은 문제 순서와 환경에서 진행합니다. 캐릭터 외형만 플레이어마다 다릅니다.
	rng.seed = int(game_data.get("seed", 1))
	visible = true
	title_label.text = str(game_data.get("title", "에너지 미니게임"))
	mode_label.text = "전원 동시 플레이  ·  %s" % game_data.get("input_hint", "빠른 도전")
	objective_label.text = "목표  |  " + str(game_data.get("objective", "제한시간 안에 최고 점수에 도전하세요."))
	lesson_label.text = "에너지 원리  |  " + str(game_data.get("lesson", ""))
	timer_bar.max_value = duration
	timer_bar.value = duration
	timer_label.text = "%02d초" % ceili(duration)
	feedback_label.text = "게임 방법을 확인하고 시작 버튼을 누르세요."
	submission_label.text = "내 점수는 종료 즉시 비공개로 제출됩니다."
	_refresh_score()
	_build_mode()
	_show_guide_popup()

func _on_submission_changed(state: Dictionary) -> void:
	if not visible or int((state.get("game", {}) as Dictionary).get("round_id", -2)) != round_id:
		return
	var phase := str((state.get("game", {}) as Dictionary).get("phase", ""))
	if phase == "ready":
		var ready_count := int(state.get("ready_count", 0))
		var player_count := int(state.get("player_count", 4))
		var guide_seconds := ceili(float(state.get("guide_remaining", 0.0)))
		if is_guide_open():
			guide_badge_label.text = "게임 방법 · %d명 준비 · %d초 뒤 자동 시작" % [ready_count, guide_seconds]
		else:
			feedback_label.text = "준비 완료! 다른 플레이어를 기다리는 중…"
			submission_label.text = "준비 %d / %d명 · %d초 뒤 자동 시작" % [ready_count, player_count, guide_seconds]
		return
	if phase == "countdown":
		var countdown := maxi(1, ceili(float(state.get("countdown_remaining", 0.0))))
		if is_guide_open():
			guide_badge_label.text = "다 함께 %d초 후 시작!" % countdown
		else:
			timer_label.text = "%d초 후" % countdown
			feedback_label.text = "모두 준비 완료! %d초 후 동시에 시작합니다." % countdown
			submission_label.text = "카운트다운이 끝나면 조작할 수 있어요."
		return
	if phase == "playing" and not round_started_locally and active and not submitted:
		_begin_local_round()
	if phase == "playing" and round_started_locally:
		var authoritative_elapsed := duration - clampf(float(state.get("time_remaining", duration + GameManager.MINIGAME_SUBMISSION_GRACE_SECONDS)) - GameManager.MINIGAME_SUBMISSION_GRACE_SECONDS, 0.0, duration)
		elapsed = maxf(elapsed, authoritative_elapsed)
	submission_label.text = "점수 제출 %d / %d명%s" % [int(state.get("submitted_count", 0)), int(state.get("player_count", 4)), "  ·  내 점수 제출 완료" if submitted else ""]

func _begin_local_round() -> void:
	if round_started_locally or not active or submitted:
		return
	round_started_locally = true
	guide_open = false
	if is_instance_valid(guide_panel):
		guide_panel.visible = false
	var content_node := card.find_child("ContentBox", false, false)
	if is_instance_valid(content_node):
		content_node.visible = true
	elapsed = 0.0
	_set_arcades_running(true)
	feedback_label.text = "게임 시작! 최고 점수에 도전하세요."

func _on_minigame_finished(results: Array) -> void:
	if not visible:
		return
	if is_instance_valid(guide_panel):
		guide_panel.visible = false
	var content_node := card.find_child("ContentBox", false, false)
	if is_instance_valid(content_node):
		content_node.visible = true
	guide_open = false
	round_started_locally = false
	active = false
	submitted = true
	if learning_snapshot.is_empty():
		learning_snapshot = _learning_metrics_snapshot()
	var learning_report: Dictionary = LEARNING_FEEDBACK.result_lines(game_id, learning_snapshot)
	_build_results(results)
	timer_label.text = "종료"
	timer_bar.value = 0
	lesson_label.text = "내 플레이  |  " + str(learning_report.get("evidence", ""))
	feedback_label.text = "다음 도전  |  " + str(learning_report.get("next_action", ""))
	feedback_label.add_theme_color_override("font_color", Color("83f2b6"))
	if standalone_mode:
		submission_label.text = "언제든 다시 플레이하거나 다른 게임을 선택할 수 있어요."
		if is_instance_valid(standalone_actions):
			standalone_actions.visible = true
		return
	submission_label.text = "잠시 후 보드 게임이 이어집니다."
	var finished_round := round_id
	get_tree().create_timer(GameManager.MINIGAME_RESULTS_SECONDS - 0.2, false).timeout.connect(func():
		if round_id == finished_round and not active:
			visible = false
	)

func _on_turn_changed(_player_idx: int) -> void:
	if not active and not standalone_mode:
		visible = false

func cancel_minigame() -> void:
	_set_arcades_running(false)
	if is_instance_valid(guide_panel):
		guide_panel.visible = false
	var content_node := card.find_child("ContentBox", false, false)
	if is_instance_valid(content_node):
		content_node.visible = true
	guide_open = false
	active = false
	submitted = false
	visible = false

func restore_online_round() -> void:
	var restored: Dictionary = GameManager.active_minigame
	if restored.is_empty():
		cancel_minigame()
		return
	visible = true
	if int(restored.get("round_id", -1)) != round_id:
		_on_minigame_started(restored)
	if str(restored.get("phase", "")) == "results":
		_on_minigame_finished(restored.get("results", []))
		return
	var local_idx := _local_player_index()
	if str(restored.get("phase", "")) == "ready" and not is_guide_open() and not GameManager.minigame_ready_players.has(local_idx):
		GameManager.start_minigame_action(local_idx, round_id)
	if GameManager.minigame_scores.has(local_idx):
		submitted = true
		active = false
		_set_arcades_running(false)
	elif submitted and str(restored.get("phase", "")) == "playing":
		# A score sent just before the outage may not have reached the host.
		GameManager.submit_minigame_score(local_idx, score, {"correct": correct, "attempts": attempts, "best_streak": best_streak}, round_id)
	_on_submission_changed(GameManager.get_minigame_state())

func _set_arcades_running(running_state: bool) -> void:
	var arcades := [
		solar_arcade, wind_arcade, grid_arcade, standby_arcade,
		hydro_arcade, sort_arcade, battery_arcade, commute_arcade, heat_arcade
	]
	for arc in arcades:
		if is_instance_valid(arc):
			if arc.has_method("set_running"):
				arc.call("set_running", running_state)
			elif "running" in arc:
				arc.set("running", running_state)

func _build_guide_ui() -> void:
	guide_panel = PanelContainer.new()
	guide_panel.name = "GuidePanel"
	guide_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guide_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("071e29fc"), Color("42d6b0"), 24.0, 24))
	guide_panel.visible = false
	card.add_child(guide_panel)

	var guide_content := VBoxContainer.new()
	guide_content.add_theme_constant_override("separation", 10)
	guide_panel.add_child(guide_content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	guide_content.add_child(header)

	guide_title_label = Label.new()
	guide_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_title_label.add_theme_font_size_override("font_size", 28)
	guide_title_label.add_theme_color_override("font_color", Color("fff0a6"))
	header.add_child(guide_title_label)

	var badge_box := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("0d3744")
	badge_style.border_color = Color("38bca8")
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(12)
	badge_style.content_margin_left = 14
	badge_style.content_margin_right = 14
	badge_style.content_margin_top = 4
	badge_style.content_margin_bottom = 4
	badge_box.add_theme_stylebox_override("panel", badge_style)
	header.add_child(badge_box)

	guide_badge_label = Label.new()
	guide_badge_label.text = "게임 방법 안내"
	guide_badge_label.add_theme_font_size_override("font_size", 15)
	guide_badge_label.add_theme_color_override("font_color", Color("8fffe0"))
	badge_box.add_child(guide_badge_label)

	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 2)
	div.color = Color("1e4a59")
	guide_content.add_child(div)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	guide_content.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	var obj_box := _make_guide_section("미션 목표", Color("79efaa"))
	body.add_child(obj_box)
	guide_objective_label = Label.new()
	guide_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_objective_label.add_theme_font_size_override("font_size", 16)
	guide_objective_label.add_theme_color_override("font_color", Color("e0f6f1"))
	obj_box.get_child(0).add_child(guide_objective_label)

	var ctrl_box := _make_guide_section("조작 방법 & 플레이 규칙", Color("79d7ef"))
	body.add_child(ctrl_box)
	guide_controls_container = VBoxContainer.new()
	guide_controls_container.add_theme_constant_override("separation", 6)
	ctrl_box.get_child(0).add_child(guide_controls_container)

	var lesson_box := _make_guide_section("알아두면 유익한 에너지 과학 원리", Color("ffd66e"))
	body.add_child(lesson_box)
	guide_lesson_label = Label.new()
	guide_lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_lesson_label.add_theme_font_size_override("font_size", 15)
	guide_lesson_label.add_theme_color_override("font_color", Color("dbeff0"))
	lesson_box.get_child(0).add_child(guide_lesson_label)

	var tip_box := _make_guide_section("고득점 공략 & 순위 보상", Color("ffb86c"))
	body.add_child(tip_box)
	guide_tip_label = Label.new()
	guide_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_tip_label.add_theme_font_size_override("font_size", 15)
	guide_tip_label.add_theme_color_override("font_color", Color("ffeac2"))
	tip_box.get_child(0).add_child(guide_tip_label)

	guide_rewards_label = Label.new()
	guide_rewards_label.text = "순위별 에너지 보상: 1위 +20  |  2위 +10  |  3위 +5  |  4위 +1"
	guide_rewards_label.add_theme_font_size_override("font_size", 15)
	guide_rewards_label.add_theme_color_override("font_color", Color("95f2d6"))
	tip_box.get_child(0).add_child(guide_rewards_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	guide_content.add_child(footer)

	guide_start_button = Button.new()
	guide_start_button.text = "게임 시작!  (Space 또는 Enter)"
	guide_start_button.custom_minimum_size = Vector2(420, 52)
	guide_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	guide_start_button.add_theme_font_size_override("font_size", 20)
	guide_start_button.pressed.connect(dismiss_guide)
	UI.apply_primary_button(guide_start_button)
	footer.add_child(guide_start_button)

func _make_guide_section(title: String, color: Color) -> PanelContainer:
	var section_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0a2530d9")
	style.border_color = Color("1f4e5e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	section_panel.add_theme_stylebox_override("panel", style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	section_panel.add_child(inner)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", color)
	inner.add_child(title_lbl)

	return section_panel

func _populate_guide_content() -> void:
	if not is_instance_valid(guide_panel):
		return
	var title := str(game_data.get("title", "에너지 미니게임"))
	var duration_val := int(game_data.get("duration", 30))
	guide_title_label.text = title
	guide_badge_label.text = "게임 방법 안내 · %d초 아케이드" % duration_val
	guide_objective_label.text = str(game_data.get("objective", "제한시간 안에 최고 점수를 달성하세요."))
	guide_lesson_label.text = str(game_data.get("lesson", "신재생에너지를 올바르게 활용하여 탄소를 줄입니다."))
	guide_tip_label.text = str(game_data.get("tip", "신속하고 정확하게 조작하여 콤보 점수를 획득하세요!"))

	for child in guide_controls_container.get_children():
		guide_controls_container.remove_child(child)
		child.queue_free()

	var controls: Array = game_data.get("controls", [])
	if controls.is_empty():
		var hint := str(game_data.get("input_hint", "키보드로 조작하세요."))
		var row := _create_control_row("기본 조작", hint)
		guide_controls_container.add_child(row)
	else:
		for item in controls:
			if item is Dictionary:
				var key_str := str(item.get("key", ""))
				var action_str := str(item.get("action", ""))
				var row := _create_control_row(key_str, action_str)
				guide_controls_container.add_child(row)

func _create_control_row(key_text: String, action_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var key_badge := PanelContainer.new()
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color("143b47")
	key_style.border_color = Color("388399")
	key_style.set_border_width_all(1)
	key_style.set_corner_radius_all(6)
	key_style.content_margin_left = 12
	key_style.content_margin_right = 12
	key_style.content_margin_top = 4
	key_style.content_margin_bottom = 4
	key_badge.add_theme_stylebox_override("panel", key_style)
	row.add_child(key_badge)

	var key_lbl := Label.new()
	key_lbl.text = key_text
	key_lbl.add_theme_font_size_override("font_size", 15)
	key_lbl.add_theme_color_override("font_color", Color("ffffff"))
	key_badge.add_child(key_lbl)

	var arrow_lbl := Label.new()
	arrow_lbl.text = "→"
	arrow_lbl.add_theme_font_size_override("font_size", 14)
	arrow_lbl.add_theme_color_override("font_color", Color("5fb5a6"))
	row.add_child(arrow_lbl)

	var action_lbl := Label.new()
	action_lbl.text = action_text
	action_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_lbl.add_theme_font_size_override("font_size", 15)
	action_lbl.add_theme_color_override("font_color", Color("d5f1ed"))
	row.add_child(action_lbl)

	return row

func _show_guide_popup() -> void:
	guide_open = true
	elapsed = 0.0
	_set_arcades_running(false)
	var content_node := card.find_child("ContentBox", false, false)
	if is_instance_valid(content_node):
		content_node.visible = false
	_populate_guide_content()
	if is_instance_valid(guide_panel):
		guide_panel.visible = true
	if is_instance_valid(guide_start_button):
		guide_start_button.grab_focus()
	feedback_label.text = "게임 방법을 확인하고 시작 버튼을 누르세요."

func dismiss_guide() -> void:
	if not guide_open:
		return
	guide_open = false
	if is_instance_valid(guide_panel):
		guide_panel.visible = false
	var content_node := card.find_child("ContentBox", false, false)
	if is_instance_valid(content_node):
		content_node.visible = true
	feedback_label.text = "준비 완료! 모두 함께 시작할 때까지 기다리세요."
	if GameManager:
		GameManager.start_minigame_action(_local_player_index(), round_id)
		if int(GameManager.active_minigame.get("round_id", -1)) == round_id:
			_on_submission_changed(GameManager.get_minigame_state())

func is_guide_open() -> bool:
	return guide_open and is_instance_valid(guide_panel) and guide_panel.visible

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
		"heat_leak": _build_heat_leak()
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
	if is_instance_valid(hydro_arcade) and hydro_arcade.has_method("set_running"):
		hydro_arcade.call("set_running", false)
	if is_instance_valid(sort_arcade) and sort_arcade.has_method("set_running"):
		sort_arcade.call("set_running", false)
	if is_instance_valid(battery_arcade) and battery_arcade.has_method("set_running"):
		battery_arcade.call("set_running", false)
	if is_instance_valid(commute_arcade) and commute_arcade.has_method("set_running"):
		commute_arcade.call("set_running", false)
	if is_instance_valid(heat_arcade) and heat_arcade.has_method("set_running"):
		heat_arcade.call("set_running", false)
	solar_arcade = null
	wind_arcade = null
	grid_arcade = null
	standby_arcade = null
	hydro_arcade = null
	sort_arcade = null
	battery_arcade = null
	commute_arcade = null
	heat_arcade = null
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
	solar_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

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
	wind_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

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
	grid_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

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
	standby_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

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
		button.text = "차단 완료 · " + str(device["name"])
		_register_success(90, "%s의 대기전력을 차단했습니다." % device["name"])
	else:
		button.text = "사용 중 · " + str(device["name"])
		_register_miss(35, "사용 중인 기기는 대기전력이 아닙니다.")

func _build_hydro_gate() -> void:
	hydro_arcade = HYDRO_GATE_RUN.new()
	hydro_arcade.arcade_event.connect(_on_hydro_arcade_event)
	hydro_arcade.game_over.connect(_on_hydro_game_over)
	arena.add_child(hydro_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	# 네 명이 같은 강우 예보와 시작 수위에서 겨루도록 공통 라운드 시드를 전달합니다.
	hydro_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

func _on_hydro_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	if points <= 0:
		feedback_label.text = message
		_show_learning_cue(success, points, count_correct)
		return
	attempts += 1
	if success:
		_register_success(points, message, count_correct)
	else:
		_register_miss(points, message)

func _on_hydro_game_over(generated_kwh: float) -> void:
	if not _can_play():
		return
	feedback_label.text = "댐이 넘쳤어요! %.1f kWh 생산 후 도전 종료" % generated_kwh
	feedback_label.add_theme_color_override("font_color", Color("ff937e"))
	var finished_round := round_id
	get_tree().create_timer(1.3, false).timeout.connect(func():
		if round_id == finished_round and _can_play():
			_submit_score()
	)

func _build_energy_sort() -> void:
	sort_arcade = ENERGY_SOURCE_SORT.new()
	sort_arcade.arcade_event.connect(_on_sort_arcade_event)
	arena.add_child(sort_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	sort_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

func _on_sort_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	attempts += 1
	if success:
		_register_success(points, message, count_correct)
	else:
		_register_miss(points, message)

func _build_battery_relay() -> void:
	battery_arcade = BATTERY_SHUTTLE.new()
	battery_arcade.arcade_event.connect(_on_battery_arcade_event)
	arena.add_child(battery_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	battery_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

func _on_battery_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	attempts += 1
	if success:
		_register_success(points, message, count_correct)
	else:
		_register_miss(points, message)

func _build_eco_commute() -> void:
	commute_arcade = SHARED_SCHOOL_BUS.new()
	commute_arcade.arcade_event.connect(_on_commute_arcade_event)
	arena.add_child(commute_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	commute_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

func _on_commute_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	if points <= 0:
		feedback_label.text = message
		_show_learning_cue(success, points, count_correct)
		return
	attempts += 1
	if success:
		_register_success(points, message, count_correct)
	else:
		_register_miss(points, message)

func _build_heat_leak() -> void:
	heat_arcade = HEAT_LEAK_DASH.new()
	heat_arcade.arcade_event.connect(_on_heat_arcade_event)
	arena.add_child(heat_arcade)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	heat_arcade.call("setup", player_data, int(game_data.get("seed", 1)))

func _on_heat_arcade_event(points: int, success: bool, message: String, count_correct: bool) -> void:
	if not _can_play():
		return
	if success:
		attempts += 1
		_register_success(points, message, count_correct)
	else:
		attempts += 1
		_register_miss(points, message)

func _update_mode(delta: float) -> void:
	match game_id:
		"solar_align":
			pass
		"wind_rhythm":
			pass
		"grid_balance":
			pass
		"battery_relay":
			pass

func _register_success(points: int, message: String, count_correct: bool = true) -> void:
	score = mini(GameManager.MINIGAME_SCORE_LIMIT, score + points)
	streak += 1
	best_streak = maxi(best_streak, streak)
	if count_correct:
		correct += 1
	feedback_label.text = "%s  ·  +%d점%s" % [message, points, "  ·  콤보 ×%d" % streak if streak >= 2 else ""]
	feedback_label.add_theme_color_override("font_color", Color("83f2b6"))
	_track_learning_event(true, points, count_correct)
	_refresh_score()

func _register_miss(penalty: int, message: String) -> void:
	score = maxi(0, score - penalty)
	streak = 0
	feedback_label.text = "%s  ·  -%d점" % [message, penalty]
	feedback_label.add_theme_color_override("font_color", Color("ffb28e"))
	_track_learning_event(false, penalty, false)
	_refresh_score()

func _track_learning_event(success: bool, points: int, count_correct: bool) -> void:
	if game_id == "solar_align" and not success and points == 25:
		learning_counts["solar_wrong"] = int(learning_counts.get("solar_wrong", 0)) + 1
	elif game_id == "wind_rhythm":
		if success and points == 75:
			learning_counts["storm_braked"] = int(learning_counts.get("storm_braked", 0)) + 1
		elif not success and points == 35:
			learning_counts["storm_broken"] = int(learning_counts.get("storm_broken", 0)) + 1
		elif success and count_correct:
			learning_counts["wind_aligned"] = int(learning_counts.get("wind_aligned", 0)) + 1
	elif game_id == "standby_hunt" and not success and points == 48:
		learning_counts["active_unplugged"] = int(learning_counts.get("active_unplugged", 0)) + 1
	elif game_id == "battery_relay" and success:
		if points == 20:
			learning_counts["battery_stored"] = int(learning_counts.get("battery_stored", 0)) + 1
		elif points == 80:
			learning_counts["battery_supplied"] = int(learning_counts.get("battery_supplied", 0)) + 1
	elif game_id == "heat_leak" and not success:
		learning_counts["closed_window_misses"] = int(learning_counts.get("closed_window_misses", 0)) + 1
	_show_learning_cue(success, points, count_correct)

func _show_learning_cue(success: bool, points: int, count_correct: bool) -> void:
	var cue: String = LEARNING_FEEDBACK.live_line(game_id, success, points, count_correct, _learning_metrics_snapshot())
	if not cue.is_empty():
		lesson_label.text = "방금 선택  |  " + cue

func _learning_metrics_snapshot() -> Dictionary:
	var metrics := learning_counts.duplicate()
	metrics["correct"] = correct
	metrics["attempts"] = attempts
	if is_instance_valid(grid_arcade):
		metrics["grid_gap"] = absf(float(grid_arcade.get("demand")) - float(grid_arcade.get("supply")))
		metrics["measurement_time"] = float(grid_arcade.get("measurement_time"))
		if float(metrics["measurement_time"]) > 0.0:
			metrics["average_gap"] = float(grid_arcade.get("gap_integral")) / float(metrics["measurement_time"])
	if is_instance_valid(standby_arcade):
		metrics["saved_watts"] = int(standby_arcade.get("saved_watts"))
	if is_instance_valid(hydro_arcade):
		metrics["generated_kwh"] = float(hydro_arcade.get("generated_kwh"))
		metrics["overflowed"] = bool(hydro_arcade.get("overflowed"))
	if is_instance_valid(commute_arcade):
		metrics["delivered_total"] = int(commute_arcade.get("delivered_total"))
		metrics["passengers"] = int(commute_arcade.get("passengers"))
	return metrics

func _refresh_score() -> void:
	if score_label:
		score_label.text = "점수  %04d" % score

func _submit_score() -> void:
	if submitted:
		return
	if is_instance_valid(hydro_arcade) and hydro_arcade.has_method("finalize_generation_score"):
		hydro_arcade.call("finalize_generation_score")
	learning_snapshot = _learning_metrics_snapshot()
	submitted = true
	active = false
	_set_arcades_running(false)
	feedback_label.text = "도전 종료! 점수를 제출했습니다."
	feedback_label.add_theme_color_override("font_color", Color("ffe083"))
	submission_label.text = "다른 플레이어의 도전이 끝나기를 기다리는 중…"
	GameManager.submit_minigame_score(_local_player_index(), score, {"correct": correct, "attempts": attempts, "best_streak": best_streak}, round_id)

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
		var columns := HBoxContainer.new()
		columns.add_theme_constant_override("separation", 12)
		row.add_child(columns)
		var rank_color := Color("fff0a6") if int(result["rank"]) == 1 else Color("d7edf0")
		var rank_label := _result_column("%d위" % int(result["rank"]), 66, rank_color)
		columns.add_child(rank_label)
		var name_label := _result_column(str(result["name"]), 0, rank_color)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		columns.add_child(name_label)
		var score_column := _result_column("%d점" % int(result["score"]), 140, rank_color)
		score_column.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		columns.add_child(score_column)
		var reward_label := _result_column("에너지 +%d" % int(result["reward"]), 165, rank_color)
		reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		columns.add_child(reward_label)

func _result_column(value: String, min_width: float, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.x = min_width
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	return label

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
	return active and not submitted and not is_guide_open()

func _local_player_index() -> int:
	if NetworkManager and NetworkManager.is_online:
		return NetworkManager.get_local_player_index()
	return 0
