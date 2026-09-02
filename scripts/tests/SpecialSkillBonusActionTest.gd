extends SceneTree

## 이동형 특수기술 완료 후 같은 턴에 주사위를 굴릴 수 있는지 실제 HUD까지 검증합니다.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp", "char_color": Color("49d97b")},
		{"name": "태양 여우 솔", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/solar_fox_sol.webp", "char_color": Color("ffd24a")},
		{"name": "물방울 정령 포포", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/water_popo.webp", "char_color": Color("49bfff")},
		{"name": "번개새 피카", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/lightning_bird_pika.webp", "char_color": Color("ff9d3d")}
	]
	main._on_start_game_requested(configs)
	await create_timer(0.55).timeout
	var game_manager: Node = root.get_node("GameManager")
	var hud: Node = main.get_node("GameBoard/UILayer/HUD")
	game_manager.players[0]["skill_energy"] = 3
	game_manager.player_state_changed.emit(0)
	hud._on_special_skill_pressed()
	hud.try_select_special_skill_tile(4)
	if not hud.center_dice_button.disabled:
		push_error("특수 이동 연출 중에는 주사위 버튼이 잠겨야 합니다.")
		quit(1)
		return
	await create_timer(2.8).timeout
	if game_manager.current_state != game_manager.TurnState.WAIT_ACTION:
		push_error("특수 이동 완료 후 같은 턴의 행동 대기로 돌아오지 않았습니다.")
		quit(1)
		return
	if hud.center_dice_button.disabled:
		push_error("특수 이동 완료 후 주사위 버튼이 다시 활성화되지 않았습니다.")
		quit(1)
		return
	if not game_manager.special_skill_used_this_turn or not hud.special_skill_button.disabled:
		push_error("같은 턴의 특수기술 재사용은 차단되어야 합니다.")
		quit(1)
		return
	hud.center_dice_button.pressed.emit()
	if game_manager.current_state != game_manager.TurnState.ROLLING_DICE:
		push_error("특수기술 이후 주사위 굴림이 시작되지 않았습니다.")
		quit(1)
		return
	print("[PASS] Special skill remains separate from the dice action")
	quit(0)
