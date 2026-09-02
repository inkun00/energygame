extends SceneTree

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("--- Starting UI Click Simulation Test ---")
	
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await create_timer(0.2).timeout
	
	var lobby = main.get_node("LobbyUI")
	var start_button = lobby.get_node("MenuPanel/Content/LocalStartButton") as Button
	
	print("[TEST] Start button visible: %s, disabled: %s, global_pos: %s, size: %s" % [
		start_button.is_visible_in_tree(),
		start_button.disabled,
		start_button.global_position,
		start_button.size
	])
	
	var btn_center = start_button.global_position + start_button.size * 0.5
	print("[TEST] Simulating real mouse click on Start Button at position %s..." % btn_center)
	
	var mb_down = InputEventMouseButton.new()
	mb_down.button_index = MOUSE_BUTTON_LEFT
	mb_down.pressed = true
	mb_down.position = btn_center
	mb_down.global_position = btn_center
	root.push_input(mb_down)
	
	await process_frame
	await create_timer(0.05).timeout
	
	var mb_up = InputEventMouseButton.new()
	mb_up.button_index = MOUSE_BUTTON_LEFT
	mb_up.pressed = false
	mb_up.position = btn_center
	mb_up.global_position = btn_center
	root.push_input(mb_up)
	
	await process_frame
	await create_timer(0.6).timeout
	
	print("[TEST] Result after Start Button Click: LobbyUI.visible = %s, GameBoard.visible = %s" % [
		lobby.visible,
		main.get_node("GameBoard").visible
	])

	# 인게임 주사위 버튼 테스트
	var game_board = main.get_node("GameBoard")
	if game_board.visible:
		var dice_button = game_board.get_node("UILayer/HUD/CenterDiceButton") as Button
		print("[TEST] Dice button visible: %s, disabled: %s, pos: %s, size: %s" % [
			dice_button.is_visible_in_tree(),
			dice_button.disabled,
			dice_button.global_position,
			dice_button.size
		])
		var d_center = dice_button.global_position + dice_button.size * 0.5
		var d_down = InputEventMouseButton.new()
		d_down.button_index = MOUSE_BUTTON_LEFT
		d_down.pressed = true
		d_down.position = d_center
		d_down.global_position = d_center
		root.push_input(d_down)
		await process_frame
		var d_up = InputEventMouseButton.new()
		d_up.button_index = MOUSE_BUTTON_LEFT
		d_up.pressed = false
		d_up.position = d_center
		d_up.global_position = d_center
		root.push_input(d_up)
		await process_frame
		await create_timer(0.5).timeout
		var gm = root.get_node_or_null("GameManager")
		if gm:
			print("[TEST] Dice roll state in GameManager: %s" % gm.current_state)

	quit(0)
