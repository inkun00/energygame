extends SceneTree

## Exercise the real Main scene and the engine's keyboard dispatch, not callbacks.
## No player records, screenshots or replay data are written by this test.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[StandaloneInputIsolation] " + message)

func _key(key: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _tap(key: Key) -> void:
	_key(key, true)
	await process_frame
	_key(key, false)
	await process_frame

func _board_inactive(board_modal: Node) -> bool:
	return not board_modal.surface_enabled and not board_modal.active and not board_modal.visible and not board_modal.is_guide_open()

func _run() -> void:
	var manager: Node = root.get_node("GameManager")
	var network: Node = root.get_node("NetworkManager")
	network.is_online = false
	manager.stop_game()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var board: Node = main.get_node("GameBoard")
	var board_modal: Node = board.minigame_modal
	_check(_board_inactive(board_modal), "The lobby must disable the hidden board modal")
	_check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "The inactive lobby board must not keep rendering its 3D viewport")
	main._open_standalone_minigames("hydro_gate")
	await process_frame
	await process_frame
	# Only pause the authority clock: actual modal processing and engine key
	# routing stay enabled, so these checks cannot bypass the original defect.
	manager.set_process(false)
	var standalone: Node = main.standalone_minigames
	var modal: Node = standalone.modal
	_check(modal.standalone_mode and modal.active and modal.is_visible_in_tree() and modal.is_guide_open(), "The visible standalone guide must be the only active minigame surface")
	_check(_board_inactive(board_modal) and not board.modals_layer.visible, "Standalone minigame_started must not activate or build a hidden board guide")
	_check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "The hidden board viewport must stay disabled throughout standalone play")
	_check(not manager.minigame_ready_players.has(0), "Opening standalone instructions must not ready the human")
	await _tap(KEY_P)
	_check(modal.practice_active and modal.hydro_arcade.practice_mode and not modal.is_guide_open(), "P through engine input must enter score-free hydro practice")
	_check(root.gui_get_focus_owner() == null, "Practice must release button focus before Space controls the gate")
	var round_id: int = int(manager.active_minigame.get("round_id", -1))
	for _press in range(3):
		await _tap(KEY_SPACE)
	_check(modal.practice_active and modal.hydro_arcade.practice_mode, "Practice Space must not accidentally end practice through another guide")
	_check(not manager.minigame_ready_players.has(0) and str(manager.active_minigame.get("phase", "")) == "ready", "Practice Space must not ready a player or begin the countdown")
	_check(_board_inactive(board_modal) and board_modal.round_id == -1, "The hidden board must stay inactive with no standalone round attached")
	_check(int(manager.active_minigame.get("round_id", -1)) == round_id and modal.score == 0 and modal.attempts == 0, "Practice must neither switch rounds nor submit competitive actions")
	await _tap(KEY_ESCAPE)
	_check(not modal.practice_active and modal.is_guide_open() and not main.exit_confirmation.visible, "Standalone Esc must return to the guide without opening the board exit dialog")
	_check(not manager.minigame_ready_players.has(0) and _board_inactive(board_modal), "Ending practice must not ready the player or enable the hidden modal")
	await _tap(KEY_ENTER)
	_check(manager.minigame_ready_players.has(0) and str(manager.active_minigame.get("phase", "")) == "countdown", "Standalone Enter must start the common countdown after the three AIs are ready")
	_check(not modal.is_guide_open() and not modal.round_started_locally and not modal.practice_active, "Enter must leave the guide but wait for synchronized competitive start")
	_check(_board_inactive(board_modal), "Even countdown updates must not activate the hidden board surface")
	manager.stop_game()
	standalone.queue_free()
	await process_frame
	await process_frame
	var players: Array[Dictionary] = [
		{"name": "Human", "is_ai": false},
		{"name": "AI 1", "is_ai": true},
		{"name": "AI 2", "is_ai": true},
		{"name": "AI 3", "is_ai": true},
	]
	main._on_start_game_requested(players, 600)
	manager.confirm_adventure_ready(0)
	await create_timer(0.15).timeout
	_check(board.visible and board.modals_layer.visible and board_modal.surface_enabled, "Normal board start must re-enable its minigame surface")
	_check(main.session_open and board.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "An active board session must resume its 3D viewport")
	manager._start_minigame(0, "hydro_gate")
	await process_frame
	_check(board_modal.active and board_modal.is_visible_in_tree() and board_modal.is_guide_open(), "A board minigame must still receive its own start signal after standalone use")
	await _tap(KEY_P)
	_check(board_modal.practice_active and board_modal.hydro_arcade.practice_mode and not board_modal.is_guide_open(), "P must also enter hydro practice inside an active board session")
	for _press in range(3):
		await _tap(KEY_SPACE)
	_check(board_modal.practice_active and board_modal.score == 0 and board_modal.attempts == 0, "Board practice Space must preserve score-free practice")
	_check(not manager.minigame_ready_players.has(0) and str(manager.active_minigame.get("phase", "")) == "ready", "Board practice Space must not mark the player ready")
	await _tap(KEY_ESCAPE)
	_check(not board_modal.practice_active and board_modal.is_guide_open() and not main.exit_confirmation.visible, "Board practice Esc must return to the guide instead of the session exit dialog")
	_check(not manager.minigame_ready_players.has(0) and main.session_open, "Finishing board practice must keep the session open and the player unready")
	await _tap(KEY_ENTER)
	_check(manager.minigame_ready_players.has(0) and str(manager.active_minigame.get("phase", "")) == "countdown", "Normal board keyboard start must keep working after surface isolation")
	main.switch_to_lobby()
	_check(_board_inactive(board_modal), "Returning to the lobby must disable the board modal again")
	_check(board.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Returning to the lobby must stop board viewport rendering again")
	manager.stop_game()
	manager.set_process(true)
	main.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("[StandaloneInputIsolation] PASS · standalone/board P/Space/Esc/Enter routing, hidden surface isolation and viewport lifecycle")
	quit(0 if failures.is_empty() else 1)
