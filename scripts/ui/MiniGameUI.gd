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
const MINIGAME_INPUT = preload("res://scripts/minigames/MiniGameInput.gd")

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
var touch_controls: HBoxContainer
var title_label: Label
var mode_label: Label
var objective_label: Label
var timer_label: Label
var timer_bar: ProgressBar
var score_label: Label
var goal_label: Label
var arena: VBoxContainer
var arena_panel: PanelContainer
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
var guide_practice_button: Button
var practice_actions: HBoxContainer
var practice_active := false
var practice_elapsed := 0.0
var practice_completed_at := -1.0
const HYDRO_PRACTICE_SECONDS := 30.0
var finishing_animation := false
var pending_results: Array = []

var active := false
var surface_enabled := true
var submitted := false
var game_data: Dictionary = {}
var game_id := ""
var round_id := -1
var duration := 30.0
var elapsed := 0.0
var simulation_elapsed := 0.0
var round_start_msec := 0
var round_pause_msec := -1
var hydro_submit_msec := -1
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
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left = 18
	card.offset_top = 10
	card.offset_right = -18
	card.offset_bottom = -10
	card.add_theme_stylebox_override("panel", UI.padded_panel(Color("0b2833fc"), Color("42d6b0"), 12.0, 18))
	add_child(card)

	var content := VBoxContainer.new()
	content.name = "ContentBox"
	content.add_theme_constant_override("separation", 6)
	card.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 27)
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
	timer_bar.add_theme_stylebox_override("background", UI.progress_background())
	timer_bar.add_theme_stylebox_override("fill", UI.progress_fill(UI.TEAL))
	status_row.add_child(timer_bar)
	score_label = Label.new()
	score_label.custom_minimum_size = Vector2(210, 34)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 23)
	score_label.add_theme_color_override("font_color", Color("ffe06b"))
	status_row.add_child(score_label)

	arena_panel = PanelContainer.new()
	arena_panel.custom_minimum_size = Vector2(0, 400)
	arena_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var arena_style := StyleBoxFlat.new()
	arena_style.bg_color = Color("071e28")
	arena_style.border_color = Color("235366")
	arena_style.set_border_width_all(2)
	arena_style.set_corner_radius_all(16)
	arena_style.content_margin_left = 8
	arena_style.content_margin_right = 8
	arena_style.content_margin_top = 8
	arena_style.content_margin_bottom = 8
	arena_panel.add_theme_stylebox_override("panel", arena_style)
	content.add_child(arena_panel)
	arena = VBoxContainer.new()
	arena.alignment = BoxContainer.ALIGNMENT_CENTER
	arena.add_theme_constant_override("separation", 12)
	arena_panel.add_child(arena)

	feedback_label = Label.new()
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.custom_minimum_size = Vector2(0, 22)
	feedback_label.add_theme_font_size_override("font_size", 17)
	feedback_label.add_theme_color_override("font_color", Color("a8d8dd"))
	content.add_child(feedback_label)

	lesson_label = Label.new()
	lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lesson_label.add_theme_font_size_override("font_size", 15)
	lesson_label.add_theme_color_override("font_color", Color("a9c9cf"))
	content.add_child(lesson_label)
	goal_label = Label.new()
	goal_label.name = "GoalProgress"
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_label.add_theme_font_size_override("font_size", 17)
	goal_label.add_theme_color_override("font_color", UI.GOLD)
	content.add_child(goal_label)

	submission_label = Label.new()
	submission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	submission_label.add_theme_font_size_override("font_size", 15)
	submission_label.add_theme_color_override("font_color", Color("72d9c1"))
	content.add_child(submission_label)
	practice_actions = HBoxContainer.new()
	practice_actions.name = "PracticeActions"
	practice_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	practice_actions.visible = false
	content.add_child(practice_actions)
	var practice_end_button := _make_button("연습 마치기 · 안내로 (Esc)", Color("287ca8"))
	# Space is a repeated gate action here, never a GUI button activation.
	# The keyboard exit remains Esc; this button is a pointer alternative.
	practice_end_button.focus_mode = Control.FOCUS_NONE
	practice_end_button.custom_minimum_size = Vector2(320, 44)
	practice_end_button.pressed.connect(_finish_hydro_practice)
	practice_actions.add_child(practice_end_button)
	_build_touch_controls(content)
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
	if not surface_enabled or not is_visible_in_tree():
		return
	if visible and practice_active and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish_hydro_practice()
		return
	if not visible or not is_guide_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if game_id == "hydro_gate" and event.keycode == KEY_P:
			get_viewport().set_input_as_handled()
			_start_hydro_practice()
			return
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			dismiss_guide()

