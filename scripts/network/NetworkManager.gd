extends Node

## 데스크톱은 ENet, 브라우저는 WebRTC를 사용하며 방을 만든 플레이어가 권한 서버가 됩니다.

signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal room_state_changed(players)
signal game_started_signal(player_configs, duration_seconds)
signal room_code_created(code)
signal room_code_lookup_failed(message)
signal external_room_ready(code)
signal external_room_failed(message)
signal room_list_received(rooms)
signal room_list_failed(message)

const DEFAULT_PORT: int = 8910
const DISCOVERY_PORT: int = 8911
const MAX_PLAYERS: int = 4
const ROOM_CODE_DIGITS := 6
const DISCOVERY_MAGIC := "energy_fairy_room_v1"
const DISCOVERY_BROADCAST_INTERVAL := 0.65
const DISCOVERY_TIMEOUT_SECONDS := 12.0
const DIRECTORY_HEARTBEAT_SECONDS := 20.0
const WEB_SIGNAL_POLL_INTERVAL := 0.35
const FULL_GAME_SNAPSHOT_INTERVAL_SECONDS := 5.0
const WEB_ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}
]

var is_online := false
var is_host := false
var my_peer_id := 1
var connected_players: Dictionary = {}
var game_peer_ids: Array[int] = []
var shared_board_tiles: Array[Dictionary] = []
var pending_local_player_info: Dictionary = {}
var game_has_started := false
var _game_signals_connected := false
var room_code := ""
var room_title := "함께하는 에너지 모험"
var room_capacity := 4
var _room_password := ""
var _join_password := ""
var _room_list_pending := false
var pending_room_code := ""
var _discovery_broadcaster: PacketPeerUDP
var _discovery_listener: PacketPeerUDP
var _discovery_broadcast_elapsed := 0.0
var _discovery_lookup_remaining := 0.0
var hosted_game_port := DEFAULT_PORT
var _room_lookup_active := false
var _directory_lookup_pending := false
var _external_room_registered := false
var _directory_heartbeat_remaining := 0.0
var _host_directory_token := ""
var _upnp_thread: Thread
var _upnp_setup_pending := false
var _upnp_gateway: UPNP
var _external_host_ip := ""
var _directory_registration_attempts := 0
var _web_transport := false
var _web_multiplayer_peer: WebRTCMultiplayerPeer
var _web_connections: Dictionary = {}
var _web_remote_description_set: Dictionary = {}
var _web_pending_candidates: Dictionary = {}
var _web_signal_poll_remaining := 0.0
var _web_signal_poll_pending := false
var _web_signaling_active := false
var _web_connect_remaining := 0.0
var _full_game_snapshot_remaining := 0.0
var _last_open_market_sync_signature := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_connect_game_signals()
	set_process(true)


func _process(delta: float) -> void:
	if _web_connect_remaining > 0.0:
		_web_connect_remaining -= delta
		if _web_connect_remaining <= 0.0:
			disconnect_network()
			room_code_lookup_failed.emit("방장과 연결하지 못했습니다. 네트워크를 확인하고 다시 참가해 주세요.")
	if _web_transport and _web_signaling_active:
		_web_signal_poll_remaining -= delta
		if _web_signal_poll_remaining <= 0.0 and not _web_signal_poll_pending:
			_web_signal_poll_remaining = WEB_SIGNAL_POLL_INTERVAL
			_poll_browser_signals()
	if is_online and is_host and not game_has_started and _discovery_broadcaster:
		_discovery_broadcast_elapsed -= delta
		if _discovery_broadcast_elapsed <= 0.0:
			_discovery_broadcast_elapsed = DISCOVERY_BROADCAST_INTERVAL
			_broadcast_room_announcement()
	if _discovery_listener:
		_poll_room_announcements()
	if _room_lookup_active:
		_discovery_lookup_remaining -= delta
		if _discovery_lookup_remaining <= 0.0:
			_stop_room_discovery()
			room_code_lookup_failed.emit("해당 방 코드를 찾지 못했습니다. 코드와 방장 상태를 확인하세요.")
	if _upnp_setup_pending and _upnp_thread and not _upnp_thread.is_alive():
		var upnp_result: Dictionary = _upnp_thread.wait_to_finish()
		_upnp_thread = null
		_upnp_setup_pending = false
		_finish_external_room_setup(upnp_result)
	if _external_room_registered and is_host and not game_has_started and not _web_transport:
		_directory_heartbeat_remaining -= delta
		if _directory_heartbeat_remaining <= 0.0:
			_directory_heartbeat_remaining = DIRECTORY_HEARTBEAT_SECONDS
			_send_directory_heartbeat()
	if is_online and is_host and game_has_started and (
		GameManager.is_game_active or GameManager.open_market_active or GameManager.village_construction_active
	):
		_full_game_snapshot_remaining -= delta
		if _full_game_snapshot_remaining <= 0.0:
			_full_game_snapshot_remaining = FULL_GAME_SNAPSHOT_INTERVAL_SECONDS
			_rpc_apply_full_game_state.rpc(_capture_game_state())


func create_room(port: int = DEFAULT_PORT, player_info: Dictionary = {}, settings: Dictionary = {}) -> Error:
	if _uses_browser_webrtc():
		return _create_browser_room(player_info, settings)
	disconnect_network()
	_configure_room(settings)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = true
	my_peer_id = multiplayer.get_unique_id()
	hosted_game_port = port
	pending_local_player_info = _sanitize_player_info(player_info)
	if pending_local_player_info.is_empty():
		pending_local_player_info = _default_player_info("방장")
	connected_players[my_peer_id] = pending_local_player_info.duplicate(true)
	room_code = _generate_room_code()
	_start_room_announcement()
	_begin_external_room_setup()
	room_code_created.emit(room_code)
	room_state_changed.emit(connected_players.duplicate(true))
	print("[Network] 플레이어 호스트 방 개설 완료 · 코드 %s (UDP %d)" % [room_code, port])
	return OK


func join_room(address: String = "127.0.0.1", port: int = DEFAULT_PORT, player_info: Dictionary = {}, password: String = "") -> Error:
	if _uses_browser_webrtc():
		return ERR_UNAVAILABLE
	disconnect_network()
	_join_password = password
	pending_local_player_info = _sanitize_player_info(player_info)
	if pending_local_player_info.is_empty():
		pending_local_player_info = _default_player_info("참가자")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = false
	print("[Network] 플레이어 호스트 연결 시도: %s:%d" % [address, port])
	return OK


