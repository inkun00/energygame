extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var players: Array[Dictionary] = [
		{"name": "캡틴 에코 · 나", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"},
		{"name": "태양 여우 솔", "is_ai": true},
		{"name": "물방울 포포", "is_ai": true},
		{"name": "바람 토끼 보리", "is_ai": true},
	]
	main._on_start_game_requested(players, 600)
	await create_timer(0.35).timeout
	root.get_node("GameManager")._start_minigame(0, "eco_commute")
	await create_timer(0.75).timeout
	var image := root.get_texture().get_image()
	var first_error := image.save_png("res://.godot/shared_school_bus_start.png")
	var modal := root.find_child("MiniGameModal", true, false)
	if modal and modal.commute_arcade:
		var game = modal.commute_arcade
		game.bus_x = game.STOP_OFFSETS[0]
		game._animate_bus_door(0.5)
		game._update_camera_and_bus()
		game._update_visuals()
	await create_timer(0.12).timeout
	image = root.get_texture().get_image()
	var door_error := image.save_png("res://.godot/shared_school_bus_open_door.png")
	if modal and modal.commute_arcade:
		var game = modal.commute_arcade
		game._attempt_pickup()
		game.bus_x = game.STOP_OFFSETS[1] - 2.0
		game.route_distance = game.bus_x
		game._update_camera_and_bus()
		game._update_visuals()
	await create_timer(0.12).timeout
	image = root.get_texture().get_image()
	var second_error := image.save_png("res://.godot/shared_school_bus_riders.png")
	if modal and modal.commute_arcade:
		var game = modal.commute_arcade
		game.passengers = game.BUS_CAPACITY
		game.bus_x = game.SCHOOL_OFFSET
		game.bus_speed = 0.0
		game.route_distance = game.SCHOOL_OFFSET
		game._update_camera_and_bus()
		game._check_school_stop()
		game._update_visuals()
	await create_timer(0.75).timeout
	image = root.get_texture().get_image()
	var third_error := image.save_png("res://.godot/shared_school_bus_dropoff.png")
	await create_timer(1.6).timeout
	image = root.get_texture().get_image()
	var entry_error := image.save_png("res://.godot/shared_school_bus_school_entry.png")
	var success := first_error == OK and door_error == OK and second_error == OK and third_error == OK and entry_error == OK
	print("[SharedBusVisual] %s" % ("PASS" if success else "FAIL"))
	quit(0 if success else 1)