func _build_touch_controls(parent: Control) -> void:
	touch_controls = HBoxContainer.new()
	touch_controls.name = "TouchControls"
	touch_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	touch_controls.add_theme_constant_override("separation", 12)
	touch_controls.visible = false
	parent.add_child(touch_controls)
	for spec in [[KEY_A, "←"], [KEY_D, "→"], [KEY_W, "↑"], [KEY_S, "↓"], [KEY_SPACE, "동작"], [KEY_E, "닫기"]]:
		var holder := Control.new()
		holder.set_meta("input_key", int(spec[0]))
		holder.custom_minimum_size = Vector2(76, 48)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		touch_controls.add_child(holder)
		var background := ColorRect.new()
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.color = Color("235366")
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(background)
		var label := Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.text = str(spec[1])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(label)
		var button := TouchScreenButton.new()
		button.name = "Touch_%d" % int(spec[0])
		var shape := RectangleShape2D.new()
		shape.size = Vector2(76, 48)
		button.shape = shape
		button.position = Vector2(38, 24)
		button.pressed.connect(MINIGAME_INPUT.set_touch.bind(int(spec[0]), true))
		button.released.connect(MINIGAME_INPUT.set_touch.bind(int(spec[0]), false))
		holder.add_child(button)

func _configure_touch_controls() -> void:
	var keys: Array = [KEY_A, KEY_D, KEY_SPACE]
	var action_label := "동작"
	match game_id:
		"solar_align": action_label = "점프"
		"wind_rhythm": action_label = "제동"
		"grid_balance": keys = [KEY_W, KEY_S]
		"standby_hunt":
			keys = [KEY_A, KEY_D, KEY_W, KEY_SPACE]
			action_label = "뽑기"
		"hydro_gate":
			keys = [KEY_A, KEY_D, KEY_W, KEY_SPACE, KEY_E]
			action_label = "열기"
		"energy_sort", "battery_relay": keys = [KEY_A, KEY_D]
		"eco_commute":
			keys = [KEY_A, KEY_D, KEY_S, KEY_SPACE]
			action_label = "태우기"
		"heat_leak": action_label = "닫기"
	for holder in touch_controls.get_children():
		var key := int(holder.get_meta("input_key"))
		holder.visible = key in keys
		if key == KEY_SPACE:
			holder.get_child(1).text = action_label

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		MINIGAME_INPUT.release_all()
	elif what == NOTIFICATION_PAUSED and round_started_locally:
		round_pause_msec = Time.get_ticks_msec()
		MINIGAME_INPUT.release_all()
	elif what == NOTIFICATION_UNPAUSED and round_pause_msec >= 0:
		var paused_for := Time.get_ticks_msec() - round_pause_msec
		round_start_msec += paused_for
		if hydro_submit_msec >= 0:
			hydro_submit_msec += paused_for
		round_pause_msec = -1

func _exit_tree() -> void:
	MINIGAME_INPUT.release_all()

