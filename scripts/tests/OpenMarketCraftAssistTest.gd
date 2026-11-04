extends SceneTree

# Keep the established runner path while testing the shared planning that
# replaces exchanging the same materials before pooled construction.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("[FAIL] " + message)

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var hud: Node = main.find_child("HUD", true, false)
	var configs: Array[Dictionary] = []
	for idx in range(4):
		configs.append({"name": "계획 친구 %d" % idx, "is_ai": false})
	main._on_start_game_requested(configs, 600)
	gm.confirm_adventure_ready(0)
	await process_frame
	gm.set_process(false)
	var buildable: Array = hud._get_player_buildable_projects({"solar_panel": 2, "smart_grid": 1})
	var found_solar := false
	for project: Dictionary in buildable:
		found_solar = found_solar or project["name"] == "태양광 발전소"
	check(found_solar, "solar panels plus a grid connection build solar without mandatory storage")
	var opportunity: Dictionary = hud._get_item_completion_opportunity("smart_grid", {"solar_panel": 2})
	check(opportunity["completes"].has("태양광 발전소"), "the missing grid connection completes the solar recipe")
	gm.players[0]["inventory"]["solar_panel"] = 2
	gm.players[1]["inventory"]["smart_grid"] = 1
	gm.players[2]["inventory"]["battery"] = 2
	gm.players[3]["inventory"]["smart_grid"] = 1
	var inventory_before: Dictionary = gm.get_team_inventory().duplicate(true)
	gm._start_team_planning_phase()
	await process_frame
	var planner: Node = hud.learning_village_ui
	check(planner.visible and planner.screen == "plan", "the shared plan opens after exploration")
	check(not hud.open_market_panel.visible, "material trading does not cover the shared plan")
	check(planner.plan_buttons.size() == gm.CONSTRUCTION_PROJECTS.size(), "all ten facility choices are available in the plan")
	check(planner.plan_recipe_labels[0].text == "건설 가능" and planner.plan_recipe_labels[3].text == "건설 가능", "recipe readiness counts friends' materials")
	planner._recommend_project(3)
	check(gm.team_plan["choices"][0] == 3, "a facility card updates the player's shared recommendation")
	check(planner.plan_player_labels[0].text.contains(gm.CONSTRUCTION_PROJECTS[3]["name"]), "the recommendation is visible to the team")
	planner._confirm_plan()
	check(gm.team_plan["ready"].has(0) and planner.plan_ready_button.disabled, "confirmation stays visible while waiting for friends")
	check(gm.get_team_inventory() == inventory_before, "proposing and confirming never transfers or consumes materials")
	for idx in range(1, 4):
		gm.confirm_team_plan(idx)
	await process_frame
	check(gm.village_construction_active and planner.screen == "", "the plan closes when team construction opens")
	check(gm.build_village_project(0, 0), "the proposed plan can use pooled parts to build solar")
	check(gm.build_village_project(3, 1), "a separate storage facility uses the remaining battery parts")
	check(gm.get_team_inventory()["solar_panel"] == 0 and gm.get_team_inventory()["battery"] == 0 and gm.get_team_inventory()["smart_grid"] == 0, "only actual buildings consume the exact team recipes")
	gm.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] Shared facility planning and recipe assistance")
	quit(0 if failures.is_empty() else 1)
