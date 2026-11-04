# 4인 온라인 UI 상태 점검

검증일: 2026-11-05. 이 문서는 UI 및 재접속 화면 복원 회귀를 기록한다. 실제 네트워크·WebRTC 전체 진행 검증은 별도 4인 통합 테스트 결과와 함께 확인한다.

## 재현 및 수정

| 문제 | 재현 조건 | 수정 |
| --- | --- | --- |
| 같은 시설이 학생마다 다른 칸에 보임 | 4개 지도에서 동일 시설을 서로 다른 칸에 요청한 뒤 첫 요청의 서버 결과를 적용 | 임시 예약 위치 대신 서버가 확정한 위치를 사용 |
| 해상도에 따라 건설 위치가 달라짐 | 크기가 다른 4개 지도에 동일한 확정 위치 적용 | 공통 `VillagePlacementRules`의 정규화된 셀 좌표를 전송하고, 각 지도 크기에 맞게 표시 |
| 빠른 재클릭으로 예약 칸이 남음 | 응답 전 같은 시설을 두 번 배치 | 대기 중인 시설의 추가 요청 차단, 해당 시설의 모든 예약 해제 |
| 서버가 거절한 건설의 칸을 다시 쓰지 못함 | 공동 재료·자리 경쟁으로 건설 요청 거절 | 요청자 전용 `game_action_rejected`를 받아 예약을 풀고 재선택 안내. 서버의 실제 원격 응답 검증은 transport 테스트 담당 |
| 재접속 후 완료된 완주 보상창이 남음 | 보상 완료 이벤트를 놓친 상태에서 완료된 서버 snapshot 적용 | 이전 보상창을 닫고 현재 미완료 보상만 다시 표시 |
| 재접속 후 시장·도감이 건설 화면을 가림 | 시장 종료 이벤트를 놓친 뒤 건설 snapshot 적용 | 시장과 도감 팝오버를 함께 닫고 건설 화면 복원. 엔딩 전환에도 같은 정리 적용 |
| 재접속 후 재료 가방 UI가 계속 숨음 | 퀴즈 종료 이벤트를 놓친 뒤 일반 턴 snapshot 적용 | 서버의 현재 퀴즈 상태로 안내·재료 UI 표시 상태 복원 |
| 튜토리얼 즉시 재시작 시 화면 갱신 콜백 중복 연결 | `GuidedTutorialTest`에서 종료 후 다음 프레임 전에 다시 시작, exit 0이지만 엔진 `ERROR` 발생 | 보드를 비활성화하거나 새 snapshot을 요청할 때 이전 일회성 콜백도 해제. 해당 회귀 재실행으로 오류 없이 통과 |

## 테스트 범위

`scripts/tests/FourPlayerUiStateTest.gd`는 네 명의 인간 플레이어 데이터와 실제 `VillageMap`, `Main`, HUD 인스턴스를 사용한다. 서로 다른 4개 지도 크기에서 드롭과 확정 표시, 중복 입력, 거절 시 예약 해제, 재접속 후 모달 정리를 검증한다. 기존 코드에서 위 회귀 assertion들이 실패하는 것을 확인한 후 수정했다.

이 테스트의 지연 응답 및 재접속 상태는 명시적인 fixture다. 학생 4명이 실제 인터넷으로 처음부터 끝까지 플레이한 결과로 해석하지 않는다. 공개 URL이나 제품 API에 상태 주입 기능을 추가하지 않았다.

추가 회귀 실행: `UiFlowRegressionTest`, `NetworkRecoveryRulesTest`, `AdventurePresentationTest`, `BoardReadabilityTest`. `CoreRulesSmokeTest`는 실제 HUD 드롭을 통한 오프라인 건설 경로가 정규화된 공통 셀 규칙에서도 유지되는지 확인한다.

최종 검증에서는 CI의 `Run regression tests` 목록 34개를 순차 headless로 실행했다. `GuidedTutorialTest`의 위 콜백 오류를 수정하고 해당 테스트만 다시 실행한 결과 **34/34 통과**, 모두 exit 0이며 `SCRIPT ERROR`, `Parse Error`, `[FAIL]`, 줄 시작 `ERROR`가 없다. 원본·수정 후 로그와 기계 판독 결과는 `.godot/four-player-final-regression/`에 남겼다. 일부 기존 테스트는 `[PASS]` 대신 `PASS` 또는 `0 failures`를 사용하므로 성공 표식의 대괄호 유무만으로 실패 처리하지 않았다.

## 4인 통합 테스트에서 사용하는 실제 UI 경로

- 로비: `LobbyUI._create_configured_room`, `_join_listed_room`은 방 UI 콜백이며, 시작은 `_room_start_button.pressed`.
- 모험 준비: `hud.adventure_planner.tutorial_button.pressed`.
- 주사위: `hud.center_dice_button.pressed`. 차례가 아닌 로컬 좌석은 입력을 보내지 않는다.
- 퀴즈: `quiz_modal.choice_container`의 Button. `answer_value` 메타데이터는 보기 값이며, 관전자는 관전 응답 경로를 사용한다.
- 미니게임: `minigame_modal.guide_start_button` 및 `guide_practice_button`. 온라인 연습 중에도 서버 시작 시각을 따르며 본게임 전에 연습 상태를 초기화한다.
- 시장: `hud.open_market_item_grid`의 Button, `open_market_confirm_button`.
- 건설: `hud.construction_list` 시설 Button → `hud.village_map` 클릭 또는 방향키·Enter → `hud.evaluate_button`.

온라인 요청은 각 클라이언트의 로컬 좌석을 사용한다. 보상·완공·최종 순위는 서버 규칙과 별도 통합 테스트가 검증한다. 이 변경에 플레이 기록 저장 기능은 없다.