func _process(delta: float) -> void:
	if not surface_enabled:
		return
	if finishing_animation:
		if is_instance_valid(commute_arcade):
			commute_arcade.call("advance_finish_animation", delta)
			if bool(commute_arcade.call("has_pending_finish_animation")):
				return
		finishing_animation = false
		if not pending_results.is_empty():
			var results := pending_results.duplicate(true)
			pending_results.clear()
			_on_minigame_finished(results)
		else:
			feedback_label.text = "모든 학생이 학교에 들어갔어요. 점수 제출 완료!"
		return
	if practice_active:
		practice_elapsed += delta
		_advance_arcade_simulation(minf(HYDRO_PRACTICE_SECONDS, practice_elapsed))
		var progress: Dictionary = hydro_arcade.call("get_practice_progress")
		goal_label.text = "조작 연습  |  " + str(progress.get("hint", "레버로 이동해요"))
		if bool(progress.get("complete", false)):
			if practice_completed_at < 0.0:
				practice_completed_at = practice_elapsed
			feedback_label.text = "수문 열기 → 물의 낙차로 발전 → 닫고 물 모으기 완료!"
			if practice_elapsed - practice_completed_at >= 2.0:
				_finish_hydro_practice()
				return
		timer_label.text = "연습 %02d초" % ceili(maxf(0.0, HYDRO_PRACTICE_SECONDS - practice_elapsed))
		timer_bar.value = maxf(0.0, HYDRO_PRACTICE_SECONDS - practice_elapsed)
		if practice_elapsed >= HYDRO_PRACTICE_SECONDS:
			_finish_hydro_practice()
		return
	if not active or submitted or not round_started_locally:
		return
	# Rendering stalls must not turn a 30-second round into a longer competition.
	elapsed = maxf(elapsed + delta, float(Time.get_ticks_msec() - round_start_msec) / 1000.0)
	if not standalone_mode and NetworkManager.is_online and NetworkManager.is_host:
		elapsed = maxf(elapsed, duration - clampf(GameManager.minigame_time_remaining - GameManager.MINIGAME_SUBMISSION_GRACE_SECONDS, 0.0, duration))
	var remaining := maxf(0.0, duration - elapsed)
	timer_label.text = "%02d초" % ceili(remaining)
	timer_bar.value = remaining
	if remaining <= 5.0:
		timer_label.add_theme_color_override("font_color", Color("ff826e"))
	else:
		timer_label.add_theme_color_override("font_color", Color("f5f7da"))
	if not is_instance_valid(solar_arcade):
		_advance_arcade_simulation(minf(duration, elapsed))
	_update_mode(delta)
	if is_instance_valid(grid_arcade) and grid_arcade.has_method("get_balance_score"):
		score = int(grid_arcade.call("get_balance_score"))
		_refresh_score()
	_refresh_goal_progress()
	if elapsed >= duration or (hydro_submit_msec >= 0 and Time.get_ticks_msec() >= hydro_submit_msec):
		# Solar CharacterBody3D must complete its last step inside the physics callback.
		if is_instance_valid(solar_arcade) and simulation_elapsed < duration - 0.00001:
			return
		_submit_score()

func _physics_process(_delta: float) -> void:
	if not active or submitted or not round_started_locally or not is_instance_valid(solar_arcade):
		return
	var clock_time := maxf(elapsed, float(Time.get_ticks_msec() - round_start_msec) / 1000.0)
	_advance_arcade_simulation(minf(duration, clock_time))

func _advance_arcade_simulation(target_time: float) -> void:
	# Render FPS must not change weather, water flow, scoring ticks or distance travelled.
	# Solar's move_and_slide is called only from _physics_process, at the physics step.
	var arcades := [solar_arcade, wind_arcade, grid_arcade, standby_arcade,
		hydro_arcade, sort_arcade, battery_arcade, commute_arcade, heat_arcade]
	var step_size := get_physics_process_delta_time() if is_instance_valid(solar_arcade) else 1.0 / 60.0
	step_size = maxf(0.001, step_size)
	while target_time - simulation_elapsed >= step_size - 0.000001:
		simulation_elapsed += step_size
		for arcade in arcades:
			if is_instance_valid(arcade):
				arcade.call("_physics_process" if arcade == solar_arcade else "_process", step_size)

