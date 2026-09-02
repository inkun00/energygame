extends Node
class_name BoardGrid

## BoardGrid: 10x10, 100칸 격자형 보드 좌표, 타일 유형, 사다리 및 미끄럼틀 링크 관리

enum TileType {
	START,
	QUIZ_CHOSUNG,
	QUIZ_OX,
	QUIZ_CHOICE,
	LADDER,
	SLIDE,
	POWERPLANT,
	CHANCE_CARD,
	REST_TURN,
	FINISH
}

const COLUMN_COUNT := 10
const ROW_COUNT := 10
const TILE_COUNT := COLUMN_COUNT * ROW_COUNT
const LAST_TILE_INDEX := TILE_COUNT - 1
const TILE_SPACING_3D := 2.2
const BOARD_WIDTH_3D := (COLUMN_COUNT - 1) * TILE_SPACING_3D + 2.6
const BOARD_DEPTH_3D := (ROW_COUNT - 1) * TILE_SPACING_3D + 2.6

# 아래에서 위로 진행하며 각 행 끝에서 방향이 바뀌는 10x10 지그재그 경로입니다.
static var TILE_POSITIONS_3D: Array[Vector3] = _create_tile_positions_3d()
static var TILE_POSITIONS: Array[Vector2] = _create_tile_positions_2d()

# 일반 이동과 모든 지름길 이동을 기존보다 정확히 30% 느리게 재생합니다.
const MOVEMENT_DURATION_SCALE := 1.30
const MOVE_STEP_SECONDS := 0.4732 * MOVEMENT_DURATION_SCALE
const SHORTCUT_MOVE_SECONDS := 2.028 * MOVEMENT_DURATION_SCALE

