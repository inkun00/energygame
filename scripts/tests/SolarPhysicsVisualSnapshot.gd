extends SceneTree

## 오픈소스 태양광 설비 충돌과 후방 충격 반응을 확인하는 스냅샷입니다.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false},
		{"name": "태양 여우 솔", "is_ai": true},
		{"name": "물방울 포포", "is_ai": true},
		{"name": "바람 토끼 보리", "is_ai": true},
	]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.4).timeout
	root.get_node("GameManager")._start_minigame(0, "solar_align")
	await create_timer(0.35).timeout
	var solar_viewport := root.find_child("SolarDashViewport", true, false)
	if not is_instance_valid(solar_viewport):
		push_error("SolarDashViewport를 찾지 못했습니다.")
		quit(1)
		return
	var solar_game = solar_viewport.get_parent()
	solar_game._spawn_terrain_obstacle(0.88, 4)
	var obstacle_record: Dictionary = solar_game.terrain_obstacles[solar_game.terrain_obstacles.size() - 1]
	var obstacle := obstacle_record["node"] as AnimatableBody3D
	obstacle.position.x = solar_game.hero_body.position.x
	solar_game._resolve_hazard_collision(obstacle)
	await create_timer(0.12).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/solar_physics_preview.png")
	print("[SolarPhysicsVisual] %s" % ("PASS" if error == OK else "FAIL"))
	quit(0 if error == OK else 1)
