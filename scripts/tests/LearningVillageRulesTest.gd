extends SceneTree

var gm: Node
var checks := 0
var failures: Array[String] = []
var ending_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("[FAIL] " + message)

func _fresh() -> void:
	gm.stop_game()
	root.get_node("NetworkManager").is_online = false
	var configs: Array[Dictionary] = []
	for idx in range(4):
		configs.append({"name": "학습 시험 %d" % idx, "is_ai": false})
	gm.setup_game(configs, 300)
	gm.set_process(false)

func _quiz(correct: bool = true) -> void:
	gm.current_turn_idx = 0
	gm.current_state = gm.TurnState.RESOLVING_QUIZ
	gm.active_quiz_player_idx = 0
	gm.active_quiz_data = {"answer": "햇빛", "explanation": "태양광 패널은 햇빛으로 전기를 만들어요.", "reward_energy": 2}
	gm.on_network_quiz_resolved(0, correct, "햇빛" if correct else "바람")

func _inventory_count() -> int:
	var count := 0
	for amount in gm.get_team_inventory().values():
		count += int(amount)
	return count

func _finish_trial() -> void:
	for idx in range(4):
		gm.finish_energy_trial(idx)

func _test_tutorial_explanation_wait() -> void:
	_fresh()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [{"name": "천천히 읽기", "is_ai": false}]
	main._on_tutorial_requested(configs)
	var tutorial: Node = main.guided_tutorial
	var quiz: Node = main.game_board.quiz_modal
	tutorial._set_stage("quiz", "3 / 7  퀴즈와 부품", "답을 고르고 이유를 확인하세요.")
	var data := {"question": "태양광 패널은 무엇으로 전기를 만들까요?", "answer": "햇빛", "options": ["햇빛", "바람", "흐르는 물", "땅속 열"], "type": 2, "explanation": "태양광 패널은 햇빛으로 전기를 만들어요.", "reward_energy": 2}
	gm.current_turn_idx = 0
	gm.current_state = gm.TurnState.RESOLVING_QUIZ
	gm.active_quiz_player_idx = 0
	gm.active_quiz_data = data.duplicate(true)
	quiz.display_quiz(0, data)
	quiz.submitted_choice = "햇빛"
	quiz._show_result(true)
	gm.set_process(true)
	var before: int = _inventory_count()
	# Real SceneTree timers and normal GameManager processing must not close a
	# practice explanation behind a learner who takes longer than twelve seconds.
	await create_timer(13.0).timeout
	_check(gm.component_choices.has(0) and gm.component_choices[0]["phase"] == "waiting", "practice explanation has no automatic component deadline")
	_check(tutorial.stage == "quiz" and quiz.result_visible and quiz.visible, "practice keeps the actual explanation readable after thirteen seconds")
	_check(_inventory_count() == before, "waiting to read does not automatically select a practice part")
	quiz.next_button.pressed.emit()
	_check(gm.component_choices[0]["phase"] == "choosing" and tutorial.stage == "component", "the learner's Next action opens practice component selection")
	var choice: Dictionary = gm.component_choices[0].duplicate(true)
	_check(gm.choose_quiz_component(0, str(choice["options"][0]), int(choice["token"])), "the acknowledged practice reward can be claimed normally")
	_check(tutorial.stage == "mini_intro" and gm.component_choices.is_empty() and _inventory_count() == before + 1, "choosing a practice part advances to the next tutorial activity exactly once")
	gm.stop_game()
	main.queue_free()
	await process_frame
	gm.set_process(false)

