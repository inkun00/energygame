extends Node

signal records_changed(game_id: String, state: Dictionary)

const ADJECTIVES := ["햇살", "바람", "물결", "새싹", "초록", "무지개", "구름", "별빛"]
const ANIMALS := ["여우", "토끼", "수달", "다람쥐", "고슴도치", "너구리", "고양이", "부엉이"]
const PROFILE_KEY := "energygame.minigame_records.v1"
@onready var _game: Node = get_node("/root/GameManager")
@onready var _network: Node = get_node("/root/NetworkManager")
var profile_path := "user://minigame_records.cfg"
var _secret := ""
var _best := {}
var _outbox := {}
var _sending := {}
var _boards := {}
var _revision := {}
var _loading := {}
var _attempt := {}
var _seen_rounds := {}
var _retry_after := 0

func _ready() -> void:
	# A dedicated server/CI simulation has no pupil playing on this device.
	if DisplayServer.get_name() == "headless": return
	_game.minigame_submission_changed.connect(_round_changed)
	_game.minigame_finished.connect(_round_finished)

func _round_key(game: Dictionary) -> String:
	return "%d/%d/%d" % [_game.game_session_id, int(game.get("round_id", -1)), int(game.get("seed", 0))]

func _seat() -> int:
	return _network.get_local_player_index() if _network.is_online else 0

func _round_changed(state: Dictionary) -> void:
	var game: Dictionary = state.get("game", {})
	if game.get("phase", "") != "playing" or _game.guided_tutorial_active: return
	var idx := _seat()
	if idx >= 0 and idx < _game.players.size() and not _game.players[idx].get("is_ai", false):
		begin_attempt(str(game["id"]), _round_key(game))

func _round_finished(results: Array) -> void:
	var game: Dictionary = _game.active_minigame
	var seat := _seat()
	if game.is_empty() or _game.guided_tutorial_active or seat < 0 or seat >= _game.players.size() or _game.players[seat].get("is_ai", false): return
	for entry in results:
		if int(entry.get("player_idx", -1)) == seat:
			var stats: Dictionary = entry.get("stats", {}).duplicate()
			stats["active_input"] = bool(_attempt.get("input", false))
			finish_attempt(str(game["id"]), _round_key(game), int(entry.get("score", 0)), stats)
			return

func _input(event: InputEvent) -> void:
	if _attempt.is_empty() or _attempt.get("finished", true) or _attempt.get("input", false): return
	if _game.active_minigame.get("phase", "") != "playing" or _game.local_minigame_practice_round_id == int(_game.active_minigame.get("round_id", -2)) or get_tree().paused: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_E]:
			_attempt["input"] = true
	elif (event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed():
		_attempt["input"] = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.35:
		_attempt["input"] = true

func _service_url() -> String:
	var url := OS.get_environment("ENERGYGAME_LEADERBOARD_URL").strip_edges()
	if url.is_empty() and OS.has_feature("web"):
		var location = JavaScriptBridge.get_interface("location")
		if location and str(location.hostname) in ["127.0.0.1", "localhost"]:
			url = "http://%s:8787" % str(location.hostname)
	if url.is_empty(): url = str(ProjectSettings.get_setting("network/leaderboard_url", "")).strip_edges()
	if url.is_empty(): url = _network._room_directory_url()
	if url.begins_with("https://") or url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:"):
		return url.trim_suffix("/")
	return ""

func _token() -> String:
	return (_secret + "|" + _service_url()).sha256_text()

func _alias() -> String:
	var digest := _token().sha256_text()
	return str(ADJECTIVES[digest.substr(0, 2).hex_to_int() % ADJECTIVES.size()]) + str(ANIMALS[digest.substr(2, 2).hex_to_int() % ANIMALS.size()]) + " " + digest.substr(4, 5).to_upper()

func _load_profile() -> void:
	if not _secret.is_empty(): return
	var data := _stored_profile()
	_secret = str(data.get_value("player", "key", ""))
	if _secret.length() != 64 or not _secret.is_valid_hex_number(false):
		_secret = Crypto.new().generate_random_bytes(32).hex_encode()
		_save_profile()
		return
	var scores: Variant = data.get_value("player", "scores", {})
	var pending: Variant = data.get_value("player", "pending", {})
	if scores is Dictionary: _best = scores
	if pending is Dictionary: _outbox = pending

func _stored_profile() -> ConfigFile:
	var data := ConfigFile.new()
	var restored := false
	if OS.has_feature("web"):
		var storage = JavaScriptBridge.get_interface("localStorage")
		if storage:
			var saved = storage.getItem(PROFILE_KEY)
			if saved is String: restored = data.parse(saved) == OK
	if not restored: data.load(profile_path)
	return data

func _save_profile() -> void:
	var data := _stored_profile()
	if data.get_value("player", "key", "") == _secret:
		var previous: Variant = data.get_value("player", "scores", {})
		if previous is Dictionary:
			for game in previous:
				if int(previous[game]) > int(_best.get(game, -1)): _best[game] = int(previous[game])
	data.set_value("player", "key", _secret)
	data.set_value("player", "scores", _best)
	data.set_value("player", "pending", _outbox)
	if OS.has_feature("web"):
		var storage = JavaScriptBridge.get_interface("localStorage")
		if storage: storage.setItem(PROFILE_KEY, data.encode_to_text())
	var staging := profile_path + ".tmp"
	if data.save(staging) == OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(staging), ProjectSettings.globalize_path(profile_path))

