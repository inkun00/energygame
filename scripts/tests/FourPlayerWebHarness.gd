extends Node

## Test-only alternate main scene. Never selected by the production export.
## Real Main/Lobby/board/modal UI, with explicit host-only scenario fixtures.
var main: Node
var sequence := 0
var elapsed := 0.0
var last_results: Array = []
var endings := 0
var restored := 0
var last_error := ""
var last_local_claim: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ProjectSettings.set_setting("network/room_directory_url", "http://127.0.0.1:19395")
	main = load("res://scenes/Main.tscn").instantiate()
	# The observer must run while paused; the real game must retain its ordinary
	# pausable root instead of inheriting this test observer's ALWAYS mode.
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	GameManager.minigame_finished.connect(func(results): last_results = results.duplicate(true))
	GameManager.game_over.connect(func(_rankings): endings += 1)
	NetworkManager.session_restored.connect(func(): restored += 1)
	NetworkManager.external_room_failed.connect(func(message): last_error = message)
	NetworkManager.room_code_lookup_failed.connect(func(message): last_error = message)
	_publish()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.15:
		return
	elapsed = 0.0
	var raw = JavaScriptBridge.eval("JSON.stringify(window.fourPlayerCommand || null)", true)
	var command = JSON.parse_string(str(raw))
	if command is Dictionary and int(command.get("sequence", 0)) > sequence:
		sequence = int(command["sequence"])
		_execute(command)
	_publish()

func _execute(command: Dictionary) -> void:
	var action := str(command.get("action", ""))
	match action:
		"create", "join":
			main.lobby_ui.nickname_edit.text = str(command.get("name", "검증"))
			main.lobby_ui.char_option_button.select(int(command.get("character", 0)))
			if action == "create":
				main.lobby_ui._create_configured_room({"name": "로컬 4인 검증"})
			else:
				main.lobby_ui._join_listed_room(str(command["code"]), "")
		"minigame_fixture":
			if NetworkManager.is_host:
				GameManager.active_quiz_data.clear()
				GameManager.active_quiz_player_idx = -1
				GameManager._start_minigame(GameManager.current_turn_idx, str(command["id"]))
		"market_fixture":
			if NetworkManager.is_host:
				# Supply construction materials; collection economy is covered separately.
				for index in range(4):
					for item in GameManager.ITEM_DEFINITIONS:
						GameManager.players[index]["inventory"][item] = 4
					GameManager.player_inventory_changed.emit(index, GameManager.players[index]["inventory"])
				GameManager.game_time_remaining = 0.01
		"drop":
			if not NetworkManager.is_host:
				NetworkManager._begin_reconnect()
				NetworkManager._next_reconnect_attempt = Time.get_ticks_msec() + 2500
		"host_leave":
			main.switch_to_lobby()

func _button(control: Variant) -> Dictionary:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return {}
	var rect: Rect2 = control.get_global_rect()
	var label: String = control.text if control is Button else ""
	if label.is_empty(): label = str(control.tooltip_text).get_slice("\n", 0)
	return {"x": rect.get_center().x, "y": rect.get_center().y, "disabled": control.disabled if control is BaseButton else false, "text": label}

func _publish() -> void:
	if not is_instance_valid(main):
		return
	var board: Node = main.game_board
	var hud: Node = board.hud
	var mini: Node = board.minigame_modal
	var quiz: Node = board.quiz_modal
	var learning: Node = hud.learning_village_ui
	var buttons := {
		"start": _button(main.lobby_ui._room_start_button),
		"ready": _button(hud.adventure_planner.tutorial_button),
		"dice": _button(hud.center_dice_button),
		"mini_ready": _button(mini.guide_start_button),
		"practice": _button(mini.guide_practice_button),
		"market_confirm": _button(hud.open_market_confirm_button),
		"plan_confirm": _button(learning.plan_ready_button),
		"trial_confirm": _button(learning.trial_confirm_button),
		"trial_retry": _button(learning.trial_retry_button),
		"finish": _button(hud.evaluate_button),
		"return": _button(hud.lobby_return_button),
		"quiz_next": _button(quiz.next_button)
	}
	var component_buttons: Array = []
	for button in learning.option_buttons:
		component_buttons.append(_button(button))
	for mode in learning.mode_buttons:
		buttons["trial_" + str(mode)] = _button(learning.mode_buttons[mode])
	var recovery_buttons: Array = main.recovery_overlay.find_children("*", "Button", true, false)
	buttons["recovery_leave"] = _button(recovery_buttons[0]) if not recovery_buttons.is_empty() and main.recovery_overlay.visible else {}
	if str(GameManager.active_minigame.get("phase", "")) == "playing":
		last_local_claim = {"score": mini.score, "stats": mini._submission_stats(), "submitted": mini.submitted, "elapsed": mini.elapsed, "time": GameManager.minigame_time_remaining}
	var choices: Array = []
	for choice in quiz.choice_container.get_children():
		if choice is Button:
			var data := _button(choice)
			data["answer"] = str(choice.get_meta("answer_value", ""))
			choices.append(data)
	var cards: Array = []
	for card in hud.construction_list.get_children():
		if card is Button:
			cards.append(_button(card))
	var map_rect: Rect2 = hud.village_map.get_global_rect()
	var players: Array = []
	for player in GameManager.players:
		players.append({"name": player.get("name"), "energy": player.get("energy"), "tile": player.get("tile_index"), "ai": player.get("is_ai"), "inventory": player.get("inventory")})
	var state := {
		"sequence": sequence, "error": last_error, "code": NetworkManager.room_code,
		"peers": NetworkManager.connected_players.size(), "local": NetworkManager.get_local_player_index(),
		"online": NetworkManager.is_online, "host": NetworkManager.is_host, "paused": get_tree().paused,
		"restored": restored, "session": main.session_open, "lobby": main.lobby_ui.visible,
		"preparation": GameManager.adventure_waiting_for_start,
		"turn": GameManager.current_turn_idx, "turns": GameManager.total_turns, "state": GameManager.current_state,
		"players": players, "buttons": buttons, "choices": choices, "cards": cards,
		"map": {"x": map_rect.position.x, "y": map_rect.position.y, "w": map_rect.size.x, "h": map_rect.size.y},
		"quiz": {"visible": quiz.visible, "active": quiz.is_active, "target": quiz.target_player_idx, "answer": str(quiz.current_quiz.get("answer", "")), "result": quiz.result_visible},
		"mini": GameManager.active_minigame, "mini_visible": mini.visible,
		"practice": mini.practice_active, "playing": mini.round_started_locally,
		"time": GameManager.minigame_time_remaining, "score": mini.score,
		"submitted": mini.submitted, "scores": GameManager.minigame_scores,
		"local_claim": last_local_claim,
		"results": last_results, "completed": GameManager.completed_minigame_ids,
		"market": GameManager.get_open_market_state(), "construction": GameManager.village_construction_active,
		"component": GameManager.get_component_choice_state(), "component_buttons": component_buttons,
		"plan": GameManager.get_team_plan_state(), "trial": GameManager.get_energy_trial_state(),
		"built": GameManager.built_project_ids, "placements": GameManager.built_project_placements,
		"endings": endings, "ending_visible": is_instance_valid(hud.ending_cinematic)
	}
	JavaScriptBridge.eval("window.fourPlayerState = %s;" % JSON.stringify(state), true)