func _run() -> void:
	gm = root.get_node("GameManager")
	gm.game_over.connect(func(_rankings: Array): ending_count += 1)
	_fresh()
	_check(gm.select_team_project(0, 3), "an explorer can choose a storage goal")
	_quiz()
	var pending: Dictionary = gm.component_choices[0].duplicate(true)
	var token: int = pending["token"]
	var item: String = pending["options"][0]
	_check(pending["phase"] == "waiting" and pending["options"].has("battery"), "correct answers offer missing parts for the chosen facility")
	_check(_inventory_count() == 0, "a correct answer does not randomly grant a material before choosing")
	_check(not gm.choose_quiz_component(0, item, token), "parts cannot be claimed before reading the quiz result")
	gm._update_component_choices(20.0)
	_check(gm.component_choices[0]["remaining"] == 8.0, "the selection clock waits for the explanation")
	gm.finish_quiz_review(0)
	_check(gm.component_choices[0]["phase"] == "choosing", "finishing the explanation opens material selection")
	_check(not gm.choose_quiz_component(0, "not_a_part", token), "an unoffered material is rejected")
	_check(not gm.choose_quiz_component(0, item, token + 1), "an incorrect request token is rejected")
	var turns_before: int = gm.total_turns
	_check(gm.choose_quiz_component(0, item, token), "the selected offered part is granted")
	_check(_inventory_count() == 1 and gm.players[0]["inventory"][item] == 1, "exactly one selected part enters the player's inventory")
	_check(gm.total_turns == turns_before + 1, "the turn continues only after choosing the part")
	_check(not gm.choose_quiz_component(0, item, token) and _inventory_count() == 1, "repeated requests cannot duplicate a part")
	gm.finish_quiz_review(0)
	_check(gm.component_choices.is_empty(), "a late review callback cannot reopen consumed choices")
	_quiz()
	var next: Dictionary = gm.component_choices[0]
	_check(next["token"] > token, "the next quiz uses a fresh token")
	gm.finish_quiz_review(0)
	_check(not gm.choose_quiz_component(0, item, token), "a previous quiz token cannot claim the next reward")
	var timeout_item: String = next["options"][0]
	var timeout_before: int = gm.players[0]["inventory"][timeout_item]
	gm._update_component_choices(9.0)
	_check(gm.component_choices.is_empty() and gm.players[0]["inventory"][timeout_item] == timeout_before + 1, "selection timeout grants one needed part and continues")
	gm._update_component_choices(9.0)
	_check(_inventory_count() == 2, "selection timeout cannot repeat a reward")

	_fresh()
	_quiz(false)
	_check(gm.component_choices.is_empty() and _inventory_count() == 0, "an incorrect answer does not offer a reward")
	_fresh()
	_quiz()
	gm._start_team_planning_phase()
	_check(_inventory_count() == 1 and gm.component_choices.is_empty(), "the exploration deadline preserves an earned reward exactly once")
	_check(gm.team_plan["active"] and not gm.open_market_active and not gm.is_game_active, "exploration proceeds to shared planning without material trading")
	var pooled: Dictionary = gm.get_team_inventory().duplicate(true)
	_check(gm.select_team_project(0, 0) and gm.select_team_project(1, 3), "friends can propose complementary shared facilities")
	_check(not gm.select_team_project(-1, 0) and not gm.select_team_project(0, 10), "invalid planning participants and facilities are rejected")
	gm.confirm_team_plan(0)
	_check(gm.team_plan["ready"].has(0), "a participant can confirm a plan")
	gm.select_team_project(0, 4)
	_check(not gm.team_plan["ready"].has(0), "changing a proposal clears that participant's previous confirmation")
	var view: Dictionary = gm.get_team_plan_state()
	view["choices"][0] = 9
	_check(gm.team_plan["choices"][0] == 4, "display snapshots cannot change the authoritative plan")
	for idx in range(3):
		gm.confirm_team_plan(idx)
	_check(gm.team_plan["active"] and not gm.village_construction_active, "construction waits for the final participant")
	gm.confirm_team_plan(3)
	_check(not gm.team_plan["active"] and gm.village_construction_active, "four confirmations enter shared construction")
	_check(gm.get_team_inventory() == pooled, "planning neither loses nor fabricates collected materials")

	_fresh()
	gm.game_time_remaining = 0.01
	gm._process(0.02)
	_check(gm.team_plan["active"], "normal exploration timeout enters planning")
	gm._process(20.0)
	_check(gm.village_construction_active, "planning timeout safely starts construction")
	gm.players[0]["inventory"]["solar_panel"] = 2
	gm.players[1]["inventory"]["smart_grid"] = 1
	gm.players[2]["inventory"]["battery"] = 2
	gm.players[3]["inventory"]["smart_grid"] = 1
	_check(gm.build_village_project(0, 0) and gm.build_village_project(3, 1), "shared materials build solar and separate energy storage")
	_check(_inventory_count() == 0, "construction spends each required team part once")
	for idx in range(4):
		gm.finish_village_construction(idx)
	_check(not gm.village_construction_active and gm.energy_trial["phase"] == "day", "finishing construction starts the electricity exercise")
	_check(not gm.kingdom_recovered and ending_count == 0, "buildings alone do not decide the ending")
	gm.finish_energy_trial(0)
	_check(gm.energy_trial["ready"].is_empty(), "a running trial cannot be skipped through the result action")
	for idx in range(4):
		_check(gm.set_energy_trial_mode(idx, "store"), "each participant controls their own storage allocation")
	gm._process(20.0)
	_check(gm.energy_trial["phase"] == "night" and is_equal_approx(gm.energy_trial["battery"], 90.0), "daylight surplus charges the installed storage")
	_check(gm.energy_trial["players"][0]["mode"] == "store", "human mode is not automatically changed at night")
	for idx in range(4):
		gm.set_energy_trial_mode(idx, "supply")
	gm._process(20.0)
	_check(gm.energy_trial["success"] and gm.energy_trial["night_coverage"] == 1.0, "supplying stored daylight electricity lights the whole night")
	_check(not gm.get_energy_trial_state()["can_retry"], "a successful trial needs no retry")
	for idx in range(3):
		gm.finish_energy_trial(idx)
	_check(ending_count == 0, "the result remains visible until every participant confirms")
	gm.finish_energy_trial(3)
	_check(gm.kingdom_recovered and ending_count == 1, "the measured successful trial creates the recovered ending")
	gm.finish_energy_trial(3)
	_check(ending_count == 1, "duplicate finish requests cannot award an ending twice")

	_fresh()
	gm.kingdom_health = 100
	gm._start_village_construction_phase()
	gm.evaluate_village()
	gm._process(40.0)
	_check(not gm.energy_trial["success"] and not gm.kingdom_recovered, "high scenery health cannot replace actual electricity supply")
	gm.finish_energy_trial(0, true)
	_check(gm.village_construction_active and gm.energy_trial.is_empty() and gm.energy_trial_retries == 1, "one failed trial can return to construction for improvement")
	gm.evaluate_village()
	gm._process(40.0)
	_check(not gm.get_energy_trial_state()["can_retry"], "the second trial offers no further retry")
	gm.finish_energy_trial(0, true)
	_check(not gm.village_construction_active and gm.energy_trial_retries == 1, "a repeated retry request cannot create an endless loop")
	_finish_trial()
	_check(not gm.kingdom_recovered and ending_count == 2, "a still-unpowered village ends honestly after confirmation")

	_fresh()
	_quiz()
	gm.finish_quiz_review(0)
	var choice_time: float = gm.component_choices[0]["remaining"]
	paused = true
	gm._process(5.0)
	paused = false
	_check(gm.component_choices[0]["remaining"] == choice_time, "reconnection pause preserves the material choice timer")
	gm._start_team_planning_phase()
	var plan_time: float = gm.team_plan["remaining"]
	paused = true
	gm._process(5.0)
	paused = false
	_check(gm.team_plan["remaining"] == plan_time, "reconnection pause preserves planning time")
	gm._finish_team_planning()
	gm.evaluate_village()
	paused = true
	gm._process(5.0)
	paused = false
	_check(gm.energy_trial["elapsed"] == 0.0, "reconnection pause preserves the day/night exercise")
	gm.stop_game()
	_check(gm.energy_trial.is_empty() and gm.component_choices.is_empty() and not gm.team_plan["active"] and gm.energy_trial_retries == 0, "leaving a game clears every learning-flow stage")
	_fresh()
	_check(gm.energy_trial.is_empty() and gm.component_choices.is_empty() and not gm.team_plan["active"] and not gm._village_result_finalized, "a new session cannot inherit previous results")
	gm.stop_game()
	await _test_tutorial_explanation_wait()
	# Let session-guarded quiz explanation callbacks retire before shutdown.
	Engine.time_scale = 100.0
	await create_timer(13.0).timeout
	Engine.time_scale = 1.0
	for voice: AudioStreamPlayer in root.get_node("AudioManager").voices:
		voice.stop()
		voice.stream = null
	await create_timer(0.5).timeout
	if failures.is_empty():
		print("[PASS] LearningVillageRulesTest: %d checks" % checks)
		quit(0)
	else:
		printerr("[FAIL] LearningVillageRulesTest: %d/%d checks failed" % [failures.size(), checks])
		quit(1)