func join_room_by_code(code: String, player_info: Dictionary = {}, password: String = "") -> Error:
	var normalized_code := code.strip_edges()
	if not is_valid_room_code(normalized_code):
		return ERR_INVALID_PARAMETER
	if _uses_browser_webrtc():
		return _join_browser_room(normalized_code, player_info, password)
	disconnect_network()
	_join_password = password
	pending_local_player_info = _sanitize_player_info(player_info)
	if pending_local_player_info.is_empty():
		pending_local_player_info = _default_player_info("참가자")
	pending_room_code = normalized_code
	_discovery_listener = PacketPeerUDP.new()
	var error := _discovery_listener.bind(DISCOVERY_PORT, "0.0.0.0")
	var has_directory := is_external_room_directory_configured()
	if error != OK:
		_discovery_listener = null
	if error != OK and not has_directory:
		return error
	_room_lookup_active = true
	_discovery_lookup_remaining = DISCOVERY_TIMEOUT_SECONDS
	if has_directory:
		_lookup_external_room(normalized_code)
	print("[Network] 6자리 방 코드 검색 중: %s" % pending_room_code)
	return OK


func is_valid_room_code(code: String) -> bool:
	if code.length() != ROOM_CODE_DIGITS or not code.is_valid_int():
		return false
	var number := code.to_int()
	return number >= 100000 and number <= 999999 and str(number) == code


func disconnect_network() -> void:
	if _external_room_registered:
		_unregister_external_room()
	_stop_room_announcement()
	_stop_room_discovery()
	_finish_pending_upnp_before_reset()
	_remove_upnp_mapping()
	var active_peer := multiplayer.multiplayer_peer
	if active_peer and not (active_peer is OfflineMultiplayerPeer):
		active_peer.close()
	for connection_variant in _web_connections.values():
		var connection := connection_variant as WebRTCPeerConnection
		if connection:
			connection.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_online = false
	is_host = false
	my_peer_id = 1
	connected_players.clear()
	game_peer_ids.clear()
	shared_board_tiles.clear()
	pending_local_player_info.clear()
	game_has_started = false
	room_code = ""
	room_title = "함께하는 에너지 모험"
	room_capacity = 4
	_room_password = ""
	_join_password = ""
	pending_room_code = ""
	hosted_game_port = DEFAULT_PORT
	_external_room_registered = false
	_directory_heartbeat_remaining = 0.0
	_host_directory_token = ""
	_web_transport = false
	_web_multiplayer_peer = null
	_web_connections.clear()
	_web_remote_description_set.clear()
	_web_pending_candidates.clear()
	_web_signal_poll_remaining = 0.0
	_web_signal_poll_pending = false
	_web_signaling_active = false
	_web_connect_remaining = 0.0
	_full_game_snapshot_remaining = 0.0
	_last_open_market_sync_signature = ""


func update_local_player_info(player_info: Dictionary) -> void:
	pending_local_player_info = _sanitize_player_info(player_info)
	if not is_online:
		return
	if is_host:
		connected_players[my_peer_id] = pending_local_player_info.duplicate(true)
		_broadcast_lobby_state()
	else:
		_rpc_register_player.rpc_id(1, pending_local_player_info, _join_password)


func start_hosted_game(duration_seconds: int) -> bool:
	if not is_online or not is_host or game_has_started:
		return false
	print("[Network] 호스트 게임 구성 시작")
	var peer_ids: Array[int] = []
	for peer_id_variant in connected_players.keys():
		peer_ids.append(int(peer_id_variant))
	peer_ids.sort()
	if my_peer_id in peer_ids:
		peer_ids.erase(my_peer_id)
		peer_ids.push_front(my_peer_id)
	peer_ids = peer_ids.slice(0, room_capacity)

	var configs: Array[Dictionary] = []
	game_peer_ids.clear()
	for peer_id in peer_ids:
		var info: Dictionary = connected_players.get(peer_id, _default_player_info("플레이어"))
		configs.append({
			"name": str(info.get("name", "플레이어")),
			"is_ai": false,
			"char_icon": str(info.get("char_icon", "")),
			"char_color": info.get("char_color", Color(0.3, 0.8, 0.5))
		})
		game_peer_ids.append(peer_id)
	while game_peer_ids.size() < room_capacity:
		game_peer_ids.append(0)

	BoardGrid.assign_random_shortcuts()
	shared_board_tiles.clear()
	for tile in BoardGrid.TILE_DATA:
		shared_board_tiles.append((tile as Dictionary).duplicate(true))
	game_has_started = true
	_full_game_snapshot_remaining = FULL_GAME_SNAPSHOT_INTERVAL_SECONDS
	_last_open_market_sync_signature = ""
	if _external_room_registered:
		_unregister_external_room()
	_stop_room_announcement()
	print("[Network] 공통 게임 시작 전송 · 사람 %d명" % configs.size())
	# 원격 시작 패킷을 먼저 큐에 넣어 뒤이어 발생하는 첫 턴 상태보다 앞서 도착시킵니다.
	_rpc_begin_game.rpc(configs, duration_seconds, game_peer_ids, shared_board_tiles)
	_rpc_begin_game(configs, duration_seconds, game_peer_ids.duplicate(), shared_board_tiles.duplicate(true))
	return true


func get_local_player_index() -> int:
	if not is_online:
		return 0
	return game_peer_ids.find(my_peer_id)


func get_player_index_for_peer(peer_id: int) -> int:
	return game_peer_ids.find(peer_id)


func is_local_player(player_idx: int) -> bool:
	return player_idx == get_local_player_index()


func get_lan_addresses() -> Array[String]:
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		addresses.append(address)
	return addresses


func _generate_room_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%06d" % rng.randi_range(100000, 999999)


func _uses_browser_webrtc() -> bool:
	return OS.has_feature("web")


func _configure_room(settings: Dictionary) -> void:
	room_title = str(settings.get("title", "함께하는 에너지 모험")).strip_edges().left(15)
	room_capacity = clampi(int(settings.get("max_players", 4)), 2, 4)
	_room_password = str(settings.get("password", ""))


func request_room_list() -> void:
	if _room_list_pending:
		return
	_room_list_pending = true
	if not _send_directory_request(HTTPClient.METHOD_GET, "/webrtc/rooms", {}, _on_room_list_response, false):
		_room_list_pending = false
		room_list_failed.emit("방 목록을 가져오지 못했습니다. 새로고침을 눌러 다시 시도하세요.")


func _on_room_list_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	_room_list_pending = false
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or not (parsed is Dictionary) or not (parsed.get("rooms") is Array):
		room_list_failed.emit("방 목록을 가져오지 못했습니다. 새로고침을 눌러 다시 시도하세요.")
		return
	room_list_received.emit(parsed["rooms"])


func _create_browser_room(player_info: Dictionary, settings: Dictionary = {}) -> Error:
	disconnect_network()
	_configure_room(settings)
	if not is_external_room_directory_configured():
		return ERR_UNCONFIGURED
	_web_transport = true
	_web_multiplayer_peer = WebRTCMultiplayerPeer.new()
	var peer_error := _web_multiplayer_peer.create_server()
	if peer_error != OK:
		_web_transport = false
		_web_multiplayer_peer = null
		return peer_error
	multiplayer.multiplayer_peer = _web_multiplayer_peer
	is_online = true
	is_host = true
	my_peer_id = 1
	pending_local_player_info = _sanitize_player_info(player_info)
	if pending_local_player_info.is_empty():
		pending_local_player_info = _default_player_info("방장")
	connected_players[my_peer_id] = pending_local_player_info.duplicate(true)
	room_code = _generate_room_code()
	_host_directory_token = Crypto.new().generate_random_bytes(24).hex_encode()
	_directory_registration_attempts = 0
	if not _register_browser_room():
		disconnect_network()
		return ERR_CANT_CONNECT
	room_code_created.emit(room_code)
	room_state_changed.emit(connected_players.duplicate(true))
	print("[Network] 브라우저 WebRTC 방 생성 중 · 코드 %s" % room_code)
	return OK


