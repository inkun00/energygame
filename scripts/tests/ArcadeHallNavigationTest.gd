extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var records := root.get_node("MiniGameRecords")
	OS.set_environment("ENERGYGAME_LEADERBOARD_URL", "offline")
	records.profile_path = OS.get_temp_dir().path_join("arcade-nav-%d.cfg" % OS.get_process_id())
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.lobby_ui.minigames_button.pressed.emit()
	await process_frame
	var hub = main.standalone_minigames
	_check(hub.menu.visible and not main.lobby_ui.visible, "Lobby button opens the arcade")
	hub.hall_button.pressed.emit()
	var hall = hub.hall
	_check(hall.visible and hall.selector.item_count == 9, "Each event has a hall")
	for i in range(9):
		hall.selector.item_selected.emit(i)
		_check(hall.selected_game == hub.AVAILABLE_IDS[i], "Selected hall matches game")
	var records_state := {"entries": [{"rank": 1, "alias": "햇살토끼", "score": 80, "mine": true}], "scope": "shared", "status": "online", "personal_best": 80, "personal_rank": 1, "alias": "햇살토끼"}
	records.records_changed.emit("solar_align", records_state)
	_check(not hall.best.text.contains("80"), "An old game's response cannot overwrite this event")
	records.records_changed.emit("heat_leak", records_state)
	_check(hall.best.text.contains("80") and hall.player_alias.text.contains("1위"), "Personal score and rank render")
	hall.challenge.pressed.emit()
	_check(hub.modal.active and hub.current_game_id == "heat_leak" and not hall.visible, "Challenge opens the correct event")
	var manager := root.get_node("GameManager")
	hub.modal.dismiss_guide()
	manager._update_minigame(manager.MINIGAME_READY_COUNTDOWN_SECONDS)
	for i in range(4):
		manager.submit_minigame_score(i, 200 - i * 30)
	await process_frame
	_check(hub.modal.standalone_actions.visible, "Arcade results contain navigation")
	hub.modal.standalone_records_button.pressed.emit()
	_check(hall.visible and hall.selected_game == "heat_leak", "Result opens its event's hall")
	hall.back.pressed.emit()
	_check(hub.modal.visible and hub.modal.standalone_actions.visible, "Hall returns to the same results")
	hub.modal.standalone_actions.get_child(0).pressed.emit()
	_check(hub.modal.active and hub.modal.is_guide_open(), "Replay starts a fresh guide")
	hub.modal.standalone_menu_requested.emit()
	hub.lobby_button.pressed.emit()
	await process_frame
	await process_frame
	_check(main.lobby_ui.visible and not is_instance_valid(main.standalone_minigames), "Arcade closes cleanly to the main screen")
	main.lobby_ui.minigames_button.pressed.emit()
	_check(main.standalone_minigames.menu.visible, "Arcade can be entered again")
	main.switch_to_lobby()
	main.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(records.profile_path)
	if failures.is_empty():
		print("[PASS] Arcade navigation, nine leaderboards, result, replay, lobby and re-entry")
	quit(0 if failures.is_empty() else 1)
