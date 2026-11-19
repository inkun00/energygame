extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, reason: String) -> void:
	if not value:
		failures.append(reason)
		push_error(reason)

func _run() -> void:
	var gm := root.get_node("GameManager")
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	var initial_mute := AudioServer.is_bus_mute(0)
	var original_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	root.add_child(main)
	await process_frame
	var hud: Node = main.game_board.hud
	main.lobby_ui._on_sound_pressed()
	var configs: Array[Dictionary] = [{"name": "탐험대장", "is_ai": false}, {"name": "친구", "is_ai": true}]
	main._on_start_game_requested(configs, 600)
	await process_frame
	check(hud.sound_muted == AudioServer.is_bus_mute(0), "Board reflects the lobby mute state")
	hud._on_sound_pressed()
	check(AudioServer.is_bus_mute(0) == initial_mute, "One board press toggles the real mixer")
	gm.start_first_turn()
	hud.adventure_planner.dismiss_tutorial()
	check(not hud.special_skill_button.visible and hud.adventure_planner.heading_label.text == "팀 목표", "First-turn HUD offers the team goal before a locked skill")
	var pawn: PlayerPawn = main.game_board.player_pawns[0]
	var faces: Dictionary = {}
	for character in main.lobby_ui.characters:
		var icon: String = character["icon"]
		pawn.setup_player({"index": 0, "char_icon": icon})
		var face := preload("res://scripts/ui/HeroFace.gd").for_portrait(icon) as AtlasTexture
		check(pawn.board_face.texture == face and not faces.has(face.region), "Each 3D hero shares its distinct portrait badge with the HUD")
		faces[face.region] = true
	check(faces.size() == 9, "The face atlas covers all nine heroes")
	var skill: Dictionary = gm.get_player_special_skill(0)
	gm.players[0]["skill_energy"] = int(skill["cost"])
	hud._on_player_state_changed(0)
	check(hud.special_skill_button.visible and hud.event_banner_label.text.contains("SP"), "First affordable special action explains quiz SP on the board")
	var modal: Node = main.game_board.minigame_modal
	for game_id in gm.MINIGAME_DEFINITIONS:
		modal.game_id = game_id
		modal._configure_touch_controls()
		var bindings: Dictionary = MiniGameInput.ACTION_KEYS[game_id]
		for holder in modal.touch_controls.get_children():
			var code: int = holder.get_meta("input_key")
			check(holder.visible == bindings.has(code), "Only playable touch actions appear in " + game_id)
			if holder.visible:
				check(holder.get_child(1).text == bindings[code], "Touch caption follows the real input binding")
	check(MiniGameInput.hint("eco_commute", "정차 완료 · Space") == "정차 완료 · 태우기", "The bus stop refers to the real boarding control")
	gm._start_minigame(0, "eco_commute")
	await process_frame
	modal._start_practice()
	await process_frame
	await process_frame
	var drive: Control
	for holder in modal.touch_controls.get_children():
		if int(holder.get_meta("input_key")) == KEY_D:
			drive = holder
	for down in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = drive.get_global_rect().get_center()
		event.index = 1
		event.pressed = down
		root.push_input(event, true)
		await process_frame
		check(MiniGameInput.is_pressed(KEY_D) == down, "Touch contact and release reach actual gameplay input")
	modal.cancel_minigame()
	main.switch_to_lobby()
	Input.emulate_touch_from_mouse = original_touch
	AudioServer.set_bus_mute(0, initial_mute)
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] First turn, nine matched portraits, SP discovery, mute transfer, nine touch layouts and real touch press/release")
	quit(0 if failures.is_empty() else 1)