func _register_browser_room() -> bool:
	if not _web_transport or not is_host or room_code.is_empty():
		return false
	_directory_registration_attempts += 1
	var payload := {"code": room_code, "host_token": _host_directory_token, "title": room_title, "max_players": room_capacity, "password": _room_password, "host_name": pending_local_player_info.get("name", "방장")}
	return _send_directory_request(HTTPClient.METHOD_POST, "/webrtc/rooms", payload, _on_browser_room_registered, false)


func _on_browser_room_registered(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	if not _web_transport or not is_online or not is_host or game_has_started:
		return
	if response_code == 200 or response_code == 201:
		_external_room_registered = true
		_web_signaling_active = true
		_web_signal_poll_remaining = 0.0
		external_room_ready.emit(room_code)
		print("[Network] 브라우저 WebRTC 방 등록 완료 · 코드 %s" % room_code)
		return
	if response_code == 409 and _directory_registration_attempts < 5:
		room_code = _generate_room_code()
		room_code_created.emit(room_code)
		_register_browser_room()
		return
	var detail := _directory_error_message(body, "WebRTC 방 등록에 실패했습니다.")
	disconnect_network()
	external_room_failed.emit(detail)


func _join_browser_room(code: String, player_info: Dictionary, password: String = "") -> Error:
	disconnect_network()
	if not is_external_room_directory_configured():
		return ERR_UNCONFIGURED
	_web_transport = true
	pending_local_player_info = _sanitize_player_info(player_info)
	if pending_local_player_info.is_empty():
		pending_local_player_info = _default_player_info("참가자")
	pending_room_code = code
	_host_directory_token = Crypto.new().generate_random_bytes(24).hex_encode()
	_room_lookup_active = true
	_discovery_lookup_remaining = DISCOVERY_TIMEOUT_SECONDS
	var payload := {"peer_token": _host_directory_token, "password": password}
	if not _send_directory_request(HTTPClient.METHOD_POST, "/webrtc/rooms/%s/join" % code.uri_encode(), payload, _on_browser_room_joined, false):
		_room_lookup_active = false
		_web_transport = false
		_host_directory_token = ""
		return ERR_CANT_CONNECT
	print("[Network] 브라우저 WebRTC 방 코드 검색 중: %s" % code)
	return OK


func _on_browser_room_joined(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	if not _web_transport or not _room_lookup_active:
		return
	if response_code != 200 and response_code != 201:
		var detail := _directory_error_message(body, "방을 찾을 수 없거나 참가할 수 없습니다.")
		_stop_room_discovery()
		_web_transport = false
		_host_directory_token = ""
		room_code_lookup_failed.emit(detail)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_stop_room_discovery()
		_web_transport = false
		room_code_lookup_failed.emit("방 연결 응답을 읽지 못했습니다.")
		return
	var peer_id := int((parsed as Dictionary).get("peer_id", 0))
	if peer_id < 2 or peer_id > MAX_PLAYERS:
		_stop_room_discovery()
		_web_transport = false
		room_code_lookup_failed.emit("방에서 참가자 번호를 배정받지 못했습니다.")
		return
	var joined_code := pending_room_code
	_web_multiplayer_peer = WebRTCMultiplayerPeer.new()
	var peer_error := _web_multiplayer_peer.create_client(peer_id)
	if peer_error != OK:
		_stop_room_discovery()
		_web_transport = false
		_web_multiplayer_peer = null
		room_code_lookup_failed.emit("브라우저 멀티플레이 연결을 준비하지 못했습니다.")
		return
	multiplayer.multiplayer_peer = _web_multiplayer_peer
	is_online = true
	is_host = false
	my_peer_id = peer_id
	room_code = joined_code
	room_title = str(parsed.get("title", "에너지 모험"))
	room_capacity = clampi(int(parsed.get("max_players", 4)), 2, 4)
	_external_room_registered = true
	_stop_room_discovery()
	_web_signaling_active = true
	_web_signal_poll_remaining = 0.0
	var connection_error := _ensure_browser_connection(1, true)
	_web_connect_remaining = 20.0
	if connection_error != OK:
		disconnect_network()
		room_code_lookup_failed.emit("방장과의 WebRTC 연결을 시작하지 못했습니다.")
		return
	print("[Network] 브라우저 WebRTC 참가자 배정 · peer=%d" % peer_id)


func _ensure_browser_connection(remote_peer_id: int, create_offer: bool) -> Error:
	if not _web_multiplayer_peer:
		return ERR_UNCONFIGURED
	if _web_connections.has(remote_peer_id):
		return OK
	var connection := WebRTCPeerConnection.new()
	var initialize_error := connection.initialize({"iceServers": WEB_ICE_SERVERS})
	if initialize_error != OK:
		return initialize_error
	connection.session_description_created.connect(_on_web_session_description_created.bind(remote_peer_id))
	connection.ice_candidate_created.connect(_on_web_ice_candidate_created.bind(remote_peer_id))
	var add_error := _web_multiplayer_peer.add_peer(connection, remote_peer_id)
	if add_error != OK:
		connection.close()
		return add_error
	_web_connections[remote_peer_id] = connection
	if not _web_pending_candidates.has(remote_peer_id):
		_web_pending_candidates[remote_peer_id] = []
	if create_offer:
		return connection.create_offer()
	return OK


func _on_web_session_description_created(type: String, sdp: String, remote_peer_id: int) -> void:
	var connection := _web_connections.get(remote_peer_id) as WebRTCPeerConnection
	if not connection:
		return
	if connection.set_local_description(type, sdp) != OK:
		return
	_send_browser_signal(remote_peer_id, type, {"sdp": sdp})


func _on_web_ice_candidate_created(media: String, index: int, sdp: String, remote_peer_id: int) -> void:
	_send_browser_signal(remote_peer_id, "candidate", {"media": media, "index": index, "sdp": sdp})


func _send_browser_signal(remote_peer_id: int, signal_type: String, data: Dictionary) -> void:
	if not _web_transport or room_code.is_empty() or _host_directory_token.is_empty():
		return
	var payload := {"to_peer": remote_peer_id, "type": signal_type, "data": data}
	_send_directory_request(HTTPClient.METHOD_POST, "/webrtc/rooms/%s/signals" % room_code.uri_encode(), payload, _on_browser_signal_sent, true)


func _on_browser_signal_sent(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()


func _poll_browser_signals() -> void:
	if not _web_signaling_active or room_code.is_empty() or _web_signal_poll_pending:
		return
	_web_signal_poll_pending = true
	if not _send_directory_request(HTTPClient.METHOD_GET, "/webrtc/rooms/%s/signals" % room_code.uri_encode(), {}, _on_browser_signals_polled, true):
		_web_signal_poll_pending = false


func _on_browser_signals_polled(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	_web_signal_poll_pending = false
	if not _web_transport or not _web_signaling_active:
		return
	if response_code == 401 or response_code == 404:
		_web_signaling_active = false
		if is_host:
			external_room_failed.emit("브라우저 게임방의 연결 시간이 만료되었습니다. 방을 다시 만들어 주세요.")
		else:
			connection_failed.emit()
		return
	if response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	for signal_variant in (parsed as Dictionary).get("signals", []):
		if signal_variant is Dictionary:
			_apply_browser_signal(signal_variant as Dictionary)


func _apply_browser_signal(signal_data: Dictionary) -> void:
	var remote_peer_id := int(signal_data.get("from_peer", 0))
	var signal_type := str(signal_data.get("type", ""))
	var data := signal_data.get("data", {}) as Dictionary
	if remote_peer_id < 1 or remote_peer_id > MAX_PLAYERS or remote_peer_id == my_peer_id:
		return
	if signal_type == "offer":
		if not is_host:
			return
		if _ensure_browser_connection(remote_peer_id, false) != OK:
			return
		_set_browser_remote_description(remote_peer_id, "offer", str(data.get("sdp", "")))
	elif signal_type == "answer":
		_set_browser_remote_description(remote_peer_id, "answer", str(data.get("sdp", "")))
	elif signal_type == "candidate":
		var candidate := {"media": str(data.get("media", "")), "index": int(data.get("index", 0)), "sdp": str(data.get("sdp", ""))}
		if bool(_web_remote_description_set.get(remote_peer_id, false)):
			_add_browser_ice_candidate(remote_peer_id, candidate)
		else:
			var pending: Array = _web_pending_candidates.get(remote_peer_id, [])
			pending.append(candidate)
			_web_pending_candidates[remote_peer_id] = pending


func _set_browser_remote_description(remote_peer_id: int, type: String, sdp: String) -> void:
	var connection := _web_connections.get(remote_peer_id) as WebRTCPeerConnection
	if not connection or sdp.is_empty():
		return
	if connection.set_remote_description(type, sdp) != OK:
		return
	_web_remote_description_set[remote_peer_id] = true
	var pending: Array = _web_pending_candidates.get(remote_peer_id, [])
	for candidate_variant in pending:
		_add_browser_ice_candidate(remote_peer_id, candidate_variant as Dictionary)
	_web_pending_candidates[remote_peer_id] = []


func _add_browser_ice_candidate(remote_peer_id: int, candidate: Dictionary) -> void:
	var connection := _web_connections.get(remote_peer_id) as WebRTCPeerConnection
	if not connection:
		return
	connection.add_ice_candidate(str(candidate.get("media", "")), int(candidate.get("index", 0)), str(candidate.get("sdp", "")))


func _start_room_announcement() -> void:
	_stop_room_announcement()
	_discovery_broadcaster = PacketPeerUDP.new()
	_discovery_broadcaster.set_broadcast_enabled(true)
	_discovery_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_discovery_broadcast_elapsed = 0.0


func _stop_room_announcement() -> void:
	if _discovery_broadcaster:
		_discovery_broadcaster.close()
	_discovery_broadcaster = null


func _broadcast_room_announcement() -> void:
	if not _discovery_broadcaster or room_code.is_empty():
		return
	var host_info: Dictionary = connected_players.get(my_peer_id, {})
	var announcement := {
		"magic": DISCOVERY_MAGIC,
		"code": room_code,
		"port": hosted_game_port,
		"host_name": str(host_info.get("name", "방장"))
	}
	_discovery_broadcaster.put_packet(JSON.stringify(announcement).to_utf8_buffer())


func _poll_room_announcements() -> void:
	while _discovery_listener and _discovery_listener.get_available_packet_count() > 0:
		var packet := _discovery_listener.get_packet()
		var sender_ip := _discovery_listener.get_packet_ip()
		var parsed = JSON.parse_string(packet.get_string_from_utf8())
		if not (parsed is Dictionary):
			continue
		var announcement := parsed as Dictionary
		if str(announcement.get("magic", "")) != DISCOVERY_MAGIC or str(announcement.get("code", "")) != pending_room_code:
			continue
		var game_port := int(announcement.get("port", DEFAULT_PORT))
		var local_info := pending_local_player_info.duplicate(true)
		print("[Network] 방 코드 일치 · %s:%d에 자동 연결" % [sender_ip, game_port])
		_stop_room_discovery()
		var error := join_room(sender_ip, game_port, local_info, _join_password)
		if error != OK:
			room_code_lookup_failed.emit("게임방 연결을 시작하지 못했습니다.")
		return


func _stop_room_discovery() -> void:
	if _discovery_listener:
		_discovery_listener.close()
	_discovery_listener = null
	_discovery_lookup_remaining = 0.0
	_room_lookup_active = false
	_directory_lookup_pending = false


func is_external_room_directory_configured() -> bool:
	return not _room_directory_url().is_empty()


func _room_directory_url() -> String:
	var environment_url := OS.get_environment("ENERGYGAME_ROOM_DIRECTORY_URL").strip_edges()
	if not environment_url.is_empty():
		return environment_url.trim_suffix("/")
	return str(ProjectSettings.get_setting("network/room_directory_url", "")).strip_edges().trim_suffix("/")


func _begin_external_room_setup() -> void:
	if not is_external_room_directory_configured():
		return
	_host_directory_token = Crypto.new().generate_random_bytes(24).hex_encode()
	_directory_registration_attempts = 0
	_upnp_setup_pending = true
	_upnp_thread = Thread.new()
	var error := _upnp_thread.start(_configure_upnp.bind(hosted_game_port))
	if error != OK:
		_upnp_setup_pending = false
		_upnp_thread = null
		external_room_failed.emit("공유기 자동 연결을 시작하지 못했습니다. 같은 네트워크 접속은 계속 사용할 수 있습니다.")


func _configure_upnp(port: int) -> Dictionary:
	var upnp := UPNP.new()
	var discover_error := upnp.discover(2500, 2, "InternetGatewayDevice")
	if discover_error != UPNP.UPNP_RESULT_SUCCESS:
		return {"error": discover_error, "message": "UPnP 공유기를 찾지 못했습니다."}
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"error": UPNP.UPNP_RESULT_NO_GATEWAY, "message": "인터넷 게이트웨이를 확인할 수 없습니다."}
	# 이전 비정상 종료로 같은 매핑이 남은 경우를 대비해 이 게임 포트만 정리합니다.
	upnp.delete_port_mapping(port, "UDP")
	var mapping_error := upnp.add_port_mapping(port, port, "Energy Fairy Kingdom", "UDP", 0)
	if mapping_error != UPNP.UPNP_RESULT_SUCCESS:
		return {"error": mapping_error, "message": "공유기에서 게임 포트를 열 수 없습니다."}
	var external_ip := upnp.query_external_address().strip_edges()
	if external_ip.is_empty():
		upnp.delete_port_mapping(port, "UDP")
		return {"error": UPNP.UPNP_RESULT_INVALID_RESPONSE, "message": "공인 주소를 확인할 수 없습니다."}
	return {"error": UPNP.UPNP_RESULT_SUCCESS, "upnp": upnp, "external_ip": external_ip}


func _finish_external_room_setup(result: Dictionary) -> void:
	if not is_online or not is_host or game_has_started:
		var unused_upnp := result.get("upnp") as UPNP
		if unused_upnp:
			unused_upnp.delete_port_mapping(hosted_game_port, "UDP")
		return
	if int(result.get("error", FAILED)) != UPNP.UPNP_RESULT_SUCCESS:
		external_room_failed.emit("%s 다른 네트워크에서는 공유기 설정을 확인해야 하며, 같은 네트워크 접속은 가능합니다." % str(result.get("message", "외부 연결 준비에 실패했습니다.")))
		return
	_upnp_gateway = result.get("upnp") as UPNP
	_external_host_ip = str(result.get("external_ip", ""))
	_register_external_room()


func _register_external_room() -> void:
	if not is_online or not is_host or room_code.is_empty() or _external_host_ip.is_empty():
		return
	_directory_registration_attempts += 1
	var payload := {
		"code": room_code,
		"port": hosted_game_port,
		"host_token": _host_directory_token,
		"public_ip": _external_host_ip
	}
	if not _send_directory_request(HTTPClient.METHOD_POST, "/rooms", payload, _on_directory_room_registered, false):
		external_room_failed.emit("방 코드 연결 서버에 접속하지 못했습니다. 같은 네트워크 접속은 계속 사용할 수 있습니다.")


func _on_directory_room_registered(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	if not is_online or not is_host or game_has_started:
		return
	if response_code == 200 or response_code == 201:
		_external_room_registered = true
		_directory_heartbeat_remaining = DIRECTORY_HEARTBEAT_SECONDS
		external_room_ready.emit(room_code)
		print("[Network] 외부 방 코드 등록 완료 · %s -> %s:%d" % [room_code, _external_host_ip, hosted_game_port])
		return
	if response_code == 409 and _directory_registration_attempts < 5:
		room_code = _generate_room_code()
		room_code_created.emit(room_code)
		_discovery_broadcast_elapsed = 0.0
		_register_external_room()
		return
	var detail := _directory_error_message(body, "방 코드 연결 서버가 등록을 거절했습니다.")
	external_room_failed.emit("%s 같은 네트워크 접속은 계속 사용할 수 있습니다." % detail)


func _lookup_external_room(code: String) -> void:
	if _directory_lookup_pending:
		return
	_directory_lookup_pending = true
	if not _send_directory_request(HTTPClient.METHOD_GET, "/rooms/%s" % code.uri_encode(), {}, _on_directory_room_lookup, false):
		_directory_lookup_pending = false


func _on_directory_room_lookup(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	_directory_lookup_pending = false
	if not _room_lookup_active or response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var endpoint := parsed as Dictionary
	var host_address := str(endpoint.get("host", "")).strip_edges()
	var game_port := int(endpoint.get("port", DEFAULT_PORT))
	if host_address.is_empty() or game_port < 1 or game_port > 65535:
		return
	_connect_to_room_endpoint(host_address, game_port)


func _connect_to_room_endpoint(host_address: String, port: int) -> void:
	if not _room_lookup_active:
		return
	var local_info := pending_local_player_info.duplicate(true)
	print("[Network] 외부 방 코드 일치 · %s:%d에 자동 연결" % [host_address, port])
	_stop_room_discovery()
	var error := join_room(host_address, port, local_info, _join_password)
	if error != OK:
		room_code_lookup_failed.emit("게임방 연결을 시작하지 못했습니다.")


func _send_directory_heartbeat() -> void:
	if not _external_room_registered or room_code.is_empty():
		return
	_send_directory_request(HTTPClient.METHOD_PUT, "/rooms/%s/heartbeat" % room_code.uri_encode(), {}, _on_directory_heartbeat_completed, true)


func _on_directory_heartbeat_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	if response_code == 404 and is_online and is_host and not game_has_started:
		_external_room_registered = false
		_register_external_room()


func _unregister_external_room() -> void:
	if room_code.is_empty() or not is_external_room_directory_configured():
		_external_room_registered = false
		return
	if _web_transport:
		_web_signaling_active = false
		if is_host:
			_send_directory_request(HTTPClient.METHOD_DELETE, "/webrtc/rooms/%s" % room_code.uri_encode(), {}, _on_directory_room_unregistered, true)
		else:
			_send_directory_request(HTTPClient.METHOD_POST, "/webrtc/rooms/%s/leave" % room_code.uri_encode(), {}, _on_directory_room_unregistered, true)
	else:
		_send_directory_request(HTTPClient.METHOD_DELETE, "/rooms/%s" % room_code.uri_encode(), {}, _on_directory_room_unregistered, true)
	_external_room_registered = false


func _on_directory_room_unregistered(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()


func _send_directory_request(method: int, path: String, payload: Dictionary, callback: Callable, authenticated: bool) -> bool:
	var base_url := _room_directory_url()
	if base_url.is_empty():
		return false
	var request := HTTPRequest.new()
	request.timeout = 5.0
	add_child(request)
	request.request_completed.connect(callback.bind(request), CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if authenticated and not _host_directory_token.is_empty():
		headers.append("Authorization: Bearer %s" % _host_directory_token)
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var error := request.request(base_url + path, headers, method, body)
	if error != OK:
		request.queue_free()
		return false
	return true


func _directory_error_message(body: PackedByteArray, fallback: String) -> String:
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		var message := str((parsed as Dictionary).get("error", "")).strip_edges()
		if not message.is_empty():
			return message
	return fallback


func _remove_upnp_mapping() -> void:
	if _upnp_gateway:
		_upnp_gateway.delete_port_mapping(hosted_game_port, "UDP")
	_upnp_gateway = null
	_external_host_ip = ""


func _finish_pending_upnp_before_reset() -> void:
	if not _upnp_setup_pending or not _upnp_thread:
		return
	var result: Dictionary = _upnp_thread.wait_to_finish()
	_upnp_thread = null
	_upnp_setup_pending = false
	var pending_gateway := result.get("upnp") as UPNP
	if pending_gateway:
		pending_gateway.delete_port_mapping(hosted_game_port, "UDP")


func _exit_tree() -> void:
	_finish_pending_upnp_before_reset()
	_remove_upnp_mapping()


func request_roll_dice(player_idx: int) -> void:
	_request_game_action("roll_dice", {"player_idx": player_idx})


func request_quiz_answer(player_idx: int, choice: String) -> void:
	_request_game_action("quiz_answer", {"player_idx": player_idx, "choice": choice})


func request_spectator_guess(target_idx: int, choice: String) -> void:
	_request_game_action("spectator_guess", {"target_idx": target_idx, "choice": choice})


func request_special_skill(player_idx: int, target_index: int) -> void:
	_request_game_action("special_skill", {"player_idx": player_idx, "target_index": target_index})


func request_lap_reward(player_idx: int, item_id: String) -> void:
	_request_game_action("lap_reward", {"player_idx": player_idx, "item_id": item_id})


func request_build_project(project_index: int, player_idx: int, map_position: Vector2) -> void:
	_request_game_action("build_project", {"project_index": project_index, "player_idx": player_idx, "map_position": map_position})


func request_open_market_offer(player_idx: int, offer: Dictionary) -> void:
	_request_game_action("open_market_offer", {"player_idx": player_idx, "offer": offer.duplicate(true)})


func request_open_market_take(player_idx: int, item_id: String) -> void:
	_request_game_action("open_market_take", {"player_idx": player_idx, "item_id": item_id})


func request_evaluate_village() -> void:
	_request_game_action("evaluate_village", {})


func _request_game_action(action: String, payload: Dictionary) -> void:
	if not is_online:
		return
	if is_host:
		_handle_game_action(my_peer_id, action, payload)
	else:
		_rpc_request_game_action.rpc_id(1, action, payload)


func _on_peer_connected(id: int) -> void:
	print("[Network] 플레이어 연결: %d" % id)
	if is_host and game_has_started:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	print("[Network] 플레이어 연결 종료: %d" % id)
	connected_players.erase(id)
	if _web_connections.has(id):
		_web_connections.erase(id)
		_web_remote_description_set.erase(id)
		_web_pending_candidates.erase(id)
	player_disconnected.emit(id)
	if is_host:
		_broadcast_lobby_state()
		var player_idx := get_player_index_for_peer(id)
		if game_has_started and player_idx >= 0 and player_idx < GameManager.players.size():
			game_peer_ids[player_idx] = 0
			GameManager.players[player_idx]["is_ai"] = true
			GameManager.player_state_changed.emit(player_idx)
			GameManager.status_message_posted.emit("🔌 %s님의 연결이 끊겨 AI가 이어서 플레이합니다." % GameManager.players[player_idx]["name"])
			if GameManager.current_turn_idx == player_idx and GameManager.current_state == GameManager.TurnState.WAIT_ACTION:
				GameManager.call_deferred("_ai_execute_turn")


func _on_connected_to_server() -> void:
	_web_connect_remaining = 0.0
	my_peer_id = multiplayer.get_unique_id()
	print("[Network] 플레이어 호스트 접속 성공: %d" % my_peer_id)
	# ENet 연결 신호가 온 직후 한 프레임 뒤 등록해 호스트의 peer_connected 처리가
	# 끝나기 전에 첫 RPC가 유실되는 환경에서도 안정적으로 입장합니다.
	call_deferred("_send_pending_registration")
	connection_succeeded.emit()


func _send_pending_registration() -> void:
	if is_online and not is_host:
		_rpc_register_player.rpc_id(1, pending_local_player_info, _join_password)


func _on_connection_failed() -> void:
	print("[Network] 플레이어 호스트 접속 실패")
	connection_failed.emit()
	disconnect_network()


func _on_server_disconnected() -> void:
	print("[Network] 방장과의 연결이 끊어졌습니다.")
	server_disconnected.emit()
	disconnect_network()


@rpc("any_peer", "reliable")
func _rpc_register_player(info: Dictionary, password: String = "") -> void:
	if not multiplayer.is_server() or game_has_started:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	print("[Network] 참가자 등록 요청: %d" % sender_id)
	if sender_id <= 0:
		return
	if not _web_transport and not _room_password.is_empty() and password != _room_password:
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	if not connected_players.has(sender_id) and connected_players.size() >= room_capacity:
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	connected_players[sender_id] = _sanitize_player_info(info)
	print("[Network] 로비 인원: %d/%d" % [connected_players.size(), MAX_PLAYERS])
	player_connected.emit(sender_id, connected_players[sender_id])
	_broadcast_lobby_state()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby(players_data: Dictionary, title: String = "에너지 모험", capacity: int = 4) -> void:
	room_title = title
	room_capacity = clampi(capacity, 2, 4)
	connected_players = players_data.duplicate(true)
	room_state_changed.emit(connected_players.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_game(configs: Array, duration_seconds: int, peer_ids: Array, board_tiles: Array) -> void:
	print("[Network] 공통 게임 시작 수신 · peer=%d" % multiplayer.get_unique_id())
	game_has_started = true
	room_capacity = clampi(peer_ids.size(), 2, 4)
	_web_signaling_active = false
	if _web_transport:
		_external_room_registered = false
	var received_peer_ids := peer_ids.duplicate()
	var received_board_tiles := board_tiles.duplicate(true)
	game_peer_ids.clear()
	for peer_id in received_peer_ids:
		game_peer_ids.append(int(peer_id))
	shared_board_tiles.clear()
	for tile in received_board_tiles:
		shared_board_tiles.append((tile as Dictionary).duplicate(true))
	var typed_configs: Array[Dictionary] = []
	for config in configs:
		typed_configs.append((config as Dictionary).duplicate(true))
	game_started_signal.emit(typed_configs, duration_seconds)


@rpc("any_peer", "reliable")
func _rpc_request_game_action(action: String, payload: Dictionary) -> void:
	if not multiplayer.is_server() or not game_has_started:
		return
	_handle_game_action(multiplayer.get_remote_sender_id(), action, payload)


func _handle_game_action(sender_peer_id: int, action: String, payload: Dictionary) -> void:
	if not is_host or not game_has_started:
		return
	var player_idx := get_player_index_for_peer(sender_peer_id)
	if player_idx < 0 or player_idx >= GameManager.players.size():
		return
	match action:
		"roll_dice":
			if int(payload.get("player_idx", -1)) == player_idx:
				GameManager.execute_roll_dice(player_idx)
		"quiz_answer":
			if int(payload.get("player_idx", -1)) == player_idx and GameManager.active_quiz_player_idx == player_idx:
				var choice := str(payload.get("choice", ""))
				GameManager.on_network_quiz_resolved(player_idx, choice == str(GameManager.active_quiz_data.get("answer", "")))
		"spectator_guess":
			GameManager.submit_spectator_quiz_guess(player_idx, int(payload.get("target_idx", -1)), str(payload.get("choice", "")))
		"special_skill":
			if int(payload.get("player_idx", -1)) == player_idx:
				GameManager.use_special_skill(player_idx, int(payload.get("target_index", -1)))
		"lap_reward":
			if int(payload.get("player_idx", -1)) == player_idx:
				GameManager.claim_lap_reward(player_idx, str(payload.get("item_id", "")))
		"build_project":
			if int(payload.get("player_idx", -1)) == player_idx:
				GameManager.build_village_project(int(payload.get("project_index", -1)), player_idx, payload.get("map_position", Vector2(-1, -1)))
		"open_market_offer":
			if int(payload.get("player_idx", -1)) == player_idx:
				GameManager.submit_open_market_offer(player_idx, payload.get("offer", {}))
		"open_market_take":
			if int(payload.get("player_idx", -1)) == player_idx:
				GameManager.take_open_market_item(player_idx, str(payload.get("item_id", "")))
		"evaluate_village":
			if sender_peer_id == 1:
				GameManager.evaluate_village()


func _broadcast_lobby_state() -> void:
	if is_host:
		_rpc_sync_lobby.rpc(connected_players, room_title, room_capacity)


func _connect_game_signals() -> void:
	if _game_signals_connected:
		return
	_game_signals_connected = true
	GameManager.turn_changed.connect(func(idx): _broadcast_game_event("turn_changed", [idx]))
	GameManager.player_moved.connect(func(idx, from_tile, to_tile): _broadcast_game_event("player_moved", [idx, from_tile, to_tile]))
	GameManager.player_state_changed.connect(func(idx): _broadcast_game_event("player_state_changed", [idx]))
	GameManager.dice_rolled.connect(func(idx, value): _broadcast_game_event("dice_rolled", [idx, value]))
	GameManager.dice_input_time_changed.connect(func(idx, seconds): _broadcast_game_event("dice_input_time_changed", [idx, seconds]))
	GameManager.quiz_requested.connect(func(idx, quiz): _broadcast_game_event("quiz_requested", [idx, quiz]))
	GameManager.quiz_resolved.connect(func(idx, correct): _broadcast_game_event("quiz_resolved", [idx, correct]))
	GameManager.spectator_quiz_bonus_resolved.connect(func(observer, target, correct, score): _broadcast_game_event("spectator_quiz_bonus_resolved", [observer, target, correct, score]))
	GameManager.game_over.connect(func(rankings): _broadcast_game_event("game_over", [rankings]))
	GameManager.status_message_posted.connect(func(message): _broadcast_game_event("status_message_posted", [message]))
	GameManager.kingdom_progress_changed.connect(func(built, total, health): _broadcast_game_event("kingdom_progress_changed", [built, total, health]))
	GameManager.player_inventory_changed.connect(func(idx, inventory): _broadcast_game_event("player_inventory_changed", [idx, inventory]))
	GameManager.tile_item_collected.connect(func(tile_idx, player_idx, item_id): _broadcast_game_event("tile_item_collected", [tile_idx, player_idx, item_id]))
	GameManager.special_skill_activated.connect(func(player_idx, target_idx, skill): _broadcast_game_event("special_skill_activated", [player_idx, target_idx, skill]))
	GameManager.special_skill_completed.connect(func(player_idx): _broadcast_game_event("special_skill_completed", [player_idx]))
	GameManager.village_construction_started.connect(func(inventories): _broadcast_game_event("village_construction_started", [inventories]))
	GameManager.village_construction_changed.connect(func(inventories, built, health): _broadcast_game_event("village_construction_changed", [inventories, built, health]))
	GameManager.game_time_changed.connect(func(remaining, total): _broadcast_game_event("game_time_changed", [remaining, total]))
	GameManager.lap_completed.connect(func(idx, lap, rank, reward): _broadcast_game_event("lap_completed", [idx, lap, rank, reward]))
	GameManager.lap_reward_requested.connect(func(idx, rank, reward): _broadcast_game_event("lap_reward_requested", [idx, rank, reward]))
	GameManager.lap_reward_completed.connect(func(idx, items): _broadcast_game_event("lap_reward_completed", [idx, items]))
	GameManager.open_market_state_changed.connect(func(state): _broadcast_game_event("open_market_state_changed", [state]))


func _broadcast_game_event(event_name: String, event_args: Array) -> void:
	if not is_online or not is_host or not game_has_started:
		return
	if event_name == "game_time_changed" or event_name == "dice_input_time_changed":
		_rpc_apply_time_event.rpc(_capture_time_patch(event_name, event_args), event_name, event_args)
		return
	if event_name == "open_market_state_changed":
		var market_state: Dictionary = event_args[0] if not event_args.is_empty() else {}
		var market_signature := var_to_str([
			market_state.get("active", false),
			market_state.get("phase", 0),
			market_state.get("submitted_players", {}),
			market_state.get("stock", {}),
			market_state.get("allowances", {}),
			market_state.get("taken_counts", {})
		])
		if market_signature == _last_open_market_sync_signature:
			_rpc_apply_time_event.rpc(_capture_time_patch(event_name, event_args), event_name, event_args)
			return
		_last_open_market_sync_signature = market_signature
	_rpc_apply_game_patch.rpc(_capture_game_state_patch(event_name, event_args), event_name, event_args)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_game_patch(patch: Dictionary, event_name: String, event_args: Array) -> void:
	if is_host:
		return
	GameManager.apply_network_patch(patch, event_name, event_args)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_apply_time_event(patch: Dictionary, event_name: String, event_args: Array) -> void:
	if is_host:
		return
	GameManager.apply_network_patch(patch, event_name, event_args)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_full_game_state(snapshot: Dictionary) -> void:
	if is_host:
		return
	GameManager.apply_network_state(snapshot, "", [])


func _capture_time_patch(event_name: String, event_args: Array) -> Dictionary:
	match event_name:
		"game_time_changed":
			return {
				"game_time_remaining": float(event_args[0]) if event_args.size() >= 1 else GameManager.game_time_remaining,
				"game_duration_seconds": int(event_args[1]) if event_args.size() >= 2 else GameManager.game_duration_seconds
			}
		"dice_input_time_changed":
			return {
				"dice_input_time_remaining": float(event_args[1]) if event_args.size() >= 2 else GameManager.dice_input_time_remaining
			}
		"open_market_state_changed":
			return {
				"open_market_time_remaining": float((event_args[0] as Dictionary).get("time_remaining", GameManager.open_market_time_remaining)) if not event_args.is_empty() else GameManager.open_market_time_remaining
			}
	return {}


func _capture_game_state_patch(event_name: String, event_args: Array) -> Dictionary:
	var patch := {
		"current_state": int(GameManager.current_state),
		"current_turn_idx": GameManager.current_turn_idx,
		"total_turns": GameManager.total_turns,
		"is_game_active": GameManager.is_game_active
	}
	match event_name:
		"turn_changed":
			patch["special_skill_used_this_turn"] = GameManager.special_skill_used_this_turn
			patch["dice_input_time_remaining"] = GameManager.dice_input_time_remaining
			patch["active_quiz_data"] = GameManager.active_quiz_data.duplicate(true)
			patch["active_quiz_player_idx"] = GameManager.active_quiz_player_idx
			patch["active_spectator_quiz_attempts"] = GameManager.active_spectator_quiz_attempts.duplicate(true)
			patch["pending_lap_reward"] = GameManager.pending_lap_reward.duplicate(true)
		"player_moved", "player_state_changed", "player_inventory_changed":
			_add_player_update(patch, int(event_args[0]) if not event_args.is_empty() else -1)
			patch["pending_lap_reward"] = GameManager.pending_lap_reward.duplicate(true)
		"quiz_requested":
			patch["active_quiz_data"] = GameManager.active_quiz_data.duplicate(true)
			patch["active_quiz_player_idx"] = GameManager.active_quiz_player_idx
			patch["active_spectator_quiz_attempts"] = GameManager.active_spectator_quiz_attempts.duplicate(true)
		"quiz_resolved":
			_add_player_update(patch, int(event_args[0]) if not event_args.is_empty() else -1)
			patch["active_quiz_data"] = GameManager.active_quiz_data.duplicate(true)
			patch["active_quiz_player_idx"] = GameManager.active_quiz_player_idx
			patch["active_spectator_quiz_attempts"] = GameManager.active_spectator_quiz_attempts.duplicate(true)
		"spectator_quiz_bonus_resolved":
			_add_player_update(patch, int(event_args[0]) if not event_args.is_empty() else -1)
			patch["active_spectator_quiz_attempts"] = GameManager.active_spectator_quiz_attempts.duplicate(true)
		"kingdom_progress_changed":
			_add_kingdom_state(patch)
		"tile_item_collected":
			if event_args.size() >= 2:
				patch["collected_item_update"] = {int(event_args[0]): int(event_args[1])}
		"special_skill_activated", "special_skill_completed":
			_add_player_update(patch, int(event_args[0]) if not event_args.is_empty() else -1)
			patch["special_skill_used_this_turn"] = GameManager.special_skill_used_this_turn
		"lap_completed", "lap_reward_requested", "lap_reward_completed":
			_add_player_update(patch, int(event_args[0]) if not event_args.is_empty() else -1)
			patch["lap_finish_orders"] = GameManager.lap_finish_orders.duplicate(true)
			patch["pending_lap_reward"] = GameManager.pending_lap_reward.duplicate(true)
		"open_market_state_changed":
			_add_open_market_state(patch)
		"village_construction_started", "village_construction_changed":
			patch["players"] = GameManager.players.duplicate(true)
			_add_kingdom_state(patch)
			patch["village_construction_active"] = GameManager.village_construction_active
			patch["village_ai_construction_running"] = GameManager.village_ai_construction_running
			patch["built_project_ids"] = GameManager.built_project_ids.duplicate()
			patch["built_project_placements"] = GameManager.built_project_placements.duplicate(true)
			patch["built_project_owners"] = GameManager.built_project_owners.duplicate(true)
		"game_over":
			patch["players"] = GameManager.players.duplicate(true)
			_add_kingdom_state(patch)
			patch["village_construction_active"] = GameManager.village_construction_active
			patch["village_ai_construction_running"] = GameManager.village_ai_construction_running
	return patch


func _add_player_update(patch: Dictionary, player_idx: int) -> void:
	if player_idx < 0 or player_idx >= GameManager.players.size():
		return
	var player_updates: Dictionary = patch.get("player_updates", {})
	player_updates[player_idx] = GameManager.players[player_idx].duplicate(true)
	patch["player_updates"] = player_updates


func _add_kingdom_state(patch: Dictionary) -> void:
	patch["projects_built"] = GameManager.projects_built
	patch["kingdom_health"] = GameManager.kingdom_health
	patch["kingdom_recovered"] = GameManager.kingdom_recovered
	patch["team_quiz_correct"] = GameManager.team_quiz_correct


func _add_open_market_state(patch: Dictionary) -> void:
	patch["open_market_active"] = GameManager.open_market_active
	patch["open_market_phase"] = int(GameManager.open_market_phase)
	patch["open_market_time_remaining"] = GameManager.open_market_time_remaining
	patch["open_market_submitted_players"] = GameManager.open_market_submitted_players.duplicate(true)
	patch["open_market_stock"] = GameManager.open_market_stock.duplicate(true)
	patch["open_market_take_allowances"] = GameManager.open_market_take_allowances.duplicate(true)
	patch["open_market_taken_counts"] = GameManager.open_market_taken_counts.duplicate(true)


func _capture_game_state() -> Dictionary:
	return {
		"players": GameManager.players.duplicate(true),
		"current_state": int(GameManager.current_state),
		"current_turn_idx": GameManager.current_turn_idx,
		"total_turns": GameManager.total_turns,
		"is_game_active": GameManager.is_game_active,
		"active_quiz_data": GameManager.active_quiz_data.duplicate(true),
		"active_quiz_player_idx": GameManager.active_quiz_player_idx,
		"active_spectator_quiz_attempts": GameManager.active_spectator_quiz_attempts.duplicate(true),
		"projects_built": GameManager.projects_built,
		"kingdom_health": GameManager.kingdom_health,
		"kingdom_recovered": GameManager.kingdom_recovered,
		"team_quiz_correct": GameManager.team_quiz_correct,
		"village_construction_active": GameManager.village_construction_active,
		"built_project_ids": GameManager.built_project_ids.duplicate(),
		"built_project_placements": GameManager.built_project_placements.duplicate(true),
		"built_project_owners": GameManager.built_project_owners.duplicate(true),
		"collected_item_tiles": GameManager.collected_item_tiles.duplicate(true),
		"special_skill_used_this_turn": GameManager.special_skill_used_this_turn,
		"game_duration_seconds": GameManager.game_duration_seconds,
		"game_time_remaining": GameManager.game_time_remaining,
		"lap_finish_orders": GameManager.lap_finish_orders.duplicate(true),
		"pending_lap_reward": GameManager.pending_lap_reward.duplicate(true),
		"dice_input_time_remaining": GameManager.dice_input_time_remaining,
		"village_ai_construction_running": GameManager.village_ai_construction_running,
		"open_market_active": GameManager.open_market_active,
		"open_market_phase": int(GameManager.open_market_phase),
		"open_market_time_remaining": GameManager.open_market_time_remaining,
		"open_market_submitted_players": GameManager.open_market_submitted_players.duplicate(true),
		"open_market_stock": GameManager.open_market_stock.duplicate(true),
		"open_market_take_allowances": GameManager.open_market_take_allowances.duplicate(true),
		"open_market_taken_counts": GameManager.open_market_taken_counts.duplicate(true)
	}


func _sanitize_player_info(info: Dictionary) -> Dictionary:
	if info.is_empty():
		return {}
	var clean_name := str(info.get("name", "플레이어")).strip_edges()
	if clean_name.is_empty():
		clean_name = "플레이어"
	clean_name = clean_name.left(6)
	return {
		"name": clean_name,
		"char_icon": str(info.get("char_icon", "res://assets/characters/eco_roster/captain_eco.webp")),
		"char_color": info.get("char_color", Color(0.3, 0.8, 0.5))
	}


func _default_player_info(player_name: String) -> Dictionary:
	return {
		"name": player_name,
		"char_icon": "res://assets/characters/eco_roster/captain_eco.webp",
		"char_color": Color(0.3, 0.8, 0.5)
	}
