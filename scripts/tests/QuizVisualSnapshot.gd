extends SceneTree

## 가장 긴 보기가 포함된 객관식 화면의 레이아웃을 확인하는 스냅샷 테스트입니다.

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp", "char_color": Color("#49d97b")},
		{"name": "태양 여우 솔", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/solar_fox_sol.webp", "char_color": Color("#ffd24a")},
		{"name": "물방울 정령 포포", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/water_popo.webp", "char_color": Color("#49bfff")},
		{"name": "번개새 피카", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/lightning_bird_pika.webp", "char_color": Color("#ff9d3d")},
	]
	main._on_start_game_requested(configs)
	await create_timer(0.5).timeout
	var quiz_modal = main.get_node("GameBoard/Modals/QuizModal")
	var quiz_database: Node = root.get_node("QuizDatabase")
	quiz_modal.display_quiz(0, quiz_database.quizzes[99])
	await create_timer(0.35).timeout

	assert(quiz_modal.choice_container.get_child_count() == 4)
	for child in quiz_modal.choice_container.get_children():
		assert(child is Button and not child.disabled)

	if not _save_frame("res://.godot/quiz_preview.png"):
		quit(1)
		return

	quiz_modal._on_choice_pressed(str(quiz_database.quizzes[99]["answer"]))
	await process_frame
	if not _save_frame("res://.godot/quiz_result_preview.png"):
		quit(1)
		return
	print("[PASS] Quiz visual previews captured")
	quit(0)


func _save_frame(path: String) -> bool:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("퀴즈 시각 미리보기 저장 실패: %s" % error)
		return false
	return true
