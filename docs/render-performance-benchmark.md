# 보드 렌더링 예산과 개발 벤치마크

## 적용 범위

이번 변경은 표시 계층만 최적화한다. 게임 규칙, 100칸, 점수, 온라인 타이머,
아케이드 물리와 조작, HUD 글자와 해상도를 바꾸지 않는다. 플레이어 기록을
저장하지 않으며 아래 숫자는 개발용 합성 장면의 집계값이다.

- 퀴즈·도감·시장·건설/결과·미니게임으로 가려진 보드 `SubViewport`는 마지막
  렌더 결과를 재사용한다. 화면을 닫으면 이벤트로 즉시 갱신을 재개한다.
- 첫 준비 화면과 숨겨진 보드도 같은 정책을 사용하되, 명시적인 시작 셰이더
  준비 단계는 계속 렌더한다. `SceneTree.paused`를 변경하지 않으며 이동 Tween,
  네트워크, 게임 시계, 별도 아케이드 viewport는 계속 독립적으로 동작한다.
  새 게임 초기화·세션 복구 뒤에는 스냅샷 한 프레임만 갱신해 이전 위치가
  남지 않게 하고, 준비 중 애니메이션과 반복 렌더 정지는 그대로 유지한다.
- 정적 타일 100개의 매 프레임 콜백을 제거한다. 특수기술로 선택 가능한 타일만
  기존 펄스 콜백을 실행한다.
- 배경 메시의 모양·재질·개별 가시성은 원래대로 유지한다. 시험한 정적 메시
  결합은 실제 프레임 시간 개선이 입증되지 않아 최종 코드에서 제거했다.

## 측정 조건과 한계

2026-11-04, Windows 개발 PC, NVIDIA GeForce RTX 4060, Godot 4.7.2,
Compatibility OpenGL, 1280×720에서 측정했다. native는 VSync와 FPS 제한을
해제한 개발용 처리량 측정이다. 실제 노트북·통합 GPU·학교 현장 결과가 아니다.
각 장면은 0.5초 대기 뒤 2.5초를 집계했다. 점수와 AI 시뮬레이션을 정지한
고정 장면이며, 미니게임 행은 grid 시각 장면과 뒤쪽 보드의 중복 렌더 비용을
비교한다. 9개 게임의 실제 플레이 성능을 대표하지 않는다.

원본 `048a01c` 측정 후 같은 빌드에서 `--legacy-board-policy`로 원래의
항상-렌더/100-콜백 정책을 재현하여 A/B 비교했다. 아래 최종 수치는 채택된
모달 렌더 정지·콜백 변경만 적용한 `clean-optimized` 로그다.
짧은 표본과 GPU 클럭/드라이버 상태 변동이 있어 active 보드의 FPS 향상을
보장하지 않는다. 특히 전체 보드의 p95/FPS는 이전보다 나쁘게 관측됐으므로
이를 active 보드 속도 개선의 증거로 해석하지 않는다.

| 장면 | 이전 정책 FPS / p95 ms | 최종 FPS / p95 ms | 전체 드로콜 이전 → 최종 |
| --- | ---: | ---: | ---: |
| 근접 보드 idle | 540.6 / 2.16 | 537.5 / 2.13 | 507.0 → 499.0 |
| 100칸 전체 보기 idle | 248.2 / 4.89 | 231.6 / 6.36 | 1846.0 → 1845.9 |
| 퀴즈가 덮은 보드 | 242.5 / 4.84 | 1109.4 / 1.06 | 1876.2 → 153.2 |
| 건설 도감이 덮은 보드 | 230.2 / 5.10 | 855.8 / 1.24 | 2015.0 → 292.0 |
| grid 시각 장면 + 뒤쪽 보드 | 241.6 / 4.97 | 1087.5 / 1.09 | 1855.0 → 132.0 |
| 로비, 보드 숨김 | 856.0 / 1.31 | 881.3 / 1.26 | 135.0 → 135.0 |

최종 전체 보드 자체의 드로콜은 **1723**, 보드 하위 노드는 **2517**로 유지한다.
가려진 장면에서는 전체 드로콜이 85.5~92.9% 줄었다. 별도 아케이드가 표시될
때 활성 viewport는 2개에서 1개가 되며, 아케이드 자체는 중지하지 않는다.

