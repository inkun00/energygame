extends "res://scripts/network/NetworkManager.gd"

## Controllable responses for the real browser-room networking state machine.
var sent: Array[Dictionary] = []
var remote_descriptions: Array[String] = []
var remote_candidates: Array[String] = []
var online_frames := false
var heartbeat_peers: Array[int] = []
var connected_browser_peer := 0
var ice_configs: Array[Dictionary] = []

func _ready() -> void:
	set_process(false)

func _send_connection_heartbeat(peer_id: int) -> void:
	heartbeat_peers.append(peer_id)

func _browser_peer_is_connected(peer_id: int) -> bool:
	return peer_id == connected_browser_peer

func _set_browser_online_frames(active: bool) -> void:
	online_frames = active

func _primary_web_directory_url() -> String:
	return "https://rooms.example/api"

func _room_directory_url() -> String:
	return "https://legacy.example"

func _send_directory_request(method: int, path: String, payload: Dictionary, callback: Callable, authenticated: bool, token_override: String = "", directory: String = "") -> bool:
	var request := HTTPRequest.new()
	request.set_meta("network_session", _network_session)
	var base_url := directory if not directory.is_empty() else _active_web_directory
	request.set_meta("directory_url", base_url)
	add_child(request)
	sent.append({"method": method, "path": path, "payload": payload, "callback": callback.bind(request),
		"directory": base_url,
		"token": token_override if not token_override.is_empty() else (_host_directory_token if authenticated else "")})
	return true

func respond(call: Dictionary, result: int, status: int, data: Dictionary = {}) -> void:
	call.callback.call(result, status, PackedStringArray(), JSON.stringify(data).to_utf8_buffer())

func _ensure_browser_connection(remote_peer_id: int, create_offer: bool) -> Error:
	ice_configs.append({"peer": remote_peer_id, "servers": _browser_ice_servers_for(remote_peer_id)})
	if create_offer:
		_web_offer_generation += 1
		_web_connection_attempts[remote_peer_id] = "probe-%d" % _web_offer_generation
		_web_peer_generations[remote_peer_id] = _web_offer_generation
	return OK

func _set_browser_remote_description(remote_peer_id: int, type: String, sdp: String) -> void:
	remote_descriptions.append(sdp)
	_web_remote_description_set[remote_peer_id] = true
	for candidate in _web_pending_candidates.get(remote_peer_id, []):
		_add_browser_ice_candidate(remote_peer_id, candidate)
	_web_pending_candidates.erase(remote_peer_id)
	if type == "offer":
		_send_browser_signal(remote_peer_id, "answer", {"sdp": "answer-" + sdp})

func _add_browser_ice_candidate(_remote_peer_id: int, candidate: Dictionary) -> void:
	remote_candidates.append(candidate.sdp)
