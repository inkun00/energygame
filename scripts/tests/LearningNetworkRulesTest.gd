extends SceneTree

## Exercises the host action dispatcher and client state-application entry points.
## Socket delivery is covered separately by the real four-player transport tests.
const TRIAL = preload("res://scripts/core/VillageEnergyTrial.gd")
const ACTIONS := ["quiz_component", "quiz_review", "team_project", "team_confirm", "trial_mode", "trial_finish"]
const LEARNING_KEYS := ["component_choices", "component_choice_serial", "team_plan", "energy_trial", "energy_trial_retries"]
const EVENTS := ["component_choice_changed", "team_plan_changed", "energy_trial_changed"]

var gm: Node
var nm: Node
var failures: Array[String] = []
var checks := 0
var event_counts: Dictionary = {}
var event_values: Dictionary = {}
var event_learning_states: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("[FAIL] Learning network: " + message)

func _new_session() -> void:
	paused = false
	nm.is_online = false
	nm.is_host = true
	nm.game_has_started = true
	nm.game_peer_ids.assign([11, 22, 33, 44])
	var configs: Array[Dictionary] = []
	for idx in range(4):
		configs.append({"name": "Seat %d" % idx, "is_ai": false})
	gm.setup_game(configs, 600)
	gm.set_process(false)

func _fixture(action: String) -> Dictionary:
	_new_session()
	var payload := {"player_idx": 1}
	match action:
		"quiz_component", "quiz_review":
			gm._offer_quiz_component(1)
			if action == "quiz_component":
				gm.finish_quiz_review(1)
				payload["token"] = int(gm.component_choices[1]["token"])
				payload["item_id"] = str(gm.component_choices[1]["options"][0])
		"team_project", "team_confirm":
			gm._start_team_planning_phase()
			if action == "team_project": payload["project_idx"] = 5
		"trial_mode", "trial_finish":
			gm.is_game_active = false
			gm.built_project_ids.assign([0, 3])
			gm._start_energy_trial()
			if action == "trial_mode":
				payload["mode"] = "store"
			else:
				TRIAL.advance(gm.energy_trial, 40.0)
				payload["retry"] = false
	return payload

func _protected_state() -> Dictionary:
	return {
		"learning": _learning_state(), "players": gm.players.duplicate(true),
		"construction": gm.village_construction_active,
		"finalized": gm._village_result_finalized,
		"state": int(gm.current_state), "turn": gm.current_turn_idx
	}

func _learning_state() -> Dictionary:
	var result := {}
	for key in LEARNING_KEYS:
		var value: Variant = gm.get(key)
		result[key] = value.duplicate(true) if value is Dictionary else value
	return result

func _reject(action: String, payload: Dictionary, label: String, peer: int = 22) -> void:
	var before := _protected_state()
	nm._handle_game_action(peer, action, payload)
	_check(_protected_state() == before, action + ": reject " + label)

func _test_authorization(action: String, valid: Dictionary) -> void:
	for malformed in [null, "1", 1.0, -1, 0, 4, {}, []]:
		var payload := valid.duplicate(true)
		payload["player_idx"] = malformed
		_reject(action, payload, "wrong seat or seat type " + str(malformed))
	var absent := valid.duplicate(true)
	absent.erase("player_idx")
	_reject(action, absent, "missing seat")
	_reject(action, valid, "unknown peer", 999)
	_reject(action, valid, "another seat's peer", 11)
	paused = true
	_reject(action, valid, "recovery pause")
	paused = false
	nm.is_host = false
	_reject(action, valid, "non-host dispatcher")
	nm.is_host = true
	nm.game_has_started = false
	_reject(action, valid, "session not started")
	nm.game_has_started = true

func _test_field_validation(action: String, valid: Dictionary) -> void:
	var invalid_fields: Dictionary = {}
	match action:
		"quiz_component":
			invalid_fields = {"token": [null, "1", 1.0, -1, 999, {}, []], "item_id": [null, 1, {}, [], "unknown_part"]}
		"team_project": invalid_fields = {"project_idx": [null, "5", 5.0, -1, 999, {}, []]}
		"trial_mode": invalid_fields = {"mode": [null, 1, {}, [], "boost", "STORE", ""]}
		"trial_finish": invalid_fields = {"retry": [null, 0, 1, "true", {}, []]}
	for field in invalid_fields:
		var absent := valid.duplicate(true)
		absent.erase(field)
		_reject(action, absent, "missing " + field)
		for value in invalid_fields[field]:
			var payload := valid.duplicate(true)
			payload[field] = value
			_reject(action, payload, "invalid " + field + " " + str(value))

