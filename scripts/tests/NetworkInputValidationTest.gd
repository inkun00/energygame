extends SceneTree

var failures: Array[String] = []
var gm: Node
var nm: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _round(game_id: String, remaining: float = 0.9) -> int:
	var configs: Array[Dictionary] = [{"name":"Host", "is_ai":false}, {"name":"Guest", "is_ai":false}]
	gm.setup_game(configs, 600)
	gm.set_process(false)
	gm._start_minigame(0, game_id)
	gm.active_minigame["phase"] = "playing"
	gm.minigame_time_remaining = remaining
	return int(gm.active_minigame["round_id"])

func _claim(score: Variant, stats: Variant, round_id: Variant, peer: int = 2, player: Variant = 1) -> void:
	nm._handle_game_action(peer, "minigame_score", {"player_idx":player, "round_id":round_id, "score":score, "stats":stats})

func _run() -> void:
	gm = root.get_node("GameManager")
	nm = root.get_node("NetworkManager")
	nm.is_host = true
	nm.game_has_started = true
	nm.game_peer_ids.assign([1, 2, 0, 0])
	var stats := {"correct":3, "attempts":5, "best_streak":3}
	var round_id := _round("solar_align", 31.0)
	_claim(5000, {"correct":0,"attempts":0,"best_streak":0}, round_id)
	_claim(100, stats, round_id)
	_check(not gm.minigame_scores.has(1), "Immediate fabricated and plausible early scores must both be rejected")
	gm.minigame_time_remaining = 0.9
	for malformed in ["300", 300.0, -1, 5001, {}, null]:
		_claim(malformed, stats, round_id)
		_check(not gm.minigame_scores.has(1), "Invalid score types/ranges must not consume the player's submission")
	for malformed in [{}, [], {"correct":0,"attempts":0,"best_streak":0}, {"correct":6,"attempts":5,"best_streak":3}, {"correct":3,"attempts":5,"best_streak":6}, {"correct":3,"attempts":-5,"best_streak":3}, {"correct":3,"attempts":4097,"best_streak":3}, {"correct":3.0,"attempts":5,"best_streak":3}]:
		_claim(300, malformed, round_id)
		_check(not gm.minigame_scores.has(1), "Malformed, empty or inconsistent activity statistics must be rejected")
	_claim(300, stats, str(round_id))
	_claim(300, {"correct":3,"attempts":5,"best_streak":3,"concept_attempts":"5"}, round_id)
	_claim(300, {"correct":3,"attempts":5,"best_streak":3,"concept_attempts":6}, round_id)
	_claim(300, {"correct":3,"attempts":5,"best_streak":3,"concept_attempts":2}, round_id)
	_claim(300, stats, round_id - 1)
	_claim(300, stats, round_id, 99)
	_claim(300, stats, round_id, 2, 0)
	_claim(300, stats, round_id, 2, "1")
	_check(gm.minigame_scores.is_empty(), "Wrong round, peer, player and player type must not affect any seat")
	paused = true
	_claim(300, stats, round_id)
	_check(gm.minigame_scores.is_empty(), "Recovery pause must reject claims")
	paused = false
	gm.players[1]["is_ai"] = true
	_claim(300, stats, round_id)
	_check(gm.minigame_scores.is_empty(), "A guest cannot submit for an AI replacement")
	gm.players[1]["is_ai"] = false
	gm.active_minigame["phase"] = "ready"
	_claim(300, stats, round_id)
	_check(gm.minigame_scores.is_empty(), "Ready phase must reject claims")
	var samples := {
		"solar_align":[300,3,5,4], "wind_rhythm":[1200,2,60,60],
		"grid_balance":[64,2,2,2], "standby_hunt":[360,3,5,3],
		"hydro_gate":[200,0,10,10], "energy_sort":[450,5,8,5],
		"battery_relay":[400,4,8,4],
		"eco_commute":[2 * gm.SHARED_SCHOOL_BUS.score_for_trip(45,56.0),2,9,8],
		"heat_leak":[330,3,4,3]
	}
	for game_id in samples:
		round_id = _round(game_id)
		_claim(5000, {"correct":0,"attempts":0,"best_streak":0}, round_id)
		_check(gm.minigame_scores.is_empty(), game_id + ": no-activity score injection must be rejected")
		var sample: Array = samples[game_id]
		var valid_stats := {"correct":sample[1],"attempts":sample[2],"best_streak":sample[3]}
		_claim(sample[0], valid_stats, round_id)
		_check(gm.minigame_scores.has(1) and int(gm.minigame_scores.get(1,{}).get("score",-1)) == sample[0], game_id + ": valid game-specific score must be accepted unchanged")
		_claim(0, valid_stats, round_id)
		_check(int(gm.minigame_scores.get(1,{}).get("score",-1)) == sample[0], game_id + ": duplicate submission must not replace score")
		round_id = _round(game_id)
		_claim(0, {"correct":0,"attempts":0,"best_streak":0}, round_id)
		_check(gm.minigame_scores.has(1), game_id + ": a zero-score round must remain valid")
	for game_id in ["solar_align","wind_rhythm","grid_balance","standby_hunt","energy_sort","battery_relay","eco_commute","heat_leak"]:
		round_id = _round(game_id)
		_claim(5000, {"correct":1,"attempts":1,"best_streak":1}, round_id)
		_check(gm.minigame_scores.is_empty(), game_id + ": score exceeding one event's maximum must be rejected")
	round_id = _round("wind_rhythm")
	_claim(150, {"correct":3,"attempts":20,"best_streak":3}, round_id)
	_check(gm.minigame_scores.is_empty(), "Wind cannot report more than two alignment/storm pairs")
	round_id = _round("grid_balance")
	_claim(4800, {"correct":0,"attempts":150,"best_streak":150}, round_id)
	_check(gm.minigame_scores.is_empty(), "Grid old automatic-tick claims must exceed the new decision limit")
	round_id = _round("battery_relay")
	_claim(160, {"correct":2,"attempts":2,"best_streak":2}, round_id)
	_check(gm.minigame_scores.is_empty(), "Empty battery cannot report supply without prior storage")
	round_id = _round("hydro_gate",31.0)
	_claim(1, {"correct":0,"attempts":1,"best_streak":1}, round_id)
	_check(gm.minigame_scores.is_empty(), "Hydro cannot finish before the earliest physically possible overflow")
	var earliest: float = gm._earliest_hydro_overflow_seconds()
	gm.minigame_time_remaining = 31.0 - earliest - 0.2
	_claim(0, {"correct":0,"attempts":0,"best_streak":0}, round_id)
	_check(gm.minigame_scores.has(1), "Legitimate early hydro overflow with no generation must remain valid")
	gm.stop_game()
	nm.is_host = false
	nm.game_has_started = false
	nm.game_peer_ids.clear()
	if failures.is_empty():
		print("[PASS] Network score validation: schema, timing, all nine scoring rules, zero score, hydro overflow, ownership and duplicates")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
