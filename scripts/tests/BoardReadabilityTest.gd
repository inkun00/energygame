extends SceneTree

## View-only board/HUD contracts. No scores or records are persisted.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _capture(name: String) -> void:
	if "--snapshots" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/readability-" + name + "-" + str(DisplayServer.window_get_size().x) + ".png")

func _run() -> void:
	var gm = root.get_node("GameManager")
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "에코 탐험대", "is_ai": false},
		{"name": "친구 2", "is_ai": true},
		{"name": "친구 3", "is_ai": true},
		{"name": "친구 4", "is_ai": true}
	]
	main._on_start_game_requested(configs, 300)
	gm.confirm_adventure_ready(0)
	gm.set_process(false)
	var board = main.game_board
	var hud = board.hud
	var planner = hud.adventure_planner
	_check(board.tile_markers.size() == 100, "All 100 board tiles remain")
	for marker in board.tile_markers:
		_check(marker.kind_badge != null and not marker.kind_label.text.is_empty(), "Every tile has a non-colour kind badge")
	var mini
	for marker in board.tile_markers:
		if marker.tile_data.get("type") == BoardGrid.TileType.MINIGAME:
			mini = marker
			break
	mini.set_minigame_completed(true)
	_check(mini.kind_label.text == "완료", "A completed minigame has an explicit completed badge")
	mini.set_minigame_completed(false)
	_check(mini.kind_label.text == "미니", "A new round resets the completion badge")
	board._refresh_board_player_focus(0)
	_check(board.player_pawns[0].board_turn_label.visible and board.player_pawns[0].board_turn_ring.visible, "Active player has a name and ring")
	_check(not board.player_pawns[1].board_turn_label.visible, "Inactive player does not add nameplate clutter")
	_check(board.player_pawns[0].board_model != null and board.player_pawns[1].board_model != null, "Default players use modeled board pawns")
	if board.player_pawns[0].board_model and board.player_pawns[1].board_model:
		_check(board.player_pawns[0].board_model.scale.x > board.player_pawns[1].board_model.scale.x, "Current player silhouette is larger")
	_check_modeled_roster(main.lobby_ui.characters, board.pawns_container)
	board._show_movement_route(0, 6)
	_check(board.movement_route_tiles == [0, 1, 2, 3, 4, 5, 6], "The actual rolled path has no missing tiles")
	_check(board.tile_markers[0].route_current and board.tile_markers[6].route_destination, "Route distinguishes current and destination")
	board._refresh_board_player_focus(0)
	_check(not board.tile_markers[6].route_ring.visible, "New turn clears the previous destination")
	var village = board.energy_fairy_village
	village.update_cutaway_view(Vector3(0, 8, 18), Vector3(0, 0, 8), true)
	_check(village.cutaway_hidden_count > 0, "Foreground scenery cutaway removes occluders")
	village.update_cutaway_view(Vector3(0, 40, 30), Vector3.ZERO, false)
	_check(village.cutaway_hidden_count == 0, "Overview restores decorative scenery")
	_check(not board.world3d.get_node("DirectionalLight3D").shadow_enabled, "Board avoids an expensive shadow-map pass")
	_check(board.world_environment.environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "Board shares matte linear lighting")
	var arcade_pawn := PlayerPawn.new()
	root.add_child(arcade_pawn)
	arcade_pawn.setup_player(gm.players[0])
	_check(arcade_pawn.board_model == null and arcade_pawn.avatar_sprite.visible and arcade_pawn.avatar_sprite.scale == Vector3.ONE, "Arcade pawn keeps its original sprite and contact size")
	arcade_pawn.queue_free()
	await create_timer(0.55).timeout
	_check(hud.center_dice_button.focus_mode == Control.FOCUS_ALL, "Dice is keyboard focusable")
	_check(not hud.turn_prompt_label.visible and not hud.get_node("TurnPromptPlate").visible, "Dice action does not have a duplicate central banner")
	for panel in hud.player_panel_nodes:
		_check(panel.find_child("StatLabel", true, false).get_theme_font_size("font_size") >= 20, "Player totals retain readable type")
	await _capture("board")
	planner.open_catalog()
	await process_frame
	_check(planner.recipe_cards[0].get_parent().columns == 1, "Recipes have one readable scrolling column")
	for button in planner.goal_buttons:
		_check(button.visible and button.focus_mode != Control.FOCUS_NONE, "Every recipe offers a discoverable keyboard-accessible goal action")
	await _capture("catalog")
	var before: Array = gm.players.duplicate(true)
	planner.select_goal(0)
	_check(gm.players == before, "Goal selection is presentation-only")
	planner.toggle_summary()
	await process_frame
	_check(planner.summary.get_global_rect().end.y <= 720.0, "Expanded material summary stays within the board: %s details %s" % [planner.summary.get_global_rect(), planner.summary_details.get_global_rect()])
	await _capture("summary")
	planner.toggle_summary()
	gm.guided_tutorial_active = true
	gm.guided_tutorial_step = "materials"
	hud._refresh_primary_action_controls()
	planner._refresh_visibility()
	_check(not planner.tutorial.visible, "Guided coach replaces the passive guide")
	_check(hud.center_dice_button.disabled, "Practice cannot roll outside its dice step")
	var roll_count: int = gm.players[0]["position"]
	hud._on_center_dice_pressed()
	_check(gm.current_state == gm.TurnState.WAIT_ACTION and int(gm.players[0]["position"]) == roll_count, "Direct dice action cannot bypass the practice stage guard")
	gm.guided_tutorial_step = "dice"
	hud._refresh_primary_action_controls()
	hud._on_dice_input_time_changed(0, 20)
	_check(not hud.center_dice_button.disabled and not hud.dice_value_label.text.contains("20"), "Practice dice is enabled without a fake countdown")
	gm.guided_tutorial_active = false
	gm.guided_tutorial_step = ""
	hud._refresh_primary_action_controls()
	board._on_player_moved(0, 0, 6)
	await create_timer(BoardGrid.get_movement_duration(0, 6) + 0.2).timeout
	_check(board.player_pawns[0].position.is_equal_approx(board.player_pawns[0]._get_tile_contact_position(6, PlayerPawn.PAWN_OFFSETS_3D[0])), "Animation ends at the unchanged tile contact position")
	await _capture("arrival")
	board._show_board_overview()
	var bounds := Rect2(Vector2.ZERO, Vector2(board.viewport.size))
	for index in range(100):
		var center := BoardGrid.get_tile_position_3d(index)
		_check(not board.camera3d.is_position_behind(center) and bounds.has_point(board.camera3d.unproject_position(center)), "Overview contains tile %d" % index)
	await _capture("overview")
	# Construction can now supply enough useful parts for every facility. Each
	# completion must have a valid decoration, including facilities five to ten.
	for count in range(1, gm.CONSTRUCTION_PROJECTS.size() + 1):
		board._on_kingdom_progress_changed(count, gm.CONSTRUCTION_PROJECTS.size(), mini(100, count * 25))
		_check(board.renewable_landmarks.get_child_count() == count, "Every completed facility gets one landmark: %d" % count)
	var landmark_positions: Dictionary = {}
	for landmark in board.renewable_landmarks.get_children():
		_check(landmark.mesh != null and landmark.material_override != null, "All ten landmarks have geometry and material")
		landmark_positions[Vector2(landmark.position.x, landmark.position.z)] = true
	_check(landmark_positions.size() == gm.CONSTRUCTION_PROJECTS.size(), "All ten landmarks occupy separate perimeter pads")
	board._on_kingdom_progress_changed(10, 10, 100)
	_check(board.renewable_landmarks.get_child_count() == 10, "Repeated progress cannot duplicate landmarks")
	gm.stop_game()
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("[PASS] Board readability: 100 tiles, active pawn, route, kind/completion badges, cutaway, readable HUD and practice input guard")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_modeled_roster(roster: Array, container: Node3D) -> void:
	var pawn := PlayerPawn.new()
	container.add_child(pawn)
	pawn.set_board_presentation(true)
	for character in roster:
		var portrait: String = character["icon"]
		var slug := portrait.get_file().get_basename()
		pawn.setup_player({"index": 0, "char_icon": portrait})
		_check(pawn.board_model != null and not pawn.avatar_sprite.visible, "%s uses a 3D board pawn" % slug)
		if not pawn.board_model or not pawn.board_animator:
			continue
		_check(pawn.board_model.scene_file_path.get_file() == slug + ".glb", "%s selects its own model" % slug)
		_check(pawn.board_animator.current_animation == "idle" and pawn.board_animator.has_animation("walk"), "%s provides an idle and a traveling gait" % slug)
		_check(pawn.board_animator.get_animation("idle").get_track_count() > 0 and pawn.board_animator.get_animation("walk").get_track_count() > 0, "%s animates its model" % slug)
	if pawn.board_model:
		pawn.setup_player({"char_icon": "res://assets/images/char_water_popo.webp"})
		_check(pawn.board_model.scene_file_path.ends_with("/water_popo.glb"), "Legacy portrait paths resolve to the same modeled character")
		pawn.animate_move_to_tile(1)
		pawn.move_tween.custom_step(BoardGrid.MOVE_STEP_SECONDS * 0.5)
		var stride_phase := fposmod(0.5 * BoardGrid.TILE_SPACING_3D / (pawn.board_model.scale.x * pawn.board_stride_length), 1.0)
		var walk_time := pawn.board_animator.current_animation_position
		_check(absf(walk_time / pawn.board_animator.current_animation_length - stride_phase) < 0.0001, "A half tile advances the authored gait by its actual distance")
		pawn._process(0.05)
		_check(is_equal_approx(pawn.board_animator.current_animation_position, walk_time), "A stationary board pawn does not advance its stride")
		_check(pawn.board_animator.current_animation == "walk" and pawn.board_model.rotation.y > 0.0 and pawn.board_model.rotation.y < PI * 0.5, "Regular movement turns gradually toward the travel direction")
		_check(absf(pawn.position.y - BoardGrid.get_tile_surface_height(1)) < 0.04, "Ordinary walking stays in contact with the tile")
		pawn._process(0.2)
		_check(pawn.board_model.basis.z.normalized().dot(Vector3.RIGHT) > 0.99, "The model faces along the row")
		pawn.set_process(false)
		pawn.move_tween.custom_step(BoardGrid.MOVE_STEP_SECONDS * 0.1)
		_check(is_equal_approx(pawn.board_animator.current_animation_position, walk_time), "A covered board keeps its rendered pose")
		pawn.set_process(true)
		pawn._process(0.01)
		_check(is_equal_approx(pawn.board_animator.current_animation_position, pawn.board_pose_time) and not is_equal_approx(pawn.board_pose_time, walk_time), "Restoring the board catches up to the traveled distance")
		pawn.snap_to_tile(8)
		pawn.animate_move_to_tile(10)
		pawn.move_tween.custom_step(BoardGrid.MOVE_STEP_SECONDS * 0.94)
		_check(pawn.board_target_yaw > PI * 0.5 and pawn.board_target_yaw < PI, "The pawn starts turning before the corner")
		pawn.snap_to_tile(9)
		pawn.animate_move_to_tile(10)
		pawn.move_tween.custom_step(BoardGrid.MOVE_STEP_SECONDS * 0.5)
		pawn._process(0.2)
		_check(pawn.board_model.basis.z.normalized().dot(Vector3.FORWARD) > 0.99, "The model turns at a board corner")
		pawn.snap_to_tile(10)
		_check(pawn.board_animator.current_animation == "idle" and is_zero_approx(pawn.shadow_mesh.position.y - pawn.GROUND_SHADOW_OFFSET), "Stopping restores idle and grounds the contact shadow")
		for tile in BoardGrid.TILE_DATA:
			if not tile.has("target"):
				continue
			pawn.snap_to_tile(int(tile.index))
			pawn.set_shield_active(true)
			pawn.animate_move_to_tile(int(tile.target))
			pawn.move_tween.custom_step(BoardGrid.SHORTCUT_MOVE_SECONDS * 0.5)
			var has_jump := pawn.board_animator.has_animation(&"jump")
			var expected_clip := &"jump" if has_jump else &"walk"
			var phase := pawn.board_animator.current_animation_position / pawn.board_animator.current_animation_length
			_check(pawn.board_shortcut_jump and pawn.board_animator.current_animation == expected_clip and is_equal_approx(phase, 0.5 if has_jump else 0.25), "Shortcut apex selects the flight pose of the model")
			_check(pawn.position.y > pawn.shadow_mesh.global_position.y + 1.5 and pawn.shield_visual.visible, "A shielded shortcut casts its shadow on the tile")
			break
	pawn.free()