# 타일별 속성 및 이벤트 메타데이터
static var TILE_DATA: Array[Dictionary] = [
	{"index": 0, "name": "위기의 왕국 관문", "type": TileType.START, "desc": "화석연료 의존으로 위기에 빠진 에너지요정 나라를 복원하세요!"},
	{"index": 1, "name": "재생에너지 설계소", "type": TileType.CHANCE_CARD, "desc": "발전소 설계 도면과 건설 자재를 확보합니다!"},
	{"index": 2, "name": "소수력 발전소", "type": TileType.POWERPLANT, "reward_energy": 2, "desc": "흐르는 물의 힘! 에너지 2개 획득"},
	{"index": 3, "name": "스마트 플러그 사다리", "type": TileType.LADDER, "target": 16, "desc": "대기전력 차단 성공! 바로 위 16번 칸으로 사다리를 탑니다!"},
	{"index": 4, "name": "열에너지 퀴즈", "type": TileType.QUIZ_CHOSUNG, "desc": "분자의 무작위 운동 에너지"},
	{"index": 5, "name": "운동에너지 퀴즈", "type": TileType.QUIZ_OX, "desc": "운동하는 물체가 가진 힘"},
	{"index": 6, "name": "풍력 발전단지", "type": TileType.POWERPLANT, "reward_energy": 2, "desc": "거대한 바람개비의 힘! 에너지 2개 획득"},
	{"index": 7, "name": "절전 지름길 사다리", "type": TileType.LADDER, "target": 12, "desc": "에너지 절약에 성공해 바로 위 12번 칸으로 사다리를 탑니다!"},
	{"index": 8, "name": "전기에너지 퀴즈", "type": TileType.QUIZ_OX, "desc": "전하의 움직임"},
	{"index": 9, "name": "전기 절약 퀴즈", "type": TileType.QUIZ_OX, "desc": "사용하지 않는 플러그를 뽑는 절약 습관을 확인합니다."},
	{"index": 10, "name": "소리에너지 퀴즈", "type": TileType.QUIZ_CHOICE, "desc": "물체의 진동과 파동"},
	{"index": 11, "name": "대기전력 절약 객관식", "type": TileType.QUIZ_OX, "desc": "사용하지 않는 전자기기의 대기전력을 줄이는 방법을 확인합니다."},
	{"index": 12, "name": "태양광 발전 사다리", "type": TileType.LADDER, "target": 27, "desc": "햇빛을 전기로 바로 전환! 바로 위 27번 칸으로 사다리를 탑니다!"},
	{"index": 13, "name": "화학에너지 퀴즈", "type": TileType.QUIZ_CHOSUNG, "desc": "화학 결합 속 포텐셜에너지"},
	{"index": 14, "name": "롤러코스터 환승역", "type": TileType.POWERPLANT, "reward_energy": 2, "desc": "위치 ⇄ 운동 에너지 상호 변환! 에너지 2개 획득"},
	{"index": 15, "name": "빈 방 전등 미끄럼틀", "type": TileType.SLIDE, "target": 4, "desc": "빈 방에 불을 켜두어 전기가 낭비되었습니다! 바로 아래 4번 칸으로 미끄러집니다!"},
	{"index": 16, "name": "에코 쉼터", "type": TileType.REST_TURN, "desc": "잠시 쉬어가며 에너지를 재충전합니다. (1턴 휴식)"},
	{"index": 17, "name": "전자기 퀴즈", "type": TileType.QUIZ_CHOSUNG, "desc": "전자기장과 전하의 흐름"},
	{"index": 18, "name": "대기전력 낭비 미끄럼틀", "type": TileType.SLIDE, "target": 1, "desc": "대기전력 낭비가 쌓였습니다! 바로 아래 1번 칸으로 미끄러집니다!"},
	{"index": 19, "name": "태양광 패널 지대", "type": TileType.POWERPLANT, "reward_energy": 3, "desc": "무한한 햇빛 에너지! 에너지 3개 획득"},
	{"index": 20, "name": "과도한 냉방 미끄럼틀", "type": TileType.SLIDE, "target": 19, "desc": "에어컨을 과도하게 사용했습니다! 바로 아래 19번 칸으로 미끄러집니다!"},
	{"index": 21, "name": "신재생에너지 퀴즈", "type": TileType.QUIZ_CHOICE, "desc": "그린수소와 지속 가능한 미래"},
	{"index": 22, "name": "수소연료전지 기지", "type": TileType.POWERPLANT, "reward_energy": 4, "desc": "물만 배출하는 궁극의 청정에너지! 에너지 4개 획득"},
	{"index": 23, "name": "그린수소 연구 퀴즈", "type": TileType.QUIZ_CHOICE, "desc": "탄소를 배출하지 않는 청정 수소 생산 방법을 확인합니다."},
	{"index": 24, "name": "그린 시티 관문", "type": TileType.CHANCE_CARD, "desc": "후반 모험을 위한 보너스 건설재료를 1개 획득!"},
	{"index": 25, "name": "고효율 조명 사다리", "type": TileType.LADDER, "target": 34, "desc": "LED 조명으로 교체 성공! 바로 위 34번 칸으로 사다리를 탑니다!"},
	{"index": 26, "name": "태양에너지 객관식", "type": TileType.QUIZ_OX, "desc": "태양에너지의 원리를 확인합니다."},
	{"index": 27, "name": "해상 풍력 발전소", "type": TileType.POWERPLANT, "reward_energy": 3, "desc": "바다의 강한 바람! 에너지 3개 획득"},
	{"index": 28, "name": "단열 리모델링 사다리", "type": TileType.LADDER, "target": 31, "desc": "열손실 차단 성공! 바로 위 31번 칸으로 사다리를 탑니다!"},
	{"index": 29, "name": "숲속 에코 쉼터", "type": TileType.REST_TURN, "desc": "숲을 돌보며 잠시 쉬어갑니다. (1턴 휴식)"},
	{"index": 30, "name": "물 낭비 미끄럼틀", "type": TileType.SLIDE, "target": 29, "desc": "수도꼭을 잠그지 않았습니다! 바로 아래 29번 칸으로 미끄러집니다!"},
	{"index": 31, "name": "순환 자원 객관식 퀴즈", "type": TileType.QUIZ_CHOICE, "desc": "순환경제와 자원 재활용 문제"},
	{"index": 32, "name": "지열 에너지 기지", "type": TileType.POWERPLANT, "reward_energy": 4, "desc": "땅속의 열을 활용! 에너지 4개 획득"},
	{"index": 33, "name": "그린 재료 보너스", "type": TileType.CHANCE_CARD, "desc": "친환경 시설용 보너스 건설재료를 1개 획득!"},
	{"index": 34, "name": "대중교통 환승 센터", "type": TileType.CHANCE_CARD, "desc": "대중교통을 이용해 탄소를 줄였습니다! 보너스 건설재료를 1개 획득합니다."},
	{"index": 35, "name": "탄소중립 실천 객관식", "type": TileType.QUIZ_OX, "desc": "생활 속 탄소중립 실천 방법을 확인합니다."},
	{"index": 36, "name": "일회용품 미끄럼틀", "type": TileType.SLIDE, "target": 23, "desc": "일회용품을 남용했습니다! 바로 아래 23번 칸으로 미끄러집니다!"},
	{"index": 37, "name": "탄소중립 객관식 퀴즈", "type": TileType.QUIZ_CHOSUNG, "desc": "탄소중립을 위한 핵심 개념"},
	{"index": 38, "name": "바이오 에너지 농장", "type": TileType.POWERPLANT, "reward_energy": 3, "desc": "유기성 자원으로 에너지 3개 획득"},
	{"index": 39, "name": "에너지 자립 사다리", "type": TileType.LADDER, "target": 40, "desc": "에너지 자립 성공! 바로 위 40번 칸으로 사다리를 탑니다!"},
	{"index": 40, "name": "기후행동 객관식", "type": TileType.QUIZ_OX, "desc": "일상의 기후행동을 점검합니다."},
	{"index": 41, "name": "대기전력 재발 미끄럼틀", "type": TileType.SLIDE, "target": 38, "desc": "대기전력 낭비가 재발했습니다! 바로 아래 38번 칸으로 미끄러집니다!"},
	{"index": 42, "name": "에너지 저장장치", "type": TileType.POWERPLANT, "reward_energy": 4, "desc": "재생에너지를 저장해 에너지 4개 획득"},
	{"index": 43, "name": "도시 숲 쉼터", "type": TileType.REST_TURN, "desc": "도시 숲에서 재충전합니다. (1턴 휴식)"},
	{"index": 44, "name": "넷제로 도시 객관식 퀴즈", "type": TileType.QUIZ_CHOICE, "desc": "미래 도시의 에너지 전략 문제"},
	{"index": 45, "name": "과소비 미끄럼틀", "type": TileType.SLIDE, "target": 34, "desc": "불필요한 과소비를 했습니다! 바로 아래 34번 칸으로 미끄러집니다!"},
	{"index": 46, "name": "그린수소 메가 플랜트", "type": TileType.POWERPLANT, "reward_energy": 5, "desc": "청정 수소 생산! 에너지 5개 획득"},
	{"index": 47, "name": "해양 에너지 연구소", "type": TileType.POWERPLANT, "reward_energy": 5, "desc": "파도와 조류의 힘을 연구해 에너지 5개 획득"},
	{"index": 48, "name": "최종 에코 보너스", "type": TileType.CHANCE_CARD, "desc": "결승선을 위한 마지막 건설재료를 1개 획득!"},
	{"index": 49, "name": "에코 생활 보너스", "type": TileType.CHANCE_CARD, "desc": "후반 여정을 위한 친환경 전략 기회를 얻습니다!"}
]

