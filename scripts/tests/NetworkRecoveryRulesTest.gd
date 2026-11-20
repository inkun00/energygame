extends SceneTree

var failures: Array[String] = []
var callback_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_browser_directory()
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var gm := root.get_node("GameManager")
	var nm := root.get_node("NetworkManager")
	var configs: Array[Dictionary] = [{"name": "방장", "is_ai": false}, {"name": "친구", "is_ai": false}]
	main._on_start_game_requested(configs, 120)
	gm._schedule_game_action(0.05, func(): callback_count += 1)
	paused = true
	await create_timer(0.15).timeout
	_expect(callback_count == 0, "scheduled turn action must not run during recovery pause")
	paused = false
	await create_timer(0.12).timeout
	_expect(callback_count == 1, "scheduled turn action resumes exactly once")

	gm.setup_game(configs, 120)
	gm.current_turn_idx = 1
	gm.players[1]["position"] = BoardGrid.LAST_TILE_INDEX
	gm._handle_lap_completion(1)
	var rewards: int = gm.pending_lap_reward.get("remaining", 0)
	gm.take_over_disconnected_player(1)
	_expect(rewards > 0 and gm.pending_lap_reward.is_empty(), "AI finishes disconnected human's reward selection")
	_expect(gm.players[1]["lap_reward_items"] == rewards, "AI grants exactly the remaining rewards")

	gm.setup_game(configs, 120)
	gm.current_turn_idx = 1
	gm.current_state = gm.TurnState.RESOLVING_QUIZ
	gm.active_quiz_player_idx = 1
	gm.active_quiz_data = root.get_node("QuizDatabase").get_random_quiz().duplicate(true)
	gm.active_quiz_time_remaining = 20.0
	var possible: Array = gm.active_quiz_data["options"].duplicate()
	gm.take_over_disconnected_player(1)
	await create_timer(0.3).timeout
	_expect(gm.quiz_collecting_peers and gm.active_quiz_player_idx == 1, "AI locks its choice while the remaining human can still answer")
	gm.submit_spectator_quiz_guess(0, 1, str(gm.active_quiz_data["answer"]))
	_expect(gm.active_quiz_player_idx == -1 and gm.last_quiz_choice in possible, "AI resolves disconnected human's pending quiz with an actual answer")

	gm.setup_game(configs, 120)
	gm._start_minigame(0, "grid_balance")
	for player_idx in range(2):
		gm.start_minigame_action(player_idx, int(gm.active_minigame["round_id"]))
	gm._update_minigame(3.1)
	for player_idx in range(4):
		gm.submit_minigame_score(player_idx, [100, 100, 50, 1][player_idx])
	var energies: Array = gm.players.map(func(player): return player["energy"])
	var modal: Node = main.get_node("GameBoard/Modals/MiniGameModal")
	modal.cancel_minigame()
	modal.restore_online_round()
	_expect(modal.visible and modal.timer_label.text == "종료", "missed minigame results restored from snapshot")
	_expect(gm.players.map(func(player): return player["energy"]) == energies, "restoring results never pays rewards twice")

	# The actual overlay button route must leave a paused game, not trap the player.
	nm.is_online = true
	nm.is_host = false
	nm.game_has_started = true
	nm.my_peer_id = 2
	nm.game_peer_ids.assign([1, 2, 0, 0])
	nm._saved_local_index = 1
	nm._fail_recovery("테스트 연결 종료")
	_expect(main.recovery_overlay.visible and paused, "failure notice appears above the real board")
	main.recovery_overlay.leave_requested.emit()
	_expect(not paused and main.lobby_ui.visible and not main.session_open, "leave returns to an interactive lobby")
	_expect(not nm.is_online and not main.recovery_overlay.visible, "leaving clears network recovery state")
	# Let cancelled scene timers release their callables before shutting down the test.
	Engine.time_scale = 100.0
	await create_timer(10.0).timeout
	Engine.time_scale = 1.0
	for voice in root.get_node("AudioManager").voices:
		voice.stop()
		voice.stream = null
	await create_timer(0.05).timeout
	await process_frame
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("[PASS] Recovery rules: pausable actions, quiz/reward AI handover, result restoration, exit UI")
		quit(0)
	else:
		quit(1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("[FAIL] Recovery rules: " + message)


func _test_browser_directory() -> void:
	var checks_before := failures.size()
	var probe: Node = load("res://scripts/tests/WebRoomDirectoryProbe.gd").new()
	root.add_child(probe)
	_test_connection_heartbeats(probe)
	_test_guest_connection_deadlines()
	var relay := {"urls": ["turn:relay.example:3478?transport=udp", "turns:relay.example:443?transport=tcp"],
		"username": "test-session", "credential": "temporary-example"}
	var provisioned := [{"urls": ["stun:relay.example:3478"]}, relay]
	_test_direct_first_ice(provisioned)
	probe._create_browser_room({})
	var old_registration: Dictionary = probe.sent.back()
	probe.disconnect_network()
	_expect(probe.sent.back().method == HTTPClient.METHOD_DELETE and probe.sent.back().token == old_registration.payload.host_token,
		"host leaving before its create response removes the public listing")
	probe._create_browser_room({})
	var active_registration: Dictionary = probe.sent.back()
	probe.respond(old_registration, HTTPRequest.RESULT_SUCCESS, 201)
	_expect(probe.sent.back().path == "/webrtc/rooms/" + old_registration.payload.code and probe.sent.back().token == old_registration.payload.host_token,
		"a room registered after cancellation is deleted with its original host credential")
	probe.respond(active_registration, HTTPRequest.RESULT_SUCCESS, 201, {"ice_servers": [
		{"urls": "stun:relay.example:3478", "credential": "ignored-on-stun"}, relay]})
	_expect(probe._web_signaling_active and probe.online_frames, "new host keeps signaling after a previous room's late registration")
	_expect(probe._web_ice_servers == provisioned, "host uses admitted relay credentials and a normalized STUN URL")
	probe.disconnect_network()
	_expect(probe._web_ice_servers == probe.WEB_ICE_SERVERS, "departing host drops session relay credentials")
	_expect(not probe.online_frames, "background online frames stop on disconnect")
	probe.sent.clear()
	probe._join_browser_room("234567", {}, "classroom")
	var admission: Dictionary = probe.sent.back()
	probe.respond(admission, HTTPRequest.RESULT_TIMEOUT, 0)
	var retried: Dictionary = probe.sent.back()
	_expect(probe.sent.size() == 2 and retried.payload == admission.payload, "retry admission with the original seat credential")
	probe.disconnect_network()
	_expect(probe.sent.back().path == "/webrtc/rooms/234567/leave", "cancel releases the pending seat")
	probe._join_browser_room("345678", {}, "")
	var new_admission: Dictionary = probe.sent.back()
	probe.respond(retried, HTTPRequest.RESULT_SUCCESS, 201, {"peer_id": 2, "ice_servers": provisioned})
	_expect(probe.sent.back().path == "/webrtc/rooms/234567/leave" and probe.sent.back().token == admission.payload.peer_token,
		"a late admission releases only the old room's reservation")
	_expect(probe._room_lookup_active and probe.pending_room_code == "345678", "late admission preserves the new join")
	_expect(probe._web_ice_servers == probe.WEB_ICE_SERVERS, "late admission cannot install a previous seat's relay credentials")
	var call_count: int = probe.sent.size()
	probe.respond(new_admission, HTTPRequest.RESULT_SUCCESS, 403, {"error": "wrong password"})
	_expect(probe.sent.size() == call_count and not probe._room_lookup_active, "invalid password ends the lookup immediately")
	probe._join_browser_room("345678", {}, "")
	probe.respond(probe.sent.back(), HTTPRequest.RESULT_SUCCESS, 201, {"peer_id": 2, "ice_servers": provisioned})
	_expect(probe.online_frames and probe._web_signaling_active, "admitted guest keeps signaling in a background tab")
	_expect(probe._web_ice_servers == provisioned, "guest receives its session relay configuration")
	probe._close_client_transport()
	_expect(probe._web_ice_servers == provisioned, "reopening the guest transport retains its current session credentials")
	_expect(not JSON.stringify(probe._capture_game_state()).contains("temporary-example"), "game snapshots omit relay credentials")
	probe.disconnect_network()
	probe._set_room_ice_servers({"ice_servers": [
		{"urls": "https://wrong.example"}, {"urls": "turn:relay.example:65536", "username": "a", "credential": "b"},
		{"urls": "turn:relay.example"}, {"urls": "stun:relay.example?transport=tcp"},
		{"urls": ["turn:relay.example", 42], "username": {}, "credential": "b"},
		{"urls": "turn:relay.example", "username": "a", "credential": "x".repeat(2049)}]})
	_expect(probe._web_ice_servers == probe.WEB_ICE_SERVERS, "invalid relay data preserves the default ICE configuration")

	probe._web_transport = true
	probe._web_signaling_active = true
	probe.is_host = true
	probe.room_code = "345678"
	probe._host_directory_token = "host-test-credential"
	probe._web_connection_attempts[2] = "new-peer"
	probe._web_peer_generations[2] = 1
	probe._send_browser_signal(2, "answer", {"sdp": "test-answer"})
	var answer: Dictionary = probe.sent.back()
	probe.respond(answer, HTTPRequest.RESULT_TIMEOUT, 0)
	_expect(probe.sent.back().payload == answer.payload and not answer.payload.data.delivery_id.is_empty(),
		"retry SDP with the same delivery ID and attempt")
	var outgoing_count: int = probe.sent.size()
	probe._web_connection_attempts[2] = "replacement"
	probe.respond(probe.sent.back(), HTTPRequest.RESULT_SUCCESS, 503)
	_expect(probe.sent.size() == outgoing_count, "late send failure cannot retry an old negotiation")

	var early := {"id": 7, "from_peer": 2, "type": "candidate", "data": {
		"attempt": "newcomer", "generation": 1, "delivery_id": "ice-a", "media": "0", "index": 0, "sdp": "test-ice"}}
	var duplicate := early.duplicate(true)
	duplicate.id = 8
	probe._poll_browser_signals()
	_expect(probe.sent.back().path.ends_with("?ack=0"), "new room has no acknowledged signals")
	probe.respond(probe.sent.back(), HTTPRequest.RESULT_SUCCESS, 200, {"signals": [early, duplicate]})
	_expect(probe._web_early_candidates.get("2:1:newcomer", []).size() == 1, "same-generation replacement keeps early ICE exactly once")
	probe._poll_browser_signals()
	_expect(probe.sent.back().path.ends_with("?ack=8"), "next poll acknowledges the processed batch")
	probe.respond(probe.sent.back(), HTTPRequest.RESULT_TIMEOUT, 0)
	_expect(probe._web_processed_signal_id == 8, "lost poll response cannot advance its cursor")
	_test_dropped_legacy_batches(probe)
	probe.is_online = true
	probe._poll_browser_signals()
	probe.respond(probe.sent.back(), HTTPRequest.RESULT_SUCCESS, 404)
	_expect(not probe.is_online and probe.room_code.is_empty(), "expired empty host room returns to the lobby")
	_expect(probe._web_processed_signal_id == 0, "leaving resets the room's signal cursor")
	probe.queue_free()
	if failures.size() == checks_before:
		print("[PASS] Browser admission, seat reuse, delayed responses, lost SDP/ICE batches, retries and acknowledgement")


func _test_connection_heartbeats(probe: Node) -> void:
	_expect(probe._heartbeat_due(1000) and not probe._heartbeat_due(1400), "send one heartbeat per wall-clock interval")
	_expect(probe._heartbeat_due(6500) and not probe._heartbeat_due(6501), "a slow board frame sends one heartbeat without a burst")
	var timeout_ms := int(probe.CONNECTION_SILENCE_SECONDS * 1000)
	var overdue := 1000 + timeout_ms + 1
	_expect(not probe._connection_is_unresponsive(2, 1000, overdue), "a quiet connection is challenged before it is closed")
	_expect(probe.heartbeat_peers == [2], "send the reliable challenge only to the quiet peer")
	_expect(not probe._connection_is_unresponsive(2, overdue + 30, overdue + 40), "an answer clears the outstanding challenge")
	var later := overdue + timeout_ms + 100
	_expect(not probe._connection_is_unresponsive(2, overdue + 30, later), "a later silence starts a new challenge")
	_expect(probe._connection_is_unresponsive(2, overdue + 30, later + timeout_ms), "a peer that ignores a full challenge enters recovery")
	probe._heartbeat_probes.clear()
	probe.connected_browser_peer = 2
	_expect(not probe._connection_is_unresponsive(2, 1000, overdue), "an open data channel still verifies its peer")
	_expect(not probe._connection_is_unresponsive(2, 1000, overdue + 19000), "a connected browser can finish a long first board frame")
	_expect(probe._connection_is_unresponsive(2, 1000, overdue + int(probe.RECONNECT_GRACE_SECONDS * 1000)), "a browser that never answers the challenge still enters recovery")
	probe.connected_browser_peer = 0
	probe._heartbeat_probes.clear()


func _test_guest_connection_deadlines() -> void:
	var guest: Node = load("res://scripts/tests/WebRoomDirectoryProbe.gd").new()
	root.add_child(guest)
	var errors: Array[String] = []
	var on_failure := func(detail: String): errors.append(detail)
	guest.room_code_lookup_failed.connect(on_failure)
	guest._join_browser_room("345678", {}, "")
	guest.respond(guest.sent.back(), HTTPRequest.RESULT_SUCCESS, 201, {"peer_id": 2})
	guest._process(30.1)
	_expect(not guest.is_online and errors.size() == 1 and "방장의 응답을 받지 못했습니다" in errors[0],
		"a silent host is identified after the bounded answer deadline")

	guest._join_browser_room("345678", {}, "")
	guest.respond(guest.sent.back(), HTTPRequest.RESULT_SUCCESS, 201, {"peer_id": 2})
	guest._web_connection_attempts[1] = "late-answer"
	guest._process(29.5)
	_expect(guest.is_online and guest._web_connect_remaining > 0.0, "slow signaling can pass the former 20 second cutoff")
	var answer := {"from_peer": 1, "type": "answer", "data": {"attempt": "late-answer", "sdp": "valid-answer"}}
	guest._apply_browser_signal(answer)
	guest._process(14.0)
	_expect(guest.is_online and guest._web_connect_remaining > 0.0, "late first host answer gives the data channel time to open")
	guest._apply_browser_signal(answer)
	guest._process(1.1)
	_expect(not guest.is_online and errors.size() == 2 and "두 기기를 직접 연결하지 못했습니다" in errors[1],
		"a known host reply distinguishes direct-link failure and cannot renew the deadline twice")
	guest.room_code_lookup_failed.disconnect(on_failure)
	guest.queue_free()


func _test_direct_first_ice(servers: Array) -> void:
	var host: Node = load("res://scripts/tests/WebRoomDirectoryProbe.gd").new()
	var guest: Node = load("res://scripts/tests/WebRoomDirectoryProbe.gd").new()
	root.add_child(host)
	root.add_child(guest)
	host._create_browser_room({})
	host.respond(host.sent.back(), HTTPRequest.RESULT_SUCCESS, 201, {"ice_servers": servers})
	var admitted := {"peer_id": 2, "ice_servers": servers}
	var direct := [servers[0]]
	guest._join_browser_room("345678", {})
	guest.respond(guest.sent.back(), HTTPRequest.RESULT_SUCCESS, 201, admitted)
	guest._process(30.1)
	_expect(guest.ice_configs.size() == 1 and guest.ice_configs[0].servers == direct and not guest.is_online,
		"a silent host consumes no relay allocation even when credentials were issued")
	guest.ice_configs.clear()
	guest._join_browser_room("345678", {})
	guest.respond(guest.sent.back(), HTTPRequest.RESULT_SUCCESS, 201, admitted)
	var seat_token: String = guest._host_directory_token
	guest._send_browser_signal(1, "offer", {"sdp": "direct"})
	var initial: Dictionary = guest.sent.back().payload
	_expect(initial.data.relay_fallback == false, "the first offer explicitly requests direct connectivity")
	host._apply_browser_signal({"from_peer": 2, "type": "offer", "data": initial.data})
	var answer: Dictionary = host.sent.back().payload
	guest._apply_browser_signal({"from_peer": 1, "type": "answer", "data": answer.data})
	_expect(guest.ice_configs[0].servers == direct and host.ice_configs[0].servers == direct,
		"neither endpoint gives TURN credentials to the browser on its direct attempt")
	guest.connected_browser_peer = 1
	guest._process(8.1)
	_expect(guest.is_online and guest.ice_configs.size() == 1, "a connected direct peer can finish opening its channels without TURN")
	guest.connected_browser_peer = 0
	guest._drop_browser_connection(1)
	guest._on_connection_failed()
	_expect(guest.ice_configs.size() == 2 and guest.ice_configs.back().servers == servers and guest._host_directory_token == seat_token,
		"a failed direct connection retries with TURN once in its original seat")
	guest._send_browser_signal(1, "offer", {"sdp": "fallback"})
	var retry: Dictionary = guest.sent.back().payload
	_expect(retry.data.relay_fallback and retry.data.attempt != initial.data.attempt and retry.data.generation > initial.data.generation,
		"fallback offers use a fresh generation")
	host._apply_browser_signal({"from_peer": 2, "type": "candidate", "data": {"attempt": retry.data.attempt, "generation": retry.data.generation, "sdp": "early-relay"}})
	host._apply_browser_signal({"from_peer": 2, "type": "offer", "data": retry.data})
	_expect(host.ice_configs.back().servers == servers and host.remote_candidates.has("early-relay"),
		"the host enables TURN for this peer and applies its early ICE candidates")
	var fallback_answer: Dictionary = host.sent.back().payload
	guest._apply_browser_signal({"from_peer": 1, "type": "answer", "data": fallback_answer.data})
	_expect(not guest._try_browser_relay(), "a failed relay attempt cannot recursively request another allocation")
	host._apply_browser_signal({"from_peer": 2, "type": "offer", "data": initial.data})
	_expect(host.ice_configs.size() == 2, "replayed direct offers cannot downgrade the replacement")
	host._apply_browser_signal({"from_peer": 3, "type": "offer", "data": {"sdp": "second-direct", "attempt": "other-seat", "relay_fallback": false}})
	_expect(host.ice_configs.back().servers == direct and host._browser_ice_servers_for(2) == servers, "only the peer needing fallback gets TURN")
	host._apply_browser_signal({"from_peer": 4, "type": "offer", "data": {"sdp": "legacy", "attempt": "legacy-seat"}})
	_expect(host.ice_configs.back().servers == servers, "old clients without two-stage signaling retain the legacy ICE choices")
	guest._reconnecting = true
	guest._reconnect_deadline = Time.get_ticks_msec() + 30000
	guest._attempt_reconnect()
	_expect(guest.ice_configs.back().servers == servers and guest._next_reconnect_attempt == guest._reconnect_deadline,
		"recovery retains a necessary relay route without resetting its bounded deadline")
	guest._join_browser_room("345678", {})
	guest.ice_configs.clear()
	guest.respond(guest.sent.back(), HTTPRequest.RESULT_SUCCESS, 201, admitted)
	guest._apply_browser_signal({"from_peer": 1, "type": "answer", "data": {"attempt": "stale", "sdp": "old"}})
	guest._process(8.2)
	_expect(guest.ice_configs.size() == 1, "a stale host answer cannot start the relay grace period")
	guest._apply_browser_signal({"from_peer": 1, "type": "answer", "data": {"attempt": guest._web_connection_attempts[1], "sdp": "new"}})
	guest._process(7.9)
	_expect(guest.ice_configs.size() == 1, "direct ICE gets its full connection window after the matched answer")
	guest._process(0.2)
	_expect(guest.ice_configs.size() == 2 and guest.ice_configs.back().servers == servers, "stalled direct ICE triggers one bounded automatic relay retry")
	guest.disconnect_network()
	host.disconnect_network()
	guest.queue_free()
	host.queue_free()


func _test_dropped_legacy_batches(host: Node) -> void:
	var guest: Node = load("res://scripts/tests/WebRoomDirectoryProbe.gd").new()
	root.add_child(guest)
	guest._web_transport = true
	guest._web_signaling_active = true
	guest.room_code = host.room_code
	guest.my_peer_id = 2
	guest._host_directory_token = "guest-test-credential"
	guest._web_peer_generations[1] = 1
	guest._web_connection_attempts[1] = "fresh-seat"
	host._web_connection_attempts[2] = "prior-seat"
	host._web_peer_generations[2] = 3

	# Both original signals are accepted by the old directory, then its poll response is lost.
	guest._send_browser_signal(1, "offer", {"sdp": "fresh-offer"})
	guest._send_browser_signal(1, "candidate", {"sdp": "guest-ice"})
	guest.respond(guest.sent[0], HTTPRequest.RESULT_SUCCESS, 202)
	guest.respond(guest.sent[1], HTTPRequest.RESULT_SUCCESS, 202)
	guest._replay_pending_browser_signals(4.1)
	_expect(guest.sent.size() == 4 and guest.sent[2].payload == guest.sent[0].payload
		and guest.sent[3].payload == guest.sent[1].payload, "lost successful offer and ICE are replayed unchanged")
	_deliver_recorded_signal(host, guest.sent[3], 2)
	_deliver_recorded_signal(host, guest.sent[2], 2)
	_deliver_recorded_signal(host, guest.sent[2], 2)
	_expect(host.remote_descriptions == ["fresh-offer"] and host.remote_candidates == ["guest-ice"],
		"generation-one successor accepts out-of-order ICE and applies its offer exactly once")
	host._apply_browser_signal({"from_peer": 2, "type": "offer", "data": {
		"attempt": "prior-seat", "generation": 3, "sdp": "expired-offer"}})
	_expect(host._web_connection_attempts[2] == "fresh-seat", "a delayed retired offer cannot displace the replacement")

	var first_answer: Dictionary = host.sent.back()
	host._send_browser_signal(2, "candidate", {"sdp": "host-ice"})
	var first_candidate: Dictionary = host.sent.back()
	host.respond(first_answer, HTTPRequest.RESULT_SUCCESS, 202)
	host.respond(first_candidate, HTTPRequest.RESULT_SUCCESS, 202)
	# The guest loses the entire first answer batch, too.
	host._replay_pending_browser_signals(4.1)
	var resent_answer: Dictionary = host.sent[-2]
	var resent_ice: Dictionary = host.sent[-1]
	_expect(resent_answer.payload == first_answer.payload and resent_ice.payload == first_candidate.payload,
		"lost successful answer and ICE are replayed unchanged")
	_deliver_recorded_signal(guest, resent_answer, 1)
	_deliver_recorded_signal(guest, resent_ice, 1)
	_deliver_recorded_signal(guest, resent_ice, 1)
	_expect(guest.remote_descriptions == ["answer-fresh-offer"] and guest.remote_candidates == ["host-ice"],
		"guest applies the recovered answer and ICE exactly once")
	host._on_peer_connected(2)
	var sent_after_connect: int = host.sent.size()
	host._replay_pending_browser_signals(4.1)
	_expect(host.sent.size() == sent_after_connect, "connected peers stop replaying handshakes")
	for index in range(5):
		guest._replay_pending_browser_signals(4.1)
	_expect(guest.sent.size() == 8, "an unanswered handshake stops after three timed replays")
	guest.queue_free()


func _deliver_recorded_signal(receiver: Node, request: Dictionary, from_peer: int) -> void:
	receiver._apply_browser_signal({"from_peer": from_peer, "type": request.payload.type, "data": request.payload.data})
