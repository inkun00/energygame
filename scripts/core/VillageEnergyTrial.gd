class_name VillageEnergyTrial
extends RefCounted
## A deterministic, shared-village electricity exercise. Values are game units,
## not real plant ratings. Each player controls one equal district allocation.

const DAY_DURATION := 20.0
const DURATION := 40.0
const CHARGE_EFFICIENCY := 0.9
const STORAGE_CAPACITY := 100.0
const REQUIRED_COVERAGE := 0.95
const REQUIRED_NIGHT_COVERAGE := 0.90
const EPSILON := 0.000001
const GENERATION := {
	0: Vector2(8.0, 0.0), # Solar: sunlight is absent during this night.
	1: Vector2(5.0, 2.0), # This forecast has weaker wind at night.
	4: Vector2(3.2, 3.2), # Flowing water is available in this scenario.
	5: Vector2(2.8, 2.8),
	6: Vector2(1.0, 4.0), # Tidal flow strengthens in this scenario, not every night.
	7: Vector2(2.5, 2.5), # Nuclear supplies electricity but is not renewable.
}
const TOTAL_FIELDS := [
	"total_generation", "total_demand", "total_delivered", "total_direct",
	"total_charge_input", "total_stored", "total_loss", "total_curtailed",
	"total_discharged", "daytime_demand", "daytime_delivered",
	"night_demand", "night_delivered", "daytime_stored", "night_discharged",
]
const FLOW_FIELDS := [
	"generation", "demand", "direct", "charging", "discharging",
	"delivered", "unserved", "battery", "capacity",
]

static func create_state(built_ids: Array, player_count: int = 4) -> Dictionary:
	var ids: Array[int] = []
	for id in built_ids:
		if typeof(id) == TYPE_INT and id >= 0 and id <= 9 and not ids.has(id):
			ids.append(id)
	ids.sort()
	var count: int = clampi(player_count, 1, 4)
	var profile := _profile(ids)
	var state: Dictionary = {
		"phase": "day", "elapsed": 0.0, "duration": DURATION,
		"phase_remaining": DAY_DURATION, "built_ids": ids,
		"player_count": count, "players": [], "profile": profile,
		"coverage": 0.0, "daytime_coverage": 0.0, "night_coverage": 0.0,
		"success": false, "required_coverage": REQUIRED_COVERAGE,
		"required_night_coverage": REQUIRED_NIGHT_COVERAGE,
	}
	for index in range(count):
		var player: Dictionary = {
			"mode": "supply", "battery": 0.0,
			"capacity": float(profile["capacity"]) / count,
			"coverage": 0.0, "daytime_coverage": 0.0,
			"night_coverage": 0.0, "light_ratio": 0.0,
		}
		for field in TOTAL_FIELDS:
			player[field] = 0.0
		state["players"].append(player)
	_refresh(state)
	return state

static func advance(state: Dictionary, delta: float) -> void:
	if state.is_empty() or not is_finite(delta) or delta <= 0.0 or is_complete(state):
		return
	var remaining: float = minf(delta, DURATION - float(state["elapsed"]))
	while remaining > 0.0:
		var is_day: bool = float(state["elapsed"]) < DAY_DURATION
		var boundary: float = DAY_DURATION if is_day else DURATION
		var step: float = minf(remaining, boundary - float(state["elapsed"]))
		if step <= 0.0:
			break
		_integrate(state, step, is_day)
		state["elapsed"] = minf(boundary, float(state["elapsed"]) + step)
		remaining = maxf(0.0, remaining - step)
	_refresh(state)

static func set_mode(state: Dictionary, player_idx: int, mode: String) -> bool:
	if state.is_empty() or is_complete(state) or mode not in ["store", "supply"]:
		return false
	var players: Array = state["players"]
	if player_idx < 0 or player_idx >= players.size():
		return false
	players[player_idx]["mode"] = mode
	_refresh(state)
	return true

static func forecast(built_ids: Array) -> Dictionary:
	# The preview assumes everybody stores by day and supplies at night.
	# Actual success depends on the choices made during the exercise.
	var state := create_state(built_ids)
	for index in range(state["player_count"]):
		set_mode(state, index, "store")
	advance(state, DAY_DURATION)
	for index in range(state["player_count"]):
		set_mode(state, index, "supply")
	advance(state, DURATION - DAY_DURATION)
	var result: Dictionary = state["profile"].duplicate(true)
	result.merge({
		"coverage": state["coverage"],
		"daytime_coverage": state["daytime_coverage"],
		"night_coverage": state["night_coverage"],
		"success": state["success"], "can_cover": state["success"],
		"built_ids": state["built_ids"].duplicate(),
		"remaining_battery": state["battery"],
	})
	return result

static func is_complete(state: Dictionary) -> bool:
	return state.get("phase", "") == "complete" or float(state.get("elapsed", 0.0)) >= DURATION

