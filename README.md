# 🌿 그린 킹덤 리빌드 (Green Kingdom Rebuild)
### 에너지 사다리: 에코 히어로즈 (Eco Heroes: Energy Ladder)

> **퀴즈와 협동 건설로 재생에너지 왕국을 복원하는 4인 과학 교육 보드게임**  
> Godot 4 기반으로 제작된 인터랙티브 교육용 턴제 보드게임 프로젝트입니다.

---

## 🎮 게임 개요

화석 연료 남용과 에너지 낭비로 인해 황폐화된 왕국에 기후 위기가 찾아왔습니다!  
플레이어들은 '에코 히어로즈'가 되어 보드판을 탐험하며 과학·환경 퀴즈를 풀고, 신재생에너지 발전소를 건설하여 탄소 괴수 보스를 물리치고 왕국을 초록빛으로 되살려야 합니다.

- **장르**: 교육용 보드게임 / 전략 시뮬레이션 / 퀴즈 배틀
- **지원 인원**: 1~4인 플레이 (로컬 및 멀티플레이어 아키텍처)
- **개발 엔진**: **Godot Engine 4.x** (GDScript, GL Compatibility / Forward+)

---

## ✨ 주요 기능 및 시스템

1. **🎲 인터랙티브 보드판 & 주사위 이동**
   - 주사위를 굴려 맵의 다양한 타일(퀴즈 타일, 건설 타일, 이벤트 타일, 보스 타일)로 이동합니다.
   - 3D/2.5D 타일 마커 및 역동적인 폰(Pawn) 이동 애니메이션.

2. **💡 과학 & 신재생에너지 퀴즈 시스템 (`QuizDatabase.gd`)**
   - 태양광, 풍력, 수력, 지열, 바이오매스, 에너지 절약 등 다양한 카테고리의 4지선다형 교육 퀴즈 수록.
   - 정답 시 에너지 자원 및 스킬 게이지 획득.

3. **🏗️ 신재생에너지 발전소 건설 시스템**
   - 카드 드래그 & 드롭을 통한 직관적인 발전소 건설 UI (`ConstructionDragCard.gd`).
   - 태양광 패널, 풍력 발전기, 수력 댐, 바이오매스 시설을 배치하여 마을의 친환경 에너지를 증대시킵니다.

4. **⚡ 캐릭터 고유 특수 스킬 & 시네마틱 컷씬**
   - 4종의 개성 넘치는 에코 히어로즈 캐릭터.
   - 화려한 3D 이펙트와 전용 시네마틱 연출 (`SpecialSkillCinematic.gd`, `SpecialSkillEffect3D.gd`).

5. **👾 탄소 괴수 보스 레이드 (`BossRaidController.gd`)**
   - 왕국을 위협하는 탄소 괴수를 정화하기 위한 보스 배틀 모달 및 합동 공격 시스템.

6. **🎵 실시간 사운드 및 이펙트 (`AudioManager.gd`)**
   - 생생한 주사위 굴림음, 정답/오답 효과음, 건설 완료 사운드 및 배경음악 탑재.

---

## 🕹️ 실행 방법

### 방법 1. 웹 브라우저에서 바로 플레이 (GitHub Pages)
- **웹 플레이 링크**: [https://inkun00.github.io/energygame/](https://inkun00.github.io/energygame/)
- 별도의 설치 없이 크롬/엣지 등 모던 웹 브라우저에서 바로 실행할 수 있습니다.

### 방법 2. 윈도우 원클릭 로컬 실행
1. 저장소를 클론합니다:
   ```bash
   git clone https://github.com/inkun00/energygame.git
   cd energygame
   ```
2. 프로젝트 루트의 `run_game.bat` 파일을 더블 클릭하여 실행합니다.

### 방법 3. Godot 에디터에서 실행
1. [Godot Engine 공식 웹사이트](https://godotengine.org/)에서 **Godot 4.x**를 다운로드합니다.
2. Godot 에디터를 실행한 후 `가져오기(Import)` 버튼을 누르고 본 프로젝트의 `project.godot` 파일을 선택합니다.
3. `F5` 키를 누르거나 상단의 재생 버튼을 클릭하여 게임을 시작합니다.

---

## 📁 프로젝트 폴더 구조

```text
energygame/
├── .github/workflows/      # GitHub Actions CI/CD (GitHub Pages 자동 배포)
├── assets/                 # 이미지, 사운드, 3D 모델, UI 에셋
│   ├── images/             # 카드 마스코트, UI 텍스처 등
│   ├── open_source/        # 오픈소스 라이선스 리소스
│   └── story/              # 오프닝 및 엔딩 스토리보드 컷씬
├── scenes/                 # 메인 화면, 게임 보드, 퀴즈, HUD, 보스 모달 씬
│   ├── Main.tscn
│   ├── GameBoard.tscn
│   ├── HUD.tscn
│   ├── LobbyUI.tscn
│   ├── QuizModal.tscn
│   └── BossModal.tscn
├── scripts/                # GDScript 게임 로직 스크립트
│   ├── battle/             # 보스 레이드 및 전투 로직
│   ├── board/              # 보드판 그리드, 타일, 3D 마을 관리
│   ├── core/               # 게임 매니저, 오디오, 메인 제어
│   ├── effects/            # 시네마틱 컷씬 및 3D 스킬 이펙트
│   ├── network/            # 멀티플레이어 및 전용 서버 관리
│   ├── player/             # 플레이어 폰 이동 및 스탯
│   ├── quiz/               # 퀴즈 데이터베이스 및 문항 로직
│   └── ui/                 # 로비, HUD, 드래그 카드, 퀴즈 UI 컨트롤러
├── export_presets.cfg      # Godot Web(HTML5) 내보내기 설정
├── project.godot           # Godot 엔진 프로젝트 메인 설정 파일
├── run_game.bat            # 윈도우 원클릭 실행 스크립트
└── README.md
```

---

## 📜 라이선스 및 크레딧

- 본 프로젝트의 3D 모델 및 UI 리소스 중 일부는 [Kenney.nl](https://kenney.nl) 오픈소스 에셋(CC0)을 활용하였습니다 (`third_party/Kenney-Starter-Kit-City-Builder/NOTICE.md` 참조).
- 저작권 (c) 2026 inkun00. All rights reserved.
