extends SceneTree

const RULES = preload("res://scripts/core/VillagePlacementRules.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm := root.get_node("GameManager")
	var configs: Array[Dictionary] = []
	for idx in range(4):
		configs.append({"name": "Builder %d" % idx, "is_ai": false})
	gm.setup_game(configs, 60)
	for player in gm.players:
		for item_id in gm.ITEM_DEFINITIONS:
			player["inventory"][item_id] = 3
	gm._start_village_construction_phase()
	var initial_inventory: Dictionary = gm.get_team_inventory()
	var initial_players: Array = gm.players.duplicate(true)
	_check(not gm.build_village_project(0, 0, Vector2(0.14, 0.71)), "wrong terrain is rejected")
	_check(not gm.build_village_project(0, 0, Vector2(700, 200)), "screen-pixel positions are rejected")
	_check(not gm.build_village_project(0, 0, Vector2(NAN, 0.18)), "nonfinite positions are rejected")
	_check(gm.get_team_inventory() == initial_inventory and gm.players == initial_players, "rejected placements spend no material or energy")
	_check(gm.build_village_project(2, 0, Vector2(0.71, 0.36)), "first online builder claims a shared city cell")
	var claimed_players: Array = gm.players.duplicate(true)
	var claimed_inventory: Dictionary = gm.get_team_inventory()
	_check(not gm.build_village_project(8, 1, Vector2(0.71, 0.36)), "different facility cannot overlap another builder")
	_check(gm.get_team_inventory() == claimed_inventory and gm.players == claimed_players, "collision rejection has no reward or material side effects")
	_check(gm.build_village_project(8, 1, Vector2(0.81, 0.41)), "same builder can retry the next free city cell")
	_check(gm.built_project_owners[2] == 0 and gm.built_project_owners[8] == 1, "accepted cells preserve distinct ownership")
	_check(gm.built_project_placements[2] == Vector2(0.71, 0.36) and gm.built_project_placements[8] == Vector2(0.81, 0.41), "wire state stores normalized canonical cells")
	_check(gm.build_village_project(3, 2), "AI/default construction selects a suitable free cell")
	_check(gm.build_village_project(9, 3), "default placement skips the occupied shared terrain cell")
	_check(gm.built_project_placements[3] != gm.built_project_placements[9], "default constructions never overlap")
	var all_solar_cells := {}
	for idx in range(RULES.PLACEMENT_CELLS["solar_field"].size()):
		all_solar_cells[idx] = RULES.PLACEMENT_CELLS["solar_field"][idx]
	_check(RULES.resolve_placement(gm.CONSTRUCTION_PROJECTS[0], RULES.INVALID_POSITION, all_solar_cells) == RULES.INVALID_POSITION, "full terrain has no default placement")
	gm.stop_game()
	if failures == 0:
		print("[PASS] Four-player construction placement rules · %d checks" % checks)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("[FAIL] " + label)
