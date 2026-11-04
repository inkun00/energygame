extends SceneTree

## Four independent ENet clients. This is a rules/integration test, not a pupil
## usability test. Board positions, reading delays and seven round clocks are
## fixtures; solar (30s) and bus (60s) retain their real production clocks.
const PORT := 18921
const SCORES := [400, 400, 300, 200]
const RANKS := [1, 1, 3, 4]
const REWARDS := [20, 20, 5, 1]
const REAL_TIME_GAMES := ["solar_align", "eco_commute"]
var role := "host"
var nm: Node
var gm: Node
var probe: Probe
var checks := 0
var failed := false
var finished := false
var reports: Dictionary = {}
var turn_automation := true
var dice_seats: Dictionary = {}
var quiz_seats: Dictionary = {}
var results: Dictionary = {}
var energy_before: Array[int] = []
var submitted_round := -1
var countdown_round := -1
var playing_round := -1
var round_started_ms := 0
var restored_count := 0
var endings: Array = []
var market_offer_sent := false
var market_take_sent := false

class Probe extends Node:
	var runner: SceneTree
	@rpc("authority", "call_local", "reliable")
	func command(kind: String, payload: Dictionary = {}) -> void:
		runner._command(kind, payload)
	@rpc("any_peer", "call_remote", "reliable")
	func report(kind: String, seat: int, payload: Dictionary) -> void:
		runner._report(kind, seat, payload)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
	call_deferred("_run")

func _run() -> void:
	nm = root.get_node("NetworkManager")
	gm = root.get_node("GameManager")
	probe = Probe.new()
	probe.name = "FourPlayerRulesProbe"
	probe.runner = self
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(probe)
	ProjectSettings.set_setting("network/room_directory_url", "")
	OS.set_environment("ENERGYGAME_ROOM_DIRECTORY_URL", "")
	nm.game_started_signal.connect(_game_started)
	nm.session_restored.connect(func(): restored_count += 1)
	gm.turn_changed.connect(_turn_changed)
	gm.dice_rolled.connect(func(idx, _value): dice_seats[idx] = true)
	gm.quiz_requested.connect(_quiz_requested)
	gm.quiz_resolved.connect(_quiz_resolved)
	gm.minigame_started.connect(_minigame_started)
	gm.minigame_submission_changed.connect(_minigame_state)
	gm.minigame_finished.connect(_minigame_finished)
	gm.component_choice_changed.connect(_component_state)
	gm.team_plan_changed.connect(_team_plan_state)
	gm.energy_trial_changed.connect(_trial_state)
	gm.game_over.connect(func(rankings): endings = rankings.duplicate(true))
	create_timer(230.0).timeout.connect(func(): _fail("watchdog expired"))
	if role == "host":
		_check(nm.create_room(PORT, {"name": "QA host"}) == OK, "host listens")
		await _until(func(): return nm.connected_players.size() == 4, "four human connections")
		_check(nm.start_hosted_game(600), "host starts four seats")
		await _all_reports("boot")
		await _host_scenario()
	else:
		await create_timer(0.5).timeout
		_check(nm.join_room("127.0.0.1", PORT, {"name": "QA " + role}) == OK, "guest joins")

func _game_started(configs: Array[Dictionary], duration: int) -> void:
	gm.setup_game(configs, duration)
	_check(gm.players.size() == 4 and gm.ai_fill_count == 0, "four human seats, no initial AI")
	# Keep the real dice/action/movement/RPC path, but make every possible first
	# roll land on a quiz so each seat exercises that path deterministically.
	for tile_idx in range(1, 7):
		BoardGrid.TILE_DATA[tile_idx]["type"] = BoardGrid.TileType.QUIZ_CHOICE
	gm.begin_adventure_preparation()
	if nm.is_host:
		gm.start_first_turn()
	_send_report("boot", {"peers": nm.game_peer_ids, "players": gm.players.size()})

