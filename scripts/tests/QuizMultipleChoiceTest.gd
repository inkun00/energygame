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
