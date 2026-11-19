extends SceneTree

class HeldRequest extends RefCounted:
	signal done(result: Dictionary)
	var path: String
	var body: Dictionary

class TestRecords extends "res://scripts/core/MiniGameRecords.gd":
	var requests: Array[HeldRequest] = []
	var enabled := false

	func _service_url() -> String:
		return "http://127.0.0.1:8787" if enabled else ""

	func _request(_method: int, path: String, data: Dictionary = {}) -> Dictionary:
		var held := HeldRequest.new()
		held.path = path
		held.body = data.duplicate(true)
		requests.append(held)
		return await held.done

var errors := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, text: String) -> void:
	if not condition:
		errors += 1
		push_error(text)

func _run() -> void:
	var path := OS.get_temp_dir().path_join("arcade-record-%s.cfg" % Crypto.new().generate_random_bytes(8).hex_encode())
	var a := TestRecords.new()
	a.profile_path = path
	root.add_child(a)
	var first: Dictionary = a.get_board("solar_align")
	check(first["scope"] == "device" and not first["has_personal_best"] and first["entries"].is_empty(), "empty offline ledger")
	var stats := {"attempts":3,"correct":2,"active_input":true}
	a.begin_attempt("solar_align", "one")
	a.finish_attempt("solar_align", "one", 0, {"attempts":0,"correct":0,"active_input":false})
	check(not a.get_board("solar_align")["has_personal_best"], "idle expiry creates no record")
	a.begin_attempt("solar_align", "two")
	a.finish_attempt("solar_align", "two", 0, stats)
	check(a.get_board("solar_align")["has_personal_best"] and a.get_board("solar_align")["personal_rank"] == 1, "played zero survives as a real first record")
	a.finish_attempt("solar_align", "two", 200, stats)
	a.begin_attempt("solar_align", "old")
	a.begin_attempt("solar_align", "three")
	a.finish_attempt("solar_align", "old", 900, stats)
	a.begin_attempt("solar_align", "two")
	a.finish_attempt("solar_align", "two", 600, stats)
	check(a.get_board("solar_align")["personal_best"] == 0, "duplicate and abandoned rounds are ignored")
	a.finish_attempt("solar_align", "three", 75, stats)
	a.free()
	var b := TestRecords.new()
	b.profile_path = path
	root.add_child(b)
	var saved := b.get_board("solar_align")
	check(saved["alias"] == first["alias"] and saved["personal_best"] == 75 and saved["entries"][0]["mine"], "identity and best restored from another instance")
	check(not b.get_board("eco_commute")["has_personal_best"], "sports keep independent bests")
	b.enabled = true
	b.fetch_board("solar_align")
	var old_fetch := b.requests[0]
	b.begin_attempt("solar_align", "four")
	var start := b.requests[1]
	b.finish_attempt("solar_align", "four", 80, stats)
	check(b.get_board("solar_align")["personal_best"] == 80 and b.requests.size() == 2, "local finish is immediate while ticket is pending")
	start.done.emit({"code":201,"data":{"attempt_id":"a".repeat(32),"expires_at":int(Time.get_unix_time_from_system()) + 900}})
	check(b.requests.size() == 3 and b.requests[2].body["score"] == 80, "ticket resolves queued finish exactly once")
	b.requests[2].done.emit({"code":200,"data":{"game_id":"solar_align","entries":[],"personal_best":80,"personal_rank":11}})
	old_fetch.done.emit({"code":200,"data":{"game_id":"solar_align","entries":[],"personal_best":20,"personal_rank":22}})
	saved = b.get_board("solar_align")
	check(saved["scope"] == "shared" and saved["shared_best"] == 80 and saved["personal_rank"] == 11, "late fetch cannot replace the confirmed board")
	b.fetch_board("solar_align")
	b.requests.back().done.emit({"code":404,"data":{}})
	saved = b.get_board("solar_align")
	check(saved["scope"] == "device" and saved["personal_best"] == 80, "unavailable service falls back to device record")
	b.free()
	DirAccess.remove_absolute(path)
	if errors == 0: print("[PASS] MiniGameRecords: offline restart, played zero, attempts, delayed ticket, stale response, shared personal rank")
	quit(1 if errors else 0)
