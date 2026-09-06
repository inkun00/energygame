extends Control
class_name QuizUIController

## QuizUIController: 모든 퀴즈를 4지선다 버튼 방식으로 표시합니다.

signal quiz_completed(is_correct)

const PLAYER_QUIZ_SECONDS := 19.5
const SPECTATOR_CLUE_SECONDS := 0.65
const SPECTATOR_COMPARE_SECONDS := 1.365
const SPECTATOR_CHOOSE_SECONDS := 2.015
const SPECTATOR_FAILSAFE_GRACE_SECONDS := 1.5
const PLAYER_RESULT_SECONDS := 2.86
const SPECTATOR_RESULT_SECONDS := 1.17
const OPTION_LINE_CHAR_LIMIT := 46
const OPTION_MARKS := ["①", "②", "③", "④"]
const UI = preload("res://scripts/ui/CommercialUI.gd")

var current_quiz: Dictionary = {}
var target_player_idx: int = 0
var timer_seconds: float = PLAYER_QUIZ_SECONDS
var is_active: bool = false
var spectator_mode: bool = false
var spectator_elapsed: float = 0.0
var spectator_stage: int = -1
var spectator_failsafe_requested := false
var spectator_guess_submitted := false
var spectator_guess_correct := false
var spectator_bonus_score := 0
var quiz_display_token: int = 0
var submitted_choice := ""

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleLabel
@onready var category_badge: Label = $Panel/CategoryBadge
@onready var question_label: Label = $Panel/QuestionLabel
@onready var hint_label: Label = $Panel/HintLabel
@onready var timer_label: Label = $Panel/TimerLabel
@onready var choice_container: VBoxContainer = $Panel/ChoiceContainer
@onready var explanation_label: Label = $Panel/ExplanationLabel
var timer_bar: ProgressBar


func _local_player_index() -> int:
	if NetworkManager and NetworkManager.is_online:
		return NetworkManager.get_local_player_index()
	return 0


func _ready() -> void:
	_apply_commercial_ui()
	visible = false
	if GameManager and not GameManager.quiz_resolved.is_connected(_on_game_quiz_resolved):
		GameManager.quiz_resolved.connect(_on_game_quiz_resolved)
	GameManager.open_market_state_changed.connect(func(state: Dictionary):
		if bool(state.get("active", false)):
			cancel_quiz())
	GameManager.village_construction_started.connect(func(_inventories: Array): cancel_quiz())
	GameManager.game_over.connect(func(_rankings: Array): cancel_quiz())


func _exploration_has_ended() -> bool:
	return GameManager.open_market_active or GameManager.village_construction_active or GameManager.current_state == GameManager.TurnState.GAME_OVER


func _process(delta: float) -> void:
	# Also handle a network state snapshot arriving before its transition event.
	if visible and _exploration_has_ended():
		cancel_quiz()
		return
	if spectator_mode and visible:
		spectator_elapsed += delta
		_update_spectator_progress()
		var expected_duration := _get_ai_think_seconds()
		if not spectator_failsafe_requested and spectator_elapsed >= expected_duration + SPECTATOR_FAILSAFE_GRACE_SECONDS:
			spectator_failsafe_requested = true
			if GameManager and GameManager.has_method("resolve_ai_quiz_if_pending"):
				GameManager.resolve_ai_quiz_if_pending(target_player_idx)
	elif is_active:
		timer_seconds -= delta
		if timer_bar:
			timer_bar.value = maxf(timer_seconds, 0.0)
		if timer_label:
			timer_label.text = "남은 시간  %d초" % max(0, int(ceil(timer_seconds)))
			timer_label.add_theme_color_override("font_color", UI.DANGER if timer_seconds <= 5.0 else UI.GOLD)
		if timer_seconds <= 0:
			_on_time_out()


