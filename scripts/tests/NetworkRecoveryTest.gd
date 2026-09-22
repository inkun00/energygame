extends SceneTree

## Run in two processes with --role=host/client. No external room service is used.
const PORT := 18912
var role := "host"
var nm: Node
var gm: Node
var modal: Node
var overlay: Node
var restored_count := 0
var waiting_count := 0
var saw_failed := false
var finished := false
var checks := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
	call_deferred("_run")

func _run() -> void:
	nm = root.get_node("NetworkManager")
	gm = root.get_node("GameManager")
	# Keep a deterministic localhost test, including on CI without router access.
	ProjectSettings.set_setting("network/room_directory_url", "")
	nm.game_started_signal.connect(func(configs, duration): gm.setup_game(configs, duration))
	nm.recovery_state_changed.connect(_recovery_changed)
	nm.session_restored.connect(_restored)
	modal = load("res://scenes/MiniGameModal.tscn").instantiate()
	root.add_child(modal)
	overlay = load("res://scripts/ui/NetworkRecoveryOverlay.gd").new()
	root.add_child(overlay)
	create_timer(40.0).timeout.connect(func(): _fail("test watchdog expired"))
	if role in ["loss_host", "loss_client"]:
		await _test_host_loss()
		return
	if role == "host":
		_check(nm.create_room(PORT, {"name": "방장"}) == OK, "host listen")
		await _until(func(): return nm.connected_players.size() == 2)
		_check(nm.start_hosted_game(120), "start hosted game")
		gm.players[1]["energy"] = 77
		gm.start_first_turn()
		await _until(func(): return waiting_count == 1)
		var remaining: float = gm.game_time_remaining
		var dice_remaining: float = gm.dice_input_time_remaining
		await create_timer(0.6).timeout
		_check(paused and is_equal_approx(gm.game_time_remaining, remaining), "host clock freezes")
		_check(is_equal_approx(gm.dice_input_time_remaining, dice_remaining), "dice clock freezes")
		await _until(func(): return not paused)
		_check(not gm.players[1]["is_ai"], "returning guest stays human")
		_check(gm.players[1]["energy"] == 77, "energy preserved")
		await create_timer(0.3).timeout
		gm._start_minigame(0, "grid_balance")
		gm.start_minigame_action(0, int(gm.active_minigame["round_id"]))
		await _until(func(): return waiting_count == 2)
		var minigame_remaining: float = gm.minigame_time_remaining
		await create_timer(0.6).timeout
		_check(paused and is_equal_approx(gm.minigame_time_remaining, minigame_remaining), "minigame clock freezes")
		await _until(func(): return not paused)
		await _until(func(): return gm.minigame_scores.has(1))
		_check(int(gm.minigame_scores[1]["score"]) == 321, "restored local score arrives once")
		# Give the guest a recovery timeout; its reserved seat becomes AI only after grace.
		await _until(func(): return waiting_count == 3)
		_check(not gm.players[1]["is_ai"], "AI does not replace guest during grace")
		nm._pending_reconnects[1] = Time.get_ticks_msec() + 200
		await _until(func(): return not paused)
		_check(gm.players[1]["is_ai"] and nm.game_peer_ids[1] == 0, "expired guest becomes AI")
		_check(nm._resume_slots.is_empty(), "expired token is revoked")
		await create_timer(1.0).timeout
		_pass()
	elif role == "intruder":
		await create_timer(3.0).timeout
		_check(nm.join_room("127.0.0.1", PORT, {"name": "참가자"}) == OK, "same-name stranger connects")
		await _until(func(): return saw_failed)
		_check(not nm.game_has_started and gm.players.is_empty(), "stranger cannot claim another player's game")
		_pass()
	else:
		await create_timer(0.25).timeout
		_check(nm.join_room("127.0.0.1", PORT, {"name": "참가자"}) == OK, "join localhost")
		await _until(func(): return nm.game_has_started)
		await create_timer(0.3).timeout
		_check(not nm._resume_token.is_empty(), "private resume credential received")
		var original_peer: int = nm.my_peer_id
		_drop_and_wait()
		await _until(func(): return restored_count == 1)
		_check(nm.my_peer_id != original_peer and nm.get_local_player_index() == 1, "new transport returns to original slot")
		_check(gm.players[1]["energy"] == 77, "authoritative snapshot restored")
		await _until(func(): return not gm.active_minigame.is_empty())
		modal.dismiss_guide()
		await _until(func(): return modal.round_started_locally)
		await create_timer(0.2).timeout
		modal.score = 321
		var round_id: int = modal.round_id
		_drop_and_wait()
		var local_elapsed: float = modal.elapsed
		await create_timer(0.6).timeout
		_check(paused and is_equal_approx(modal.elapsed, local_elapsed), "local arcade freezes")
		_check(overlay.visible, "recovery notice visible while paused")
		await _until(func(): return restored_count == 2)
		_check(modal.score == 321 and modal.round_id == round_id, "minigame progress preserved")
		modal._submit_score()
		await _until(func(): return gm.minigame_scores.has(1))
		_drop_and_wait()
		nm._reconnect_deadline = Time.get_ticks_msec() + 450
		nm._next_reconnect_attempt = Time.get_ticks_msec() + 5000
		await _until(func(): return saw_failed)
		_check(paused and overlay.visible and nm.game_has_started, "failure preserves game behind notice")
		await create_timer(0.3).timeout
		nm.disconnect_network()
		_check(not paused and not overlay.visible, "leaving releases pause and notice")
		_pass()