func get_board(game_id: String) -> Dictionary:
	_load_profile()
	var best := int(_best.get(game_id, 0))
	var nickname := _alias()
	var state := {"game_id": game_id, "alias": nickname, "entries": [], "personal_best": best, "has_personal_best": _best.has(game_id), "shared_best": 0, "personal_rank": 0, "status": "offline", "scope": "device"}
	if _boards.has(game_id) and Time.get_ticks_msec() >= _retry_after:
		var online: Dictionary = _boards[game_id]
		state.merge({"entries": online["entries"].duplicate(true), "personal_best": maxi(best, int(online["personal_best"])), "shared_best": int(online["personal_best"]), "personal_rank": int(online["personal_rank"]), "scope": "shared", "status": "online"}, true)
		state["has_personal_best"] = _best.has(game_id) or int(online["personal_rank"]) > 0
	elif _best.has(game_id):
		state["entries"] = [{"rank": 1, "alias": nickname, "score": best, "mine": true}]
		state["personal_rank"] = 1
	if _loading.has(game_id): state["status"] = "loading"
	return state

func _updated(game: String) -> void:
	records_changed.emit(game, get_board(game))

func _online_allowed() -> bool:
	return not _service_url().is_empty() and Time.get_ticks_msec() >= _retry_after

func _next_revision(game: String) -> int:
	var version := int(_revision.get(game, 0)) + 1
	_revision[game] = version
	return version

func fetch_board(game_id: String) -> void:
	if not _game.MINIGAME_DEFINITIONS.has(game_id): return
	_load_profile()
	if not _online_allowed():
		_updated(game_id)
		return
	_flush_outbox()
	if _loading.has(game_id): return
	var version := _next_revision(game_id)
	_loading[game_id] = true
	_updated(game_id)
	var result := await _request(HTTPClient.METHOD_GET, "/scores/" + game_id)
	if int(_revision.get(game_id, 0)) != version: return
	_loading.erase(game_id)
	_accept_board(game_id, result)

func _accept_board(game: String, result: Dictionary) -> void:
	var data: Dictionary = result["data"]
	if int(result["code"]) == 200 and data.get("game_id", "") == game and data.get("entries") is Array and data.has("personal_rank") and data.has("personal_best"):
		_boards[game] = data
		var shared_best := int(data["personal_best"])
		if int(data["personal_rank"]) > 0 and shared_best > int(_best.get(game, -1)):
			_best[game] = shared_best
			_save_profile()
	else:
		_boards.erase(game)
	_updated(game)

