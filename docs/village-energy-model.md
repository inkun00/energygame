# 마을 전기 시험 모델

`scripts/core/VillageEnergyTrial.gd`는 건설한 시설과 플레이어의 조작만으로 결과를 계산한다. 낮 20초, 밤 20초 동안 각 구역의 전기 공급과 저장량을 보여 준다. 기록을 파일이나 계정에 저장하지 않는다.

## 플레이와 판정

- 모든 플레이어는 같은 시설에서 나온 전기, 수요, 저장 용량을 똑같이 나눈 구역 하나를 맡는다. 구역별 저장량과 버튼 선택은 따로 계산한다.
- 발전한 전기는 현재 수요에 먼저 공급한다. `store`는 남는 전기만 저장하고, `supply`는 현재 발전량이 부족할 때 저장한 전기를 꺼낸다.
- 시작할 때 저장량은 0이고 버튼은 `supply`다. 낮밤이 바뀌어도 플레이어의 버튼을 자동으로 바꾸지 않는다.
- 저장 시설이 없으면 저장 용량이 0이다. 배터리는 발전소가 아니므로 빈 배터리는 전기를 공급할 수 없다.
- 결과는 **실제로 공급한 전기 / 필요한 전기**를 시간 전체에 걸쳐 누적한 비율이다. 전체 95% 이상, 밤 90% 이상이면 성공이다. 시설 개수나 기존 경관 점수로 성공을 대신 판정하지 않는다.
- 충분한 발전 조합이나 수요 절감으로 밤 수요를 충족하면 저장 시설 없이도 성공한다. 배터리가 모든 전력망에 반드시 필요하다는 뜻으로 표현하지 않는다.
- 부족할 때 남은 재료로 시설을 보완하고 한 번 더 시험하는 흐름은 GameManager가 관리한다. 이 모델은 한 번의 40초 시험만 계산한다.

## 게임 수치

전기 흐름의 단위는 **게임 전기칸/초**, 저장량은 **게임 전기칸**이다. 실제 MW, 발전소 크기, 발전 기술의 효율이나 우열을 나타내지 않는다. 아래 값은 짧은 활동에서 낮에 남는 전기와 밤의 부족분을 눈으로 비교하도록 정한 게임 균형값이다. 실제 하루의 시간축이나 수요 곡선을 축척한 자료도 아니다.

기본 수요는 낮 3, 밤 4이다. 시험에서는 밤에 조명 등을 더 사용하는 마을을 가정한다.

| ID | 시설 | 낮 발전 | 밤 발전 | 추가 효과와 조건 |
| --- | --- | ---: | ---: | --- |
| 0 | 태양광 | 8 | 0 | 맑은 낮, 해가 진 밤 |
| 1 | 풍력 | 5 | 2 | 이번 시험의 예보에서는 밤에 바람이 약해짐 |
| 2 | 효율 건물 | 0 | 0 | 수요를 낮 0.75, 밤 1 줄임 |
| 3 | 저장 시설 | 0 | 0 | 총 용량 100, 빈 상태로 시작 |
| 4 | 소수력 | 3.2 | 3.2 | 시험 내내 물이 흐르는 조건 |
| 5 | 지열 | 2.8 | 2.8 | 시험 중 일정한 공급 |
| 6 | 조력 | 1 | 4 | 이번 시험에서는 바닷물 흐름이 뒤에 강해짐 |
| 7 | 원자력 | 2.5 | 2.5 | 전기를 공급하지만 재생에너지는 아님 |
| 8 | 자원 순환 시설 | 0 | 0 | 새 재료 생산에 필요한 수요를 낮·밤 각각 0.25 줄임 |
| 9 | 전기 교통 시설 | 0 | 0 | 낮의 버스 충전 수요 0.75 추가 |

풍력이 항상 밤에 약하거나 조력이 항상 밤에 강한 것은 아니다. 위 값은 해당 시험의 **날씨와 바닷물 흐름 조건**이다. 소수력의 출력도 실제로는 유량과 낙차에 따라 달라진다. 자원 순환의 절감량은 재료와 공정에 따라 달라지고, 전기 교통 시설도 충전에 전기가 필요하다. 이 시험은 교통수단 전체의 에너지 소비나 수명 주기 배출량을 비교하지 않는다.

