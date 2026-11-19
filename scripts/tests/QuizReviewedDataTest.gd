extends SceneTree

## Structural regression, not proof of scientific or classroom effectiveness.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var database: Node = root.get_node("QuizDatabase")
	_check(database.quizzes.size() == 200, "All 200 reviewed questions must load")
	var grades := {4: 0, 5: 0, 6: 0}
	var diagrams := {4: 0, 5: 0, 6: 0}
	var longest_points := 0.0
	var shortest_points := 0.0
	for quiz in database.quizzes:
		var id := str(quiz.get("id", ""))
		var grade := int(quiz.get("min_grade", 0))
		_check(grade in [4, 5, 6], id + ": explicit minimum grade is required")
		_check(int(quiz.get("difficulty", 0)) in [1, 2, 3], id + ": difficulty must be 1..3")
		_check(str(quiz.get("learning_objective", "")).strip_edges().length() >= 5, id + ": learning objective is required")
		_check(not str(quiz.get("explanation", "")).strip_edges().is_empty(), id + ": explanation is required")
		_check(database._is_valid_multiple_choice_quiz(quiz), id + ": four distinct, non-empty options and one matching answer are required")
		if grades.has(grade):
			grades[grade] += 1
		var lengths := []
		for option in quiz["options"]: lengths.append(str(option).replace(" ", "").length())
		var answer_length := str(quiz["answer"]).replace(" ", "").length()
		if answer_length == lengths.max(): longest_points += 1.0 / lengths.count(answer_length)
		if answer_length == lengths.min(): shortest_points += 1.0 / lengths.count(answer_length)
		if quiz.has("diagram"):
			diagrams[grade] += 1
			var diagram: Dictionary = quiz["diagram"]
			_check(diagram["labels"].size() >= 2, id + ": readable diagram labels")
			if diagram.has("values"):
				_check(diagram["values"].size() == diagram["labels"].size() and not str(diagram.get("unit", "")).is_empty(), id + ": every bar has a value and common unit")
			for option in quiz["options"]:
				if option != quiz["answer"]:
					_check(not str(quiz.get("choice_feedback", {}).get(option, "")).is_empty(), id + ": each wrong diagram interpretation gets its own feedback")
	for grade in grades: _check(diagrams[grade] >= 5, "Each grade includes at least five diagram questions")
	_check(longest_points / 200.0 <= 0.30 and shortest_points / 200.0 <= 0.30, "Neither the longest nor shortest printed option predicts the answer above 30%, counting ties fractionally")
	_check(grades[4] >= 40, "Grade 4 needs at least 40 eligible questions")
	_check(grades[5] > 0 and grades[6] > 0, "Higher-grade questions must remain available")
	_check(database._minimum_grade({"min_grade": 4, "question": "생활 속 절전", "options": ["온실가스"]}) == 4, "Reviewed grade must override distractor keywords")
	_check(not database._is_valid_multiple_choice_quiz({"id": "bad", "question": "?", "options": ["a", "a", "b", "c"], "answer": "a"}), "Duplicate choices must be rejected")
	for grade in [4, 5, 6]:
		database.configure_learning_grade(grade)
		var eligible := 0
		for quiz in database.quizzes:
			if database._minimum_grade(quiz) <= grade:
				eligible += 1
		var seen: Dictionary = {}
		for draw in range(eligible):
			var selected: Dictionary = database.get_random_quiz()
			_check(not seen.has(selected["id"]), "No repeated question before the grade pool is exhausted")
			seen[selected["id"]] = true
			_check(database._minimum_grade(selected) <= grade, "Grade filter must use reviewed metadata")
			_check(selected["answer"] in selected["options"], "Shuffling must preserve the correct answer")
			_check(float(selected["time_limit"]) >= 20.0 and float(selected["time_limit"]) <= 40.0, "Age-adjusted reading time must remain 20..40 seconds")
		_check(seen.size() == eligible, "Every eligible question must be reachable")
		database.get_random_quiz()
		_check(database._session_quiz_ids.size() == 1, "Exhaustion starts a fresh in-memory pool")
	database.configure_learning_grade(5)
	for grade in [4, 5, 6]:
		database.configure_learning_grade(grade)
		database.configure_challenge(true)
		var advanced: Dictionary = database.get_random_quiz()
		_check(int(advanced["min_grade"]) == grade and (advanced.has("diagram") or int(advanced["difficulty"]) >= 3), "Challenge starts with on-grade reasoning")
	database.configure_challenge(false)
	database.configure_learning_grade(5)
	print("Reviewed quiz grade distribution: ", grades)
	print("Diagram counts ", diagrams, ", longest/shortest heuristic accuracy ", longest_points / 2.0, "% / ", shortest_points / 2.0, "%")
	if failures.is_empty():
		print("[PASS] QuizReviewedData · 200 metadata, distinct options, grade pools, reading time, no repeats")
	quit(0 if failures.is_empty() else 1)
