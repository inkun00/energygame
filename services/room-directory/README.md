# 6자리 방 코드 연결 서버

설치형 게임은 같은 LAN의 방을 먼저 찾는다. 외부 접속용 Cloudflare Worker는 D1에 `방 코드 → 방장 공인 IPv4/UDP 포트`를 최대 90초 동안 보관한다. 실제 게임 데이터는 방장과 참가자가 ENet으로 직접 주고받는다. 방장이 대기하는 동안 20초마다 만료 시간이 갱신되며, 게임을 시작하거나 방을 닫으면 등록이 삭제된다.

현재 배포 주소: `https://energygame-room-directory.energygame-room-directory.workers.dev`

Godot의 `network/room_directory_url`에도 위 주소가 설정되어 있다.

## 브라우저 멀티플레이

웹 게임의 기본 연결 서버는 `network/web_room_directory_url`에 지정된 Vercel API다. 방 코드를 만들거나 입력하면 서버가 Firestore의 `energygameWebRooms/{code}`에서 좌석과 신호를 관리한다. 방장이 방을 닫으면 해당 문서가 삭제된다. 비정상 종료한 방은 만료 후에 참가할 수 없으며 새 방을 만들 때 만료 문서를 정리한다. 기본 서버에 코드가 없으면 기존 Worker에서 이전 웹 버전의 방을 확인한다.

직접 연결이 어려운 네트워크에 TURN을 제공하려면 해당 방을 서비스하는 서버에 Cloudflare Realtime의 `TURN_KEY_ID`, `TURN_KEY_API_TOKEN`을 설정한다. Vercel과 Worker의 환경 설정은 독립적이다. 등록한 참가자는 `ice_servers` 필드로 해당 자리의 2시간짜리 임시 인증 정보를 받는다. 중계 설정이 없거나 발급이 지연되면 기본 STUN 설정으로 직접 연결을 시도한다.

`GET /webrtc/rooms`는 만료되지 않은 대기실을 최대 100개 반환한다. 사용자가 '열린 방 목록 보기'나 '목록 새로고침'을 눌렀을 때만 이 API를 호출한다. 방 코드, 제목, 방장 닉네임, 정원, 현재 인원, 비밀번호 여부를 공개한다.

방 생성에는 `title`(1~15자), `max_players`(2~4), 선택적 `password`(최대 64자)를 전달한다. 비밀번호는 방별 salt와 PBKDF2-SHA256 100,000회로 해시해 저장한다. 코드 직접 참가도 같은 `/join` 인증을 거친다. 참가자는 `/leave`로 자리를 반환하며 비정상 종료한 참가자의 자리는 마지막 갱신 시각으로부터 120초 후 만료된다. 선택한 정원까지 AI를 채우고 게임을 시작한다.

웹 빌드는 ENet 대신 WebRTC를 사용한다. `/webrtc/rooms`에서 방을 등록하고, 6자리 코드로 참가자 번호를 배정한다. `/webrtc/rooms/:code/signals`는 인증된 참가자 간 SDP와 ICE 후보만 전달하며 게임 데이터는 브라우저끼리 직접 전송한다. 게임 시작 시 방장은 `POST /webrtc/rooms/:code/start`로 방을 잠근다. 진행 중인 방은 목록에서 숨기고 새 참가를 거부하지만, 기존 참가자의 신호 교환과 만료 갱신은 유지한다.

웹 클라이언트는 협상·재접속 중에 0.35초마다 신호를 확인한다. 방장은 대기실에서 2초마다 새 참가자를 확인하고, 연결이 안정된 게임에서는 조회 간격이 15초로 늘어난다. 서버는 30초가 지난 뒤의 첫 조회에서 좌석 만료 시간을 갱신한다. `expires_at`은 저장된 좌석의 만료 시각이다.

연결 단절 시 게임을 최대 30초 동안 정지하고 기존 참가자의 비공개 복구 토큰으로 같은 자리에 자동 재접속한다. 복귀하지 않은 참가자는 AI로 전환하며 복구 토큰을 폐기한다. 방장을 복구할 수 없으면 마지막 확인 기록과 로비 복귀 안내를 표시한다. 방장 교체, 브라우저 새로고침/종료 후 복원은 지원하지 않는다.