# 기존 50칸의 학습 흐름을 보존하면서 후반 50칸을 생성해 총 100칸을 구성합니다.
# 발전소·쉼터·보너스를 일정 간격으로 배치하고 나머지는 다양한 에너지 퀴즈로 채웁니다.
static var _tile_data_initialized: bool = _initialize_tile_data()

static func _initialize_tile_data() -> bool:
	for tile_index in range(TILE_DATA.size(), LAST_TILE_INDEX):
		TILE_DATA.append(_make_extended_tile_data(tile_index))
	TILE_DATA.append({
		"index": LAST_TILE_INDEX,
		"name": "왕국 중앙 공사 현장",
		"type": TileType.FINISH,
		"desc": "마지막 자재를 전달해 에너지요정 왕국의 친환경 전환을 완성하세요!"
	})
	return TILE_DATA.size() == TILE_COUNT

static func _make_extended_tile_data(tile_index: int) -> Dictionary:
	match tile_index:
		52:
			return {"index": tile_index, "name": "조력 에너지 연구소", "type": TileType.POWERPLANT, "reward_energy": 4, "desc": "밀물과 썰물의 힘으로 에너지 4개 획득"}
		56:
			return {"index": tile_index, "name": "바람꽃 쉼터", "type": TileType.REST_TURN, "desc": "바람꽃 정원에서 에너지를 재충전합니다. (1턴 휴식)"}
		60:
			return {"index": tile_index, "name": "태양열 마을 온실", "type": TileType.POWERPLANT, "reward_energy": 4, "desc": "태양열로 온실을 데워 에너지 4개 획득"}
		64:
			return {"index": tile_index, "name": "자원순환 보너스", "type": TileType.CHANCE_CARD, "desc": "버려진 자원에서 새로운 건설 기회를 발견합니다!"}
		68:
			return {"index": tile_index, "name": "심부 지열 발전소", "type": TileType.POWERPLANT, "reward_energy": 5, "desc": "깊은 땅속 열을 활용해 에너지 5개 획득"}
		72:
			return {"index": tile_index, "name": "푸른 숲 쉼터", "type": TileType.REST_TURN, "desc": "탄소를 흡수하는 숲을 돌보며 쉽니다. (1턴 휴식)"}
		76:
			return {"index": tile_index, "name": "부유식 해상 풍력단지", "type": TileType.POWERPLANT, "reward_energy": 5, "desc": "먼바다의 강한 바람으로 에너지 5개 획득"}
		80:
			return {"index": tile_index, "name": "스마트그리드 보너스", "type": TileType.CHANCE_CARD, "desc": "전기를 똑똑하게 나누는 친환경 전략 기회를 얻습니다!"}
		84:
			return {"index": tile_index, "name": "계곡 소수력 발전소", "type": TileType.POWERPLANT, "reward_energy": 5, "desc": "계곡물의 흐름으로 에너지 5개 획득"}
		88:
			return {"index": tile_index, "name": "요정 연못 쉼터", "type": TileType.REST_TURN, "desc": "맑은 연못에서 마지막 도전을 준비합니다. (1턴 휴식)"}
		92:
			return {"index": tile_index, "name": "그린수소 충전도시", "type": TileType.POWERPLANT, "reward_energy": 6, "desc": "재생에너지로 만든 수소를 공급해 에너지 6개 획득"}
		96:
			return {"index": tile_index, "name": "왕국 복원 보너스", "type": TileType.CHANCE_CARD, "desc": "완주를 앞두고 마지막 친환경 전략 기회를 얻습니다!"}
		98:
			return {"index": tile_index, "name": "초대형 에너지 저장소", "type": TileType.POWERPLANT, "reward_energy": 6, "desc": "남는 청정에너지를 저장해 에너지 6개 획득"}

	var quiz_kind := tile_index % 3
	if quiz_kind == 0:
		return {"index": tile_index, "name": "친환경 생활 OX 퀴즈", "type": TileType.QUIZ_OX, "desc": "생활 속 에너지 절약 습관을 확인합니다."}
	if quiz_kind == 1:
		return {"index": tile_index, "name": "에너지 전환 객관식", "type": TileType.QUIZ_CHOICE, "desc": "지속 가능한 에너지 전환 방법을 선택합니다."}
	return {"index": tile_index, "name": "탄소중립 개념 퀴즈", "type": TileType.QUIZ_CHOSUNG, "desc": "탄소중립과 재생에너지의 핵심 개념을 맞힙니다."}