func begin_attempt(game_id: String, round_key: String) -> void:
	if not _game.MINIGAME_DEFINITIONS.has(game_id) or round_key.is_empty(): return
	var identity := game_id + "/" + round_key
	if _seen_rounds.has(identity): return
	if _seen_rounds.size() >= 128: _seen_rounds.erase(_seen_rounds.keys()[0])
	_seen_rounds[identity] = true
	_load_profile()
	var round := {"key": round_key, "game": game_id, "nonce": Crypto.new().generate_random_bytes(16).hex_encode(), "id": "", "finished": false}
	_attempt = round
	if not _online_allowed(): return
	_flush_outbox()
	var result := await _request(HTTPClient.METHOD_POST, "/scores/%s/attempts" % game_id, {"round_key": round["nonce"]})
	var data: Dictionary = result["data"]
	if int(result["code"]) in [200, 201] and str(data.get("attempt_id", "")).length() == 32:
		round["id"] = str(data["attempt_id"])
		round["expires"] = int(data.get("expires_at", 0))
		if round["finished"]: _queue_finish(round)

func finish_attempt(game_id: String, round_key: String, score: int, stats: Dictionary) -> void:
	if _attempt.get("key", "") != round_key or _attempt.get("game", "") != game_id or _attempt.get("finished", true): return
	_attempt["finished"] = true
	var attempts := int(stats.get("attempts", 0))
	var correct := int(stats.get("correct", 0))
	if score < 0 or score > _game.MINIGAME_SCORE_LIMIT or not bool(stats.get("active_input", false)) or attempts <= 0 or attempts > _game.MINIGAME_NETWORK_EVENT_LIMIT or correct < 0 or correct > attempts: return
	_attempt["score"] = score
	_attempt["stats"] = {"attempts": attempts, "correct": correct, "active_input": true}
	if score > int(_best.get(game_id, -1)):
		_best[game_id] = score
		_save_profile()
	_updated(game_id)
	if not str(_attempt["id"]).is_empty(): _queue_finish(_attempt)

func _queue_finish(round: Dictionary) -> void:
	if not round.has("score"): return
	_outbox[round["id"]] = {"game": round["game"], "score": round["score"], "stats": round["stats"], "expires": round["expires"], "url": _service_url()}
	_save_profile()
	_flush_outbox()

func _flush_outbox() -> void:
	for id: String in _outbox.keys():
		var item: Dictionary = _outbox[id]
		if int(item.get("expires", 0)) < int(Time.get_unix_time_from_system()):
			_outbox.erase(id)
			_save_profile()
		elif _online_allowed() and not _sending.has(id) and item.get("url", "") == _service_url():
			_send_finish(id, item)

func _send_finish(id: String, item: Dictionary) -> void:
	_sending[id] = true
	var game := str(item["game"])
	var version := _next_revision(game)
	_loading.erase(game)
	var result := await _request(HTTPClient.METHOD_POST, "/scores/%s/attempts/%s" % [game, id], {"score": item["score"], "stats": item["stats"]})
	_sending.erase(id)
	var code := int(result["code"])
	if code == 200 or code in [400, 401, 404, 409, 410, 422]:
		_outbox.erase(id)
		_save_profile()
	if code == 200:
		# A finish response can race both a fetch and an earlier completed run.
		# The caller may already be looking at another sport.
		if version == int(_revision.get(game, 0)):
			_accept_board(game, result)
		else:
			_loading.erase(game)
			fetch_board(game)
	elif not _online_allowed():
		_updated(game)

func _request(method: int, path: String, data: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	# A full class may start together. Ticket and finish requests run in the background.
	http.timeout = 20.0 if method == HTTPClient.METHOD_POST else 4.0
	http.max_redirects = 0
	http.body_size_limit = 16384
	add_child(http)
	var headers := PackedStringArray(["Authorization: Bearer " + _token(), "Content-Type: application/json"])
	var err := http.request(_service_url() + path, headers, method, "" if data.is_empty() else JSON.stringify(data))
	var code := 0
	var parsed: Variant = {}
	if err == OK:
		var response: Array = await http.request_completed
		if response[0] == HTTPRequest.RESULT_SUCCESS:
			code = int(response[1])
			if code >= 200 and code < 300:
				parsed = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	http.queue_free()
	if (code == 404 and path.count("/") <= 3) or code == 0 or code == 429 or code >= 500:
		_retry_after = Time.get_ticks_msec() + (3600000 if code == 404 else 60000)
	return {"code": code, "data": parsed if parsed is Dictionary else {}}
