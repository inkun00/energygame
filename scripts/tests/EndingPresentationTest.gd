extends SceneTree

const ENDING = preload("res://scripts/effects/EndingCinematic.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[EndingPresentation] " + message)

func _capture(name: String) -> void:
	if "--snapshots" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/qa-audit-b/ending")
	root.get_texture().get_image().save_png("res://.godot/qa-audit-b/ending/%s-%dx%d.png" % [name, root.size.x, root.size.y])

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("Ending presentation timeout"); quit(1))
	var manager: Node = root.get_node("GameManager")
	var before_players: Array = manager.players.duplicate(true)
	var result: Variant = await _verify_presentation()
	_check(result == true, "Presentation test must reach completion without a runtime error")
	_check(manager.players == before_players, "Ending presentation cannot change player scores or statistics")
	await process_frame
	if failures.is_empty(): print("[PASS] EndingPresentation: real team snapshots, village recovery, 1280/1024 safe layout and intentional skip inputs")
	quit(0 if failures.is_empty() else 1)

func _verify_presentation() -> bool:
	var portraits := ["captain_eco", "solar_fox_sol", "water_popo", "wind_rabbit_bori"]
	var names := ["에코 대장", "태양 여우 솔", "물방울 포포", "바람 토끼 보리"]
	var players: Array[Dictionary] = []
	for index in range(3, -1, -1):
		players.append({"index": index, "name": names[index], "char_icon": "res://assets/characters/eco_roster/%s.webp" % portraits[index], "quiz_correct": index + 2, "construction_contribution": index + 5, "project_completion_bonus": index % 3})
	var ending = ENDING.new()
	ending.setup(true, 80, 70, players)
	root.add_child(ending)
	ending.set_process(false)
	ending._process(5.9)
	_check(ending.scene_index == 0, "Children get at least six seconds to read each recovery scene")
	ending._process(0.2)
	_check(ending.scene_index == 1, "The story still advances automatically after its reading window")
	_check(ending.team_snapshot.size() == 4 and ending.team_snapshot[0]["index"] == 0, "Actual selected heroes stay in seat order, not winner order")
	players[0]["quiz_correct"] = 999
	_check(ending.team_snapshot[3]["quiz_correct"] == 5, "Scene contributions are an immutable copy of the supplied round results")
	_check(str(ending.scenes[0]["image"]).contains("kingdom_stage_0") and str(ending.scenes[1]["image"]).contains("kingdom_stage_50") and str(ending.scenes[2]["image"]).contains("kingdom_stage_100"), "The same village visibly changes from polluted to recovering to restored using existing art")
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 600)]:
		root.size = dimensions
		await process_frame
		await process_frame
		ending._show_scene(0, true)
		await _capture("recovery-before")
		ending._show_scene(2, true)
		await process_frame
		await process_frame
		_check(ending.team_cards.size() == 4 and ending._team_panel.visible, "All four heroes' contributions remain readable throughout the story")
		var scene_rect: Rect2 = ending.get_global_rect()
		var team_rect: Rect2 = ending._team_panel.get_global_rect()
		var caption_rect: Rect2 = ending._caption_panel.get_global_rect()
		_check(scene_rect.encloses(team_rect) and scene_rect.encloses(caption_rect) and not team_rect.intersects(caption_rect), "Team and caption panels stay on-screen without overlap at each laptop size")
		for index in range(ending.team_cards.size()):
			var card: PanelContainer = ending.team_cards[index]
			var portrait := card.find_child("HeroPortrait", true, false) as TextureRect
			var learning := card.find_child("LearningContribution", true, false) as Label
			var construction := card.find_child("BuildingContribution", true, false) as Label
			_check(portrait.texture.resource_path.ends_with(portraits[index] + ".webp"), "Each contribution is linked to that selected hero's existing portrait")
			_check(learning.text == "퀴즈 %d · 재료 %d" % [index + 2, index + 5] and construction.text == "시설 %d곳 완공" % (index % 3), "Contribution labels use real quiz/material/build values, not fabricated hero roles")
			_check(card.get_global_rect().encloses(learning.get_global_rect()) and card.get_global_rect().encloses(construction.get_global_rect()), "Contribution numbers fit their own card")
		_check(ending._energy_label.text.contains("80") and ending._energy_label.text.contains("70"), "Final energy values are preserved rather than simulated scores")
		await _capture("recovery-after-team")
	ending.setup(false, 35, 70, players)
	ending.set_process(false)
	ending._show_scene(2, true)
	_check(not ending.is_success and ending.subtitle_text.contains("또 다시 도전") and ending._recovery_label.text.contains("다음 도전"), "An incomplete village remains an encouraging retry, not a false recovery")
	await _capture("next-challenge")
	ending._show_scene(0, true)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	ending._gui_input(wheel)
	var held := InputEventKey.new()
	held.keycode = KEY_ENTER
	held.pressed = true
	held.echo = true
	ending._gui_input(held)
	_check(ending.scene_index == 0, "Scrolling or key-repeat cannot accidentally skip the story")
	held.echo = false
	ending._gui_input(held)
	_check(ending.scene_index == 1, "An intentional Enter press still advances one scene")
	var finished := [0]
	ending.animation_finished.connect(func(): finished[0] += 1)
	ending._show_scene(2, true)
	ending._process(6.1)
	_check(not ending._finished_emitted and finished[0] == 0, "The last scene gives nine seconds to review the team contributions")
	ending._finish()
	ending._finish()
	_check(finished[0] == 1, "Finishing the story reveals results exactly once")
	await process_frame
	return true