func _on_minigame_started(data: Dictionary) -> void:
	if not surface_enabled:
		return
	MINIGAME_INPUT.release_all()
	finishing_animation = false
	pending_results.clear()
	practice_active = false
	practice_actions.visible = false
	game_data = data.duplicate(true)
	game_id = str(game_data.get("id", "solar_align"))
	_configure_touch_controls()
	round_id = int(game_data.get("round_id", -1))
	duration = float(game_data.get("duration", 30.0))
	elapsed = 0.0
	simulation_elapsed = 0.0
	round_start_msec = 0
	round_pause_msec = -1
	hydro_submit_msec = -1
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
	mode_label.text = "%d초 · 전원 동시 도전" % int(duration)
	objective_label.text = "목표  |  " + str(game_data.get("objective", "제한시간 안에 최고 점수에 도전하세요."))
	lesson_label.text = "에너지 원리  |  " + str(game_data.get("lesson", ""))
	timer_bar.max_value = duration
	timer_bar.value = duration
	timer_label.text = "%02d초" % ceili(duration)
	feedback_label.text = "게임 방법을 확인하고 시작 버튼을 누르세요."
	submission_label.text = "내 점수는 종료 즉시 비공개로 제출됩니다."
	_refresh_score()
	_build_mode()
	_refresh_goal_progress()
	_show_guide_popup()

func _on_submission_changed(state: Dictionary) -> void:
	if not surface_enabled or not visible or int((state.get("game", {}) as Dictionary).get("round_id", -2)) != round_id:
		return
	var phase := str((state.get("game", {}) as Dictionary).get("phase", ""))
	if phase == "ready":
		var ready_count := int(state.get("ready_count", 0))
		var player_count := int(state.get("player_count", 4))
		var guide_seconds := ceili(float(state.get("guide_remaining", 0.0)))
		if practice_active:
			submission_label.text = "점수 없는 조작 연습 · %d초 뒤 전체 자동 시작" % guide_seconds
		elif is_guide_open():
			guide_badge_label.text = "게임 방법 · %d명 준비 · %d초 뒤 자동 시작" % [ready_count, guide_seconds]
		else:
			feedback_label.text = "준비 완료! 다른 플레이어를 기다리는 중…"
			submission_label.text = "준비 %d / %d명 · %d초 뒤 자동 시작" % [ready_count, player_count, guide_seconds]
		return
	if phase == "countdown":
		if practice_active:
			_finish_hydro_practice()
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
		round_start_msec = mini(round_start_msec, Time.get_ticks_msec() - roundi(elapsed * 1000.0))
	submission_label.text = "점수 제출 %d / %d명%s" % [int(state.get("submitted_count", 0)), int(state.get("player_count", 4)), "  ·  내 점수 제출 완료" if submitted else ""]

func _begin_local_round() -> void:
	if round_started_locally or not active or submitted:
		return
	# A host timeout/reconnect can start the round while a player is practicing.
	# Reset the same seed and discard every practice action before competition.
	if practice_active:
		_finish_hydro_practice(false)
	round_started_locally = true
	round_start_msec = Time.get_ticks_msec()
	round_pause_msec = -1
	objective_label.visible = false
	lesson_label.visible = false
	goal_label.visible = true
	guide_open = false
	if is_instance_valid(guide_panel):
		guide_panel.visible = false
	var content_node := card.find_child("ContentBox", false, false)
	if is_instance_valid(content_node):
		content_node.visible = true
	elapsed = 0.0
	simulation_elapsed = 0.0
	_set_arcades_running(true)
	feedback_label.text = "게임 시작! 조건을 보고 알맞게 선택해요."