func _test_accepted_action(action: String) -> void:
	var payload := _fixture(action)
	var others: Array = [gm.players[0].duplicate(true), gm.players[2].duplicate(true), gm.players[3].duplicate(true)]
	var original_inventory: Dictionary = gm.players[1]["inventory"].duplicate(true)
	nm._handle_game_action(22, action, payload)
	match action:
		"quiz_component":
			var item_id: String = payload["item_id"]
			_check(not gm.component_choices.has(1) and int(gm.players[1]["inventory"][item_id]) == int(original_inventory[item_id]) + 1, "Owning peer receives exactly its chosen component")
			_reject(action, payload, "duplicate consumed token")
			gm._offer_quiz_component(1)
			gm.finish_quiz_review(1)
			_reject(action, payload, "previous choice token after another quiz")
		"quiz_review":
			_check(gm.component_choices[1]["phase"] == "choosing", "Owning peer advances its review to component selection")
			_reject(action, payload, "duplicate review completion")
		"team_project":
			_check(int(gm.team_plan["choices"][1]) == 5 and int(gm.team_plan["choices"][0]) == 0, "Project recommendation changes only the owning seat")
		"team_confirm":
			_check(gm.team_plan["ready"] == {1: true} and bool(gm.team_plan["active"]), "One peer cannot confirm the other three seats")
			_reject(action, payload, "duplicate plan confirmation")
		"trial_mode":
			_check(gm.energy_trial["players"][1]["mode"] == "store" and gm.energy_trial["players"][0]["mode"] == "supply", "Trial mode changes only the owning district")
		"trial_finish":
			_check(gm.energy_trial["ready"] == {1: true} and not gm._village_result_finalized, "One result acknowledgement cannot end the four-player trial")
			_reject(action, payload, "duplicate trial acknowledgement")
	_check(others == [gm.players[0], gm.players[2], gm.players[3]], action + ": other players' inventories and rewards stay unchanged")

func _test_phase_guards_and_retry() -> void:
	var payload := _fixture("quiz_component")
	gm.component_choices[1]["phase"] = "waiting"
	_reject("quiz_component", payload, "choosing before the review ends")
	payload = _fixture("team_confirm")
	gm.team_plan["active"] = false
	_reject("team_confirm", payload, "confirming outside planning")
	payload = _fixture("trial_finish")
	gm.energy_trial = TRIAL.create_state([0, 3], 4)
	gm.energy_trial["ready"] = {}
	_reject("trial_finish", payload, "finishing before all forty seconds")
	payload = _fixture("trial_mode")
	TRIAL.advance(gm.energy_trial, 40.0)
	_reject("trial_mode", payload, "changing a completed trial")
	payload = _fixture("trial_finish")
	_check(not bool(gm.energy_trial["success"]), "Retry fixture has a genuine night supply shortage")
	payload["retry"] = true
	nm._handle_game_action(22, "trial_finish", payload)
	_check(gm.energy_trial_retries == 1 and gm.energy_trial.is_empty() and gm.village_construction_active, "A valid retry returns the whole team to construction exactly once")
	_reject("trial_finish", payload, "duplicate retry during construction")
	gm._start_energy_trial()
	TRIAL.advance(gm.energy_trial, 40.0)
	nm._handle_game_action(22, "trial_finish", payload)
	_check(gm.energy_trial_retries == 1 and not gm.village_construction_active and gm.energy_trial["ready"] == {1: true}, "A second retry request cannot grant another construction round")

func _on_learning_event(state: Dictionary, event_name: String) -> void:
	event_counts[event_name] = int(event_counts.get(event_name, 0)) + 1
	event_values[event_name] = state.duplicate(true)
	event_learning_states[event_name] = _learning_state()

func _seed_snapshot_state() -> void:
	_new_session()
	gm._offer_quiz_component(1)
	gm.finish_quiz_review(1)
	gm.team_plan = {"active": false, "remaining": 13.5, "choices": {0: 0, 1: 3}, "ready": {1: true}}
	gm.energy_trial = TRIAL.create_state([0, 3], 4)
	TRIAL.set_mode(gm.energy_trial, 1, "store")
	TRIAL.advance(gm.energy_trial, 7.5)
	gm.energy_trial["ready"] = {}
	gm.energy_trial_retries = 1

func _event_state(event_name: String) -> Dictionary:
	match event_name:
		"component_choice_changed": return gm.get_component_choice_state()
		"team_plan_changed": return gm.get_team_plan_state()
		"energy_trial_changed": return gm.get_energy_trial_state()
	return {}

