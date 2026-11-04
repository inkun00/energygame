extends SceneTree

## Four actual ENet processes, no external room service or public test hooks.
## Run --role=host and --role=guest1/guest2/guest3 together on localhost.
const TEST_PORT := 18926
var role := "host"
var nm: Node
var gm: Node
var finished := false
var checks := 0
var restored := 0
var rejections := 0
var failed_recovery := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
	call_deferred("_run")

func _run() -> void:
	nm = root.get_node("NetworkManager")
	gm = root.get_node("GameManager")
	ProjectSettings.set_setting("network/room_directory_url", "")
	OS.set_environment("ENERGYGAME_ROOM_DIRECTORY_URL", "")
	nm.game_started_signal.connect(func(configs, duration): gm.setup_game(configs, duration))
	nm.session_restored.connect(func(): restored += 1)
	nm.game_action_rejected.connect(func(action, payload):
		if action == "build_project" and payload.get("project_index") == -1:
			rejections += 1)
	nm.recovery_state_changed.connect(func(state):
		if state.get("mode") == "failed": failed_recovery = true)
	create_timer(30.0).timeout.connect(func(): _fail("watchdog expired"))
	if role == "host":
		await _host()
	else:
		await _guest()

func _host() -> void:
	_check(nm.create_room(TEST_PORT, {"name": "Host"}) == OK, "host opens local room")
	await _until(func(): return nm.connected_players.size() == 4)
	_check(nm._pending_registrations.is_empty(), "all three simultaneous connections register")
	_check(nm.start_hosted_game(120), "four-human game starts")
	_check(nm.game_peer_ids.size() == 4 and not nm.game_peer_ids.has(0), "four unique human seats")
	gm.start_first_turn()
	for player_idx in range(4):
		gm.players[player_idx]["energy"] = 100 + player_idx
		gm.player_state_changed.emit(player_idx)
	nm.request_build_project(-1, 0, Vector2.ZERO)
	_check(rejections == 1, "host receives a rejected construction acknowledgement")
	await _until(func(): return nm._pending_reconnects.size() == 3)
	var clock: float = gm.game_time_remaining
	var dice_clock: float = gm.dice_input_time_remaining
	await create_timer(0.5).timeout
	_check(paused and is_equal_approx(clock, gm.game_time_remaining), "three losses freeze board clock")
	_check(is_equal_approx(dice_clock, gm.dice_input_time_remaining), "three losses freeze turn clock")
	var absent_idx := _seat("guest3")
	# Shorten only this test's grace deadline; production remains 30 seconds.
	nm._pending_reconnects[absent_idx] = Time.get_ticks_msec() + 6500
	await _until(func(): return nm.connected_players.size() == 3 and nm._pending_reconnects.size() == 1)
	_check(paused, "two returns cannot resume while third player's grace remains")
	for guest_name in ["guest1", "guest2"]:
		var player_idx := _seat(guest_name)
		_check(not gm.players[player_idx]["is_ai"] and gm.players[player_idx]["energy"] == 100 + player_idx,
			"returned " + guest_name + " keeps original slot and energy")
	await _until(func(): return nm._pending_reconnects.is_empty())
	_check(not paused and gm.players[absent_idx]["is_ai"], "only timed-out seat becomes AI and all others resume")
	_check(nm.game_peer_ids[absent_idx] == 0 and nm._resume_slots.size() == 2, "expired credential is revoked")
	for player_idx in range(4):
		gm.players[player_idx]["energy"] = 900 + player_idx
		gm.player_state_changed.emit(player_idx)
	await create_timer(1.0).timeout
	_pass()

func _guest() -> void:
	await create_timer(0.3).timeout
	_check(nm.join_room("127.0.0.1", TEST_PORT, {"name": role}) == OK, "guest joins localhost")
	await _until(func(): return nm.game_has_started)
	var own_idx: int = nm.get_local_player_index()
	_check(own_idx > 0 and nm.game_peer_ids.size() == 4, "guest sees all four seats")
	await _until(func(): return gm.players[own_idx]["energy"] == 100 + own_idx)
	nm.request_build_project(-1, own_idx, Vector2.ZERO)
	await _until(func(): return rejections == 1)
	_check(rejections == 1, "rejected construction returns only to requester")
	var previous_peer: int = nm.my_peer_id
	nm._begin_reconnect()
	var delay_ms := 2000 if role == "guest1" else 4000
	nm._next_reconnect_attempt = Time.get_ticks_msec() + (60000 if role == "guest3" else delay_ms)
	if role == "guest3":
		nm._reconnect_deadline = Time.get_ticks_msec() + 8000
		await _until(func(): return failed_recovery)
		_check(paused and nm._recovery_failed, "expired guest sees bounded recovery failure")
		nm.disconnect_network()
		_check(not paused, "failed guest can return to lobby")
		_pass()
		return
	# session_restored emits only when every pending player returns or expires.
	await _until(func(): return nm._restoration_pending)
	_check(paused and nm.get_local_player_index() == own_idx, "first restored peer stays paused for others")
	_check(nm.my_peer_id != previous_peer, "new ENet peer ID maps back to original player")
	await _until(func(): return restored == 1)
	_check(not paused, "all-peer recovery barrier releases each restored guest once")
	await _until(func(): return gm.players[own_idx]["energy"] == 900 + own_idx)
	_check(gm.players[_seat("guest3")]["is_ai"], "AI replacement synchronizes to surviving guest")
	await _until(func(): return nm._reconnecting)
	_check(paused and gm.players[own_idx]["energy"] == 900 + own_idx, "host termination freezes latest state")
	nm._reconnect_deadline = Time.get_ticks_msec() + 350
	nm._next_reconnect_attempt = Time.get_ticks_msec() + 5000
	await _until(func(): return failed_recovery)
	_check(paused and nm._recovery_failed, "host loss ends in explicit failure, not endless waiting")
	_pass()

func _seat(player_name: String) -> int:
	for player_idx in range(gm.players.size()):
		if gm.players[player_idx]["name"] == player_name: return player_idx
	return -1

func _until(predicate: Callable) -> void:
	while not predicate.call() and not finished:
		await create_timer(0.025).timeout

func _check(value: bool, message: String) -> void:
	if not value:
		_fail(message)
	checks += 1

func _fail(message: String) -> void:
	if finished: return
	finished = true
	push_error("[FAIL] Four-player transport %s: %s" % [role, message])
	nm.disconnect_network()
	quit(1)

func _pass() -> void:
	if finished: return
	finished = true
	print("[PASS] Four-player transport %s: %d checks" % [role, checks])
	nm.disconnect_network()
	quit(0)
