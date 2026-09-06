extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	assert(not main.session_open)
	main.request_game_exit()
	assert(not main.exit_confirmation.visible)
	var configs: Array[Dictionary] = [{"name": "탐험가", "is_ai": false}]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.15).timeout
	var gm = root.get_node("GameManager")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main._input(escape)
	assert(main.exit_confirmation.visible and main.session_open and gm.is_game_active)
	main.exit_confirmation.get_cancel_button().pressed.emit()
	assert(not main.exit_confirmation.visible and main.session_open and gm.is_game_active)
	gm.players[0]["inventory"]["solar_panel"] = 2
	gm._start_open_market_phase()
	main.request_game_exit()
	assert(main.exit_confirmation.visible and main.session_open and gm.open_market_active)
	main.exit_confirmation.confirmed.emit()
	assert(not main.session_open and main.lobby_ui.visible and not gm.open_market_active)
	main._on_start_game_requested(configs, 600)
	main.request_game_exit()
	main._on_network_server_disconnected()
	assert(not main.session_open and not main.exit_confirmation.visible)
	main.queue_free()
	await process_frame
	print("[PASS] Exit confirmation: Escape, cancel, market, confirm, disconnect")
	quit()
