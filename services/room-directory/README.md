# 6자리 방 코드 연결 서버

Cloudflare Worker와 D1에 `방 코드 → 방장 공인 IPv4/UDP 포트`를 최대 90초 동안만 보관한다. 실제 게임 데이터는 이 서버를 통과하지 않고 방장과 참가자가 ENet으로 직접 주고받는다. 방장이 대기하는 동안 20초마다 만료 시간이 갱신되며, 게임을 시작하거나 방을 닫으면 등록이 삭제된다.

현재 배포 주소: `https://energygame-room-directory.energygame-room-directory.workers.dev`

Godot의 `network/room_directory_url`에도 위 주소가 설정되어 있다.

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
