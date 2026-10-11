extends RefCounted
class_name MiniGameLearningFeedback

## 플레이어가 실제로 한 행동과 게임에서 측정한 값만 교육 피드백으로 보여 줍니다.

static func goal_requirement(game_id: String) -> String:
	match game_id:
		"solar_align": return "패널을 3번 이상 맞게 골라요. 패널 선택의 60% 이상을 맞혀요."
		"wind_rhythm": return "풍향 맞추기와 돌풍을 보고 멈추기를 각각 1번 해요."
		"grid_balance": return "수요에 맞춰 조절하고 작은 차이를 1초씩, 2번 지켜요."
		"standby_hunt": return "대기 기기만 2번 이상 골라요. 선택의 60% 이상을 맞혀요."
		"hydro_gate": return "수위 70% 이상에서 열어 발전하고, 다시 닫아 물을 모아요."
		"energy_sort": return "처음 선택을 2번 이상 맞혀요. 선택의 60% 이상을 맞혀요."
		"battery_relay": return "먼저 저장한 전기를 흐릴 때 도시로 1번 보내요."
		"eco_commute": return "2명 이상 함께 태워 학교에 1번 내려줘요."
		"heat_leak": return "열린 창문을 2번 이상 골라요. 선택의 60% 이상을 맞혀요."
	return "조건을 보고 알맞은 행동을 해요."

static func live_line(game_id: String, success: bool, points: int, count_correct: bool, metrics: Dictionary = {}) -> String:
	match game_id:
		"solar_align":
			if success and count_correct:
				return "햇빛을 향한 패널을 지나며 전기를 만들었어요."
			if not success and points == 25:
				return "태양이 옮겨 가면 빛이 닿는 패널도 다시 골라야 해요."
		"wind_rhythm":
			if success and points == 75:
				return "위험 돌풍에서 멈춰 터빈 날개를 지켰어요."
			if not success and points == 35:
				return "강풍에 계속 돌리면 터빈 날개가 부러져요."
			if success and count_correct:
				return "풍향에 맞춰 돌린 동안 전기를 만들었어요."
		"grid_balance":
			if success:
				return "지금 수요·공급 차이 %.1f MW · 가까울수록 유리해요." % absf(float(metrics.get("grid_gap", 0.0)))
		"standby_hunt":
			if success and count_correct:
				return "사용하지 않는 기기의 대기전력을 %d W 줄였어요." % int(metrics.get("saved_watts", 0))
			if not success and points == 48:
				return "사용 중인 기기는 그대로 두고 대기 중인 기기를 찾아요."
		"hydro_gate":
			if success and points > 0:
				return "낙차로 터빈을 돌려 누적 %.1f kWh를 만들었어요." % float(metrics.get("generated_kwh", 0.0))
			if not success:
				return "물이 넘치기 전에 수문을 열어야 발전을 이어 갈 수 있어요."
		"energy_sort":
			if success and count_correct:
				return "발전 원료를 보고 알맞은 에너지원으로 분류했어요."
			if not success:
				return "햇빛·바람·물처럼 다시 얻을 수 있는 원료인지 살펴요."
		"battery_relay":
			if success and points == 20:
				return "남는 전기를 배터리에 저장했어요."
			if success and points == 80:
				return "저장한 전기를 필요한 도시로 보냈어요."
		"eco_commute":
			if success and points == 0:
				return "학생들이 버스에 함께 탔어요. 학교에서 정확히 세워 주세요."
			if success and count_correct:
				return "학생 %d명이 버스로 학교에 도착했어요." % int(metrics.get("delivered_total", 0))
		"heat_leak":
			if success and count_correct:
				return "열린 창문을 닫아 더운 바깥 공기가 들어오지 않아요."
			if not success:
				return "이미 닫힌 창문 말고 열린 창문을 찾아요."
	return ""

static func result_lines(game_id: String, metrics: Dictionary) -> Dictionary:
	var evidence := ""
	var next_action := ""
	match game_id:
		"solar_align":
			evidence = "햇빛을 향한 패널 %d개 통과 · 반대 패널 %d회" % [int(metrics.get("correct", 0)), int(metrics.get("solar_wrong", 0))]
			next_action = "태양이 이동하면 빛을 받는 패널을 다시 찾으세요."
		"wind_rhythm":
			evidence = "풍향 정렬 %d회 · 돌풍 안전 정지 %d회 · 파손 %d회" % [int(metrics.get("wind_aligned", 0)), int(metrics.get("storm_braked", 0)), int(metrics.get("storm_broken", 0))]
			next_action = "보통 바람엔 브레이크를 놓고, 돌풍을 본 뒤 눌러요."
		"grid_balance":
			if float(metrics.get("measurement_time", 0.0)) > 0.0:
				evidence = "평균 수요·공급 차이 %.1f MW" % float(metrics.get("average_gap", 0.0))
			else:
				evidence = "전력망 조절 기록 없음"
			next_action = "공급이 적으면 올리고 많으면 내려요. 작은 차이를 1초 지켜요."
		"standby_hunt":
			evidence = "대기전력 %d W 차단 · 사용 중 기기 차단 %d회" % [int(metrics.get("saved_watts", 0)), int(metrics.get("active_unplugged", 0))]
			next_action = "사용 중인 기기는 두고 대기 중인 플러그를 찾으세요."
		"hydro_gate":
			evidence = "터빈 전기 %.1f kWh · %s" % [float(metrics.get("generated_kwh", 0.0)), "댐 범람" if bool(metrics.get("overflowed", false)) else "범람 없음"]
			next_action = "수위와 비 예보를 봐요. 물이 높을 때 열고, 줄면 닫아 모아요."
		"energy_sort":
			evidence = "처음 선택 정답 %d회 · 첫 선택 %d회" % [int(metrics.get("correct", 0)), int(metrics.get("first_sort_attempts", metrics.get("attempts", 0)))]
			next_action = "틀린 물건은 이유를 읽고 다시 골라요. 다시 고친 답은 연습이에요."
		"battery_relay":
			evidence = "남는 전기 %d칸 저장 · 도시 공급 %d회" % [int(metrics.get("battery_stored", 0)), int(metrics.get("battery_supplied", 0))]
			if metrics.has("battery_units"):
				evidence += " · 배터리에 %d칸 남음" % int(metrics["battery_units"])
			next_action = "남는 전기를 먼저 저장하고 필요할 때 보내세요."
		"eco_commute":
			evidence = "학교 도착 %d명 · 버스에 남은 학생 %d명" % [int(metrics.get("delivered_total", 0)), int(metrics.get("passengers", 0))]
			if float(metrics.get("trip_solo_energy", 0.0)) > 0.0:
				evidence += " · 같은 길: 혼자 %.1f / 함께 1인당 %.1f" % [float(metrics["trip_solo_energy"]), float(metrics["trip_per_person"])]
			next_action = "정류장에서 태운 뒤 학교 앞에 정확히 멈추세요."
		"heat_leak":
			evidence = "열린 창문 %d개 닫음 · 닫힌 창문 선택 %d회" % [int(metrics.get("correct", 0)), int(metrics.get("closed_window_misses", 0))]
			if metrics.has("cooling_used"):
				evidence += " · 냉방 사용량 %.1f (게임 속 비교 값)" % float(metrics["cooling_used"])
			next_action = "에어컨이 켜진 공간에서는 열린 창문을 찾아 닫으세요."
		_:
			evidence = "도전 기록을 확인했어요."
			next_action = "다음 도전에서 에너지 선택을 다시 해 보세요."
	return {"evidence": evidence, "next_action": next_action}