func _host_scenario() -> void:
	probe.command.rpc("ready")
	await create_timer(0.45).timeout
	_check(gm.adventure_waiting_for_start, "first three ready cannot start four-player game")
	_check(is_equal_approx(gm.game_time_remaining, 600.0) and gm.dice_input_time_remaining == 0.0, "preparation freezes exploration/dice clocks")
	await _until(func(): return quiz_seats.size() == 4, "all seats answer a quiz", 45.0)
	await create_timer(1.1).timeout
	probe.command.rpc("checkpoint", {"key": "turns"})
	await _all_reports("turns")
	_check_same_reports("turns")
	_check(gm.team_quiz_correct == 4, "four accepted correct answers counted once")
	for player in gm.players:
		_check(int(player["quiz_correct"]) == 1, "each player earns one quiz success")
	for game_id in gm.MINIGAME_DEFINITIONS:
		results.clear()
		gm._start_minigame(0, game_id)
		var round_id: int = gm.minigame_round_count
		await _all_reports("start_%d" % round_id)
		_check_same_reports("start_%d" % round_id)
		await _until(func(): return str(gm.active_minigame.get("phase", "")) == "playing", "all humans share countdown")
		await create_timer(0.35).timeout
		_check(gm.minigame_scores.is_empty(), "early and stale score claims rejected: " + game_id)
		if game_id not in REAL_TIME_GAMES:
			# Fixture acceleration, not a claim to have played the arcade itself.
			gm.minigame_time_remaining = gm.MINIGAME_SUBMISSION_GRACE_SECONDS
			gm.minigame_submission_changed.emit(gm.get_minigame_state())
		await _all_reports("result_%d" % round_id, 70.0)
		_check_same_reports("result_%d" % round_id)
		var saved_energies := _energies()
		gm._finalize_minigame()
		gm._finalize_minigame()
		_check(saved_energies == _energies(), "duplicate finalization cannot grant more energy")
		_check(game_id in gm.completed_minigame_ids, "completed minigame recorded once")
		# Skip only the result-reading delay; queued old round callbacks must be inert.
		gm._complete_minigame_turn(round_id)
		await create_timer(0.7).timeout
	# Verify the production tile route never restarts an already played game.
	var repeat_tile := 7
	BoardGrid.TILE_DATA[repeat_tile]["type"] = BoardGrid.TileType.MINIGAME
	BoardGrid.TILE_DATA[repeat_tile]["minigame_id"] = "solar_align"
	var old_round: int = gm.minigame_round_count
	gm._resolve_tile_event(gm.current_turn_idx, repeat_tile)
	_check(gm.active_minigame.is_empty() and gm.minigame_round_count == old_round, "second visit skips completed minigame")
	await create_timer(0.7).timeout
	probe.command.rpc("disconnect", {"seat": 3})
	await _until(func(): return nm._pending_reconnects.has(3), "fourth seat actually disconnects")
	var frozen_time: float = gm.game_time_remaining
	await create_timer(0.4).timeout
	_check(paused and is_equal_approx(frozen_time, gm.game_time_remaining), "all players pause during recovery")
	await _until(func(): return not paused and nm._pending_reconnects.is_empty(), "guest returns with original seat")
	await _all_reports("restored")
	_check(not gm.players[3]["is_ai"], "reconnected player remains human")
	probe.command.rpc("checkpoint", {"key": "recovery"})
	await _all_reports("recovery")
	_check_same_reports("recovery")
	# Supply a bounded shared-material fixture to cover planning and construction.
	for idx in range(4):
		for item in gm.ITEM_DEFINITIONS:
			gm.players[idx]["inventory"][item] = 2
		gm.player_inventory_changed.emit(idx, gm.players[idx]["inventory"].duplicate(true))
	gm.game_time_remaining = 0.01
	await _until(func(): return gm.village_construction_active, "shared plan completes for all four humans")
	_check(gm.get_team_inventory()["solar_panel"] == 8, "planning keeps shared materials intact")
	var inventory_before: Dictionary = gm.get_team_inventory()
	probe.command.rpc("invalid_build")
	await _all_reports("invalid_build")
	_check(gm.projects_built == 0 and gm.get_team_inventory() == inventory_before, "invalid terrain/pixel coordinates spend no materials")
	probe.command.rpc("build")
	await _until(func(): return gm.projects_built == 4, "four players build distinct projects")
	await create_timer(0.3).timeout
	_check(gm.built_project_owners.size() == 4 and gm.kingdom_health == 100, "four construction owners and shared health")
	inventory_before = gm.get_team_inventory()
	probe.command.rpc("occupied_build")
	await _all_reports("occupied_build")
	_check(gm.projects_built == 4 and gm.get_team_inventory() == inventory_before, "concurrent second facilities cannot consume an occupied shared pad")
	probe.command.rpc("checkpoint", {"key": "construction"})
	await _all_reports("construction")
	_check_same_reports("construction")
	probe.command.rpc("finish")
	await _until(func(): return not gm.energy_trial.is_empty(), "construction opens shared electricity trial")
	await _until(func(): return endings.size() == 4, "four players operate batteries and reach ending", 50.0)
	await create_timer(0.25).timeout
	probe.command.rpc("checkpoint", {"key": "ending"})
	await _all_reports("ending")
	_check_same_reports("ending")
	_check(gm.kingdom_recovered and not gm.village_construction_active, "shared successful ending")
	var final_energy := _energies()
	gm.evaluate_village(true)
	_check(_energies() == final_energy, "ending cannot grant movement rewards twice")
	probe.command.rpc("pass")