저장 효율은 게임값 90%로 둔다. 충전 입력의 10%를 손실로 계산하며, 방전 손실·자기 방전·출력 제한은 40초 활동을 단순하게 유지하기 위해 생략한다. 이 값은 특정 배터리 제품의 성능을 인용한 것이 아니다.

## 에너지 보존

매 시점에 발전량 중 수요만큼을 먼저 직접 공급한다. 남은 발전량과 부족한 수요량은 동시에 양수가 될 수 없다.

```text
직접 공급 = min(발전량, 수요)
충전 입력 = min(남는 발전량, 남은 용량 / 0.9)    [store일 때만]
충전된 양 = 충전 입력 × 0.9
방전량 = min(부족한 수요, 저장량)               [supply일 때만]

누적 발전 = 누적 공급 + 현재 저장량 + 충전 손실 + 사용하지 못한 전기
누적 충전된 양 = 현재 저장량 + 누적 방전량
```

누적 계산에는 구간의 실제 길이를 곱한다. `advance`는 낮밤 경계에서 시간을 나눠 계산하므로 긴 프레임 하나와 여러 짧은 프레임의 결과가 같다. 40초를 넘는 입력은 종료 시점까지만 반영하며 종료한 결과는 이후 조작으로 바뀌지 않는다.

## API와 화면 연결

```gdscript
create_state(built_ids: Array, player_count: int = 4) -> Dictionary
advance(state: Dictionary, delta: float) -> void
set_mode(state: Dictionary, player_idx: int, mode: String) -> bool
forecast(built_ids: Array) -> Dictionary
is_complete(state: Dictionary) -> bool
```

`create_state`는 시설 ID 0–9만 받아 중복을 제거한다. 플레이어 수는 1–4이다. `advance`는 상태를 제자리에서 갱신한다. `set_mode`는 `store`, `supply`만 받으며 잘못된 구역·명령이나 종료 후 명령에는 `false`를 반환한다.

| 상태 필드 | 의미 |
| --- | --- |
| `phase` | `day`, `night`, `complete` |
| `elapsed`, `duration`, `phase_remaining` | 지난 시간, 전체 40초, 현재 구간의 남은 초 |
| `built_ids`, `player_count`, `players` | 시설 목록, 구역 수, 구역별 상태 |
| `generation`, `demand`, `direct` | 현재 발전, 수요, 직접 공급 속도 |
| `charging`, `discharging`, `delivered`, `unserved` | 현재 충전 입력, 방전, 공급, 부족 속도 |
| `battery`, `capacity` | 저장량, 최대 저장량 |
| `light_ratio` | 현재 공급 / 현재 수요, 0–1 |
| `coverage`, `daytime_coverage`, `night_coverage` | 전체·낮·밤 누적 충족률, 모두 0–1 |
| `success` | 종료 후 전체 95%, 밤 90% 조건을 함께 만족하는지 |
| `condition_label`, `profile` | 해당 구간의 조건, 시설별 효과를 합산한 낮밤 예측 |

`players`에도 흐름·저장·충족률 필드가 있으며 `mode`가 추가된다. 최상위 흐름과 저장량은 구역별 값을 합한 것이다. 누적 분모가 아직 0인 구간의 충족률은 0이다. `total_generation`, `total_demand`, `total_delivered`, `total_direct`, `total_charge_input`, `total_stored`, `total_loss`, `total_curtailed`, `total_discharged`, `daytime_demand`, `daytime_delivered`, `night_demand`, `night_delivered`도 구역과 전체에 제공한다.

흐름 필드는 다음 순간의 공급 상태다. 배터리가 막 고갈된 순간에는 공급이 줄어든 모습이 표시되지만, 누적 충족률은 고갈되기 전 실제로 공급했던 양까지 정확히 포함한다. 종료 후 흐름 필드는 마지막 밤 조건의 상태로 남고, 최종 결과에는 누적 충족률을 사용한다.