재접속 검사는 `scripts/tests/NetworkRecoveryTest.gd`를 `--role=host`, `--role=client`, `--role=intruder`로 각각 실행한다. `loss_host`, `loss_client` 조합은 방장 종료를 검사한다. `NetworkRecoveryRulesTest.gd`는 일시정지, AI 인계, 결과 복원과 실제 로비 복귀 동작을 검사한다. 이 검사들과 Worker의 Node 테스트는 배포 CI에도 포함된다.

실제 브라우저 검사는 `scenes/tests/NetworkRecoveryWebHarness.tscn`을 임시 시작 씬으로 지정해 `.godot/recovery-web/index.html`로 Web 디버그 내보내기를 한 뒤, 시작 씬을 `scenes/Main.tscn`으로 되돌리고 `node scripts/tests/run_network_web_test.cjs`를 실행한다(명령은 저장소 루트 기준). Node 22 이상과 Playwright/Chromium이 필요하다. 선택적으로 `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`를 지정할 수 있다. 이 검사는 로컬 SQLite 방 서비스와 브라우저 2개만 사용하며, 공개 게임방 서비스에는 접속하지 않는다.

4인 전체 화면 검사는 저장소 루트에서 `node scripts/tests/export_four_player_web.cjs` 다음 `node scripts/tests/run_four_player_web_test.cjs`로 실행한다. 별도 테스트 프로젝트를 사용하므로 실제 시작 씬을 바꾸지 않는다. 독립 브라우저 4개, 로컬 Worker/D1, 실제 WebRTC와 키보드 입력으로 9종 미니게임 및 준비·재접속·시장·건설·엔딩을 검사한다. 자세한 범위와 fixture는 [4인 검증 보고서](../../docs/four-player-online-verification.md)를 참고한다.

Firestore 코드 입장 검사는 로컬 Firestore 에뮬레이터를 시작한 뒤 `FIRESTORE_EMULATOR_HOST`를 해당 `127.0.0.1:포트`로 지정하고 `node scripts/tests/run_four_player_web_test.cjs --code-room-smoke`로 실행한다. 이 검사는 방 목록과 기존 Worker를 차단하고 방 코드를 입력한 네 브라우저가 게임을 시작하는지 확인한다.

WebRTC 테이블은 `schema.sql`에 포함되어 있으며 Worker가 첫 WebRTC 요청에서 `IF NOT EXISTS`로 준비한다. 데스크톱 ENet 방과 웹 WebRTC 방 사이의 교차 접속은 지원하지 않는다.

## 다른 계정으로 다시 배포할 때