static func summarize(state: Dictionary, projects: Array, district_index: int = -1) -> Dictionary:
	var districts: Array = state.get("players", [])
	var record: Dictionary = districts[district_index] if district_index >= 0 and district_index < districts.size() else state
	var ids: Array = state.get("built_ids", [])
	var names: Array[String] = []
	var generators: Array[String] = []
	for id in ids:
		if id >= 0 and id < projects.size():
			var facility := str(projects[id]["name"])
			names.append(facility)
			if GENERATION.has(id): generators.append(facility)
	var day := float(record.get("daytime_coverage", 0.0))
	var night := float(record.get("night_coverage", 0.0))
	var overall := float(record.get("coverage", 0.0))
	var success := overall + EPSILON >= REQUIRED_COVERAGE and night + EPSILON >= REQUIRED_NIGHT_COVERAGE
	var day_store := float(record.get("daytime_stored", record.get("total_stored", 0.0)))
	var night_use := float(record.get("night_discharged", record.get("total_discharged", 0.0)))
	var cause := ""
	var advice := ""
	var period := "낮과 밤"
	if success:
		if night_use > EPSILON:
			cause = "낮에 저장한 전기 %.1f칸 중 %.1f칸을 밤에 꺼내 썼어요." % [day_store, night_use]
		elif not generators.is_empty():
			cause = "%s에서 만든 전기를 바로 보냈어요." % "·".join(generators)
		if 2 in ids or 8 in ids: cause += " 절전 시설 덕분에 필요한 전기도 줄었어요."
		advice = "시설을 하나 바꾸면 어느 시간의 공급이 달라질까요?"
	elif generators.is_empty():
		cause = "마을에서 전기를 만드는 시설이 없었어요."
		advice = "강물이 있는 곳에 소수력 발전소를 놓고 낮과 밤을 비교해 봐요."
	elif day + EPSILON < night:
		period = "낮"
		cause = "낮에 만든 전기가 마을에서 쓸 양보다 적었어요."
		advice = "낮에 발전하는 태양광을 더하거나 절전 건물로 수요를 줄여 봐요."
	elif day < 0.95 and absf(day - night) < 0.05:
		cause = "낮과 밤 모두 마을에서 쓸 전기가 부족했어요."
		advice = "강물이나 지열로 두 시간대 모두 발전해 봐요."
	else:
		period = "밤"
		if 3 not in ids:
			cause = "밤에 발전량이 부족했고, 저장소도 없었어요."
			advice = "낮에 전기가 남으면 저장소를, 남지 않으면 밤에도 발전할 시설을 더해 봐요."
		elif day_store < EPSILON:
			cause = "밤에 쓸 전기를 낮에 저장하지 못했어요."
			advice = "낮에 전기가 남을 때 ‘전기 저장’을 눌러 봐요." if float(record.get("total_curtailed", 0.0)) > EPSILON else "낮에 발전을 늘려 저장할 전기를 먼저 마련해 봐요."
		elif float(record.get("battery", 0.0)) > EPSILON:
			var empty_district := false
			if district_index < 0:
				for area in districts:
					if float(area.get("night_coverage", 1.0)) < 0.99 and float(area.get("battery", 0.0)) <= EPSILON:
						empty_district = true
			if empty_district:
				cause = "한 구역의 배터리는 비었는데 다른 구역에는 전기가 남았어요."
				advice = "각자 낮에 자기 구역의 전기를 저장하고, 밤에는 함께 꺼내 봐요."
			else:
				cause = "밤이 끝났을 때도 배터리에 전기가 %.1f칸 남았어요." % float(record["battery"])
				advice = "밤에 필요한 전기가 모자랄 때 ‘배터리 전기 사용’을 눌러 봐요."
		else:
			cause = "저장한 전기를 꺼냈지만 밤에 필요한 양보다 적었어요."
			advice = "밤에도 발전하는 시설을 더하거나 절전 시설로 수요를 줄여 봐요."
	return {"success": success, "coverage": overall, "daytime_coverage": day, "night_coverage": night,
		"built_ids": ids.duplicate(), "facilities": names, "period": period, "cause": cause, "advice": advice}

static func comparison(before: Dictionary, after: Dictionary) -> String:
	if before.is_empty(): return ""
	return "첫 시험 → 이번 시험    낮 %d%% → %d%%   ·   밤 %d%% → %d%%" % [
		roundi(float(before.get("daytime_coverage", 0.0)) * 100.0), roundi(float(after.get("daytime_coverage", 0.0)) * 100.0),
		roundi(float(before.get("night_coverage", 0.0)) * 100.0), roundi(float(after.get("night_coverage", 0.0)) * 100.0)]

