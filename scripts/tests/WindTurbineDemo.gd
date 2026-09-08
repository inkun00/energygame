extends SceneTree

## 풍력 터빈 파일럿을 로비 진행 없이 바로 체험하는 실행용 데모입니다.

func _initialize() -> void:
	call_deferred("_launch_demo")

func _launch_demo() -> void:
	DisplayServer.window_set_title("에코 히어로즈 · 풍력 터빈 파일럿 데모")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var players: Array[Dictionary] = [
		{"name": "캡틴 에코 · 나", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"},
		{"name": "태양 여우 솔", "is_ai": true},
		{"name": "물방울 포포", "is_ai": true},
		{"name": "바람 토끼 보리", "is_ai": true},
	]
	main._on_start_game_requested(players, 600)
	await create_timer(0.5).timeout
	root.get_node("GameManager")._start_minigame(0, "wind_rhythm")
