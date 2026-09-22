extends Node

## Local-only WebRTC integration harness; export this scene as main for browser tests.
var role := "host"
var code := ""
var modal: Node
var overlay: Node
var restored := false
var failed := false
var waiting := false

func _ready() -> void:
	role = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('role') || 'host'", true))
	code = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('code') || ''", true))
	ProjectSettings.set_setting("network/room_directory_url", "http://127.0.0.1:19090")
	modal = load("res://scenes/MiniGameModal.tscn").instantiate()
	add_child(modal)
	overlay = load("res://scripts/ui/NetworkRecoveryOverlay.gd").new()
	add_child(overlay)
	NetworkManager.game_started_signal.connect(func(configs, duration): GameManager.setup_game(configs, duration))
	NetworkManager.session_restored.connect(func():
		modal.restore_online_round()
		# Freeze scoring at the observation point so the next browser frame cannot add points.
		modal._set_arcades_running(false)
		restored = true)
	NetworkManager.recovery_state_changed.connect(func(state):
		if state.get("mode") == "waiting":
			waiting = true)
	NetworkManager.connection_failed.connect(func(): _fail("initial connection failed"))
	NetworkManager.external_room_failed.connect(_fail)
	NetworkManager.room_code_lookup_failed.connect(_fail)
	get_tree().create_timer(65.0).timeout.connect(func(): _fail("browser watchdog"))
	_run()

func _run() -> void:
	if role == "host":
		if NetworkManager.create_room(8910, {"name": "방장"}) != OK:
			_fail("create web room")
			return
		await NetworkManager.external_room_ready
		_publish("ready", {"code": NetworkManager.room_code})
		await _until(func(): return NetworkManager.connected_players.size() == 2)
		NetworkManager.start_hosted_game(120)
		GameManager.players[1]["energy"] = 77
		await get_tree().create_timer(0.3).timeout
		GameManager._start_minigame(0, "grid_balance")
		GameManager.start_minigame_action(0, int(GameManager.active_minigame["round_id"]))
		await _until(func(): return waiting)
		var frozen_time := GameManager.minigame_time_remaining
		await get_tree().create_timer(0.7).timeout
		if not get_tree().paused or not is_equal_approx(frozen_time, GameManager.minigame_time_remaining):
			_fail("host minigame did not pause")
			return
		await _until(func(): return not get_tree().paused)
		await _until(func(): return GameManager.minigame_scores.has(1))
		if GameManager.players[1]["is_ai"] or int(GameManager.minigame_scores[1]["score"]) != 432:
			_fail("restored score or human slot differs")
			return
		_publish("passed", {"checks": "WebRTC host: pause, same slot, score delivery", "code": NetworkManager.room_code})
	else:
		if NetworkManager.join_room_by_code(code, {"name": "참가자"}) != OK:
			_fail("join web room")
			return
		await _until(func(): return not GameManager.active_minigame.is_empty())
		modal.dismiss_guide()
		await _until(func(): return modal.round_started_locally)
		await get_tree().create_timer(0.3).timeout
		modal.score = 432
		NetworkManager._begin_reconnect()
		NetworkManager._next_reconnect_attempt = Time.get_ticks_msec() + 2300
		_publish("reconnecting")
		var elapsed: float = modal.elapsed
		await get_tree().create_timer(0.8).timeout
		if not get_tree().paused or not is_equal_approx(elapsed, modal.elapsed):
			_fail("guest arcade did not pause")
			return
		await _until(func(): return restored)
		if NetworkManager.get_local_player_index() != 1 or GameManager.players[1]["energy"] != 77 or modal.score != 432:
			_fail("guest state differs after WebRTC recovery: slot=%d energy=%d score=%d" % [NetworkManager.get_local_player_index(), GameManager.players[1]["energy"], modal.score])
			return
		modal._submit_score()
		await _until(func(): return GameManager.minigame_scores.has(1))
		_publish("passed", {"checks": "WebRTC guest: pause, credential, snapshot, local progress"})

func _until(predicate: Callable) -> void:
	while not predicate.call() and not failed:
		await get_tree().create_timer(0.025).timeout

func _publish(status: String, extra: Dictionary = {}) -> void:
	var payload := extra.duplicate()
	payload["status"] = status
	payload["role"] = role
	JavaScriptBridge.eval("window.recoveryTest = %s; if (window.energyGameReady) window.energyGameReady();" % JSON.stringify(payload))
	print("[WEB TEST] ", JSON.stringify(payload))

func _fail(message: String) -> void:
	if failed:
		return
	failed = true
	_publish("failed", {"message": message})
