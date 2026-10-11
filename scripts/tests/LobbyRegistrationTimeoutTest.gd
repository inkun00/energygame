extends SceneTree

## Run host and idle1..idle4 together. idle1 then registers normally in a freed slot.
const TEST_PORT := 18920
var role := "host"
var nm: Node
var disconnected := false
var finished := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
	call_deferred("_run")

func _until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and not finished and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()

func _run() -> void:
	nm = root.get_node("NetworkManager")
	ProjectSettings.set_setting("network/room_directory_url", "")
	OS.set_environment("ENERGYGAME_ROOM_DIRECTORY_URL", "")
	create_timer(18.0).timeout.connect(func(): _fail("watchdog expired"))
	if role == "host":
		if nm.create_room(TEST_PORT, {"name":"QA host"}) != OK:
			_fail("cannot open local test port")
			return
		if not await _until(func(): return nm._pending_registrations.size() == 4, 4.0):
			_fail("four unregistered peers must connect")
			return
		if not await _until(func(): return nm._pending_registrations.is_empty() and get_multiplayer().get_peers().is_empty(), 6.0):
			_fail("lobby must release all four unregistered peers after five seconds")
			return
		if nm.game_has_started or nm.connected_players.size() != 1:
			_fail("cleanup must run before game start and preserve the host")
			return
		if not await _until(func(): return nm.connected_players.size() == 2, 3.0):
			_fail("normal registration must succeed in a freed slot")
			return
		await create_timer(0.5).timeout
	else:
		# Keep the real Godot/ENet handshake, omitting only the application RPC.
		get_multiplayer().connected_to_server.disconnect(nm._on_connected_to_server)
		nm.server_disconnected.connect(func(): disconnected = true)
		await create_timer(0.3).timeout
		if nm.join_room("127.0.0.1", TEST_PORT, {"name":"Idle"}) != OK:
			_fail("cannot connect idle peer")
			return
		if not await _until(func(): return disconnected):
			_fail("unregistered peer must be disconnected by the host")
			return
		if role == "idle1":
			await create_timer(0.6).timeout
			get_multiplayer().connected_to_server.connect(nm._on_connected_to_server)
			nm.join_room("127.0.0.1", TEST_PORT, {"name":"Normal"})
			if not await _until(func(): return nm.connected_players.has(nm.my_peer_id), 3.0):
				_fail("normal client cannot register after cleanup")
				return
			await create_timer(0.2).timeout
	finished = true
	print("[PASS] Lobby registration timeout %s: expired idle connections and normal replacement" % role)
	nm.disconnect_network()
	quit(0)

func _fail(message: String) -> void:
	if finished: return
	finished = true
	push_error("[FAIL] Lobby timeout %s: %s" % [role, message])
	if nm: nm.disconnect_network()
	quit(1)
