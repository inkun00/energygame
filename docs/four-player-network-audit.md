# 4인 온라인 통신 검증 — 2026-11-05

## 범위

외부 이용자의 방에 접속하지 않고, 실제 ENet 프로세스 4개 및 메모리 SQLite에 연결한 실제 room-directory Worker로 검증했다. 브라우저 WebRTC 전체 플레이 검증은 별도 `FourPlayerWebHarness` / `run_four_player_web_test.cjs`에서 담당한다. 테스트 전용 스크립트만 추가했으며 배포 게임에 디버그 입력, 점수 저장, 공개 테스트 API를 추가하지 않았다.

## 재현하고 수정한 문제

| 문제 | 수정 전 증거 | 수정 |
| --- | --- | --- |
| 친구 3명이 동시에 참가하면 빈자리가 있어도 2명이 거절됨 | 4인 방에 join 3개를 동시에 요청하면 HTTP `201, 409, 409` | 빈자리 선택과 삽입을 하나의 SQL 문장으로 실행. 현재 `201, 201, 201`, peer `2, 3, 4` |
| 같은 참가 요청 재시도가 자리를 중복 예약할 수 있음 | 별도 요청마다 새 빈 peer 번호를 선택하는 구조, 동시 재시도도 실패 | 참가 토큰이 이미 예약한 자리는 그대로 반환. 3개 동시 요청과 후속 재시도 모두 같은 peer2, 총 인원은 호스트 포함2명 |
| 만료 직전 입장 재시도가 성공해도 예전 시각에 자리가 만료됨 | 남은1초에 같은 토큰으로 재시도하면 응답은120초 연장되지만 DB는 옛 만료시각 유지, 2초 뒤 signaling 인증 실패 | 같은 자리·토큰의 DB 만료시각도 갱신. 늦게 처리된 옛 요청이 시간을 줄이지 않도록 기존값과 최댓값 사용 |
| 만료된 자리의 이전 WebRTC 메시지가 새 참가자에게 도착 | peer2 만료 후 새 토큰으로 참가해 poll하면 이전 참가자를 위한 `old-answer`가 반환됨 | 만료 peer의 발신·수신 대기 신호를 지운 뒤 번호 재사용 |
| 여러 연결이 같은 poll에서 끊길 때 이미 닫히는 ENet peer로 송신 | 3명 동시 연결 종료 시 `Unable to send packet on channel 0, max channels: 0` 3건 | 호스트 경유 구조에 불필요한 client 간 relay 해제. 끊김 poll을 마친 뒤 남은 연결에 로비·복구 정보를 전송 |
| 경합으로 거절된 건설 요청이 사용자에게 응답하지 않음 | `build_village_project()`의 false 반환을 무시하여 클라이언트 지도에 예약칸이 남을 수 있음 | 요청자에게만 reliable 권한 RPC로 `game_action_rejected("build_project", {project_index})` 전달. 호스트 로컬에도 동일 signal. HUD가 예약칸을 해제 |

시작 잠금과 참가 삽입 사이의 경합도 검사한다. 입장 처리가 진행되는 사이 방장이 게임을 시작하면 추가 자리를 배정하지 않는다. 기존 비밀번호·정원·방장 권한·토큰 비공개·진행 중 신규 참가 금지 검증도 유지한다.

## 실제 4개 프로세스 시나리오

`FourPlayerTransportTest.gd`는 호스트와 guest1/2/3를 실제 localhost UDP **18926**에 연결한다.

1. 세 참가자의 동시 등록, 4명 모두 사람인 시작 상태와 고유 자리 확인.
2. 각 클라이언트의 건설 거절 응답 및 호스트 로컬 거절 응답 확인.
3. 세 참가자의 실제 ENet 연결을 함께 끊고 게임·주사위 시간이 정지하는지 확인.
4. 두 참가자가 새 ENet peer ID로 돌아와 원래 자리와 에너지를 복구하는지 확인.
5. 두 명이 돌아와도 나머지 한 명의 유예 중에는 계속 정지하는지 확인.
6. 돌아오지 않은 한 명만 AI로 전환, 해당 복구 토큰 폐기, 호스트와 두 클라이언트가 함께 재개하는지 확인.
7. 호스트 종료 시 남은 클라이언트가 마지막 상태를 보존한 채 멈추고, 무한 대기 대신 실패 상태와 로비 복귀가 가능한지 확인.

기본 유예는 실제 게임의 **30초** 그대로 유지한다. 테스트의 대기 비용만 줄이려고 테스트 내부에서 마지막 참가자와 호스트 상실의 deadline을 당긴다.

## 실행과 확인 결과

```powershell
node scripts/tests/run_four_player_transport_test.cjs
cd services/room-directory
npm test
```

Godot가 PATH에 없으면 `GODOT_BIN`에 Godot 콘솔 실행 파일 경로를 지정한다. 네이티브 runner는 프로세스 종료 코드, PASS 표식, GDScript/엔진 오류의 부재를 모두 검사하고 `.godot/four-player-transport/`에 각 역할 로그를 남긴다.

- 4인 실제 ENet: 호스트12 / guest1 9 / guest2 9 / guest3 5, **35개 검사 통과**, 엔진 오류 없음.
- room-directory: **14/14 통과**. 기존9개 + 동시3명 / 중복 요청 / 재시도 TTL / 만료 자리 / 시작 경합5개. TTL은 가상시각으로 만료1초 전 재시도 및 재시도2초 뒤 signaling 성공을 확인.
- 기존 `NetworkRecoveryTest.gd` host/client/intruder 실제3프로세스: **24개 검사 통과**, 엔진 오류 없음. 이름을 복제한 외부 참가자가 기존 자리를 복구할 수 없음을 포함.
- `NetworkPayloadSmokeTest.gd`: 통과.
- `NetworkInputValidationTest.gd`: 통과. 9종 미니게임의 점수 형식·시간·소유권·중복 제출 검증 유지.
- UI 담당의 `FourPlayerUiStateTest.gd`, `UiFlowRegressionTest.gd`, `NetworkRecoveryRulesTest.gd`: 거절 예약 해제와 기존 복구 UI 통과.

## 한계와 반영 위치

이 검증은 동일 PC의 독립 프로세스와 로컬 서비스의 통합 시험이다. 서로 다른 학교 Wi-Fi, 방화벽, NAT/TURN, 저사양 기기 네 대, 실제 학생의 동시 조작과 이해도를 검증했다는 의미는 아니다. WebRTC 브라우저 검증 결과는 전체 검증 보고서를 함께 참조한다.

서비스 슬롯·신호 변경은 **room-directory Cloudflare Worker**에 별도로 반영해야 하며 Vercel 게임 파일만 배포해서는 적용되지 않는다. 이 감사 작업에서는 서비스에 배포하거나 이용자의 기존 방을 변경하지 않았다.
