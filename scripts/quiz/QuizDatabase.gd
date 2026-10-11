extends Node

## QuizDatabase: 초등 4~6학년 에너지 소양 200선. 출제 기록은 한 판의 메모리에만 둡니다.

enum QuizType { MULTI_CHOICE }

const QUIZ_DATA_PATHS: Array[String] = [
	"res://assets/data/energy_100_quizzes.json",
	"res://assets/data/energy_extra_100_quizzes.json"
]
const EXPECTED_QUIZ_COUNT := 200

var quizzes: Array[Dictionary] = []
var learning_grade := 5
var _session_quiz_ids: Dictionary = {}

func configure_learning_grade(grade: int) -> void:
	learning_grade = clampi(grade, 4, 6)
	_session_quiz_ids.clear()

func _minimum_grade(quiz: Dictionary) -> int:
	# Reviewed metadata is authoritative; a keyword in a wrong option must not
	# silently move an otherwise everyday question to a different grade.
	if quiz.has("min_grade"):
		return clampi(int(quiz["min_grade"]), 4, 6)
	var text := str(quiz.get("category", "")) + str(quiz.get("question", "")) + " ".join(quiz.get("options", []))
	if "발전단가" in text or "산업화 이전" in text or "에너지 안보" in text or "자립도" in text or "핵분열" in text:
		return 6
	if "탄소중립" in text or "온실가스" in text or "화학 에너지" in text or "원자력" in text:
		return 5
	return 4

func reading_seconds(quiz: Dictionary) -> float:
	var characters := str(quiz.get("question", "")).length()
	for option in quiz.get("options", []):
		characters += str(option).length()
	var reading_rate := 7.0 if learning_grade == 4 else (9.0 if learning_grade == 5 else 11.0)
	return clampf(12.0 + float(characters) / reading_rate, 20.0, 40.0)


func _init() -> void:
	quizzes = _load_quizzes()


func _load_quizzes() -> Array[Dictionary]:
	var loaded_quizzes: Array[Dictionary] = []
	var loaded_ids: Dictionary = {}
	for data_path in QUIZ_DATA_PATHS:
		if not FileAccess.file_exists(data_path):
			push_error("퀴즈 데이터 파일을 찾을 수 없습니다: %s" % data_path)
			continue

		var parsed_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
		if not parsed_data is Array:
			push_error("퀴즈 데이터가 JSON 배열 형식이 아닙니다: %s" % data_path)
			continue

		for raw_quiz: Variant in parsed_data:
			if not raw_quiz is Dictionary:
				continue
			var quiz: Dictionary = raw_quiz.duplicate(true)
			quiz["type"] = QuizType.MULTI_CHOICE
			var quiz_id := str(quiz.get("id", ""))
			if loaded_ids.has(quiz_id):
				push_error("중복된 퀴즈 ID를 건너뜁니다: %s" % quiz_id)
				continue
			if _is_valid_multiple_choice_quiz(quiz):
				loaded_quizzes.append(quiz)
				loaded_ids[quiz_id] = true
			else:
				push_error("잘못된 객관식 퀴즈를 건너뜁니다: %s" % str(quiz.get("id", "알 수 없음")))

	if loaded_quizzes.size() != EXPECTED_QUIZ_COUNT:
		push_error("객관식 퀴즈는 %d개여야 하지만 %d개를 불러왔습니다." % [EXPECTED_QUIZ_COUNT, loaded_quizzes.size()])
	return loaded_quizzes


func _is_valid_multiple_choice_quiz(quiz: Dictionary) -> bool:
	var options: Variant = quiz.get("options", [])
	if not options is Array or options.size() != 4:
		return false
	var unique_options: Dictionary = {}
	for option in options:
		if not option is String or str(option).strip_edges().is_empty():
			return false
		unique_options[str(option).strip_edges()] = true
	return (
		not str(quiz.get("id", "")).is_empty()
		and not str(quiz.get("question", "")).is_empty()
		and unique_options.size() == 4
		and quiz.get("answer", "") in options
	)


func get_random_quiz() -> Dictionary:
	if quizzes.is_empty():
		return _get_fallback_quiz()
	var pool: Array[Dictionary] = []
	for quiz in quizzes:
		if _minimum_grade(quiz) <= learning_grade:
			pool.append(quiz)
	if pool.is_empty():
		return _get_fallback_quiz()
	var available: Array[Dictionary] = []
	for quiz in pool:
		if not _session_quiz_ids.has(str(quiz["id"])):
			available.append(quiz)
	if available.is_empty():
		_session_quiz_ids.clear()
		available = pool
	var selected := available[randi() % available.size()].duplicate(true)
	_session_quiz_ids[str(selected["id"])] = true
	var options: Array = selected["options"]
	options.shuffle()
	selected["time_limit"] = reading_seconds(selected)
	selected["ai_think_seconds"] = clampf(float(selected["time_limit"]) * randf_range(0.35, 0.55), 5.0, 15.0)
	return selected


func get_quiz_by_type(_type: QuizType = QuizType.MULTI_CHOICE) -> Dictionary:
	return get_random_quiz()


func _get_fallback_quiz() -> Dictionary:
	return {
		"id": "fallback_quiz",
		"type": QuizType.MULTI_CHOICE,
		"category": "에너지 상식",
		"question": "에너지 문제를 불러오지 못했습니다. 에너지를 아끼는 행동은 무엇일까요?",
		"options": ["사용하지 않는 전등 끄기", "냉장고 문 열어두기", "빈방 난방하기", "물을 계속 틀어두기"],
		"answer": "사용하지 않는 전등 끄기",
		"explanation": "사용하지 않는 전등을 끄면 전기 에너지를 아낄 수 있습니다.",
		"reward_energy": 2,
		"min_grade": 4, "difficulty": 1, "learning_objective": "사용하지 않는 전등을 꺼 전기를 아낀다."
	}