1. [Cloudflare 대시보드](https://dash.cloudflare.com/)에서 무료 계정을 만든다.
2. 이 폴더에서 `npx wrangler login`을 실행한다.
3. `npx wrangler d1 create energygame-room-directory`를 실행한다.
4. 출력된 `database_id`로 `wrangler.toml`의 기존 `database_id` 값을 교체한다.
5. `npx wrangler d1 execute energygame-room-directory --remote --file=schema.sql`을 실행한다.
6. `npm run test` 후 `npm run deploy`를 실행한다.
7. 배포 결과 URL(예: `https://energygame-room-directory.<계정>.workers.dev`)을 Godot `project.godot`의 `network/room_directory_url`에 입력한다. 개발 중에는 환경 변수 `ENERGYGAME_ROOM_DIRECTORY_URL`로 덮어쓸 수도 있다.

## 미니게임 명예의 전당

공개 게임의 아홉 종목은 Firebase Cloud Firestore를 사용합니다. 종목별 개인 최고점은 `energygameLeaderboards/{game}/bests/{owner}`에, 시도와 발급 횟수는 `energygameScoreRuntime`에 보관합니다. 각 종목은 점수 내림차순으로 10명까지 보여 주고 동점에는 같은 순위를 줍니다. 10명 밖이어도 본인의 순위를 돌려주며, 실제 조작을 제출한 첫 0점도 기록합니다.

클라이언트는 기기에서 무작위 키를 만들고 서비스 주소별 인증값을 사용합니다. 서버에 남는 식별자는 해시입니다. 공개 별명은 그 해시로 생성하며 학생 이름과 방 코드를 받지 않습니다. 인증값을 잃거나 다른 브라우저 프로필을 사용하면 새 기록으로 시작합니다.

- `GET /scores/:game`은 상위 기록과 인증된 사용자의 최고점·순위를 반환합니다.
- `POST /scores/:game/attempts`는 실제 경기 시작에 기기 인증값과 무작위 `round_key`를 받아 15분짜리 시도를 발급합니다. 같은 요청을 재전송하면 기존 시도를 반환합니다.
- `POST /scores/:game/attempts/:id`는 해당 사용자와 종목, 서버 경과 시간, 게임별 점수 상한과 실제 조작·시도 통계를 확인합니다. 새 경기로 넘어간 미완료 시도는 닫힙니다. 같은 완주의 재전송은 최고점을 한 번만 반영합니다. 서버는 모든 입력을 재생하지 않으므로 기록은 검증 가능한 범위 안의 **클라이언트 보고 점수**입니다.
- 분당 발급 한도는 기기당 5회, 네트워크당 120회입니다. 제한에 쓰는 네트워크 값은 날짜별 해시이며 시도 내역은 다음 발급 요청에서 24시간이 지난 건부터 정리합니다.
- 인터넷이나 점수 경로가 없을 때는 기기 기록을 곧바로 표시합니다. 서버 시도를 받은 완주만 만료 전 재전송할 수 있습니다. 오프라인에서 시작한 점수는 기기에 보관합니다.

로컬 확인은 이 디렉터리에서 다음 두 명령을 실행합니다.

```sh
npx wrangler d1 execute energygame-room-directory --local --file=schema.sql
npx wrangler dev --local --ip 127.0.0.1 --port 8787
```

`http://127.0.0.1:8000`의 웹 게임은 같은 호스트의 8787번 포트를 사용합니다. 네이티브 개발판에서는 `ENERGYGAME_LEADERBOARD_URL=http://127.0.0.1:8787`로 지정할 수 있습니다.

GitHub Pages와 Vercel의 공개 게임은 `network/leaderboard_url`에 설정된 동일한 Vercel 순위 API를 사용합니다. API는 Worker와 점수 검사 규칙을 공유합니다. 공개 API가 경기 결과를 검증한 뒤 Firestore 트랜잭션으로 저장합니다.

Vercel 프로젝트 `energygame-minigames-demo`의 Root Directory는 `services/room-directory`입니다. 저장소 루트에서 `python tools/stage_vercel_site.py build/web build/production-site/services/room-directory`를 실행한 뒤, 상위 폴더인 `build/production-site`를 기존 Vercel 프로젝트에 연결해 배포합니다. 프로덕션 환경에 `FIREBASE_PROJECT_ID`, `GCP_SERVICE_ACCOUNT_EMAIL`, `GCP_WORKLOAD_IDENTITY_PROVIDER`를 설정합니다. 마지막 값은 `projects/{number}/locations/global/workloadIdentityPools/{pool}/providers/{provider}` 형태입니다. Google Cloud의 Workload Identity Federation은 해당 Vercel 프로젝트의 production 주체만 서비스 계정을 맡을 수 있게 구성합니다. 서비스 계정에는 게임 데이터베이스에 대한 Cloud Datastore User 권한이 필요합니다.

기존 순위를 옮길 때는 내보낸 비공개 SQLite 파일로 `node tools/migrate-scores.mjs --sqlite <파일> --project <프로젝트ID> --apply`를 실행합니다. 도구는 Google Application Default Credentials를 사용합니다. 공개 API 전환 후 이전 저장소의 마지막 스냅샷으로 재실행하고, `--apply`를 `--verify`로 바꿔 검증합니다. 이미 등록된 더 높은 점수와 나중에 시작한 시도는 보존합니다.

## 연결 범위

방 코드 서버가 켜져 있고 방장 공유기가 UPnP 포트 매핑을 허용하면 서로 다른 Wi-Fi나 통신사에서도 6자리 코드로 접속할 수 있다. UPnP가 꺼져 있거나 통신사가 CGNAT을 사용하면 직접 연결은 실패할 수 있으며, 이때 같은 네트워크 자동 검색은 계속 작동한다. CGNAT까지 지원하려면 추후 게임 패킷 릴레이 서버가 필요하다.
