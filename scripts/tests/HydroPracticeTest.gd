extends SceneTree

const INPUT = preload("res://scripts/minigames/MiniGameInput.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var manager: Node = root.get_node("GameManager")
	var network: Node = root.get_node("NetworkManager")
	network.is_online = false
	var configs: Array[Dictionary] = [{"name": "Practice", "is_ai": false}, {"name": "AI1", "is_ai": true}, {"name": "AI2", "is_ai": true}, {"name": "AI3", "is_ai": true}]
	manager.setup_game(configs, 600)
	manager.stop_game()
	var modal: Node = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	modal.set_process(false)
	var definition: Dictionary = manager.MINIGAME_DEFINITIONS["hydro_gate"].duplicate(true)
	definition["round_id"] = 992
	definition["seed"] = 23
	modal._on_minigame_started(definition)
	_check(modal.guide_practice_button.visible, "Hydro guide must offer optional practice")
	modal._start_hydro_practice()
	var hydro: Node = modal.hydro_arcade
	_check(modal.practice_active and hydro.practice_mode and not modal._can_play(), "Practice must never count as competitive play")
	_check(root.gui_get_focus_owner() == null, "Practice must release GUI focus so Space cannot press a button")
	_check(not manager.minigame_ready_players.has(0), "Practice must not mark a human ready")
	hydro.hero_x = hydro.LEVER_X[0]
	hydro._update_station()
	for tap in range(3):
		INPUT.set_touch(KEY_SPACE, true)
		hydro._process(1.0 / 60.0)
		INPUT.set_touch(KEY_SPACE, false)
		hydro._process(1.0 / 60.0)
	_check(hydro.open_gate == 0, "Practice uses the real three-tap gate-opening control")
	hydro._advance_simulation(1.0)
	_check(hydro.generated_kwh > 0.0 and modal.score == 0 and modal.attempts == 0, "Visible practice generation must not become a score or attempt")
	INPUT.set_touch(KEY_E, true)
	hydro._process(1.0 / 60.0)
	INPUT.release_all()
	_check(hydro.open_gate == -1, "Practice uses the real E gate-closing control")
	hydro.water_level = 99.9
	hydro._advance_simulation(1.0)
	_check(not hydro.overflowed and hydro.water_level <= 98.0, "Practice must not end in overflow")
	modal._finish_hydro_practice()
	_check(modal.is_guide_open() and not modal.practice_active, "Ending practice returns to the guide, not into an unsynchronized round")
	_check(not hydro.practice_mode and hydro.generated_kwh == 0.0 and hydro.elapsed == 0.0 and hydro.open_gate == -1, "Practice state must reset completely")
	_check(is_equal_approx(hydro.water_level, hydro.initial_level_for_seed(23)), "Competition restores the same seeded initial water level")
	modal._start_hydro_practice()
	modal._begin_local_round()
	_check(not modal.practice_active and not hydro.practice_mode and modal.round_started_locally, "A host timeout can interrupt practice safely")
	_check(modal.score == 0 and hydro.generated_kwh == 0.0 and modal.simulation_elapsed == 0.0, "Automatic start must not carry practice progress")
	hydro.water_level = 99.9
	hydro._advance_simulation(1.0)
	_check(hydro.overflowed and modal.hydro_submit_msec >= 0, "The actual competition retains overflow game-over")
	modal.cancel_minigame()
	modal.queue_free()
	manager.stop_game()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("[PASS] HydroPractice · real controls, no scores, seed reset, auto-start, real overflow")
	quit(0 if failures.is_empty() else 1)