# 매 게임 시작 시 사다리와 미끄럼틀을 다시 배치한다. 핵심 발전소·퀴즈·시작/도착 칸은
# 고정하고, 각 지름길의 양 끝을 모두 점유 처리해 겹침과 무한 순환을 원천적으로 막는다.
# 대표 퀴즈 칸은 항상 남겨 두어 게임 중 객관식 학습 흐름이 끊기지 않게 합니다.
const SHORTCUT_PROTECTED_INDICES: Array[int] = [0, 1, 2, 4, 5, 6, 10, 11, 14, 19, 22, 23, 27, 32, 34, 35, 38, 42, 46, 47, 48, 49, 52, 56, 60, 64, 68, 72, 76, 80, 84, 88, 92, 96, 98, 99]
const RANDOM_LADDER_COUNT := 8
const RANDOM_SLIDE_COUNT := 8
static var _shortcut_free_template: Array[Dictionary] = []
static var _previous_shortcut_signature := ""

static func assign_random_shortcuts() -> void:
	if _shortcut_free_template.is_empty():
		_shortcut_free_template = _create_shortcut_free_template()
	var rng := RandomNumberGenerator.new()
	# 바로 직전 게임과 같은 배치가 나올 확률까지 피하기 위해 몇 번 다시 뽑습니다.
	for attempt in range(4):
		TILE_DATA = _shortcut_free_template.duplicate(true)
		rng.randomize()
		var occupied_endpoints: Dictionary = {}
		_assign_random_shortcut_kind(rng, TileType.LADDER, RANDOM_LADDER_COUNT, occupied_endpoints)
		_assign_random_shortcut_kind(rng, TileType.SLIDE, RANDOM_SLIDE_COUNT, occupied_endpoints)
		var signature := get_shortcut_signature()
		if signature != _previous_shortcut_signature or attempt == 3:
			_previous_shortcut_signature = signature
			return