func _command(kind: String, payload: Dictionary) -> void:
	var seat: int = nm.get_local_player_index()
	match kind:
		"ready":
			# A remote seat cannot ready/roll for another human.
			if not nm.is_host:
				nm.request_adventure_ready(0)
				nm.request_roll_dice(0)
			await create_timer(0.1 + float(seat) * 0.25).timeout
			gm.confirm_adventure_ready(seat)
		"checkpoint":
			_send_report(str(payload["key"]), _snapshot())
		"disconnect":
			if seat != int(payload["seat"]): return
			var old_peer: int = nm.my_peer_id
			nm._begin_reconnect()
			nm._next_reconnect_attempt = Time.get_ticks_msec() + 1400
			await _until(func(): return restored_count > 0, "transport restores")
			_check(nm.my_peer_id != old_peer and nm.get_local_player_index() == seat, "new peer restores original seat")
			_send_report("restored", {"seat": seat})
		"build":
			var placement: Vector2 = gm.VILLAGE_PLACEMENT_RULES.resolve_placement(gm.CONSTRUCTION_PROJECTS[seat], Vector2(-1, -1), {})
			nm.request_build_project(seat, seat, placement)
			nm.request_build_project(seat, seat, placement)
		"invalid_build":
			# The first position is a real pad of the wrong terrain; the second
			# is the old screen-pixel wire format, which must never reach storage.
			nm.request_build_project(seat, seat, Vector2(0.14, 0.71))
			nm.request_build_project(seat, seat, Vector2(400, 300))
			_send_report("invalid_build", {})
		"occupied_build":
			if seat == 2:
				nm.request_build_project(8, seat, Vector2(0.71, 0.36))
			if seat == 3:
				nm.request_build_project(9, seat, Vector2(0.44, 0.44))
			_send_report("occupied_build", {})
		"finish":
			nm.request_evaluate_village()
		"pass":
			finished = true
			print("[PASS] Four-player online rules %s · %d checks · 9 rounds · four-human turns/quiz/components/planning/construction/electricity/ending · real ENet reconnect" % [role, checks])
			# Leave the authority alive until all peers have received the final packet.
			await create_timer(0.7 if nm.is_host else 0.3).timeout
			nm.disconnect_network()
			quit(1 if failed else 0)

func _turn_changed(idx: int) -> void:
	if nm.is_host: print("[TRACE] turn %d / quiz seats %s" % [idx, quiz_seats.keys()])
	if not turn_automation or idx != nm.get_local_player_index() or quiz_seats.has(idx): return
	await create_timer(0.15).timeout
	nm.request_roll_dice(idx)