static func _profile(ids: Array) -> Dictionary:
	var output := Vector2.ZERO
	for id in ids:
		if GENERATION.has(id):
			output += GENERATION[id]
	var day_demand := 3.0
	var night_demand := 4.0
	if ids.has(2):
		day_demand -= 0.75
		night_demand -= 1.0
	if ids.has(8):
		day_demand -= 0.25
		night_demand -= 0.25
	if ids.has(9):
		day_demand += 0.75
	return {
		"day_generation": float(output.x), "night_generation": float(output.y),
		"day_demand": day_demand, "night_demand": night_demand,
		"capacity": STORAGE_CAPACITY if ids.has(3) else 0.0,
		"has_storage": ids.has(3), "has_nuclear": ids.has(7),
		"day_condition": "맑음 · 바람 강함 · 바닷물 흐름 약함",
		"night_condition": "해가 짐 · 바람 약함 · 바닷물 흐름 강함",
	}

static func _integrate(state: Dictionary, dt: float, is_day: bool) -> void:
	var profile: Dictionary = state["profile"]
	var count: int = int(state["player_count"])
	var generation: float = float(profile["day_generation" if is_day else "night_generation"]) / count
	var demand: float = float(profile["day_demand" if is_day else "night_demand"]) / count
	var direct: float = minf(generation, demand) * dt
	var surplus: float = maxf(0.0, generation - demand) * dt
	var shortage: float = maxf(0.0, demand - generation) * dt
	for player: Dictionary in state["players"]:
		var charge_input := 0.0
		var discharge := 0.0
		if player["mode"] == "store":
			charge_input = minf(surplus, maxf(0.0, float(player["capacity"]) - float(player["battery"])) / CHARGE_EFFICIENCY)
		else:
			discharge = minf(shortage, float(player["battery"]))
		var stored: float = charge_input * CHARGE_EFFICIENCY
		player["battery"] = clampf(float(player["battery"]) + stored - discharge, 0.0, float(player["capacity"]))
		player["total_generation"] += generation * dt
		player["total_demand"] += demand * dt
		player["total_direct"] += direct
		player["total_delivered"] += direct + discharge
		player["total_charge_input"] += charge_input
		player["total_stored"] += stored
		player["total_loss"] += charge_input - stored
		player["total_curtailed"] += surplus - charge_input
		player["total_discharged"] += discharge
		if is_day:
			player["daytime_stored"] = float(player.get("daytime_stored", 0.0)) + stored
		else:
			player["night_discharged"] = float(player.get("night_discharged", 0.0)) + discharge
		var prefix := "daytime" if is_day else "night"
		player[prefix + "_demand"] += demand * dt
		player[prefix + "_delivered"] += direct + discharge

static func _refresh(state: Dictionary) -> void:
	var elapsed: float = float(state["elapsed"])
	var is_day: bool = elapsed < DAY_DURATION
	state["phase"] = "complete" if elapsed >= DURATION else ("day" if is_day else "night")
	state["phase_remaining"] = maxf(0.0, (DAY_DURATION if is_day else DURATION) - elapsed)
	var profile: Dictionary = state["profile"]
	state["condition_label"] = profile["day_condition" if is_day else "night_condition"]
	for field in FLOW_FIELDS:
		state[field] = 0.0
	for field in TOTAL_FIELDS:
		state[field] = 0.0
	var count: int = int(state["player_count"])
	for player: Dictionary in state["players"]:
		var generation: float = float(profile["day_generation" if is_day else "night_generation"]) / count
		var demand: float = float(profile["day_demand" if is_day else "night_demand"]) / count
		var direct: float = minf(generation, demand)
		var charge: float = maxf(0.0, generation - demand) if player["mode"] == "store" and float(player["battery"]) < float(player["capacity"]) - EPSILON else 0.0
		var discharge: float = maxf(0.0, demand - generation) if player["mode"] == "supply" and float(player["battery"]) > EPSILON else 0.0
		player["generation"] = generation
		player["demand"] = demand
		player["direct"] = direct
		player["charging"] = charge
		player["discharging"] = discharge
		player["delivered"] = direct + discharge
		player["unserved"] = maxf(0.0, demand - direct - discharge)
		player["light_ratio"] = _ratio(direct + discharge, demand)
		_update_coverage(player)
		for field in FLOW_FIELDS:
			state[field] += float(player.get(field, 0.0))
		for field in TOTAL_FIELDS:
			state[field] += float(player.get(field, 0.0))
	_update_coverage(state)
	state["light_ratio"] = _ratio(float(state["delivered"]), float(state["demand"]))
	state["success"] = is_complete(state) and float(state["coverage"]) + EPSILON >= REQUIRED_COVERAGE and float(state["night_coverage"]) + EPSILON >= REQUIRED_NIGHT_COVERAGE

static func _update_coverage(target: Dictionary) -> void:
	target["coverage"] = _ratio(float(target["total_delivered"]), float(target["total_demand"]))
	target["daytime_coverage"] = _ratio(float(target["daytime_delivered"]), float(target["daytime_demand"]))
	target["night_coverage"] = _ratio(float(target["night_delivered"]), float(target["night_demand"]))

static func _ratio(delivered: float, demand: float) -> float:
	return clampf(delivered / demand, 0.0, 1.0) if demand > 0.0 else 0.0