func _check_learning_fields(packet: Dictionary, expected: Dictionary, label: String) -> void:
	for key in LEARNING_KEYS:
		_check(packet.has(key) and packet.get(key) == expected[key], label + ": includes " + key)

func _test_state_replication() -> void:
	_seed_snapshot_state()
	var expected := _learning_state()
	var full: Dictionary = nm._capture_game_state()
	_check_learning_fields(full, expected, "Full reconnect snapshot")
	gm._reset_learning_flow()
	nm.is_online = true
	nm.is_host = false
	nm._rpc_apply_full_game_state(full)
	_check(_learning_state() == expected, "Full snapshot restores component selection, plan, running trial and retry count")
	full["component_choices"][1]["token"] = -99
	_check(_learning_state() == expected, "Client state does not alias the full snapshot's nested dictionaries")
	for event_name in EVENTS:
		_seed_snapshot_state()
		expected = _learning_state()
		var args := [_event_state(event_name)]
		var patch: Dictionary = nm._capture_game_state_patch(event_name, args)
		_check_learning_fields(patch, expected, event_name)
		gm._reset_learning_flow()
		event_counts.clear()
		event_values.clear()
		event_learning_states.clear()
		nm.is_online = true
		nm.is_host = false
		nm._rpc_apply_game_patch(patch, event_name, args)
		_check(_learning_state() == expected, event_name + ": client restores every learning field before the UI event")
		_check(int(event_counts.get(event_name, 0)) == 1 and event_values.get(event_name, {}) == args[0], event_name + ": client replays one authoritative UI event")
		_check(event_learning_states.get(event_name, {}) == expected, event_name + ": UI callback sees the restored state, never the previous stage")
		patch["team_plan"]["choices"][1] = 9
		_check(_learning_state() == expected, event_name + ": applied state is independent of the incoming packet")
		# Empty fields must remove stale modals and trial state, not preserve them.
		nm.is_online = false
		nm.is_host = true
		gm._reset_learning_flow()
		var empty_expected := _learning_state()
		var empty_args := [_event_state(event_name)]
		var clear_patch: Dictionary = nm._capture_game_state_patch(event_name, empty_args)
		gm.component_choices = expected["component_choices"].duplicate(true)
		gm.team_plan = expected["team_plan"].duplicate(true)
		gm.energy_trial = expected["energy_trial"].duplicate(true)
		gm.energy_trial_retries = 1
		nm.is_online = true
		nm.is_host = false
		nm._rpc_apply_game_patch(clear_patch, event_name, empty_args)
		_check(_learning_state() == empty_expected, event_name + ": empty host state clears obsolete client stages")

func _check_reset(label: String) -> void:
	_check(gm.component_choices.is_empty() and gm.component_choice_serial == 0, label + ": no outstanding quiz token or component choice")
	_check(not bool(gm.team_plan["active"]) and gm.team_plan["choices"].is_empty() and gm.team_plan["ready"].is_empty(), label + ": no old recommendations or confirmations")
	_check(gm.energy_trial.is_empty() and gm.energy_trial_retries == 0 and not gm._village_result_finalized, label + ": no old trial, spent retry or final result")

func _test_session_reset() -> void:
	_seed_snapshot_state()
	var old_session: int = gm.game_session_id
	gm.stop_game()
	_check_reset("Stopping")
	_check(gm.game_session_id > old_session, "Stopping invalidates delayed session callbacks")
	_seed_snapshot_state()
	_new_session()
	_check_reset("Starting another game")
	_check(gm.is_game_active, "Restart still creates an active new exploration session")

func _run() -> void:
	gm = root.get_node("GameManager")
	nm = root.get_node("NetworkManager")
	for event_name in EVENTS:
		gm.connect(event_name, _on_learning_event.bind(event_name))
	for action in ACTIONS:
		var payload := _fixture(action)
		_test_authorization(action, payload)
		_test_field_validation(action, payload)
		_test_accepted_action(action)
	_test_phase_guards_and_retry()
	_test_state_replication()
	_test_session_reset()
	nm.is_online = false
	nm.is_host = false
	nm.game_has_started = false
	nm.game_peer_ids.clear()
	gm.stop_game()
	if failures.is_empty():
		print("[PASS] Learning network · %d checks · six actions, schemas, ownership, pause, duplicates, snapshots, events and restart" % checks)
	quit(0 if failures.is_empty() else 1)