### 미채택 실험: 정적 메시 결합

정적 메시 200개를 69개로 결합하면 전체 보드 드로콜은 1723→1592, 보드
하위 노드는 2517→2386으로 줄었다. 정지 프레임의 102,480개 픽셀 표본 중
RGB 채널 차이가 4%를 넘은 표본은 2개로 외관도 거의 같았다. 그러나 결합
전/후 전체 보드 p95는 6.36→6.55ms(+3.0%), FPS는 231.6→225.5(-2.63%)였다.
근접 p95는 2.13→2.29ms(+7.5%), primitives는 15140→15830(+4.56%)였다.
멀리 떨어진 수로·길·다리를 하나의 큰 경계 상자로 묶어 개별 frustum culling을
잃었을 가능성이 있으나, 확정 원인으로 단정하지 않는다. 프레임 시간 이득이
입증되지 않은 복잡성을 배포하지 않기 위해 기능·호출·전용 검사를 제거했다.
이 수치는 최종 적용 결과가 아니라 미채택 실험 기록이다.

첫 원본 전체 보기 표본은 p50 3.77ms / p95 4.27ms와 달리 평균 9.5 FPS라는
단발성 긴 지연을 포함했다. 초기 렌더/스케줄링 영향 가능성이 있지만 원인을
특정하지 않았으며, 이를 정상 상태 FPS나 확정적인 셰이더 문제로 보고하지 않는다.

Chromium SwiftShader WebGL로도 두 차례 시도했다. 첫 집계 이전 초기화가
장시간 지연되어 세션을 종료했고, 신뢰할 WebGL 프레임 수치를 얻지 못했다.
따라서 위 native 숫자를 웹 성능이나 저사양 실기로 바꿔 표현하지 않는다.

## 재현

에셋 import 후 실제 렌더러에서 실행한다. headless는 GPU 증거로 사용할 수
없으므로 벤치마크가 종료 코드 2로 거절한다. `RenderQualityTest`는 headless CI용이다.

```powershell
godot --headless --path . --import
godot --path . --rendering-method gl_compatibility --resolution 1280x720 --script scripts/tests/RenderPerformanceBenchmark.gd -- --label=optimized
godot --path . --rendering-method gl_compatibility --resolution 1280x720 --script scripts/tests/RenderPerformanceBenchmark.gd -- --label=legacy-policy --legacy-board-policy
godot --headless --path . --script scripts/tests/RenderQualityTest.gd
```

벤치마크는 `[RENDER_BENCH]` JSON과 종료 표지만 출력하고 파일을 쓰지 않는다.
필요한 로그는 개발자가 `.godot/` 아래로 리다이렉트한다. 배포 UI에서는 실행하지 않는다.
`get_render_info()`는 중지한 viewport의 마지막 카운터를 유지하므로, 중지 후
그 숫자가 0이라고 해석하면 안 된다. 비교에는 전체 프레임 카운터와 실제
활성 viewport 수를 사용한다. 일부 `Performance` 값은 갱신이 늦거나 release
빌드에서 0이므로 `engine_process_mean_ms`만으로 성능 향상을 주장하지 않는다.

API 근거: [Godot Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html),
[SubViewport update modes](https://docs.godotengine.org/en/stable/classes/class_subviewport.html),
[Viewport rendering counters](https://docs.godotengine.org/en/stable/classes/class_viewport.html).

## 남은 검증

실제 저사양 노트북에서 active 보드/9종 플레이의 프레임 시간과 입력 반응을
측정해야 한다. 더 큰 재질 통합이나 자동 해상도 축소는 이 결과만으로 추가하지
않았다. 전자는 개별 타일/컷어웨이 상태를 훼손할 수 있고 후자는 글자 선명도를
낮출 수 있기 때문이다. 현재 회귀는 준비→튜토리얼, 모달 닫기→보드 복귀,
기존 이동/온라인 점수 동기화의 기능적 무결성을 함께 확인하도록 구성했다.