func _on_minigame_finished(results: Array) -> void:
	if not visible:
		return
	if finishing_animation:
		pending_results = results.duplicate(true)
		return
	# A delayed browser can receive the host's final results before its own
	# score callback. Finish the already-started entrance even in that order.
	if is_instance_valid(commute_arcade) and bool(commute_arcade.call("has_pending_finish_animation")):
		if learning_snapshot.is_empty():
			learning_snapshot = _learning_metrics_snapshot()
		for entry_variant in results:
			var entry: Dictionary = entry_variant
			if int(entry.get("player_idx", -1)) == _local_player_index():
				score = int(entry.get("score", 0))
				_refresh_score()
				break
		active = false
		submitted = true
		round_started_locally = false
		_set_arcades_running(false)
		finishing_animation = bool(commute_arcade.call("begin_finish_animation"))
		if finishing_animation:
			pending_results = results.duplicate(true)
			timer_label.text = "하차 중"
			timer_bar.value = 0
			feedback_label.text = "점수 집계 완료! 학생들이 학교에 들어가는 중이에요."
			return
	if practice_active:
		_finish_hydro_practice(false)
	if is_instance_valid(guide_panel):
		guide_panel.visible = false
	var content_node := card.find_child("ContentBox", false, false)
	if is_instance_valid(content_node):
		content_node.visible = true
	guide_open = false
	round_started_locally = false
	active = false
	submitted = true
	_set_arcades_running(false)
	if learning_snapshot.is_empty():
		learning_snapshot = _learning_metrics_snapshot()
	var learning_report: Dictionary = LEARNING_FEEDBACK.result_lines(game_id, learning_snapshot)
	for entry_variant in results:
		var entry: Dictionary = entry_variant
		if int(entry.get("player_idx", -1)) == _local_player_index():
			score = int(entry.get("score", 0))
			_refresh_score()
			break
	_build_results(results)
	objective_label.visible = false
	lesson_label.visible = true
	goal_label.visible = false
	timer_label.text = "종료"
	timer_bar.value = 0
	lesson_label.text = "내 플레이  |  " + str(learning_report.get("evidence", ""))
	feedback_label.text = "함께 확인  |  " + str(learning_report.get("next_action", ""))
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
	finishing_animation = false
	pending_results.clear()
	practice_active = false
	practice_actions.visible = false
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

func set_surface_enabled(value: bool) -> void:
	surface_enabled = value
	if not value:
		cancel_minigame()

func restore_online_round() -> void:
	if not surface_enabled:
		return
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
	if str(restored.get("phase", "")) == "ready" and not is_guide_open() and not practice_active and not GameManager.minigame_ready_players.has(local_idx):
		GameManager.start_minigame_action(local_idx, round_id)
	if GameManager.minigame_scores.has(local_idx):
		submitted = true
		active = false
		_set_arcades_running(false)
	elif submitted and str(restored.get("phase", "")) == "playing":
		# A score sent just before the outage may not have reached the host.
		GameManager.submit_minigame_score(local_idx, score, _submission_stats(), round_id)
	_on_submission_changed(GameManager.get_minigame_state())