func display_quiz(player_idx: int, quiz_data: Dictionary) -> void:
	# A late quiz event must not cover the market or construction screen again.
	if _exploration_has_ended():
		cancel_quiz()
		return
	quiz_display_token += 1
	# 결과 처리 중 원본 데이터가 비워져도 화면 문구가 유지되도록 깊은 복사를 사용합니다.
	current_quiz = quiz_data.duplicate(true)
	if current_quiz.is_empty():
		current_quiz = QuizDatabase.get_random_quiz().duplicate(true)
	target_player_idx = player_idx
	timer_seconds = PLAYER_QUIZ_SECONDS
	spectator_elapsed = 0.0
	spectator_stage = -1
	spectator_failsafe_requested = false
	spectator_guess_submitted = false
	spectator_guess_correct = false
	spectator_bonus_score = 0
	submitted_choice = ""
	var player_is_ai := false
	var player_name := "플레이어 %d" % (player_idx + 1)
	if GameManager and player_idx >= 0 and player_idx < GameManager.players.size():
		player_is_ai = GameManager.players[player_idx].get("is_ai", false)
		player_name = GameManager.players[player_idx].get("name", player_name)
	spectator_mode = player_idx != _local_player_index() or player_is_ai
	is_active = not spectator_mode

	title_label.text = ("%s님의 문제 풀이" % player_name) if spectator_mode else "에코 에너지 퀴즈"
	category_badge.text = "  %s  " % str(current_quiz.get("category", "에너지 상식"))
	question_label.text = str(current_quiz.get("question", "문제를 불러오지 못했습니다. 다시 시도해 주세요."))
	if question_label.text.strip_edges().is_empty():
		question_label.text = "문제를 불러오지 못했습니다. 다시 시도해 주세요."
	hint_label.text = ("먼저 정답을 맞히면 내 턴 점수의 절반인 %d점을 얻습니다. 한 번만 선택할 수 있어요!" % GameManager.SPECTATOR_QUIZ_BONUS_SCORE) if _can_submit_spectator_guess() else "정답이라고 생각하는 보기를 하나 선택하세요."
	explanation_label.text = ("👀 %s님이 문제를 읽고 있습니다..." % player_name) if spectator_mode else ""
	explanation_label.remove_theme_color_override("font_color")
	timer_label.text = "AI 답변까지 약 %d초" % ceili(_get_ai_think_seconds()) if spectator_mode else "남은 시간  %d초" % int(PLAYER_QUIZ_SECONDS)
	timer_label.visible = true
	if timer_bar:
		timer_bar.max_value = _get_ai_think_seconds() if spectator_mode else PLAYER_QUIZ_SECONDS
		timer_bar.value = timer_bar.max_value
		timer_bar.visible = true

	_build_choice_buttons(spectator_mode and not _can_submit_spectator_guess())
	# 모든 콘텐츠를 구성한 다음 팝업을 노출해 빈 화면이 한 프레임 보이지 않게 합니다.
	visible = true
	panel.modulate = Color(1, 1, 1, 0)
	panel.scale = Vector2(0.96, 0.96)
	panel.pivot_offset = panel.size * 0.5
	var popup_tween := create_tween().set_parallel(true)
	popup_tween.tween_property(panel, "modulate", Color.WHITE, 0.18)
	popup_tween.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	call_deferred("_restore_missing_text", quiz_display_token, player_name)
	_update_spectator_progress()


func _build_choice_buttons(disabled: bool) -> void:
	for child in choice_container.get_children():
		child.queue_free()

	var options: Array = current_quiz.get("options", [])
	if options.size() != 4:
		options = ["사용하지 않는 전등 끄기", "냉장고 문 열어두기", "빈방 난방하기", "물을 계속 틀어두기"]
		current_quiz["answer"] = options[0]

	var choice_accents: Array[Color] = [Color("54e2c0"), Color("67b7ff"), Color("b691ff"), Color("ffb86b")]
	for option_index in range(options.size()):
		var option_value := str(options[option_index])
		var display_text := _format_option_text(option_value, option_index)
		var button := Button.new()
		button.text = display_text
		button.set_meta("answer_value", option_value)
		button.custom_minimum_size = Vector2(0, 50 + display_text.count("\n") * 20)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_constant_override("outline_size", 2)
		button.disabled = disabled
		UI.apply_secondary_button(button, choice_accents[option_index])
		button.pressed.connect(_on_choice_pressed.bind(option_value))
		choice_container.add_child(button)


