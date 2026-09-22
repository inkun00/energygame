extends SceneTree

const FEEDBACK = preload("res://scripts/minigames/MiniGameLearningFeedback.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[LearningFeedbackTest] " + message)

func _run() -> void:
	await process_frame
	var definitions: Dictionary = root.get_node("GameManager").MINIGAME_DEFINITIONS
	for id_variant in definitions.keys():
		var game_id := str(id_variant)
		var empty_report: Dictionary = FEEDBACK.result_lines(game_id, {})
		_check(not str(empty_report.get("evidence", "")).is_empty(), "%s: 도전 기록이 없어도 결과 문장이 필요합니다." % game_id)
		_check(not str(empty_report.get("next_action", "")).is_empty(), "%s: 다음 행동을 제시해야 합니다." % game_id)
	_check("2.5 MW" in str(FEEDBACK.result_lines("grid_balance", {"measurement_time": 10.0, "average_gap": 2.5})["evidence"]), "전력망은 점수 대신 실제 평균 차이를 표시해야 합니다.")
	_check("기록 없음" in str(FEEDBACK.result_lines("grid_balance", {})["evidence"]), "전력망 미측정은 0 MW라고 꾸며내지 않아야 합니다.")
	_check("12.4 kWh" in str(FEEDBACK.result_lines("hydro_gate", {"generated_kwh": 12.4, "overflowed": true})["evidence"]), "수력 발전량을 실제 단위로 표시해야 합니다.")
	_check("댐 범람" in str(FEEDBACK.result_lines("hydro_gate", {"overflowed": true})["evidence"]), "수력 범람을 결과에 남겨야 합니다.")
	_check("닫힌 창문 선택 2회" in str(FEEDBACK.result_lines("heat_leak", {"correct": 3, "closed_window_misses": 2})["evidence"]), "창문 선택 실수를 결과에 남겨야 합니다.")
	_check(FEEDBACK.live_line("solar_align", true, 30, false).is_empty(), "장애물 점프를 태양광 학습 행동으로 취급하지 않아야 합니다.")
	_check("날개" in FEEDBACK.live_line("wind_rhythm", false, 35, false), "위험 돌풍을 놓쳤을 때 파손 이유를 설명해야 합니다.")

	var modal_scene := load("res://scenes/MiniGameModal.tscn") as PackedScene
	var modal := modal_scene.instantiate()
	root.add_child(modal)
	await process_frame
	modal.visible = true
	modal.game_id = "battery_relay"
	modal.round_id = 1001
	modal.active = true
	modal.submitted = false
	modal._register_success(20, "남는 전기 1칸을 배터리에 저장", true)
	_check("저장" in modal.lesson_label.text, "플레이 중 저장 행동이 즉시 교육 문구에 반영돼야 합니다.")
	modal._register_success(80, "저장 전기로 도시의 불을 켰어요", true)
	_check("도시" in modal.lesson_label.text, "플레이 중 공급 행동이 즉시 교육 문구에 반영돼야 합니다.")
	var results := [
		{"player_idx": 0, "rank": 1, "name": "나", "score": 100, "reward": 20},
		{"player_idx": 1, "rank": 2, "name": "AI 1", "score": 80, "reward": 10},
		{"player_idx": 2, "rank": 3, "name": "AI 2", "score": 60, "reward": 5},
		{"player_idx": 3, "rank": 4, "name": "AI 3", "score": 40, "reward": 1},
	]
	modal._on_minigame_finished(results)
	await process_frame
	_check("1칸 저장" in modal.lesson_label.text and "1회" in modal.lesson_label.text, "결과는 실제 저장·공급 횟수를 보여야 합니다.")
	_check(modal.arena.get_child_count() == 5, "교육 문구 추가 후에도 4인 순위 행이 유지돼야 합니다.")
	var score_column_x := -1.0
	for row_index in range(1, 5):
		var columns: HBoxContainer = modal.arena.get_child(row_index).get_child(0)
		_check(columns.get_child_count() == 4, "순위·이름·점수·보상을 각각의 열에 표시해야 합니다.")
		var current_x: float = columns.get_child(2).get_global_rect().position.x
		if score_column_x >= 0.0:
			_check(is_equal_approx(current_x, score_column_x), "네 명의 점수 열이 수직으로 정렬돼야 합니다.")
		score_column_x = current_x
	_check(modal.lesson_label.get_global_rect().end.y < modal.card.get_global_rect().end.y, "개인 기록이 결과 카드 바깥으로 밀리면 안 됩니다.")
	_check(modal.feedback_label.get_global_rect().end.y <= modal.lesson_label.get_global_rect().position.y, "결과 행동 제안과 개인 기록이 겹치면 안 됩니다.")
	var grid_script := load("res://scripts/minigames/SmartGridBalance3D.gd")
	modal.grid_arcade = grid_script.new()
	modal.grid_arcade.set("demand", 70.0)
	modal.grid_arcade.set("supply", 65.0)
	modal.grid_arcade.set("measurement_time", 10.0)
	modal.grid_arcade.set("gap_integral", 25.0)
	var measured: Dictionary = modal._learning_metrics_snapshot()
	_check(is_equal_approx(float(measured.get("average_gap", -1.0)), 2.5), "전력망 결과는 실제 누적 차이를 측정 시간으로 나눠야 합니다.")
	modal.grid_arcade.free()
	modal.grid_arcade = null
	modal.queue_free()
	await process_frame
	var bus_script := load("res://scripts/minigames/SharedSchoolBus3D.gd")
	var bus = bus_script.new()
	root.add_child(bus)
	bus.setup({}, 31)
	bus.passengers = 3
	bus.route_distance = 100.0
	var observed_delivery := {"count": -1}
	bus.arcade_event.connect(func(_points, success, _message, count_correct):
		if success and count_correct:
			observed_delivery["count"] = bus.delivered_total
	)
	bus._unload_at_school(0.0)
	_check(int(observed_delivery["count"]) == 3, "학교 하차 이벤트는 갱신된 누적 도착 인원을 전달해야 합니다.")
	bus.queue_free()
	await process_frame
	if failures.is_empty():
		print("[LearningFeedbackTest] PASS · 9 game reports, live cues, measured results, ranking UI")
	quit(0 if failures.is_empty() else 1)
