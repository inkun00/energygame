extends SceneTree

# Check visual inventory against the real inventory, including a smaller laptop.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	create_timer(35).timeout.connect(func(): quit(1))
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var gm = root.get_node("GameManager")
	var configs: Array[Dictionary] = [{"name": "탐험대", "is_ai": false}]
	main._on_start_game_requested(configs)
	gm.set_process(false)
	gm.confirm_adventure_ready(0)
	var planner = main.game_board.hud.adventure_planner
	planner.dismiss_tutorial()
	planner.refresh({"solar_panel": 1})
	var slots: Array = planner.recipe_slots[0]
	_check(slots.size() == 3, "Solar recipe shows two panel sockets and one grid socket")
	_check(slots[0]["filled"] and not slots[1]["filled"] and not slots[2]["filled"], "One collected panel fills only one socket")
	planner.refresh({"solar_panel": 2, "smart_grid": 1})
	for slot in slots:
		_check(slot["filled"], "Complete recipe fills all actual part sockets")
	planner.refresh({})
	for slot in slots:
		_check(not slot["filled"], "A new inventory clears previous socket state")
	for dimensions in [Vector2(1280, 720), Vector2(1024, 600)]:
		planner.size = dimensions
		planner._apply_summary_layout()
		await process_frame
		await process_frame
		_check(planner.summary.size.y <= 64, "Collapsed bag leaves room for the board at %s" % dimensions)
		_check(planner.summary.get_rect().end.y <= dimensions.y, "Bag remains inside %s" % dimensions)
		planner.open_catalog()
		await process_frame
		await process_frame
		var panel: Control = planner.catalog.get_child(1)
		_check(panel.get_rect().end.x <= dimensions.x and panel.get_rect().end.y <= dimensions.y, "Catalog fits %s: %s" % [dimensions, panel.get_rect()])
		for index in range(planner.recipe_cards.size()):
			var card: Control = planner.recipe_cards[index]
			var action: Control = planner.goal_buttons[index]
			_check(action.get_global_rect().end.x <= card.get_global_rect().end.x, "Recipe action fits its card")
		planner.close_catalog()
	gm.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("[PASS] Design polish: actual part sockets, reset, compact bag and two laptop layouts")
	quit(0 if failures.is_empty() else 1)