func _format_option_text(option: String, option_index: int) -> String:
	var words := option.split(" ", false)
	var lines: Array[String] = []
	var current_line := ""
	for word in words:
		var candidate := str(word) if current_line.is_empty() else "%s %s" % [current_line, word]
		if candidate.length() <= OPTION_LINE_CHAR_LIMIT or current_line.is_empty():
			current_line = candidate
		else:
			lines.append(current_line)
			current_line = str(word)
	if not current_line.is_empty():
		lines.append(current_line)
	if lines.is_empty():
		lines.append(option)

	var body := ""
	for line_index in range(lines.size()):
		if line_index > 0:
			body += "\n   "
		body += lines[line_index]
	var mark: String = OPTION_MARKS[option_index] if option_index < OPTION_MARKS.size() else "•"
	return "%s %s" % [mark, body]


func _restore_missing_text(display_token: int, player_name: String) -> void:
	if display_token != quiz_display_token or not visible:
		return
	if title_label.text.strip_edges().is_empty():
		title_label.text = ("%s님의 문제 풀이" % player_name) if spectator_mode else "에코 에너지 퀴즈"
	if category_badge.text.strip_edges().is_empty():
		category_badge.text = "  에너지 상식  "
	if question_label.text.strip_edges().is_empty():
		question_label.text = "문제를 불러오지 못했습니다. 다시 시도해 주세요."


func cancel_quiz() -> void:
	quiz_display_token += 1
	is_active = false
	spectator_mode = false
	spectator_failsafe_requested = false
	spectator_guess_submitted = false
	spectator_guess_correct = false
	spectator_bonus_score = 0
	current_quiz.clear()
	visible = false


func _update_spectator_progress() -> void:
	if not spectator_mode:
		return
	var expected_duration := _get_ai_think_seconds()
	var remaining := maxf(0.0, expected_duration - spectator_elapsed)
	if timer_label:
		timer_label.text = "AI 답변까지 약 %d초" % ceili(remaining)
	if timer_bar:
		timer_bar.max_value = expected_duration
		timer_bar.value = remaining
	if spectator_guess_submitted:
		return
	var next_stage := 0
	if spectator_elapsed >= SPECTATOR_CHOOSE_SECONDS:
		next_stage = 3
	elif spectator_elapsed >= SPECTATOR_COMPARE_SECONDS:
		next_stage = 2
	elif spectator_elapsed >= SPECTATOR_CLUE_SECONDS:
		next_stage = 1
	if next_stage == spectator_stage:
		if spectator_stage == 3:
			explanation_label.text = "✅ 가장 가능성 높은 답을 검토하는 중...  (%d초 남음)" % ceili(remaining)
		return
	spectator_stage = next_stage
	var player_name: String = str(GameManager.players[target_player_idx].get("name", "다른 플레이어")) if GameManager and target_player_idx < GameManager.players.size() else "다른 플레이어"
	match spectator_stage:
		0:
			explanation_label.text = "👀 %s님이 문제를 차근차근 읽고 있습니다..." % player_name
		1:
			explanation_label.text = "🔎 질문의 핵심 단서를 찾는 중..."
		2:
			explanation_label.text = "🧩 발견한 단서와 보기를 비교하는 중..."
		3:
			explanation_label.text = "✅ 가장 가능성 높은 답을 검토하는 중...  (%d초 남음)" % ceili(remaining)

func _get_ai_think_seconds() -> float:
	if GameManager:
		return float(GameManager.AI_QUIZ_THINK_SECONDS)
	return 8.9


