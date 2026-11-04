extends SceneTree

## Opt-in developer benchmark. Prints aggregate engine counters; never records
## player input, names, scores or personal play history, and writes no files.
const SAMPLE_SECONDS := 2.5
var main: Node
var board: Node
var gm: Node
var reports: Array[Dictionary] = []
var label := "working-tree"
var legacy_board_policy := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
		elif argument == "--legacy-board-policy":
			legacy_board_policy = true
	call_deferred("_run")

func _viewport_inventory() -> Dictionary:
	var active := 0
	var total := 0
	for node in root.find_children("*", "SubViewport", true, false):
		total += 1
		if node.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			active += 1
	var tile_callbacks := 0
	for marker in board.tile_markers:
		if marker.is_processing(): tile_callbacks += 1
	return {"viewports": total, "active_viewports": active, "processing_tiles": tile_callbacks}

func _sample(phase: String) -> void:
	if legacy_board_policy:
		# A/B the old presentation policy in the SAME build/assets/process budget.
		# This test-only override is not reachable from the game UI.
		board.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if board.visible else SubViewport.UPDATE_DISABLED
		board.energy_fairy_village.set_process(board.visible)
		for pawn in board.player_pawns: pawn.set_process(true)
		for marker in board.tile_markers: marker.set_process(true)
	await create_timer(0.5).timeout
	var frames: Array[float] = []
	var process_ms := 0.0
	var draw_calls := 0.0
	var primitives := 0.0
	var objects := 0.0
	var board_draw_calls := 0.0
	var previous := Time.get_ticks_usec()
	var started := previous
	while Time.get_ticks_usec() - started < int(SAMPLE_SECONDS * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		board_draw_calls += board.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	frames.sort()
	var count := maxi(frames.size(), 1)
	var report := {
		"label": label,
		"legacy_board_policy": legacy_board_policy,
		"phase": phase,
		"platform": OS.get_name(),
		"renderer": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"physical_window": str(DisplayServer.window_get_size()),
		"samples": count,
		"seconds": snappedf(seconds, 0.001),
		"fps": snappedf(float(count) / maxf(seconds, 0.001), 0.1),
		"frame_p50_ms": snappedf(frames[int(float(count - 1) * 0.50)], 0.01),
		"frame_p95_ms": snappedf(frames[int(float(count - 1) * 0.95)], 0.01),
		"frame_p99_ms": snappedf(frames[int(float(count - 1) * 0.99)], 0.01),
		"frame_max_ms": snappedf(frames.back(), 0.01),
		"engine_process_mean_ms": snappedf(process_ms / count, 0.01),
		"draw_calls_mean": snappedf(draw_calls / count, 0.1),
		"board_draw_calls_mean": snappedf(board_draw_calls / count, 0.1),
		"rendered_objects_mean": snappedf(objects / count, 0.1),
		"rendered_primitives_mean": snappedf(primitives / count, 1),
		"scene_nodes": root.get_tree().get_node_count(),
		"board_nodes": board.find_children("*", "", true, false).size(),
	}
	report.merge(_viewport_inventory())
	reports.append(report)
	print("[RENDER_BENCH] " + JSON.stringify(report))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.renderBenchReports=" + JSON.stringify(reports), true)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("RenderPerformanceBenchmark requires a real renderer; headless counters are not GPU evidence")
		quit(2)
		return
	seed(20261104)
	# Browser timing remains RAF paced: an uncapped native setting can overwhelm
	# a software WebGL command queue and does not represent ordinary web play.
	Engine.max_fps = 60 if OS.has_feature("web") else 0
	if not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	gm = root.get_node("GameManager")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [{"name":"Benchmark", "is_ai":false}]
	main._on_start_game_requested(configs, 300)
	gm.confirm_adventure_ready(0)
	gm.set_process(false)
	board = main.game_board
	board.hud.adventure_planner.dismiss_tutorial()
	await create_timer(0.8).timeout
	await _sample("board_close_idle")
	board._show_board_overview()
	await _sample("board_overview_idle")
	var quiz := {"question":"태양광 패널은 어떤 에너지를 이용할까요?", "options":["햇빛", "소리", "진동", "자석"], "answer":"햇빛", "explanation":"태양광 패널은 햇빛을 전기로 바꿔요.", "reward_energy":2, "time_limit":30.0}
	board.quiz_modal.display_quiz(0, quiz)
	await _sample("quiz_overlay")
	board.quiz_modal.cancel_quiz()
	board.hud.adventure_planner.open_catalog()
	await _sample("catalog_overlay")
	board.hud.adventure_planner.close_catalog()
	var data: Dictionary = gm.MINIGAME_DEFINITIONS["grid_balance"].duplicate(true)
	data.merge({"id":"grid_balance", "phase":"playing", "seed":20261104, "round_id":1, "duration":30.0}, true)
	board.minigame_modal._on_minigame_started(data)
	board.minigame_modal.guide_panel.hide()
	board.minigame_modal.game_id = "grid_balance"
	board.minigame_modal.grid_arcade.set_running(true)
	board.minigame_modal.active = false
	await _sample("grid_visible_over_board")
	board.minigame_modal.cancel_minigame()
	main.switch_to_lobby()
	await _sample("lobby_board_hidden")
	gm.stop_game()
	main.queue_free()
	await process_frame
	print("[RENDER_BENCH_DONE] " + label)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.renderBenchDone=true", true)
	quit(0)
