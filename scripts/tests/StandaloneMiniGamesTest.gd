extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[StandaloneMiniGamesTest] " + message)

func _run() -> void:
	await process_frame
	var launcher = load("res://scripts/ui/StandaloneMiniGames.gd").new()
	root.add_child(launcher)
	await process_frame
	launcher.open_request("eco_commute")
	await process_frame
	_check(launcher.current_game_id == "eco_commute" and not launcher.menu.visible, "직접 링크가 통학 버스 미니게임을 바로 시작해야 합니다.")
	_check(launcher.modal.visible and launcher.modal.active, "보드 없이 미니게임 모달을 플레이할 수 있어야 합니다.")
	_check(launcher.modal.duration == 60.0 and launcher.modal.timer_bar.max_value == 60.0, "통학 버스 단독 플레이는 60초로 시작해야 합니다.")
	_check(is_instance_valid(launcher.modal.commute_arcade), "전용 링크가 버튼 퀴즈가 아닌 3D 통학 버스 게임을 열어야 합니다.")
	_check(root.get_node("GameManager").players.size() == 4, "사람 한 명과 AI 세 명이 참가해야 합니다.")
	var manager = root.get_node("GameManager")
	launcher.modal.dismiss_guide()
	manager._update_minigame(manager.MINIGAME_READY_COUNTDOWN_SECONDS)
	_check(launcher.modal.round_started_locally, "단독 데모도 공통 카운트다운 후 시작해야 합니다.")
	for player_idx in range(4):
		manager.submit_minigame_score(player_idx, 400 - player_idx * 100)
	await process_frame
	_check(launcher.modal.visible and launcher.modal.standalone_actions.visible, "결과 화면에 반복 플레이 버튼이 남아 있어야 합니다.")
	launcher._replay()
	_check(launcher.modal.active and manager.is_game_active, "다시 플레이가 새로운 라운드를 시작해야 합니다.")
	launcher._show_menu()
	_check(launcher.menu.visible and not launcher.modal.visible, "게임 선택 화면으로 돌아올 수 있어야 합니다.")
	launcher.open_request("heat_leak")
	await process_frame
	_check(launcher.current_game_id == "heat_leak" and is_instance_valid(launcher.modal.heat_arcade), "새 단열 미니게임도 전용 링크로 직접 열려야 합니다.")
	_check(launcher.modal.duration == 30.0 and manager.players.size() == 4, "단열 게임은 사람과 AI가 함께 30초 동안 진행해야 합니다.")
	launcher.queue_free()
	manager.stop_game()
	if failures.is_empty():
		print("[PASS] Standalone minigames · direct link, AI, replay, menu")
		quit(0)
	else:
		print("[FAIL] Standalone minigames · %d issue(s)" % failures.size())
		quit(1)
