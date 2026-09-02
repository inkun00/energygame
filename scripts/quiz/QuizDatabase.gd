extends Node

## QuizDatabase: 초등 4학년 에너지 소양 200선 객관식 데이터베이스

enum QuizType { MULTI_CHOICE }

const QUIZ_DATA_PATHS: Array[String] = [
	"res://assets/data/energy_100_quizzes.json",
	"res://assets/data/energy_extra_100_quizzes.json"
]
const EXPECTED_QUIZ_COUNT := 200

var quizzes: Array[Dictionary] = []


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
	return (
		not str(quiz.get("id", "")).is_empty()
		and not str(quiz.get("question", "")).is_empty()
		and options is Array
		and options.size() == 4
		and quiz.get("answer", "") in options
	)


func get_random_quiz() -> Dictionary:
	if quizzes.is_empty():
		return _get_fallback_quiz()
	return quizzes[randi() % quizzes.size()].duplicate(true)


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
		"reward_energy": 2
	}
