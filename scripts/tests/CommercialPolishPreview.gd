extends SceneTree

const UI = preload("res://scripts/ui/CommercialUI.gd")
var failures: Array[String] = []
var capture := false

func _initialize() -> void:
	capture = "--snapshots" in OS.get_cmdline_user_args()
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func snapshot(filename: String) -> void:
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + filename + ".png")

func _run() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.1).timeout
	var lobby: Node = main.get_node("LobbyUI")
	var network: Node = root.get_node("NetworkManager")
	var manager: Node = root.get_node("GameManager")
	var button := Button.new()
	root.add_child(button)
	for repeat in range(6):
		UI.apply_primary_button(button)
		UI.apply_secondary_button(button)
	check(button.pressed.get_connections().size() == 1, "State refresh must not duplicate click feedback")
	check(button.button_down.get_connections().size() == 1, "State refresh must not duplicate press animation")
	button.button_down.emit()
	await create_timer(0.1).timeout
	button.button_up.emit()
	await create_timer(0.15).timeout
	check(button.scale.is_equal_approx(Vector2.ONE), "Release must restore button scale")
	button.queue_free()
	network.is_online = true
	network.is_host = true
	network.my_peer_id = 1
	network.room_code = "123456"
	var roster := {}
	for index in range(4):
		roster[index + 1] = {"name": ["에너지탐험대장", "바람을모으는친구", "물방울친구", "햇빛탐험가"][index], "char_icon": lobby.characters[index]["icon"]}
	lobby._on_room_state_changed(roster)
	await process_frame
	await process_frame
	check(lobby._room_portraits.size() == 4, "Every joined player must appear on the departure stage")
	check(lobby._room_cards.get_global_rect().end.x <= 1280, "Four departure characters must fit horizontally")
	check(lobby._room_start_button.get_global_rect().end.y <= 720, "Departure action must fit vertically")
	await snapshot("commercial_room_polish")
	network.disconnect_network()
	lobby._room_popup.hide()
	var configs: Array[Dictionary] = []
	for index in range(4):
		configs.append({"name": roster[index + 1]["name"], "char_icon": lobby.characters[index]["icon"], "char_color": lobby.characters[index]["color"], "is_ai": false})
	main._on_start_game_requested(configs)
	manager.set_process(false)
	var hud: Node = main.find_child("HUD", true, false)
	hud.adventure_planner.dismiss_tutorial()
	hud.adventure_planner.dismiss_tutorial()
	for active in range(4):
		manager.current_turn_idx = active
		hud.update_all_player_panels()
		await process_frame
		await process_frame
		for index in range(4):
			var panel: Control = hud.player_panel_nodes[index]
			check(panel.get_global_rect().end.x <= 1280, "Player card %d must fit when %d is active" % [index, active])
			check(panel.size.y >= 80 if index == active else panel.size.y <= 68, "Only the current player card should expand")
	manager.current_turn_idx = 0
	hud.update_all_player_panels()
	hud._show_event_banner("태양광 패널 +1")
	await create_timer(0.3).timeout
	check(hud.event_banner.size.y <= 60, "A short event should stay a small toast after a longer status")
	await snapshot("commercial_board_polish")
	manager.players[0]["inventory"]["solar_panel"] = 1
	manager.player_inventory_changed.emit(0, manager.players[0]["inventory"])
	await create_timer(0.3).timeout
	check(hud._reward_flight_count == 1, "A new local material must fly toward the bag once")
	await snapshot("commercial_material_delivery")
	await create_timer(1.2).timeout
	check(hud._reward_flight_count == 0, "Reward animation must clean itself up")
	hud._play_material_delivery("solar_panel", 1)
	hud._show_event_banner("태양광 패널 +1")
	hud._on_learning_stage_visibility_changed(true)
	check(not hud.event_banner.visible and hud._reward_flight_count == 0, "Learning overlays must clear board reward feedback")
	manager.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] Commercial polish: four-player layout, departure stage, one-shot feedback and reward delivery")
	quit(0 if failures.is_empty() else 1)
