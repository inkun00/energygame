extends SceneTree

const INPUT = preload("res://scripts/minigames/MiniGameInput.gd")
var failures: Array[String] = []
var manager: Node
var modal: Node
var current_arcade: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[BClarity] " + message)

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("BClarity watchdog expired"); quit(1))
	manager = root.get_node("GameManager")
	root.get_node("NetworkManager").is_online = false
	var players: Array[Dictionary] = []
	for index in range(4):
		players.append({"name": "검사%d" % index, "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"})
	manager.setup_game(players, 600)
	manager.stop_game()
	modal = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	modal.set_process(false)
	for test in ["_test_sort", "_test_battery", "_test_bus", "_test_heat", "_test_gallery"]:
		var completed: Variant = await call(test)
		_check(completed == true, test + " must finish without a script/runtime error")
	if is_instance_valid(modal):
		modal.cancel_minigame()
		modal.queue_free()
	manager.stop_game()
	INPUT.release_all()
	await process_frame
	if failures.is_empty(): print("[PASS] BClarity: linked cargo, charge/store/discharge, aligned bus/three-lane entry, cooling comparison and responsive gallery")
	quit(0 if failures.is_empty() else 1)

func _open_game(game_id: String) -> Node:
	INPUT.release_all()
	var definition: Dictionary = manager.MINIGAME_DEFINITIONS[game_id].duplicate(true)
	definition["round_id"] = 7200
	definition["seed"] = 31
	modal._on_minigame_started(definition)
	modal._begin_local_round()
	modal.set_process(false)
	current_arcade = {"energy_sort": modal.sort_arcade, "battery_relay": modal.battery_arcade, "eco_commute": modal.commute_arcade, "heat_leak": modal.heat_arcade}[game_id]
	return current_arcade

func _capture(name: String) -> void:
	if "--snapshots" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	# Controlled-state captures do not run the modal clock. Hide the one-frame
	# action flash so it does not remain artificially frozen over the scene.
	if is_instance_valid(current_arcade):
		(current_arcade.get("flash") as ColorRect).color = Color.TRANSPARENT
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/qa-audit-b/clarity")
	root.get_texture().get_image().save_png("res://.godot/qa-audit-b/clarity/%s.png" % name)

func _test_sort() -> bool:
	var game := _open_game("energy_sort")
	var card: Sprite3D = game.icon_anchor.get_node("KenneyCargoCard")
	_check(card.texture.resource_path == "res://assets/open_source/kenney_adventure/panel_brown.webp", "Sort uses the existing Kenney parcel art")
	for step in range(6):
		game.item_step = step
		game._next_item()
		_check(game.carried_name.text == game.current_source["name"], "Each carried source has its actual name next to the hero")
		if game.current_source["shape"] == "coal":
			_check(game.source_shape.has_node("KenneyCoalRock"), "Coal reuses the imported Kenney rock, not an unrelated device")
	game.item_step = 0
	game._next_item()
	var nodes_before: int = game.world.get_child_count()
	INPUT.set_touch(KEY_D, true)
	for tick in range(15): game._process(1.0 / 60.0)
	INPUT.release_all()
	_check(is_equal_approx(game.icon_anchor.position.x - game.hero_x, 0.86) and game.icon_anchor.position.y < 1.3, "Parcel stays beside the right hand, not floating above the character")
	_check(game.world.get_child_count() == nodes_before, "Moving a parcel never allocates additional world objects")
	await _capture("sort-linked-cargo")
	game.hero_x = -game.DELIVERY_X
	game._deliver(0)
	_check(not game.hand_link.visible and not game.icon_anchor.visible and game.returning_to_center, "Delivery hides the parcel/handle throughout the natural return")
	return true

func _test_battery() -> bool:
	var game := _open_game("battery_relay")
	_check(game.get_flow_stage() == "collect" and game.flow_step_labels.size() == 3, "Battery starts with a visible three-stage flow and an empty store")
	game.hero_x = game.SOLAR_X
	game._try_station_action()
	game._update_visuals()
	_check(game.get_flow_stage() == "charge" and game.flow_step_labels[1].text.begins_with("▶"), "Taking spare electricity highlights the charging destination")
	game.hero_x = game.BATTERY_X
	game._try_station_action()
	game._update_visuals()
	_check(game.battery_units == 1 and game.get_flow_stage() == "stored" and game.transfer_pulses[0].visible, "Actual charging fills a cell and retains the short transfer feedback")
	await _capture("battery-stored")
	game.elapsed = 5.1
	game.charging_remaining = 0.0
	game._try_station_action()
	game._update_visuals()
	_check(game.cargo == 2 and game.get_flow_stage() == "discharge" and game.flow_step_labels[2].text.begins_with("▶"), "Only cloudy weather exposes the stored-energy supply step")
	game.hero_x = game.CITY_X
	game._try_station_action()
	game._update_visuals()
	_check(game.city_energy_remaining == 1.0 and game.get_flow_stage() == "supply" and game.city_windows[0].material_override == game.city_on_material, "A real city delivery keeps the light and supply feedback visible")
	await _capture("battery-supply")
	return true

