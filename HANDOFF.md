# HANDOFF

## 2026-03-19

### 작업 요약
- `ping/server.ps1`를 신규 작성해 `http://+:9000/`에서 정적 파일과 `GET /pings` JSON 응답을 함께 서빙하도록 구성함.
- `ping/server.ps1`는 `ping/hosts.json`을 읽고, 서버 시작 직후 1회 측정 후 10초마다 각 host에 ping을 보내 최신 상태를 메모리에 유지하도록 구성함.
- `GET /pings` 응답 필드를 `destination`, `status`, `rtt`, `succeededAt`로 고정하고, 실패 시 마지막 성공 시각을 유지하도록 정리함.
- `ping/script.js`를 수정해 `dest`/`successedAt` 대신 `destination`/`succeededAt`를 읽도록 맞춤.
- 이후 `ping/server.ps1`는 `acs/server.ps1`, `wchat/server.ps1`의 함수/변수 컨벤션에 맞춰 `Import-*`, `Invoke-*Route`, `Send-*Response`, `$lock`, `$ps`, `$path` 스타일로 재정리함.
- 이후 worker 로직을 `ping/ping-worker.psm1`로 분리하고, `server.ps1`는 `Import-Module`, `InitialSessionState.ImportPSModule`, `AddCommand("Invoke-PingWorkerLoop")` 구조로 정리해 `AddScript` 의존을 제거함.
- 이후 제어 흐름 스타일도 정리해 깊은 중첩 대신 guard/one-line `if`와 짧은 `try/catch/finally`를 우선 사용하는 형태로 평탄화함.

### 검증 메모
- `pwsh -NoLogo -NoProfile -File /workspaces/mil/ping/server.ps1` 실행 후 `http://127.0.0.1:9000/` HTML 응답 확인.
- `curl -sS http://127.0.0.1:9000/script.js` 응답 확인.
- `curl -sS http://127.0.0.1:9000/pings` 응답 확인.
- 현재 세션에서는 외부 ICMP 응답을 확인하지 못했고, 현재 `hosts.json` 기준 `/pings`는 `timeout`/`error`만 반환함. 실제 성공 케이스의 `succeededAt` 유지 여부는 응답 가능한 host로 재확인 필요.

## 2026-03-18

### 작업 요약
- `wchat/server.ps1`를 수정해 `http://+:8080/`에서 `index.html`을 직접 서빙하고, 같은 서버에서 `/ws` WebSocket 업그레이드를 처리하게 함.
- `wchat/index.html`를 수정해 하드코딩된 `ws://localhost:8080/ws/` 대신 현재 페이지의 `location.protocol`과 `location.host`를 기준으로 `ws://` 또는 `wss://`를 계산하도록 변경함.
- `wchat/server.ps1`의 WebSocket 수신 처리를 `Task.Run`에서 클라이언트별 전용 runspace 실행 구조로 변경함.
- `wchat/wchat-worker.psm1`를 추가해 runspace worker 코드를 별도 모듈로 분리하고, `ScriptBlock.ToString()` 없이 `ImportPSModule + AddCommand`로 로드하게 함.
- handler 정리는 `BeginInvoke`/`EndInvoke`/`Dispose`를 명시적으로 감싸는 방식으로 정리함.

### 검증 메모
- `curl http://127.0.0.1:8080/`로 HTML 서빙 확인.
- `curl http://127.0.0.1:8080/ws`로 일반 HTTP 요청 시 400 응답 확인.
- 로컬 WebSocket 클라이언트로 `hello` 전송 후 동일 메시지 수신까지 재확인 필요.

## 2026-03-11

### 작업 요약
- `acs`가 `list.json`을 FE 조회에도 사용하도록 확장함.
- `acs` 현황판의 기본 진입 뷰를 `로그 보기`로 변경함.
- `GET /members`를 추가하고, 현황판에서 이름 컬럼/이름 검색/카드 이름 표시를 지원하게 함.
- `POST /access` 성공 응답에 `name`을 추가하고, 스캐너 성공 메시지가 이름 기준으로 표시되게 조정함.
- 스캐너 화면에 임시로 붙였던 별도 군번/이름 확인 패널은 제거함.
- HTML/CSS 셀렉터는 `loc-*`, `msg-*`, `bd-*`, `log-*` 축약형으로 정리함.
- 현황판 기본 진입 뷰는 `로그 보기`다.

### 다음 세션 인계 포인트
- `acs/list.json`은 허용 군번 검증과 이름 표시용 공용 소스다.
- `acs/board.html` 로그 표는 이름 컬럼을 포함하고 이름 검색을 지원한다.
- 스캐너 성공 메시지는 서버 응답의 `name`을 사용한다.
- 변경 확인 시 `acs/server.ps1` 재시작이 필요하다.
- `acs/board.html`은 처음 열면 로그 테이블이 먼저 보인다.
- 상태 카드는 동일 페이지 안에서 `현황 보기` 전환 버튼으로 계속 접근한다.

## 2026-03-09

### 작업 요약
- 루트 `AUDIT.md`를 신규 작성함.
- 최소 구현, 최소 검증, 유틸리티 분리 기준을 짧은 규칙 문서로 정리함.
- 루트 `AGENTS.md`에서 `AUDIT.md`를 참조하도록 연결함.

### 다음 세션 인계 포인트
- 루트 `AUDIT.md`는 저장소 전반에서 공통으로 따를 감사 기준 문서다.
- 각 작업 디렉토리의 `SPEC.md`와 함께 루트 `AUDIT.md`를 먼저 확인하는 흐름으로 사용하면 된다.