static func get_shortcut_signature() -> String:
	var links: Array[String] = []
	for tile in TILE_DATA:
		var tile_type: int = tile.get("type", TileType.QUIZ_OX)
		if tile_type in [TileType.LADDER, TileType.SLIDE]:
			links.append("%d:%d>%d" % [tile_type, int(tile["index"]), int(tile.get("target", -1))])
	links.sort()
	return "|".join(links)

static func _create_shortcut_free_template() -> Array[Dictionary]:
	var template: Array[Dictionary] = TILE_DATA.duplicate(true)
	for tile in template:
		var tile_type: int = tile.get("type", TileType.QUIZ_OX)
		if tile_type not in [TileType.LADDER, TileType.SLIDE]:
			continue
		var tile_index := int(tile["index"])
		tile.erase("target")
		tile["type"] = TileType.QUIZ_OX
		tile["name"] = "에너지 길찾기 퀴즈"
		tile["desc"] = "친환경 생활 습관을 확인하는 퀴즈입니다."
	return template

static func _assign_random_shortcut_kind(rng: RandomNumberGenerator, shortcut_type: int, desired_count: int, occupied_endpoints: Dictionary) -> void:
	var assigned_count := 0
	while assigned_count < desired_count:
		var candidates := _get_available_shortcut_links(shortcut_type, occupied_endpoints)
		if candidates.is_empty():
			return
		var selected: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
		var source_index := int(selected["source"])
		var target_index := int(selected["target"])
		var source_tile: Dictionary = TILE_DATA[source_index]
		source_tile["type"] = shortcut_type
		source_tile["target"] = target_index
		if shortcut_type == TileType.LADDER:
			source_tile["name"] = "절약 실천 사다리"
			source_tile["desc"] = "에너지 절약에 성공했습니다! %d번 칸으로 올라갑니다." % target_index
		else:
			source_tile["name"] = "에너지 낭비 미끄럼틀"
			source_tile["desc"] = "에너지가 낭비되었습니다! %d번 칸으로 내려갑니다." % target_index
		occupied_endpoints[source_index] = true
		occupied_endpoints[target_index] = true
		assigned_count += 1

