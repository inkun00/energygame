extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var gm = root.get_node("GameManager")
	var quiz = main.find_child("QuizModal", true, false)
	var hud = main.find_child("HUD", true, false)
	var completions := []
	quiz.quiz_completed.connect(func(correct: bool): completions.append(correct))
	var configs: Array[Dictionary] = [{"name": "나", "is_ai": false}, {"name": "친구", "is_ai": false}, {"name": "동료", "is_ai": false}, {"name": "탐험가", "is_ai": false}]
	var data := {"question": "전기가 잘 흐르는 물질은?", "type": "MULTIPLE", "options": ["나무", "구리", "고무", "플라스틱"], "answer": "구리", "reward_energy": 2}
	for scenario in ["own", "spectator", "pending_result"]:
		completions.clear()
		main._on_start_game_requested(configs, 600)
		gm.confirm_adventure_ready(0)
		await create_timer(0.15).timeout
		gm.set_process(false)
		gm.players[0]["inventory"]["solar_panel"] = 2
		var target := 1 if scenario == "spectator" else 0
		gm.current_turn_idx = target
		gm.current_state = gm.TurnState.RESOLVING_QUIZ
		gm.active_quiz_player_idx = target
		gm.active_quiz_data = data.duplicate(true)
		gm.active_quiz_time_remaining = 20.5
		quiz.display_quiz(target, data)
		check(quiz.visible, scenario + ": quiz should be visible before transition")
		if scenario == "spectator":
			quiz.spectator_guess_submitted = true
		if scenario == "pending_result":
			quiz.submitted_choice = "구리"
			var before_energy: int = gm.players[0]["energy"]
			quiz._show_result(true)
			check(completions.size() == 1 and gm.players[0]["energy"] == before_energy + 2, "Answer is submitted exactly once before local explanation reading")
			check(quiz.result_visible and quiz.next_button.visible, "Resolved answer should offer a readable explanation and local next button")
		gm._start_open_market_phase()
		check(hud.open_market_panel.visible, scenario + ": market should open")
		check(not quiz.visible and not quiz.is_active and not quiz.spectator_mode, scenario + ": quiz and timers must stop immediately")
		quiz.display_quiz(1, data)
		check(not quiz.visible, scenario + ": late quiz event must not reopen modal")
		var energy: int = gm.players[0]["energy"]
		var completion_count := completions.size()
		await create_timer(quiz.result_reading_seconds(data) + 0.2).timeout
		check(completions.size() == completion_count and gm.players[0]["energy"] == energy, scenario + ": closing old explanation must not resubmit or grant additional rewards")
		check(hud.open_market_panel.visible and not quiz.visible, scenario + ": market stays accessible after old callbacks")
		gm.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("[PASS] Quiz to market: own answer, spectator wait, pending result, late events")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