func _quiz_requested(idx: int, quiz: Dictionary) -> void:
	if not turn_automation: return
	var answer := str(quiz["answer"])
	var seat: int = nm.get_local_player_index()
	if seat != idx:
		nm.request_spectator_guess(idx, answer)
		return
	await create_timer(0.2).timeout
	nm.request_quiz_answer(idx, answer)
	nm.request_quiz_answer(idx, answer)

func _quiz_resolved(idx: int, correct: bool) -> void:
	_check(correct and not quiz_seats.has(idx), "quiz answer resolves exactly once")
	quiz_seats[idx] = true
	if quiz_seats.size() == 4:
		turn_automation = false
	if nm.get_local_player_index() == idx:
		# Skip only review reading time; earn the part via the real validated action.
		await create_timer(0.2).timeout
		gm.finish_quiz_review(idx)

func _component_state(state: Dictionary) -> void:
	var seat: int = nm.get_local_player_index()
	var choice: Dictionary = (state.get("choices", {}) as Dictionary).get(seat, {})
	if str(choice.get("phase", "")) == "choosing":
		gm.choose_quiz_component(seat, str(choice["options"][0]), int(choice["token"]))
		gm.choose_quiz_component(seat, str(choice["options"][0]), int(choice["token"]))

func _team_plan_state(state: Dictionary) -> void:
	var seat: int = nm.get_local_player_index()
	if bool(state.get("active", false)) and not (state.get("ready", {}) as Dictionary).has(seat):
		gm.confirm_team_plan(seat)

func _trial_state(state: Dictionary) -> void:
	if state.is_empty(): return
	var seat: int = nm.get_local_player_index()
	if str(state.get("phase", "")) == "complete":
		if not (state.get("ready", {}) as Dictionary).has(seat):
			gm.finish_energy_trial(seat)
	elif str(state.get("phase", "")) == "night" and str(state["players"][seat]["mode"]) != "supply":
		gm.set_energy_trial_mode(seat, "supply")
	elif str(state.get("phase", "")) == "day" and str(state["players"][seat]["mode"]) != "store":
		gm.set_energy_trial_mode(seat, "store")

func _minigame_started(data: Dictionary) -> void:
	if nm.is_host: print("[TRACE] round %s" % data["id"])
	var round_id := int(data["round_id"])
	_check(data["phase"] == "ready", "round opens at human ready barrier")
	var expected_duration := 60.0 if data["id"] == "eco_commute" else 30.0
	_check(float(data["duration"]) == expected_duration, "production round duration")
	energy_before = _energies()
	_send_report("start_%d" % round_id, {"seed": data["seed"], "id": data["id"], "duration": data["duration"], "round_id": round_id})
	await create_timer(0.1 + float(nm.get_local_player_index()) * 0.12).timeout
	gm.start_minigame_action(nm.get_local_player_index(), round_id)

func _minigame_state(state: Dictionary) -> void:
	var game: Dictionary = state.get("game", {})
	var round_id := int(game.get("round_id", -1))
	var phase := str(game.get("phase", ""))
	if phase == "countdown":
		countdown_round = round_id
	if phase != "playing": return
	var seat: int = nm.get_local_player_index()
	if playing_round != round_id:
		_check(countdown_round == round_id, "every client observes shared countdown before playing")
		playing_round = round_id
		round_started_ms = Time.get_ticks_msec()
		nm.request_minigame_score(seat, 400, _score_stats(str(game["id"])), round_id - 1)
		nm.request_minigame_score(seat, 400, _score_stats(str(game["id"])), round_id)
	if float(state.get("time_remaining", 99.0)) <= gm.MINIGAME_SUBMISSION_GRACE_SECONDS + 0.05 and submitted_round != round_id:
		submitted_round = round_id
		if game["id"] in REAL_TIME_GAMES:
			_check(Time.get_ticks_msec() - round_started_ms >= int(float(game["duration"]) * 1000.0) - 600, "real-time round is not shortened")
		nm.request_minigame_score(seat, SCORES[seat], _score_stats(str(game["id"])), round_id)
		nm.request_minigame_score(seat, 999, _score_stats(str(game["id"])), round_id)

