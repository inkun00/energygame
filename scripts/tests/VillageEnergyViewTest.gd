extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(1))
	var gm: Node = root.get_node("GameManager")
	var configs: Array[Dictionary] = []
	for player_name in ["하나", "둘", "셋", "넷"]: configs.append({"name": player_name, "is_ai": false})
	gm.setup_game(configs, 600)
	gm.set_process(false)
	var placement_rules = load("res://scripts/core/VillagePlacementRules.gd")
	var trial_rules = load("res://scripts/core/VillageEnergyTrial.gd")
	for project_id in range(gm.CONSTRUCTION_PROJECTS.size()):
		gm.built_project_ids.append(project_id)
		gm.built_project_placements[project_id] = placement_rules.resolve_placement(gm.CONSTRUCTION_PROJECTS[project_id], Vector2(-1, -1), gm.built_project_placements)
		gm.built_project_owners[project_id] = project_id % 4
	var state: Dictionary = trial_rules.create_state(gm.built_project_ids, 4)
	var view: Control = load("res://scripts/ui/VillageEnergyView.gd").new()
	view.size = Vector2(1184, 380)
	root.add_child(view)
	await process_frame
	view.update_snapshot(state, 0)
	check(view.village_map.get_placed_project_count() == 10, "All ten built facilities continue into the energy trial")
	check(not view.village_map.drop_enabled, "The trial cannot move or build facilities")
	check(view.village_map.find_children("AssemblyParts*", "", false, false).is_empty(), "Already built facilities are not reconstructed when the trial opens")
	for dimensions in [Vector2(1184, 380), Vector2(928, 280), Vector2(1184, 380)]:
		view.size = dimensions
		await process_frame
		var map: Control = view.village_map
		var expected_aspect: float = float(map.MAP_TEXTURE.get_width()) / float(map.MAP_TEXTURE.get_height())
		check(absf(map.size.x / map.size.y - expected_aspect) < 0.001, "Village image keeps its original proportions after resize")
		for project_id in gm.built_project_ids:
			var facility: Control = map.placed_project_nodes[project_id]
			var normalized: Vector2 = gm.built_project_placements[project_id]
			var expected: Vector2 = map._clamp_icon_position(normalized * map.size - map.BUILDING_SIZE * 0.5)
			check(facility.position.distance_to(expected) < 0.01, "Built facility %d remains at the host's normalized cell after resize" % project_id)
			check(facility.get_node_or_null("OwnerBadge") != null, "Facility %d keeps its construction owner" % project_id)
	var elapsed_before: float = state["elapsed"]
	view._process(3.0)
	check(state["elapsed"] == elapsed_before and view.snapshot["elapsed"] == elapsed_before, "Presentation animation cannot advance the authoritative trial")
	for idx in range(4): trial_rules.set_mode(state, idx, "store")
	trial_rules.advance(state, 20.0)
	view.update_snapshot(state, 0)
	check(view.snapshot["phase"] == "night" and view.snapshot["battery"] == state["battery"], "Night and storage visualization use the delivered snapshot")
	var stored_before: float = view.snapshot["battery"]
	state["battery"] = -99.0
	check(view.snapshot["battery"] == stored_before, "The view owns a snapshot copy, never a mutable simulation reference")
	view.queue_free()
	gm.stop_game()
	await process_frame
	if failures.is_empty(): print("[PASS] Village energy view: ten real placements, resize, ownership, immutable snapshots, no simulation clock")
	quit(0 if failures.is_empty() else 1)