static func _get_available_shortcut_links(shortcut_type: int, occupied_endpoints: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for source_index in range(1, LAST_TILE_INDEX):
		if not _is_shortcut_endpoint_available(source_index, occupied_endpoints):
			continue
		for target_index in range(1, LAST_TILE_INDEX):
			if not _is_shortcut_endpoint_available(target_index, occupied_endpoints):
				continue
			if not is_vertical_shortcut_link(source_index, target_index):
				continue
			if shortcut_type == TileType.LADDER and target_index <= source_index:
				continue
			if shortcut_type == TileType.SLIDE and target_index >= source_index:
				continue
			candidates.append({"source": source_index, "target": target_index})
	return candidates

static func _is_shortcut_endpoint_available(tile_index: int, occupied_endpoints: Dictionary) -> bool:
	if tile_index in SHORTCUT_PROTECTED_INDICES or occupied_endpoints.has(tile_index):
		return false
	var tile_type: int = TILE_DATA[tile_index].get("type", TileType.QUIZ_OX)
	return tile_type in [TileType.QUIZ_CHOSUNG, TileType.QUIZ_OX, TileType.QUIZ_CHOICE, TileType.CHANCE_CARD]

static func _create_tile_positions_3d() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for row in range(ROW_COUNT):
		for step in range(COLUMN_COUNT):
			var column := step if row % 2 == 0 else COLUMN_COUNT - 1 - step
			var x := (float(column) - float(COLUMN_COUNT - 1) * 0.5) * TILE_SPACING_3D
			var z := (float(ROW_COUNT - 1) * 0.5 - float(row)) * TILE_SPACING_3D
			positions.append(Vector3(x, 0.28 if positions.size() == LAST_TILE_INDEX else 0.2, z))
	return positions

static func _create_tile_positions_2d() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var horizontal_spacing := 1140.0 / float(COLUMN_COUNT - 1)
	for row in range(ROW_COUNT):
		for step in range(COLUMN_COUNT):
			var column := step if row % 2 == 0 else COLUMN_COUNT - 1 - step
			positions.append(Vector2(70.0 + float(column) * horizontal_spacing, 560.0 - float(row) * 100.0))
	return positions

static func get_tile_position(index: int) -> Vector2:
	index = clamp(index, 0, TILE_POSITIONS.size() - 1)
	return TILE_POSITIONS[index]

static func get_tile_position_3d(index: int) -> Vector3:
	index = clamp(index, 0, TILE_POSITIONS_3D.size() - 1)
	return TILE_POSITIONS_3D[index]

static func get_tile_surface_height(index: int) -> float:
	index = clampi(index, 0, LAST_TILE_INDEX)
	# TileMarker3D의 BoxMesh는 타일 좌표를 중심으로 생성됩니다. 캐릭터와 그림자는
	# 이 상단면에 맞춰 배치해 타일 바닥을 뚫거나 공중에 뜨지 않게 합니다.
	var tile_height := 0.40 if index in [0, LAST_TILE_INDEX] else 0.34
	return get_tile_position_3d(index).y + tile_height * 0.5

static func get_tile_row(index: int) -> int:
	return int(clampi(index, 0, LAST_TILE_INDEX) / COLUMN_COUNT)

static func get_tile_column(index: int) -> int:
	var row := get_tile_row(index)
	var step := clampi(index, 0, LAST_TILE_INDEX) % COLUMN_COUNT
	return step if row % 2 == 0 else COLUMN_COUNT - 1 - step

static func is_vertical_shortcut_link(from_tile: int, to_tile: int) -> bool:
	if from_tile < 0 or from_tile > LAST_TILE_INDEX or to_tile < 0 or to_tile > LAST_TILE_INDEX:
		return false
	return get_tile_column(from_tile) == get_tile_column(to_tile) and abs(get_tile_row(from_tile) - get_tile_row(to_tile)) == 1

static func get_tile_data(index: int) -> Dictionary:
	index = clamp(index, 0, TILE_DATA.size() - 1)
	return TILE_DATA[index]

static func is_shortcut_transition(from_tile: int, to_tile: int) -> bool:
	var tile := get_tile_data(from_tile)
	var tile_type: int = tile.get("type", TileType.START)
	return tile_type in [TileType.LADDER, TileType.SLIDE] and tile.get("target", -1) == to_tile

static func get_movement_duration(from_tile: int, to_tile: int) -> float:
	if from_tile == to_tile:
		return 0.0
	if is_shortcut_transition(from_tile, to_tile):
		return SHORTCUT_MOVE_SECONDS
	return abs(to_tile - from_tile) * MOVE_STEP_SECONDS
