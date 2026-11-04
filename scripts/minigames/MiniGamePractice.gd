extends RefCounted

## Session-only coaching. Progress comes from the game's real action events;
## it never writes competitive scores, readiness, rewards or saved records.
const HINTS := {
	"solar_align": ["A/D로 햇빛을 정면으로 받는 패널 길을 골라요. Space로 장애물을 넘어요.", "태양이 바뀌면 다시 골라요. 알맞은 패널을 한 번 더 지나가요."],
	"wind_rhythm": ["A/D로 바람 화살표와 터빈 방향을 맞춰 전기를 만들어요.", "발전 성공! 빨간 돌풍이 오면 Space를 새로 눌러 멈춰요."],
	"grid_balance": ["W/S로 공급 막대를 움직여 수요와 작은 차이를 1초 유지해요.", "수요가 달라지면 다시 맞춰요. 도시의 불빛도 살펴봐요."],
	"standby_hunt": ["A/D 이동 · W 점프. 꺼져 있지만 전기를 쓰는 기기 앞에서 Space!", "한 번 더 대기전력을 차단해요. 사용 중인 기기는 그대로 두어요."],
	"energy_sort": ["손에 든 에너지원을 보고 A/D로 알맞은 분류 통로를 골라요.", "다음 에너지원도 분류해요. 틀렸다면 같은 카드를 다시 골라요."],
	"battery_relay": ["A/D로 맑을 때 태양광에서 전기를 받아 가운데 배터리에 가져가요.", "흐릴 때 배터리에서 전기를 받아 도시로 가져가요."],
	"eco_commute": ["D/A 길게 가속 · S 정차. 정류장에서 Space로 2명 이상 태워요.", "D로 학교까지 달린 뒤 정차선 중앙에 S로 멈춰요. 학생들이 내려요."],
	"heat_leak": ["A/D로 열린 창문에 다가가 Space! 더운 공기를 막아요.", "열린 창문을 하나 더 닫고 에어컨 전기 사용 속도가 줄어드는지 보아요."]
}
const SUCCESSES := {
	"solar_align": "햇빛을 정면으로 받는 패널을 골라 발전했어요!",
	"wind_rhythm": "보통 바람에는 발전, 위험 돌풍에는 정지!",
	"grid_balance": "변하는 수요에 맞춰 공급을 조절했어요!",
	"standby_hunt": "꺼진 기기에 남아 쓰이던 전기를 줄였어요!",
	"energy_sort": "에너지원의 특징을 보고 알맞게 분류했어요!",
	"battery_relay": "남는 전기를 저장했다가 부족할 때 공급했어요!",
	"eco_commute": "학생들이 함께 타고 학교에 도착했어요!",
	"heat_leak": "창문을 닫아 더운 공기를 막고 냉방 전기를 아꼈어요!"
}

var game_id: String
var step := 0

func _init(id: String) -> void:
	game_id = id

func record(points: int, success: bool, count_correct: bool, arcade: Node) -> void:
	if not success or step >= 2:
		return
	match game_id:
		"wind_rhythm":
			if step == 0 and not bool(arcade.get("storm_phase")) and points > 0:
				step = 1
			elif step == 1 and bool(arcade.get("storm_phase")) and count_correct:
				step = 2
		"battery_relay":
			if step == 0 and points == 20:
				step = 1
			elif step == 1 and count_correct:
				step = 2
		"eco_commute":
			if step == 0 and int(arcade.get("passengers")) >= 2:
				step = 1
			elif step == 1 and count_correct:
				step = 2
		"energy_sort":
			# A corrected classification is successful learning during practice,
			# even though competition correctly withholds its first-choice reward.
			step += 1
		_:
			if count_correct:
				step += 1

func progress(arcade: Node) -> Dictionary:
	if game_id == "hydro_gate":
		return arcade.call("get_practice_progress")
	var complete := step >= 2
	var hint: String = SUCCESSES.get(game_id, "연습 완료!") if complete else HINTS[game_id][step]
	if complete and game_id == "eco_commute" and bool(arcade.call("has_pending_finish_animation")):
		return {"step": step, "complete": false, "hint": "학교 도착! 학생들이 문을 지나 학교에 들어가고 있어요."}
	return {"step": step, "complete": complete, "hint": hint}

static func seconds_for(id: String) -> float:
	return 30.0 if id == "hydro_gate" else 60.0
