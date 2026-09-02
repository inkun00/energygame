extends SceneTree

const SIMULATION_SPEED := 30.0
const REAL_TIME_LIMIT_MS := 25000

var failures: Array[String] = []
var stats := {
	"turns": 0,
	"dice_rolls": 0,
	"moves": 0,
	"quizzes": 0,
	"game_over": false,
	"ranking_count": 0
}

func _initialize() -> void:
	call_deferred("_run_simulation")

func _run_simulation() -> void:
	seed(20260827)
	Engine.time_scale = SIMULATION_SPEED

	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var game_manager = root.get_node("GameManager")
	game_manager.turn_changed.connect(func(_idx: int): stats["turns"] += 1)
	game_manager.dice_rolled.connect(func(_idx: int, _value: int): stats["dice_rolls"] += 1)
	game_manager.player_moved.connect(func(_idx: int, _from: int, _to: int): stats["moves"] += 1)
	game_manager.quiz_requested.connect(func(_idx: int, _quiz: Dictionary): stats["quizzes"] += 1)
	game_manager.game_over.connect(func(rankings: Array):
		stats["game_over"] = true
		stats["ranking_count"] = rankings.size()
		_validate_rankings(rankings)
	)

	var configs: Array[Dictionary] = []
	for i in range(4):
		configs.append({"name": "시뮬레이션 AI %d" % (i + 1), "is_ai": true})
	main._on_start_game_requested(configs)

	var deadline := Time.get_ticks_msec() + REAL_TIME_LIMIT_MS
	while not stats["game_over"] and Time.get_ticks_msec() < deadline:
		await process_frame

	_expect(stats["game_over"], "제한 시간 안에 게임이 종료되지 않았습니다.")
	_expect(stats["ranking_count"] == 4, "게임 종료 랭킹에 4명이 포함되어야 합니다.")
	_expect(stats["turns"] >= 4, "각 플레이어에게 최소 한 번 이상 턴이 돌아야 합니다.")
	_expect(stats["dice_rolls"] > 0, "시뮬레이션에서 주사위가 한 번도 굴려지지 않았습니다.")
	_expect(stats["moves"] > 0, "시뮬레이션에서 플레이어 이동이 발생하지 않았습니다.")
	_expect(stats["quizzes"] > 0, "시뮬레이션에서 퀴즈 이벤트가 한 번도 발생하지 않았습니다.")

	Engine.time_scale = 1.0
	main.switch_to_lobby()
	await process_frame
	main.queue_free()
	await process_frame

	print("[SIMULATION] %s" % JSON.stringify(stats))
	if failures.is_empty():
		print("[PASS] Full AI game simulation")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _validate_rankings(rankings: Array) -> void:
	for i in range(1, rankings.size()):
		_expect(rankings[i - 1]["energy"] >= rankings[i]["energy"], "최종 랭킹이 보유 에너지 내림차순이 아닙니다.")
		_expect(rankings[i]["final_score"] == rankings[i]["energy"], "최종 점수는 순위 기준인 보유 에너지와 같아야 합니다.")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
