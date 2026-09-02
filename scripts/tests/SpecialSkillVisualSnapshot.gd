extends SceneTree

## 특수기술의 대상 지정 안내 화면을 눈으로 검증하는 스냅샷입니다.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.png", "char_color": Color("#49d97b")},
		{"name": "태양 여우 솔 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/solar_fox_sol.png", "char_color": Color("#ffd24a")},
		{"name": "물방울 정령 포포 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/water_popo.png", "char_color": Color("#49bfff")},
		{"name": "번개새 피카 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/lightning_bird_pika.png", "char_color": Color("#ff9d3d")},
	]
	main._on_start_game_requested(configs)
	await create_timer(0.55).timeout
	var game_manager = root.get_node("GameManager")
	game_manager.players[0]["skill_energy"] = 3
	game_manager.player_state_changed.emit(0)
	var hud = main.get_node("GameBoard/UILayer/HUD")
	hud._on_special_skill_pressed()
	assert(hud.special_skill_target_panel.visible)
	await process_frame
	if not _save_frame("res://.godot/special_skill_preview.png"):
		quit(1)
		return
	assert(hud.try_select_special_skill_tile(4))
	await create_timer(0.42).timeout
	var world3d: Node = main.get_node("GameBoard/ViewportContainer/SubViewport/World3D")
	assert(world3d.find_child("SpecialSkillEffect3D", true, false) != null)
	assert(hud.find_child("SpecialSkillCinematic", true, false) != null)
	if not _save_frame("res://.godot/special_skill_effect_preview.png"):
		quit(1)
		return
	await create_timer(2.45).timeout
	assert(game_manager.current_state == game_manager.TurnState.WAIT_ACTION)
	assert(not hud.center_dice_button.disabled)
	assert(hud.special_skill_button.disabled)
	if not _save_frame("res://.godot/special_skill_dice_ready_preview.png"):
		quit(1)
		return
	print("[PASS] Special skill targeting and animation previews captured")
	quit(0)


func _save_frame(path: String) -> bool:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("특수기술 미리보기 저장 실패: %s" % error)
		return false
	return true
