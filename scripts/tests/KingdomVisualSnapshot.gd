extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp", "char_color": Color("#49d97b")},
		{"name": "태양 여우 솔", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/solar_fox_sol.webp", "char_color": Color("#ffd24a")},
		{"name": "물방울 정령 포포", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/water_popo.webp", "char_color": Color("#49bfff")},
		{"name": "번개새 피카", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/lightning_bird_pika.webp", "char_color": Color("#ff9d3d")},
	]
	main._on_start_game_requested(configs)
	await create_timer(0.5).timeout
	var game_manager: Node = root.get_node("GameManager")
	for player_idx in range(game_manager.players.size()):
		game_manager.players[player_idx]["inventory"] = game_manager._create_empty_inventory()
	game_manager.players[0]["inventory"]["recycled_composite"] = 2
	game_manager.players[0]["inventory"]["smart_grid"] = 1
	game_manager.players[1]["inventory"]["fast_charge_module"] = 2
	game_manager.players[1]["inventory"]["battery"] = 1
	game_manager._start_village_construction_phase()
	await create_timer(0.5).timeout
	var village_map: Node = main.find_child("VillageMap", true, false)
	village_map._can_drop_data(village_map.get_terrain_build_cell_center("eco_city", 1), village_map.create_drop_payload(8, 0))
	await process_frame
	if not _save_frame("res://.godot/kingdom_build_preview.png"):
		quit(1)
		return

	village_map._drop_data(village_map.get_terrain_build_cell_center("eco_city", 1), village_map.create_drop_payload(8, 0))
	village_map._drop_data(village_map.get_terrain_build_cell_center("grid_hub", 1), village_map.create_drop_payload(9, 1))
	game_manager.evaluate_village()
	await create_timer(0.8).timeout
	if not _save_frame("res://.godot/kingdom_failure_ending_preview.png"):
		quit(1)
		return
	var hud: Node = main.get_node("GameBoard/UILayer/HUD")
	if is_instance_valid(hud.ending_cinematic):
		hud.ending_cinematic._finish()
	game_manager.kingdom_health = 80
	game_manager.kingdom_recovered = true
	hud._play_ending_cinematic(true, [])
	await create_timer(0.8).timeout
	if not _save_frame("res://.godot/kingdom_success_ending_preview.png"):
		quit(1)
		return
	if is_instance_valid(hud.ending_cinematic):
		hud.ending_cinematic._finish()
	await process_frame
	if not hud.victory_modal.visible:
		push_error("엔딩 애니메이션 종료 후 결과 화면이 열리지 않았습니다.")
		quit(1)
		return
	print("[PASS] Kingdom visual previews captured")
	quit(0)

func _save_frame(path: String) -> bool:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("왕국 시각 미리보기 저장 실패: %s" % error)
		return false
	return true
