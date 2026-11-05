extends SceneTree

## Visual QA captures are development artifacts, never saved player history.
var failures: Array[String] = []
var emitted_events := 0
var capture := false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[GuidePreview] " + message)

func _run() -> void:
	capture = "--capture-guide" in OS.get_cmdline_user_args()
	var gm: Node = root.get_node("GameManager")
	gm.set_process(false)
	root.get_node("NetworkManager").is_online = false
	var players: Array[Dictionary] = []
	for index in range(4):
		players.append({"name": "안내 확인 %d" % index, "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"})
	gm.setup_game(players, 600)
	var modal = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	modal.set_process(false)
	modal.set_physics_process(false)
	if capture:
		DirAccess.make_dir_recursive_absolute("res://.godot/qa-guide-polish")
	for viewport_size in [Vector2i(1024, 600), Vector2i(1280, 720)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		for id in gm.MINIGAME_DEFINITIONS:
			var data: Dictionary = gm.MINIGAME_DEFINITIONS[id].duplicate(true)
			data.merge({"seed": 31, "round_id": 777, "phase": "ready"}, true)
			gm.active_minigame = data.duplicate(true)
			gm.minigame_waiting_for_start = true
			gm.minigame_ready_players.clear()
			modal._on_minigame_started(data)
			await process_frame
			await process_frame
			var demo: Control = modal.guide_preview
			demo.set_process(false)
			var clone: Node = demo.arcade
			var original: Node = modal._current_arcade()
			_check(clone != original and clone.process_mode == Node.PROCESS_MODE_DISABLED, id + ": isolated disabled simulation tree")
			_check(clone.get("viewport") != original.get("viewport"), id + ": separate render target")
			_check(clone.get("world") != original.get("world"), id + ": separate world")
			_check(not original.get("running"), id + ": competition remains stopped")
			var random_state: int = 0
			if original.get("rng") is RandomNumberGenerator:
				random_state = original.get("rng").state
			clone.arcade_event.connect(func(_points: int, _success: bool, _message: String, _count: bool): emitted_events += 1)
			for tick in range(180):
				demo.preview_time = float(tick) / 30.0
				demo._animate_demo(1.0 / 30.0)
			_check(emitted_events == 0 and modal.score == 0 and modal.correct == 0 and modal.attempts == 0, id + ": automatic demonstration cannot earn points")
			_check(gm.minigame_scores.is_empty() and gm.minigame_ready_players.is_empty(), id + ": demonstration cannot submit or ready players")
			_check(gm.active_minigame == data, id + ": round and shared seed remain untouched")
			if original.get("rng") is RandomNumberGenerator:
				_check(original.get("rng").state == random_state, id + ": scenario RNG remains untouched")
			var button_rect: Rect2 = modal.guide_start_button.get_global_rect()
			_check(button_rect.end.y <= viewport_size.y and button_rect.end.x <= viewport_size.x, id + ": start button fits " + str(viewport_size))
			_check(modal.guide_preview.size.y >= 196.0, id + ": demonstration retains usable height")
			if id == "grid_balance":
				for field in ["supply_bar", "demand_bar"]:
					var bar: Control = clone.get(field)
					_check(bar.is_visible_in_tree() and bar.get_global_rect().end.y <= demo.get_global_rect().end.y - 42.0, "grid: " + field + " stays above the demonstration caption")
			if capture:
				demo.preview_time = 2.9
				demo._animate_demo(0.016)
				await process_frame
				await RenderingServer.frame_post_draw
				var picture := root.get_texture().get_image()
				_check(picture.save_png("res://.godot/qa-guide-polish/%s-%dx%d.png" % [id, viewport_size.x, viewport_size.y]) == OK, id + ": capture")
			modal.guide_panel.hide()
			_check(clone.get("viewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, id + ": hidden preview stops rendering")
			modal.cancel_minigame()
			await process_frame
	gm.stop_game()
	modal.queue_free()
	await process_frame
	print("[GuidePreview] %s · 9 isolated demonstrations, no points/readiness/RNG changes, 1024/1280 layouts" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
