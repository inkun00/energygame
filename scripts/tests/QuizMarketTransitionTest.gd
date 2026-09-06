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
		main._on_start_game_requested(configs, 600)
		await create_timer(0.15).timeout
		gm.set_process(false)
		gm.players[0]["inventory"]["solar_panel"] = 2
		gm.current_state = gm.TurnState.RESOLVING_QUIZ
		quiz.display_quiz(1 if scenario == "spectator" else 0, data)
		check(quiz.visible, scenario + ": quiz should be visible before transition")
		if scenario == "spectator":
			quiz.spectator_guess_submitted = true
		if scenario == "pending_result":
			quiz._show_result(true)
		gm._start_open_market_phase()
		check(hud.open_market_panel.visible, scenario + ": market should open")
		check(not quiz.visible and not quiz.is_active and not quiz.spectator_mode, scenario + ": quiz and timers must stop immediately")
		quiz.display_quiz(1, data)
		check(not quiz.visible, scenario + ": late quiz event must not reopen modal")
		var energy: int = gm.players[0]["energy"]
		await create_timer(quiz.PLAYER_RESULT_SECONDS + 0.2).timeout
		check(completions.is_empty() and gm.players[0]["energy"] == energy, scenario + ": cancelled result must not submit or grant rewards")
		check(hud.open_market_panel.visible and not quiz.visible, scenario + ": market stays accessible after old callbacks")
		gm.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("[PASS] Quiz to market: own answer, spectator wait, pending result, late events")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