func _on_game_quiz_resolved(player_idx: int, is_correct: bool) -> void:
	if not spectator_mode or not visible or player_idx != target_player_idx:
		return
	var selected_answer := _get_observed_answer(is_correct)
	_reveal_selected_answer(selected_answer)
	var player_name: String = str(GameManager.players[player_idx].get("name", "다른 플레이어")) if GameManager and player_idx < GameManager.players.size() else "다른 플레이어"
	var result_lines: Array[String] = []
	if spectator_guess_submitted:
		result_lines.append(("⚡ 내 선행 도전: 정답 (+%d점)" % spectator_bonus_score) if spectator_guess_correct else "💭 내 선행 도전: 오답 (+0점)")
	result_lines.append("👉 %s님의 선택: %s" % [player_name, selected_answer])
	_show_result(is_correct, "\n".join(result_lines), false)


func _get_observed_answer(is_correct: bool) -> String:
	var correct_answer := str(current_quiz.get("answer", ""))
	if is_correct:
		return correct_answer
	for option in current_quiz.get("options", []):
		if str(option) != correct_answer:
			return str(option)
	return "선택한 보기"


func _reveal_selected_answer(selected_answer: String) -> void:
	for child in choice_container.get_children():
		if child is Button:
			child.disabled = true
			var answer_value := str(child.get_meta("answer_value", ""))
			child.set_meta("was_selected", answer_value == selected_answer)
			if answer_value == selected_answer:
				child.add_theme_stylebox_override("disabled", UI.button_style(Color("4b4020"), UI.GOLD, 10, 14.0, 8.0))
				child.add_theme_color_override("font_disabled_color", Color("fff5cf"))
			else:
				child.add_theme_stylebox_override("disabled", UI.button_style(Color("172a32"), Color("304c55"), 10, 14.0, 8.0))
				child.add_theme_color_override("font_disabled_color", Color("71868b"))


func _on_choice_pressed(choice: String) -> void:
	if spectator_mode:
		_on_spectator_choice_pressed(choice)
		return
	if not is_active:
		return
	submitted_choice = choice
	_reveal_selected_answer(choice)
	var correct_answer := str(current_quiz.get("answer", ""))
	_show_result(choice == correct_answer)


func _can_submit_spectator_guess() -> bool:
	var local_idx := _local_player_index()
	return spectator_mode \
		and not spectator_guess_submitted \
		and GameManager != null \
		and local_idx >= 0 \
		and target_player_idx != local_idx \
		and GameManager.players.size() > 0 \
		and local_idx < GameManager.players.size() \
		and not bool(GameManager.players[local_idx].get("is_ai", false)) \
		and GameManager.current_state == GameManager.TurnState.RESOLVING_QUIZ \
		and GameManager.active_quiz_player_idx == target_player_idx


func _on_spectator_choice_pressed(choice: String) -> void:
	if not _can_submit_spectator_guess():
		return
	var result: Dictionary
	if NetworkManager.is_online:
		NetworkManager.request_spectator_guess(target_player_idx, choice)
		result = {
			"accepted": true,
			"is_correct": choice == str(current_quiz.get("answer", "")),
			"bonus_score": GameManager.SPECTATOR_QUIZ_BONUS_SCORE if choice == str(current_quiz.get("answer", "")) else 0
		}
	else:
		result = GameManager.submit_spectator_quiz_guess(_local_player_index(), target_player_idx, choice)
		if not bool(result.get("accepted", false)):
			return
	spectator_guess_submitted = true
	spectator_guess_correct = bool(result.get("is_correct", false))
	spectator_bonus_score = int(result.get("bonus_score", 0))
	_reveal_selected_answer(choice)
	var player_name: String = str(GameManager.players[target_player_idx].get("name", "다른 플레이어")) if target_player_idx < GameManager.players.size() else "다른 플레이어"
	if spectator_guess_correct:
		explanation_label.text = "⚡ 선행 정답 성공! 보너스 +%d점\n이제 %s님의 답을 지켜보세요." % [spectator_bonus_score, player_name]
		explanation_label.add_theme_color_override("font_color", UI.SUCCESS)
	else:
		explanation_label.text = "💭 선행 답안은 오답입니다. 보너스 점수는 없어요.\n이제 %s님의 답을 지켜보세요." % player_name
		explanation_label.add_theme_color_override("font_color", UI.DANGER)
	hint_label.text = "보너스 도전 완료 · 대상 플레이어의 답변을 기다리는 중"


