# 6자리 방 코드 연결 서버

Cloudflare Worker와 D1에 `방 코드 → 방장 공인 IPv4/UDP 포트`를 최대 90초 동안만 보관한다. 실제 게임 데이터는 이 서버를 통과하지 않고 방장과 참가자가 ENet으로 직접 주고받는다. 방장이 대기하는 동안 20초마다 만료 시간이 갱신되며, 게임을 시작하거나 방을 닫으면 등록이 삭제된다.

현재 배포 주소: `https://energygame-room-directory.energygame-room-directory.workers.dev`

Godot의 `network/room_directory_url`에도 위 주소가 설정되어 있다.

## 브라우저 멀티플레이

`GET /webrtc/rooms`는 만료되지 않은 방을 최대 100개 반환한다. 방 제목, 방장 닉네임, 정원, 현재 예약/참가 인원, 비밀번호 여부만 공개하며 인증 토큰과 비밀번호 해시는 반환하지 않는다. 클라이언트는 최초 대기실 진입 및 사용자의 새로고침에서만 이 API를 호출한다. 방 내부의 연결 신호 교환은 별개다.

방 생성에는 `title`(1~15자), `max_players`(2~4), 선택적 `password`(최대 64자)를 전달한다. 비밀번호는 방별 salt와 PBKDF2-SHA256 100,000회로 해시해 `webrtc_room_settings`에 저장한다. 코드 직접 참가도 같은 `/join` 인증을 거친다. 참가자는 `/leave`로 자리를 반환하며 비정상 종료한 참가자의 자리는 120초 후 만료된다. 선택한 정원까지 AI를 채우고 게임을 시작한다.

웹 빌드는 ENet 대신 WebRTC를 사용한다. `/webrtc/rooms`에서 방을 등록하고, 6자리 코드로 참가자 번호를 배정한다. `/webrtc/rooms/:code/signals`는 인증된 참가자 간 SDP와 ICE 후보만 전달하며 게임 데이터는 브라우저끼리 직접 전송한다. 게임 시작 시 방장은 `POST /webrtc/rooms/:code/start`로 방을 잠근다. 진행 중인 방은 목록에서 숨기고 새 참가를 거부하지만, 기존 참가자의 신호 교환과 만료 갱신은 유지한다.

연결 단절 시 게임을 최대 30초 동안 정지하고 기존 참가자의 비공개 복구 토큰으로 같은 자리에 자동 재접속한다. 복귀하지 않은 참가자는 AI로 전환하며 복구 토큰을 폐기한다. 방장을 복구할 수 없으면 마지막 확인 기록과 로비 복귀 안내를 표시한다. 방장 교체, 브라우저 새로고침/종료 후 복원은 지원하지 않는다. 클라이언트 배포 전에 이 Worker의 `/start` 변경도 배포해야 한다. 신규 `webrtc_started_rooms` 테이블은 첫 요청에서 자동 생성한다.

재접속 검사는 `scripts/tests/NetworkRecoveryTest.gd`를 `--role=host`, `--role=client`, `--role=intruder`로 각각 실행한다. `loss_host`, `loss_client` 조합은 방장 종료를 검사한다. `NetworkRecoveryRulesTest.gd`는 일시정지, AI 인계, 결과 복원과 실제 로비 복귀 동작을 검사한다. 이 검사들과 Worker의 Node 테스트는 배포 CI에도 포함된다.

실제 브라우저 검사는 `scenes/tests/NetworkRecoveryWebHarness.tscn`을 임시 시작 씬으로 지정해 `.godot/recovery-web/index.html`로 Web 디버그 내보내기를 한 뒤, 시작 씬을 `scenes/Main.tscn`으로 되돌리고 `node scripts/tests/run_network_web_test.cjs`를 실행한다(명령은 저장소 루트 기준). Node 22 이상과 Playwright/Chromium이 필요하다. 선택적으로 `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`를 지정할 수 있다. 이 검사는 로컬 SQLite 방 서비스와 브라우저 2개만 사용하며, 공개 게임방 서비스에는 접속하지 않는다.

WebRTC 테이블은 `schema.sql`에 포함되어 있으며 Worker가 첫 WebRTC 요청에서 `IF NOT EXISTS`로 준비한다. 현재 STUN만 설정되어 있어 직접 P2P 통신을 차단하는 학교·회사 네트워크에서는 연결이 실패할 수 있다. 이러한 환경까지 지원하려면 TURN 중계 서버가 필요하다. 데스크톱 ENet 방과 웹 WebRTC 방 사이의 교차 접속은 지원하지 않는다.

## 다른 계정으로 다시 배포할 때

1. [Cloudflare 대시보드](https://dash.cloudflare.com/)에서 무료 계정을 만든다.
2. 이 폴더에서 `npx wrangler login`을 실행한다.
3. `npx wrangler d1 create energygame-room-directory`를 실행한다.
4. 출력된 `database_id`로 `wrangler.toml`의 기존 `database_id` 값을 교체한다.
5. `npx wrangler d1 execute energygame-room-directory --remote --file=schema.sql`을 실행한다.
6. `npm run test` 후 `npm run deploy`를 실행한다.
7. 배포 결과 URL(예: `https://energygame-room-directory.<계정>.workers.dev`)을 Godot `project.godot`의 `network/room_directory_url`에 입력한다. 개발 중에는 환경 변수 `ENERGYGAME_ROOM_DIRECTORY_URL`로 덮어쓸 수도 있다.

## 연결 범위

방 코드 서버가 켜져 있고 방장 공유기가 UPnP 포트 매핑을 허용하면 서로 다른 Wi-Fi나 통신사에서도 6자리 코드로 접속할 수 있다. UPnP가 꺼져 있거나 통신사가 CGNAT을 사용하면 직접 연결은 실패할 수 있으며, 이때 같은 네트워크 자동 검색은 계속 작동한다. CGNAT까지 지원하려면 추후 게임 패킷 릴레이 서버가 필요하다.