func _test_bus() -> bool:
	var game := _open_game("eco_commute")
	_check(game.BUS_CAPACITY == 45 and int(manager.MINIGAME_DEFINITIONS["eco_commute"]["duration"]) == 60, "Bus keeps the 45-person / 60-second rules")
	game.bus_x = 12.0
	game.bus_speed = 2.0
	game._update_camera_and_bus()
	game._update_visuals()
	_check(game.service_label.text.contains("중앙 맞음") and game.parking_reference.position.x == 0.0, "The bus's visible centre marker matches the actual stop coordinate")
	game.bus_speed = 0.0
	game._update_visuals()
	_check(game.service_label.text.contains("Space"), "An aligned stopped bus visibly offers pickup")
	await _capture("bus-aligned-stop")
	game.passengers = 45
	game.bus_x = 56.8
	game.route_distance = 56.8
	game.elapsed = 60.0
	game.segments[0]["school_served"] = true
	game._unload_at_school(56.0)
	var students: Array = game.dropped_students.duplicate()
	_check(absf(float(students[0]["start_x"]) - (game.bus_x + 1.08)) <= 0.081, "Off-centre legal school stops still spawn pupils at the actual bus door")
	var lane_points: Array[Vector3] = []
	for index in range(3): lane_points.append(game.dropoff_path_position(students[index], 0.6))
	_check(lane_points[0].distance_to(lane_points[1]) > 0.25 and lane_points[1].distance_to(lane_points[2]) > 0.25, "Three walking lanes visibly separate students instead of one ghosted line")
	_check(game.get_finish_animation_seconds() > 3.0 and game.get_finish_animation_seconds() < 4.0, "All 45 walking animations fit the existing bounded result handoff")
	var final_score: int = modal.score
	var delivered: int = game.delivered_total
	game.begin_finish_animation()
	game.advance_finish_animation(0.85)
	await _capture("bus-three-lane-entry")
	for tick in range(240): game.advance_finish_animation(1.0 / 60.0)
	_check(not game.has_pending_finish_animation() and game.elapsed == 60.0 and game.bus_x == 56.8 and game.delivered_total == delivered and modal.score == final_score, "Cosmetic entry preserves the submitted time, position, learning count and score")
	return true

func _test_heat() -> bool:
	var game := _open_game("heat_leak")
	var window: Dictionary = {}
	for candidate in game.windows:
		if candidate["open"]:
			window = candidate
			break
	game.hero_x = float(window["x"])
	game.hero.position.x = game.hero_x
	game._animate_heat(0.4)
	game._update_overlay()
	_check(str(window["status"].text).contains("열림") and window["particles"][0].visible, "Open windows pair a visible opening with incoming hot air and a written state")
	var first_particle: Vector3 = window["particles"][0].position
	game.elapsed += 0.2
	game._animate_heat(0.0)
	_check(window["particles"][0].position.z > first_particle.z, "Hot air travels from the outside plane into the classroom")
	await _capture("heat-open-influx")
	game._try_close()
	_check(is_equal_approx(game.usage_before_close - game.usage_after_close, game.OPEN_WINDOW_USE), "The closing comparison uses the actual per-window reduction")
	_check(game.preview_label.text.contains("→") and game.preview_label.text.contains("냉방"), "After closing, the power comparison explains that cooling continues")
	_check(str(window["status"].text) == "닫힘" and not window["particles"][0].visible and game.cool_air.size() == 4, "A closed window stops hot influx while blue cooling air remains")
	await _capture("heat-closed-comparison")
	return true

func _test_gallery() -> bool:
	modal.cancel_minigame()
	modal.queue_free()
	await process_frame
	# Load after autoload registration; preloading the full modal from a runner
	# can compile its GameManager references before that singleton exists.
	var gallery: Node = load("res://scripts/ui/StandaloneMiniGames.gd").new()
	root.add_child(gallery)
	gallery._show_menu()
	for dimensions in [Vector2i(1366, 768), Vector2i(1024, 600)]:
		root.size = dimensions
		gallery._update_menu_layout()
		await process_frame
		await process_frame
		_check(gallery.card_buttons.size() == 9 and gallery.cards_grid.columns == (2 if dimensions.x < 1150 else 3), "Gallery adapts nine cards to two or three columns")
		for button in gallery.card_buttons:
			var picture := button.find_child("ScenePreview", true, false) as TextureRect
			var action := button.find_child("MissionAction", true, false) as Label
			_check(picture.texture != null and picture.size.y >= 116.0 and action.autowrap_mode == TextServer.AUTOWRAP_OFF, "Each mission has a larger image and one action line")
		gallery.card_buttons[8].grab_focus()
		await process_frame
		await process_frame
		await _capture("gallery-%dx%d" % [dimensions.x, dimensions.y])
		_check(gallery.cards_scroll.scroll_vertical > 0, "Keyboard focus scrolls the final card into view")
		var last_rect: Rect2 = gallery.card_buttons[8].get_global_rect()
		var scroll_rect: Rect2 = gallery.cards_scroll.get_global_rect()
		_check(last_rect.position.y >= scroll_rect.position.y - 1.0 and last_rect.end.y <= scroll_rect.end.y + 1.0, "The focused final card is not clipped below the scroll viewport")
		var expected: NodePath = gallery.card_buttons[mini(8, gallery.cards_grid.columns)].get_path()
		_check(gallery.card_buttons[0].focus_neighbor_bottom == expected, "Down navigation follows the current card column count")
	gallery.current_game_id = "battery_relay"
	gallery._show_menu()
	await process_frame
	await process_frame
	_check(root.gui_get_focus_owner() == gallery.card_buttons[6], "Returning to the gallery restores focus without storing player records")
	gallery.queue_free()
	await process_frame
	return true