func _on_time_out() -> void:
	if not is_active:
		return
	submitted_choice = ""
	_show_result(false, "⏰ 시간 초과!")


func _show_result(is_correct: bool, prefix: String = "", should_submit_result: bool = true) -> void:
	is_active = false
	spectator_mode = false
	for child in choice_container.get_children():
		if child is Button:
			child.disabled = true
	var explanation := str(current_quiz.get("explanation", ""))
	var prefix_line := (prefix + "\n") if not prefix.is_empty() else ""
	if is_correct:
		var reward_energy: int = current_quiz.get("reward_energy", 2)
		explanation_label.text = "%s🎉 정답입니다! (+%d 에너지)\n%s" % [prefix_line, reward_energy, explanation]
		explanation_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		var answer := str(current_quiz.get("answer", ""))
		explanation_label.text = "%s❌ 오답입니다! (정답: %s)\n%s" % [prefix_line, answer, explanation]
		explanation_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
	var correct_answer := str(current_quiz.get("answer", ""))
	for child in choice_container.get_children():
		if child is Button:
			var answer_value := str(child.get_meta("answer_value", ""))
			if answer_value == correct_answer:
				child.add_theme_stylebox_override("disabled", UI.button_style(Color("173b2d"), UI.SUCCESS, 10, 14.0, 8.0))
				child.add_theme_color_override("font_disabled_color", Color("ddffe8"))
			elif bool(child.get_meta("was_selected", false)):
				child.add_theme_stylebox_override("disabled", UI.button_style(Color("47272c"), UI.DANGER, 10, 14.0, 8.0))
				child.add_theme_color_override("font_disabled_color", Color("ffe0e0"))
	if timer_bar:
		timer_bar.visible = false
	if timer_label:
		timer_label.visible = false

	var result_token := quiz_display_token
	var result_delay := PLAYER_RESULT_SECONDS if should_submit_result else SPECTATOR_RESULT_SECONDS
	get_tree().create_timer(result_delay).timeout.connect(func():
		if result_token != quiz_display_token or _exploration_has_ended():
			return
		visible = false
		if should_submit_result:
			quiz_completed.emit(is_correct)
			if NetworkManager.is_online:
				NetworkManager.request_quiz_answer(target_player_idx, submitted_choice)
			elif GameManager:
				GameManager.on_network_quiz_resolved(target_player_idx, is_correct)
	)

func _apply_commercial_ui() -> void:
	var dimmer := get_node_or_null("Dimmer") as ColorRect
	if dimmer:
		dimmer.color = Color(0.005, 0.02, 0.03, 0.84)
	if panel:
		panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("102d39"), Color("4b8ca0"), 20.0, 18))
	if title_label:
		title_label.add_theme_color_override("font_color", UI.GOLD)
	if category_badge:
		category_badge.add_theme_color_override("font_color", UI.TEAL)
	if question_label:
		question_label.add_theme_color_override("font_color", UI.TEXT)
	if hint_label:
		hint_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
	if timer_label:
		timer_label.add_theme_color_override("font_color", UI.GOLD)
	timer_bar = ProgressBar.new()
	timer_bar.name = "TimerBar"
	timer_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	timer_bar.offset_left = 48.0
	timer_bar.offset_top = -16.0
	timer_bar.offset_right = -48.0
	timer_bar.offset_bottom = -8.0
	timer_bar.show_percentage = false
	timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_bar.add_theme_stylebox_override("background", UI.progress_background())
	timer_bar.add_theme_stylebox_override("fill", UI.progress_fill(UI.GOLD))
	panel.add_child(timer_bar)
