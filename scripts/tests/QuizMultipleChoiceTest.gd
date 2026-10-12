extends SceneTree

## 에너지 200문항과 객관식 전용 UI를 독립적으로 검증합니다.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var quiz_database: Node = root.get_node("QuizDatabase")
	_expect(quiz_database.quizzes.size() == 200, "에너지 퀴즈가 정확히 200개여야 합니다.")
	var quiz_ids := {}
	for quiz in quiz_database.quizzes:
		var options: Array = quiz.get("options", [])
		quiz_ids[quiz.get("id", "")] = true
		_expect(quiz.get("type", -1) == 0, "%s의 유형이 객관식이 아닙니다." % quiz.get("id", "알 수 없음"))
		_expect(options.size() == 4, "%s의 보기가 4개가 아닙니다." % quiz.get("id", "알 수 없음"))
		_expect(quiz.get("answer", "") in options, "%s의 정답이 보기 안에 없습니다." % quiz.get("id", "알 수 없음"))
	_expect(quiz_ids.size() == 200, "퀴즈 ID 200개가 모두 고유해야 합니다.")

	var quiz_modal = load("res://scenes/QuizModal.tscn").instantiate()
	root.add_child(quiz_modal)
	await process_frame
	for quiz in quiz_database.quizzes:
		quiz_modal.display_quiz(0, quiz)
		await process_frame
		_expect(quiz_modal.choice_container.get_child_count() == 4, "%s가 보기 버튼 4개를 표시하지 않습니다." % quiz.get("id", "알 수 없음"))
		for child in quiz_modal.choice_container.get_children():
			_expect(child is Button, "객관식 보기에는 버튼만 있어야 합니다.")
			if child is Button:
				_expect(not child.disabled, "로컬 플레이어의 보기 버튼은 활성화되어야 합니다.")
		quiz_modal.cancel_quiz()

	# Correct answers are submitted immediately; the explanation is a separate
	# local reading overlay with a next button, never a second answer callback.
	var gm = root.get_node("GameManager")
	var configs: Array[Dictionary] = [{"name": "나", "is_ai": false}, {"name": "친구", "is_ai": false}]
	gm.setup_game(configs)
	gm.set_process(false)
	var data := {"question": "빈방의 전등은 어떻게 할까요?", "type": 0, "options": ["끈다", "계속 켠다", "더 켠다", "새 전등을 켠다"], "answer": "끈다", "explanation": "아무도 쓰지 않는 방의 전등을 끄면 전기 사용량을 줄일 수 있어요.", "reward_energy": 2, "time_limit": 20.0}
	gm.current_state = gm.TurnState.RESOLVING_QUIZ
	gm.active_quiz_player_idx = 0
	gm.active_quiz_data = data.duplicate(true)
	gm.active_quiz_time_remaining = 21.0
	quiz_modal.display_quiz(0, data)
	var energy_before: int = gm.players[0]["energy"]
	var completions := []
	quiz_modal.quiz_completed.connect(func(correct: bool): completions.append(correct))
	quiz_modal._on_choice_pressed("끈다")
	_expect(gm.players[0]["energy"] == energy_before + 2 and completions.size() == 1, "Choosing an answer should submit immediately exactly once")
	_expect(quiz_modal.result_visible and quiz_modal.next_button.visible and not quiz_modal.choice_container.visible, "Readable result and next button should replace the choices")
	_expect(quiz_modal.explanation_label.text.contains("에너지 +2") and quiz_modal.explanation_label.text.contains("동점 비교용 퀴즈 점수 +10"), "Energy and tie-break score must be labelled separately")
	_expect(quiz_modal.result_seconds_remaining >= 7.0 and quiz_modal.result_seconds_remaining <= 12.0, "Result must allow 7–12 seconds to read")
	await process_frame
	var reading_before_pause: float = quiz_modal.result_seconds_remaining
	paused = true
	await create_timer(0.2, true).timeout
	_expect(is_equal_approx(quiz_modal.result_seconds_remaining, reading_before_pause), "Network recovery pause must not consume local explanation reading time")
	paused = false
	await process_frame
	_expect(reading_before_pause - quiz_modal.result_seconds_remaining < 0.08 and quiz_modal.visible, "Restoring from pause must preserve the shared reading time instead of applying paused wall time")
	quiz_modal.next_button.pressed.emit()
	quiz_modal._process(30.0)
	_expect(not quiz_modal.visible and not quiz_modal.result_visible and completions.size() == 1 and gm.players[0]["energy"] == energy_before + 2, "Local next/timeout must neither block nor submit a second answer")
	_expect(quiz_modal.result_reading_seconds({"answer": "짧은 답", "explanation": "짧은 해설"}, 4) == 7.0, "Short explanations still need at least seven seconds")
	_expect(quiz_modal.result_reading_seconds({"answer": "답", "explanation": "가".repeat(200)}, 4) == 12.0, "Long explanations need the bounded twelve-second reading time")
	# A host timeout can arrive before a low-frame-rate client's local timer.
	gm.current_state = gm.TurnState.RESOLVING_QUIZ
	gm.active_quiz_player_idx = 0
	gm.active_quiz_data = data.duplicate(true)
	quiz_modal.display_quiz(0, data)
	gm.last_quiz_choice = ""
	gm.quiz_resolved.emit(0, false)
	_expect(not quiz_modal.is_active and quiz_modal.result_visible and quiz_modal.explanation_label.text.contains("시간 초과"), "Authoritative timeout must stop local answer input and show its explanation")
	_expect(completions.size() == 1, "Authoritative timeout display must not submit a second answer")
	quiz_modal.cancel_quiz()
	gm.stop_game()
	# Let the already-scheduled shared review callback expire harmlessly after
	# stop_game, instead of leaving its SceneTreeTimer alive at test shutdown.
	await create_timer(quiz_modal.result_duration_seconds + 0.1).timeout

	quiz_modal.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] 200 multiple-choice quizzes validated")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
