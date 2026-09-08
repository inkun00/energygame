extends SceneTree

## 위험 돌풍 경고가 실제 플레이 화면에서 충분히 눈에 띄는지 확인하는 스냅샷입니다.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"},
		{"name": "태양 여우 솔", "is_ai": true},
		{"name": "물방울 포포", "is_ai": true},
		{"name": "바람 토끼 보리", "is_ai": true},
	]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.4).timeout
	root.get_node("GameManager")._start_minigame(0, "wind_rhythm")
	await create_timer(0.4).timeout
	var wind_viewport := root.find_child("WindPilotViewport", true, false)
	if not is_instance_valid(wind_viewport):
		push_error("WindPilotViewport를 찾지 못했습니다.")
		quit(1)
		return
	var wind_game = wind_viewport.get_parent()
	wind_game.phase_index = 3
	wind_game._start_next_wind_phase()
	await create_timer(0.65).timeout
	var image := root.get_texture().get_image()
	var storm_error := image.save_png("res://.godot/wind_turbine_storm_preview.png")
	if storm_error != OK:
		print("[WindTurbineStormVisual] FAIL")
		quit(1)
		return
	await create_timer(3.55).timeout
	var break_image := root.get_texture().get_image()
	var break_error := break_image.save_png("res://.godot/wind_turbine_break_preview.png")
	print("[WindTurbineStormVisual] %s" % ("PASS" if break_error == OK else "FAIL"))
	quit(0 if break_error == OK else 1)