func _set_arcades_running(running_state: bool) -> void:
	if not running_state:
		MINIGAME_INPUT.release_all()
	else:
		get_viewport().gui_release_focus()
	if is_instance_valid(touch_controls):
		touch_controls.visible = running_state and DisplayServer.is_touchscreen_available()
		arena_panel.custom_minimum_size.y = 320 if touch_controls.visible else 400
	var arcades := [
		solar_arcade, wind_arcade, grid_arcade, standby_arcade,
		hydro_arcade, sort_arcade, battery_arcade, commute_arcade, heat_arcade
	]
	for arc in arcades:
		if is_instance_valid(arc):
			# The modal owns the shared simulation clock; children must not run twice.
			arc.set_process(false)
			arc.set_physics_process(false)
			arc.custom_minimum_size.y = 304 if touch_controls.visible else 384
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
	# 원리는 설명을 읽는 대신 게임 안의 물·빛·도시 반응으로 경험합니다.
	lesson_box.visible = false
	body.add_child(lesson_box)
	guide_lesson_label = Label.new()
	guide_lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_lesson_label.add_theme_font_size_override("font_size", 15)
	guide_lesson_label.add_theme_color_override("font_color", Color("dbeff0"))
	lesson_box.get_child(0).add_child(guide_lesson_label)

	var tip_box := _make_guide_section("목표와 보너스", Color("ffb86c"))
	body.add_child(tip_box)
	guide_tip_label = Label.new()
	guide_tip_label.visible = false
	guide_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_tip_label.add_theme_font_size_override("font_size", 15)
	guide_tip_label.add_theme_color_override("font_color", Color("ffeac2"))
	tip_box.get_child(0).add_child(guide_tip_label)

	guide_rewards_label = Label.new()
	guide_rewards_label.text = "목표 행동을 확인하면 순위에 따라 에너지를 받아요. 0점은 보상 없이 다시 연습해요."
	guide_rewards_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_rewards_label.add_theme_font_size_override("font_size", 15)
	guide_rewards_label.add_theme_color_override("font_color", Color("95f2d6"))
	tip_box.get_child(0).add_child(guide_rewards_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	guide_content.add_child(footer)
	guide_practice_button = Button.new()
	guide_practice_button.text = "조작 연습 (P)"
	guide_practice_button.custom_minimum_size = Vector2(190, 52)
	guide_practice_button.add_theme_font_size_override("font_size", 18)
	guide_practice_button.pressed.connect(_start_hydro_practice)
	UI.apply_secondary_button(guide_practice_button)
	footer.add_child(guide_practice_button)

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
	guide_practice_button.visible = game_id == "hydro_gate"
	guide_rewards_label.text = "%s\n목표 달성 + 양수 점수: 순위에 따라 에너지 20 / 10 / 5 / 1. 같은 점수는 공동 순위예요." % LEARNING_FEEDBACK.goal_requirement(game_id)

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
	if not guide_open or practice_active:
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

func _start_hydro_practice() -> void:
	if game_id != "hydro_gate" or not is_guide_open() or round_started_locally or not active:
		return
	practice_active = true
	practice_elapsed = 0.0
	practice_completed_at = -1.0
	simulation_elapsed = 0.0
	guide_panel.visible = false
	card.find_child("ContentBox", false, false).visible = true
	objective_label.visible = false
	lesson_label.visible = false
	goal_label.visible = true
	goal_label.text = "조작 연습  |  1. A/D로 가까운 수문 레버에 이동해요."
	practice_actions.visible = true
	timer_bar.max_value = HYDRO_PRACTICE_SECONDS
	timer_bar.value = HYDRO_PRACTICE_SECONDS
	score_label.text = "점수 없는 연습"
	feedback_label.text = "연습에서는 넘치지 않아요. 실제 게임은 새 상태로 모두 함께 시작해요."
	submission_label.text = "연습 후 시작 버튼을 누르면 준비 완료 · Esc로 안내로 돌아가기"
	hydro_arcade.call("set_practice_mode", true)
	_set_arcades_running(true)

func _finish_hydro_practice(show_guide: bool = true) -> void:
	if not practice_active:
		return
	practice_active = false
	practice_completed_at = -1.0
	practice_actions.visible = false
	_set_arcades_running(false)
	var local_idx := _local_player_index()
	var player_data: Dictionary = GameManager.players[local_idx] if local_idx >= 0 and local_idx < GameManager.players.size() else {}
	hydro_arcade.call("setup", player_data, int(game_data.get("seed", 1)))
	_set_arcades_running(false)
	simulation_elapsed = 0.0
	elapsed = 0.0
	timer_bar.max_value = duration
	timer_bar.value = duration
	timer_label.text = "%02d초" % ceili(duration)
	_refresh_score()
	_refresh_goal_progress()
	if show_guide:
		_show_guide_popup()

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
	finishing_animation = false
	pending_results.clear()
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
	if points <= 0 and not count_correct:
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
	hydro_submit_msec = Time.get_ticks_msec() + 1300

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
	if is_instance_valid(sort_arcade) and bool(sort_arcade.get("retrying_item")):
		learning_counts["sort_retries"] = int(learning_counts.get("sort_retries", 0)) + 1
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
	if count_correct:
		correct += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
	feedback_label.text = "%s%s%s" % [message, "  ·  +%d점" % points if points > 0 else "", "  ·  목표 행동 ×%d" % streak if count_correct and streak >= 2 else ""]
	feedback_label.add_theme_color_override("font_color", Color("83f2b6"))
	_track_learning_event(true, points, count_correct)
	_refresh_score()

func _register_miss(penalty: int, message: String) -> void:
	score = maxi(0, score - penalty)
	streak = 0
	feedback_label.text = message + ("  ·  -%d점" % penalty if penalty > 0 else "")
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
		if round_started_locally and not submitted and game_id != "energy_sort":
			feedback_label.text = cue + ("  +%d점" % points if success and points > 0 else "  -%d점" % points if not success and points > 0 else "")
	_refresh_goal_progress()

func _refresh_goal_progress() -> void:
	if not is_instance_valid(goal_label):
		return
	var stats := _submission_stats()
	var goal_correct := int(stats.get("correct", 0))
	var concept_attempts := int(stats.get("concept_attempts", 0))
	var accuracy := 0 if concept_attempts <= 0 else roundi(100.0 * float(goal_correct) / float(concept_attempts))
	var progress := ""
	match game_id:
		"solar_align": progress = "햇빛 받는 패널 %d/3 · 올바른 선택 %d%% / 목표 60%%" % [mini(3, goal_correct), accuracy]
		"wind_rhythm": progress = "풍향 맞춤 %d/1 · 돌풍 정지 %d/1" % [mini(1, int(learning_counts.get("wind_aligned", 0))), mini(1, int(learning_counts.get("storm_braked", 0)))]
		"grid_balance": progress = "균형 유지 %d/2 · 평균 차이 %.1f MW" % [mini(2, goal_correct), float(_learning_metrics_snapshot().get("average_gap", 0.0))]
		"standby_hunt": progress = "대기전력 차단 %d/2 · 올바른 선택 %d%% / 목표 60%%" % [mini(2, goal_correct), accuracy]
		"hydro_gate": progress = "높은 수위에서 발전 %d/1 · 닫아 물 모으기 %d/1" % [mini(1, goal_correct), mini(1, int(stats.get("hydro_managed_closures", 0)))]
		"energy_sort": progress = "첫 선택 성공 %d/2 · 올바른 분류 %d%% / 목표 60%%" % [mini(2, goal_correct), accuracy]
		"battery_relay": progress = "저장한 전기를 부족할 때 공급 %d/1" % mini(1, goal_correct)
		"eco_commute": progress = "2명 이상 함께 학교 하차 %d/1" % mini(1, goal_correct)
		"heat_leak": progress = "열린 창문 닫기 %d/2 · 올바른 선택 %d%% / 목표 60%%" % [mini(2, goal_correct), accuracy]
	var achieved := GameManager.has_minigame_goal_actions(game_id, score, stats)
	goal_label.text = ("보너스 목표 달성 ✓  |  " if achieved else "보너스 목표  |  ") + progress
	goal_label.add_theme_color_override("font_color", UI.SUCCESS if achieved else UI.GOLD)

func _learning_metrics_snapshot() -> Dictionary:
	var metrics := learning_counts.duplicate()
	metrics["correct"] = correct
	metrics["attempts"] = attempts
	if game_id == "energy_sort":
		metrics["first_sort_attempts"] = attempts - int(learning_counts.get("sort_retries", 0))
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
		metrics["hydro_closures"] = int(hydro_arcade.get("managed_closures"))
	if is_instance_valid(commute_arcade):
		metrics["delivered_total"] = int(commute_arcade.get("delivered_total"))
		metrics["passengers"] = int(commute_arcade.get("passengers"))
		metrics["trip_per_person"] = float(commute_arcade.get("last_trip_per_person"))
		metrics["trip_solo_energy"] = float(commute_arcade.get("last_trip_solo_energy"))
	if is_instance_valid(battery_arcade):
		metrics["battery_units"] = int(battery_arcade.get("battery_units"))
	if is_instance_valid(heat_arcade):
		metrics["cooling_used"] = float(heat_arcade.get("cooling_used"))
	return metrics

func _refresh_score() -> void:
	if score_label:
		score_label.text = "점수  %04d" % score

func _submit_score() -> void:
	if submitted:
		return
	if is_instance_valid(hydro_arcade) and hydro_arcade.has_method("finalize_generation_score"):
		hydro_arcade.call("finalize_generation_score")
	if is_instance_valid(grid_arcade) and grid_arcade.has_method("finalize_balance_score"):
		score = int(grid_arcade.call("finalize_balance_score"))
		_refresh_score()
	learning_snapshot = _learning_metrics_snapshot()
	submitted = true
	active = false
	_set_arcades_running(false)
	timer_label.text = "종료"
	timer_bar.value = 0
	feedback_label.text = "도전 종료! 점수를 제출했습니다."
	feedback_label.add_theme_color_override("font_color", Color("ffe083"))
	submission_label.text = "다른 플레이어의 도전이 끝나기를 기다리는 중…"
	if is_instance_valid(commute_arcade):
		finishing_animation = bool(commute_arcade.call("begin_finish_animation"))
		if finishing_animation:
			timer_label.text = "하차 중"
			feedback_label.text = "점수 집계 완료! 학생들이 학교에 들어가는 중이에요."
	GameManager.submit_minigame_score(_local_player_index(), score, _submission_stats(), round_id)

func _submission_stats() -> Dictionary:
	var goal_correct := correct
	var reported_attempts := attempts
	if is_instance_valid(grid_arcade):
		# Phase events are normally emitted after a hold or a demand change.
		# An unfinished last adjustment is still a real attempt, even at the buzzer.
		if bool(grid_arcade.get("phase_adjusted")) and not bool(grid_arcade.get("phase_scored")):
			reported_attempts += 1
		if bool(grid_arcade.get("ever_adjusted")):
			reported_attempts = maxi(1, reported_attempts)
	var concept_attempts := reported_attempts
	if game_id == "solar_align":
		concept_attempts = correct + int(learning_counts.get("solar_wrong", 0))
	elif game_id == "standby_hunt":
		concept_attempts = correct + int(learning_counts.get("active_unplugged", 0))
	elif game_id == "energy_sort":
		concept_attempts = attempts - int(learning_counts.get("sort_retries", 0))
	elif game_id == "wind_rhythm":
		goal_correct = mini(int(learning_counts.get("wind_aligned", 0)), int(learning_counts.get("storm_braked", 0)))
	if is_instance_valid(hydro_arcade) and bool(hydro_arcade.get("overflowed")):
		goal_correct = 0
	var stats := {"correct": goal_correct, "attempts": reported_attempts, "concept_attempts": concept_attempts, "best_streak": best_streak}
	if is_instance_valid(hydro_arcade):
		stats["hydro_managed_closures"] = int(hydro_arcade.get("managed_closures"))
	return stats

func _build_results(results: Array) -> void:
	_clear_arena()
	var heading := _arena_label("미니게임 순위 · 에너지 보너스", 24, Color("ffe06b"))
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
		var rank_label := _result_column("%d위" % int(result["rank"]) if int(result["rank"]) > 0 else "연습", 66, rank_color)
		columns.add_child(rank_label)
		var name_label := _result_column(str(result["name"]), 0, rank_color)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		columns.add_child(name_label)
		var score_column := _result_column("%d점" % int(result["score"]), 140, rank_color)
		score_column.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		columns.add_child(score_column)
		var reward_label := _result_column("에너지 +%d" % int(result["reward"]) if bool(result.get("goal_checked", false)) else "목표 미달 · +0", 180, rank_color)
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
	return active and round_started_locally and not practice_active and not submitted and not is_guide_open()

func _local_player_index() -> int:
	if NetworkManager and NetworkManager.is_online:
		return NetworkManager.get_local_player_index()
	return 0
