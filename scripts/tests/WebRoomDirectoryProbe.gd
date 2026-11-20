extends "res://scripts/network/NetworkManager.gd"

## Controllable responses for the real browser-room networking state machine.
var sent: Array[Dictionary] = []
var remote_descriptions: Array[String] = []
var remote_candidates: Array[String] = []
var online_frames := false

func _ready() -> void:
	set_process(false)

func _set_browser_online_frames(active: bool) -> void:
	online_frames = active

func _send_directory_request(method: int, path: String, payload: Dictionary, callback: Callable, authenticated: bool, token_override: String = "") -> bool:
	var request := HTTPRequest.new()
	request.set_meta("network_session", _network_session)
	add_child(request)
	sent.append({"method": method, "path": path, "payload": payload, "callback": callback.bind(request),
		"token": token_override if not token_override.is_empty() else (_host_directory_token if authenticated else "")})
	return true

func respond(call: Dictionary, result: int, status: int, data: Dictionary = {}) -> void:
	call.callback.call(result, status, PackedStringArray(), JSON.stringify(data).to_utf8_buffer())

func _ensure_browser_connection(_remote_peer_id: int, _create_offer: bool) -> Error:
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