func _drop_and_wait() -> void:
	# Close the actual ENet transport, leaving the authoritative game untouched.
	nm._begin_reconnect()
	nm._next_reconnect_attempt = Time.get_ticks_msec() + 1300

func _test_host_loss() -> void:
	if role == "loss_host":
		_check(nm.create_room(PORT + 1, {"name": "방장"}) == OK, "host-loss listen")
		await _until(func(): return nm.connected_players.size() == 2)
		_check(nm.start_hosted_game(120), "host-loss game starts")
		gm.players[1]["energy"] = 77
		gm.player_state_changed.emit(1)
		await create_timer(0.6).timeout
		# A real server close must invoke the client's automatic recovery path.
		nm.disconnect_network()
		_pass()
	else:
		await create_timer(0.25).timeout
		_check(nm.join_room("127.0.0.1", PORT + 1, {"name": "참가자"}) == OK, "host-loss join")
		await _until(func(): return nm._reconnecting)
		_check(paused and gm.is_game_active, "host loss freezes instead of clearing session")
		_check(gm.players[1]["energy"] == 77, "last confirmed progress retained")
		nm._reconnect_deadline = Time.get_ticks_msec() + 400
		await _until(func(): return saw_failed)
		_check(overlay.visible and overlay.countdown_label.text.contains("77"), "failure screen shows last confirmed record")
		_check(nm._recovery_failed, "no indefinite reconnect")
		_pass()

func _restored() -> void:
	restored_count += 1
	modal.restore_online_round()

func _recovery_changed(state: Dictionary) -> void:
	if state.get("mode") == "waiting" and int(state.get("remaining", 0)) == 30:
		waiting_count += 1
	if state.get("mode") == "failed":
		saw_failed = true

func _until(predicate: Callable) -> void:
	while not predicate.call() and not finished:
		await create_timer(0.025).timeout

func _check(value: bool, message: String) -> void:
	if not value:
		_fail(message)
	checks += 1

func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	push_error("[FAIL] Recovery %s: %s" % [role, message])
	nm.disconnect_network()
	quit(1)

func _pass() -> void:
	if finished:
		return
	finished = true
	print("[PASS] Recovery %s: %d checks" % [role, checks])
	nm.disconnect_network()
	quit(0)
