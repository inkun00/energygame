extends SceneTree

const UI = preload("res://scripts/ui/CommercialUI.gd")
const PAWN = preload("res://scripts/player/PlayerPawn.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[QualityPresentation] " + message)

func _run() -> void:
	var manager: Node = root.get_node("GameManager")
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.2).timeout
	var lobby: Node = main.get_node("LobbyUI")
	for index in range(lobby.characters.size()):
		lobby._on_character_selected(index)
		await process_frame
		await process_frame
		await process_frame
		var rect: Rect2 = lobby.hero_badge.get_global_rect()
		_check(rect.end.y <= 720.0, "Character %d introduction must fit the 720px scene" % index)
		var description_rect: Rect2 = lobby.skill_description_label.get_global_rect()
		_check(description_rect.end.y <= rect.end.y, "Character %d skill must remain inside its card" % index)
	_check(lobby.learning_grade_option.item_count == 3, "Grade 4, 5 and 6 must be selectable")
	lobby.learning_grade_option.select(0)
	lobby._apply_learning_grade()
	_check(manager.learning_grade == 4, "Grade selection must reach the quiz rules")
	lobby.learning_grade_option.select(2)
	lobby._apply_learning_grade()
	_check(manager.learning_grade == 6, "Advanced grade must reach the quiz rules")
	_check(lobby.game_time_option_button.tooltip_text.contains("별도"), "Exploration time must not pretend to be total session duration")
	main.queue_free()
	await process_frame
	var button := Button.new()
	UI.apply_primary_button(button)
	_check(button.get_theme_color("font_focus_color") == UI.INK, "Keyboard focus must keep dark text on the yellow button")
	button.free()
	var pawn := PAWN.new()
	root.add_child(pawn)
	pawn.setup_player({"char_icon": "res://assets/characters/eco_roster/captain_eco.webp"})
	pawn.set_side_run_enabled(true)
	pawn._set_avatar_animation_state(true)
	pawn.animation_elapsed = 0.27
	pawn._set_avatar_animation_state(true)
	_check(is_equal_approx(pawn.animation_elapsed, 0.27), "Repeated movement reports must not reset the running sheet")
	pawn.animation_phase = 10.0
	pawn.animation_speed = 20.0
	pawn._process(0.1)
	var fast_phase: float = pawn.animation_phase
	pawn.animation_speed = 0.0
	pawn._process(0.1)
	_check(pawn.animation_phase > fast_phase and pawn.animation_phase - fast_phase <= 1.5, "Speed changes must advance phase, not recalculate old frames")
	pawn._update_hop_position(0.25, Vector3.ZERO, Vector3(1, 0, 0), 0.5)
	_check(pawn.avatar_sprite.scale.y > 1.0, "Hop must have a light takeoff pose")
	pawn._place_on_tile(0)
	_check(pawn.avatar_sprite.scale == Vector3.ONE, "Landing must restore the sprite pose")
	pawn.queue_free()
	await process_frame
	var modal: Node = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	var configs: Array[Dictionary] = [{"name": "Test", "is_ai": false}]
	manager.setup_game(configs, 600)
	manager.stop_game()
	for game_id in manager.MINIGAME_DEFINITIONS:
		var definition: Dictionary = manager.MINIGAME_DEFINITIONS[game_id].duplicate(true)
		definition["round_id"] = 900
		definition["seed"] = 20260921
		modal._on_minigame_started(definition)
		modal._begin_local_round()
		await process_frame
		await process_frame
		_check(not modal.objective_label.visible and not modal.lesson_label.visible, "%s must not duplicate long instructions during play" % game_id)
		_check(modal.goal_label.visible and modal.goal_label.text.contains("목표"), "%s must show live bonus progress" % game_id)
		_check(modal.arena_panel.size.y >= 400.0, "%s arena must use at least 400px" % game_id)
		_check(modal.card.get_global_rect().end.y <= root.get_visible_rect().size.y, "%s play card must fit the screen" % game_id)
		if game_id == "grid_balance":
			modal.grid_arcade._apply_supply_input(1.0, 0.01)
			modal.grid_arcade.measurement_time = 30.0
			modal.grid_arcade.gap_integral = 600.0
			modal.score = modal.grid_arcade.get_balance_score()
			var last_attempt: Dictionary = modal._submission_stats()
			_check(modal.score > 0 and int(last_attempt["attempts"]) == 1, "Last-second grid input must submit a real attempt instead of being rejected")
			var frozen: int = modal.grid_arcade.finalize_balance_score()
			modal.grid_arcade.gap_integral = 1800.0
			_check(modal.grid_arcade.get_balance_score() == frozen, "Final grid score must not change after the buzzer")
		if game_id == "energy_sort":
			modal.sort_arcade.retrying_item = false
			for _attempt in range(4):
				modal._on_sort_arcade_event(90, true, "First correct", true)
			for _attempt in range(2):
				modal._on_sort_arcade_event(30, false, "First incorrect", false)
			modal.sort_arcade.retrying_item = true
			for _attempt in range(2):
				modal._on_sort_arcade_event(0, true, "Retry practice", false)
			var stats: Dictionary = modal._submission_stats()
			_check(stats["attempts"] == 8 and stats["concept_attempts"] == 6, "Sort retry practice must not double-penalize first-choice accuracy")
			_check(manager.has_minigame_goal_actions("energy_sort", modal.score, stats), "Human and AI 4/6 first-choice success must earn the same eligibility")
		if game_id == "heat_leak":
			modal.round_start_msec = Time.get_ticks_msec() - 5000
			modal.elapsed = 0.0
			modal._process(0.01)
			_check(modal.elapsed >= 5.0, "A render stall must not extend a timed round")
			_check(absf(modal.heat_arcade.elapsed - 5.0) < 0.05, "Heat simulation must catch up to the same round clock")
			modal._advance_arcade_simulation(25.1)
			_check(modal.heat_arcade.next_wave == modal.heat_arcade.WAVE_COUNT, "The last window wave must still occur after a render stall")
		if game_id in ["hydro_gate", "battery_relay"]:
			modal._advance_arcade_simulation(5.1)
			var arcade: Node = modal.hydro_arcade if game_id == "hydro_gate" else modal.battery_arcade
			_check(absf(arcade.elapsed - 5.1) < 0.05, "%s weather and simulation must follow the shared elapsed time" % game_id)
			var previous_time: float = arcade.elapsed
			modal._advance_arcade_simulation(5.1)
			_check(is_equal_approx(arcade.elapsed, previous_time), "A repeated clock target must not simulate the same interval twice")
		if game_id == "energy_sort":
			modal._register_miss(30, "석탄은 다시 만들어지는 데 매우 오랜 시간이 걸려요.")
			_check(modal.feedback_label.text.contains("매우 오랜"), "Sort feedback must preserve the actual wrong-answer reason")
		modal.cancel_minigame()
	modal.queue_free()
	manager.stop_game()
	await process_frame
	if failures.is_empty():
		print("[QualityPresentation] PASS · character layout, grades, contrast, animation and nine live goal displays")
	quit(0 if failures.is_empty() else 1)