func _score_stats(game_id: String) -> Dictionary:
	var correct := 7
	var attempts := 10
	if game_id == "wind_rhythm": correct = 1
	if game_id == "grid_balance":
		correct = 2
		attempts = 2
	if game_id == "battery_relay":
		correct = 4
		attempts = 8
	return {"correct": correct, "attempts": attempts, "concept_attempts": attempts, "best_streak": correct, "hydro_managed_closures": 1}

func _minigame_finished(ranking: Array) -> void:
	var round_id: int = gm.active_minigame["round_id"]
	_check(not results.has(round_id), "one result event per round")
	results[round_id] = true
	_check(ranking.size() == 4, "four scores in round results")
	for entry in ranking:
		var idx := int(entry["player_idx"])
		_check(int(entry["score"]) == SCORES[idx], "accepted score belongs to correct seat")
		_check(int(entry["rank"]) == RANKS[idx] and int(entry["reward"]) == REWARDS[idx] and bool(entry["goal_checked"]), "competition ties grant 20/20/5/1 after goal actions")
		_check(int(gm.players[idx]["energy"]) - energy_before[idx] == REWARDS[idx], "energy bonus applied once on every peer")
	_send_report("result_%d" % round_id, {"ranking": ranking, "energies": _energies(), "completed": gm.completed_minigame_ids})

func _market_state(state: Dictionary) -> void:
	if not bool(state.get("active", false)): return
	var seat: int = nm.get_local_player_index()
	if int(state["phase"]) == gm.OpenMarketPhase.OFFERING and not market_offer_sent:
		market_offer_sent = true
		nm.request_open_market_offer(seat, {"solar_panel": 1})
		nm.request_open_market_offer(seat, {"solar_panel": 1})
	elif int(state["phase"]) == gm.OpenMarketPhase.TAKING and not market_take_sent:
		market_take_sent = true
		nm.request_open_market_take(seat, "solar_panel")
		nm.request_open_market_take(seat, "solar_panel")

func _energies() -> Array[int]:
	var values: Array[int] = []
	for player in gm.players: values.append(int(player["energy"]))
	return values

func _snapshot() -> Dictionary:
	return {"players": gm.players.duplicate(true), "turn": gm.current_turn_idx, "total_turns": gm.total_turns, "quizzes": gm.team_quiz_correct, "completed": gm.completed_minigame_ids.duplicate(), "projects": gm.built_project_ids.duplicate(), "owners": gm.built_project_owners.duplicate(), "health": gm.kingdom_health, "endings": endings.duplicate(true)}

func _send_report(kind: String, payload: Dictionary) -> void:
	var seat: int = nm.get_local_player_index()
	if nm.is_host:
		_report(kind, seat, payload)
	else:
		probe.report.rpc_id(1, kind, seat, payload)

func _report(kind: String, seat: int, payload: Dictionary) -> void:
	if not reports.has(kind): reports[kind] = {}
	reports[kind][seat] = payload.duplicate(true)

func _all_reports(kind: String, timeout_seconds: float = 15.0) -> void:
	var expected := 1 if kind == "restored" else 4
	await _until(func(): return reports.has(kind) and reports[kind].size() == expected, "all reports: " + kind, timeout_seconds)

func _check_same_reports(kind: String) -> void:
	if not reports.has(kind) or not reports[kind].has(0):
		_fail("missing authoritative report " + kind)
		return
	for seat in range(1, 4):
		_check(reports[kind].get(seat) == reports[kind][0], "identical state on seat %d: %s" % [seat, kind])

func _until(predicate: Callable, label: String, timeout_seconds: float = 15.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline and not failed:
		await create_timer(0.025).timeout
	_check(predicate.call(), label)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: _fail(label)

func _fail(label: String) -> void:
	if failed or finished: return
	failed = true
	push_error("[FAIL] Four-player online rules %s: %s" % [role, label])
	if nm: nm.disconnect_network()
	quit(1)