`forecast`는 모든 플레이어가 낮에 저장하고 밤에 공급했을 때의 예측을 반환한다. `day_generation`, `night_generation`, `day_demand`, `night_demand`, `capacity`, `has_storage`, `has_nuclear`, `day_condition`, `night_condition`과 세 충족률, `success`, `can_cover`, `remaining_battery`를 포함한다. 예상 성공은 실제 조작을 대신하지 않는다.

## 확인한 조합

| 조합과 조작 | 전체 충족 | 밤 충족 | 결과 |
| --- | ---: | ---: | --- |
| 태양광만 | 42.86% | 0% | 밤 전기 부족 |
| 태양광 + 저장, 낮 저장·밤 공급 | 100% | 100% | 성공, 마지막 저장량 10 |
| 같은 시설, 저장 버튼을 누르지 않음 | 42.86% | 0% | 밤 전기 부족 |
| 같은 시설, 밤에도 계속 저장 | 42.86% | 0% | 저장한 전기를 사용하지 못함 |
| 같은 시설, 4명 중 3명만 저장·공급 | 85.71% | 75% | 한 구역의 밤 전기 부족 |
| 풍력 + 저장, 낮 저장·밤 공급 | 97.14% | 95% | 성공, 종료 전에 저장량 소진 |
| 소수력 + 효율 건물 | 100% | 100% | 저장 시설 없이 성공 |
| 태양광 + 조력 | 100% | 100% | 시험의 서로 다른 발전 조건으로 성공 |
| 태양광 + 소수력 + 저장 | 100% | 100% | 성공 |

`scripts/tests/VillageEnergyTrialTest.gd`는 개별 10개 시설, 모든 1,024개 시설 조합, 구역별 공정성, 저장 선택의 실제 효과, 에너지 보존, 비정상 입력, 큰 시간 간격, 종료 이후 불변성을 검증한다.

## 과학 근거

2026-11-05에 아래 1차 자료를 확인했다. 근거는 동작 원리에 사용했으며 게임 수치의 근거로 오인하지 않는다.

- 태양광 발전은 햇빛의 영향을 받으며, 저장한 에너지는 나중에 사용할 수 있다. [미국 에너지부: Solar Energy and Storage Basics](https://www.energy.gov/cmei/systems/solar-integration-solar-energy-and-storage-basics)
- 전기 저장은 발전과 사용 시점을 연결하며, 충전·방전 과정에서 손실이 생긴다. [미국 EIA: Energy Storage for Electricity Generation](https://www.eia.gov/energyexplained/electricity/energy-storage-for-electricity-generation.php)
- 수력에서 얻을 수 있는 에너지는 물의 흐름과 낙차에 영향을 받는다. [미국 에너지부: How Hydropower Works](https://www.energy.gov/cmei/water/how-hydropower-works)
- 지열은 날씨와 관계없이 지속적인 공급에 활용할 수 있다. [미국 에너지부: Geothermal FAQs](https://www.energy.gov/hgeo/geothermal/geothermal-faqs)
- 조력은 조수에 따른 수위와 물 흐름을 이용한다. [미국 EIA: Tidal Power](https://www.eia.gov/energyexplained/hydropower/tidal-power.php)
- 단열은 열의 이동을 줄여 난방·냉방에 필요한 에너지를 줄인다. [미국 ENERGY STAR: Insulation Fact Sheet](https://www.energystar.gov/sites/default/files/asset/document/Insulation%20Fact%20Sheet.pdf)
- 재활용은 새 원료를 얻고 가공하는 데 필요한 에너지를 절약할 수 있다. [미국 EPA: Recycling Basics and Benefits](https://www.epa.gov/recycle/recycling-basics-and-benefits)
- 원자력은 비재생 에너지원으로 분류한다. [미국 EIA: Sources of Energy](https://www.eia.gov/energyexplained/what-is-energy/sources-of-energy.php)
