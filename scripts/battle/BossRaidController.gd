extends RefCounted
class_name BossRaidController

## BossRaidController: 중간보스(뱀파이어) 및 최종보스(기후위기 타이탄) 전투 시스템

enum BossType { NONE, VAMPIRE_STANDBY, CLIMATE_TITAN }

var active_boss_type: BossType = BossType.NONE
var boss_name: String = ""
var max_hp: int = 100
var current_hp: int = 100
var reward_energy: int = 10
var boss_sprite_path: String = ""
var weakness_desc: String = ""

func start_boss_battle(type: BossType) -> void:
	active_boss_type = type
	if type == BossType.VAMPIRE_STANDBY:
		boss_name = "대기전력 뱀파이어"
		max_hp = 60
		current_hp = 60
		reward_energy = 8
		boss_sprite_path = "res://assets/images/boss_vampire_standby.webp"
		weakness_desc = "퇴치 조건: 태양광 패널·풍력 날개·배터리·스마트 그리드 중 재료 1개"
	elif type == BossType.CLIMATE_TITAN:
		boss_name = "기후위기 매연 타이탄"
		max_hp = 120
		current_hp = 120
		reward_energy = 15
		boss_sprite_path = "res://assets/images/boss_climate_titan.webp"
		weakness_desc = "퇴치 조건: 핵심 건설재료를 사용해 총 120 피해 주기"
	else:
		reset_battle()

func apply_damage(damage: int) -> bool:
	current_hp = max(0, current_hp - damage)
	return current_hp <= 0 # Returns true if boss is defeated

func reset_battle() -> void:
	active_boss_type = BossType.NONE
	boss_name = ""
	max_hp = 0
	current_hp = 0
