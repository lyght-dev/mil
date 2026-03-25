# HANDOFF

## 2026-03-25

### 작업 요약
- `volleyball/`에 2인 온라인 배구 MVP를 신규 구현함.
- `volleyball/server.ps1`를 추가해 `http://+:8090/`에서 정적 파일과 `/ws` WebSocket을 함께 처리하도록 구성함.
- 서버는 단일 룸/최대 2명(`left`, `right`)만 허용하고, 3번째 접속은 `room_full` 이벤트 후 종료하도록 처리함.
- 서버 권한 모델로 물리 시뮬레이션(이동/점프/중력/벽/네트/플레이어 충돌/바닥 판정)을 30Hz 틱에서 계산하도록 구현함.
- 바닥 접촉 시 점수 없이 `round_reset` 이벤트를 보내고 즉시 라운드를 리셋하도록 구성함.
- `volleyball/volleyball-worker.psm1`를 추가해 클라이언트 입력 수신(runspace handler)과 연결 해제 정리를 분리함.
- `volleyball/index.html`, `volleyball/script.js`, `volleyball/style.css`를 추가해 캔버스 기반 기본 도형 렌더와 키보드 입력 전송을 구현함.
- `volleyball/SPEC.md`를 신설해 MVP 계약(단일 룸, 서버 권한, 무점수 랠리)을 문서화함.
- 추가 수정: `Client disconnected` 직후 간헐적으로 발생한 `Move-PlayerBody` 입력 타입 예외(`System.Object[] -> Hashtable`)를 수정함.
  - `Move-PlayerBody`의 입력 타입 강제를 제거하고 `Get-InputFlag`로 안전하게 불리언을 해석하도록 변경함.
  - 틱 루프에서 플레이어/입력 참조를 점(`.`) 표기 대신 키 인덱서(`["left"]["input"]`)로 고정해 배열 해석 가능성을 줄임.
- 추가 수정: 입력/전송 정책을 재조정해 트래픽/조작 문제를 함께 수정함.
  - `volleyball/script.js`에서 `setInterval(sendInput, 50)`를 제거하고 keydown/keyup으로 입력 상태가 실제 변경될 때만 전송하도록 변경함.
  - 마지막 전송 입력과 동일하면 전송을 스킵하는 dedupe를 추가함.
  - 키 매핑을 역할 분리 없이 `ArrowLeft/ArrowRight/ArrowUp` 단일 매핑으로 통일함.
  - `volleyball/server.ps1`에서 물리 틱(33ms)과 state 브로드캐스트 틱(66ms, 약 15Hz)을 분리함.
  - `event` 메시지(`round_reset`, `peer_left`, `room_full`)는 즉시 전송 유지함.
- 추가 수정: 변경점 스트림 우선 동작으로 조정함.
  - FE는 `state` 메시지에서 플레이어 좌표를 덮어쓰지 않고, 공/라운드/phase만 반영함.
  - FE는 로컬 입력(`inputState`) + 원격 입력 변경(`input_update`)으로 양쪽 플레이어를 고정 스텝(33ms) 로컬 시뮬레이션함.
  - 서버/worker는 입력 값이 실제 변경된 경우에만 `input_update`를 브로드캐스트함.
  - FE는 본인 role의 `input_update`는 무시하고 상대 role만 반영함.
  - `volleyball/SPEC.md`에 `input_update` 메시지 계약을 추가함.
- 추가 수정: `input` 1회 전송 후 disconnect 및 불필요한 `state` 스트림 문제를 정리함.
  - worker에서 `PendingInputEvents` 큐에 직접 적재하던 경로를 제거해 disconnect 유발 가능 지점을 제거함.
  - 서버가 틱마다 slot 입력 변화 여부를 비교해 변경된 경우에만 `input_update`를 즉시 브로드캐스트하도록 이동함.
  - 주기적 `state` 전송을 비활성화하고, 현재 모드는 `welcome` + `event` + `input_update` 중심으로 동작하도록 조정함.
  - FE는 `welcome` 수신 시 즉시 `playing`으로 전환하고, `peer_left` 시 `waiting`으로 전환하도록 상태 전환을 로컬 이벤트 기반으로 변경함.
  - 서버의 `Build-StatePayload`/`state` 브로드캐스트 경로는 제거해, `{"type":"state",...}` 메시지가 더 이상 주기적으로 흘러오지 않게 정리함.
  - FE는 호환을 위해 `state` 수신 분기 코드는 유지하되, 실제 운영 모드는 `input_update` 기반으로 동작함.

### 검증 메모
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/volleyball/server.ps1' -Raw)); 'PARSE_OK'"` 확인.
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/volleyball/volleyball-worker.psm1' -Raw)); 'PARSE_OK'"` 확인.
- 서버 실행 상태에서 `curl -sS -o /tmp/volley_index.html -w "%{http_code}" http://127.0.0.1:8090/` -> `200` 확인.
- 서버 실행 상태에서 `curl -sS -o /tmp/volley_script.js -w "%{http_code}" http://127.0.0.1:8090/script.js` -> `200` 확인.
- 서버 실행 상태에서 `curl -sS -o /tmp/volley_style.css -w "%{http_code}" http://127.0.0.1:8090/style.css` -> `200` 확인.
- 서버 실행 상태에서 `curl -sS -o /tmp/volley_ws.txt -w "%{http_code}" http://127.0.0.1:8090/ws` -> `400` 확인.
- 권한 상승 WebSocket 점검에서 서버 로그 기준 `Client connected: left/right`까지는 확인했으나, 샌드박스 환경의 소켓 제약/세션 특성으로 `room_full` 수신 페이로드 자동 캡처는 완료하지 못함. 브라우저 3탭으로 재확인 필요.
- 추가 검증: `volleyball/server.ps1` 파서 재검사 `PARSE_OK` 확인.
- 추가 검증: `node --check /workspaces/mil/volleyball/script.js` 통과.
- 추가 검증: `volleyball/server.ps1`, `volleyball/volleyball-worker.psm1` 파서 `PARSE_OK` 재확인.
- 추가 검증: `volleyball/SPEC.md`를 현재 전송 모드(주기적 state 없음) 기준으로 갱신.
- 운영 메모: 반영 확인 시 기존 서버 프로세스를 종료 후 재시작하고 브라우저 하드 리로드로 구버전 JS 캐시를 비운 뒤 확인 필요.

### 추가 작업 요약 (acs setting 1차)
- `acs/setting.html`, `acs/setting.css`, `acs/setting.js`를 추가해 설정 페이지 레이아웃/디자인을 신규 구성함.
- 설정 페이지는 사용자 추가/삭제 UI 골격만 제공하고, 버튼/검색 입력은 비활성 처리해 기능 연결을 보류함.
- `acs/board.html` 상단 액션에 `설정` 링크(`/setting.html`)를 추가함.
- `acs/server.ps1` 정적 라우팅에 `/setting.html`, `/setting.css`, `/setting.js`를 추가함.
- `acs/SPEC.md` 정적 리소스 목록을 확장하고, 설정 페이지는 1차에서 UI-only임을 명시함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/acs/server.ps1' -Raw)); 'PARSE_OK'"` -> `PARSE_OK`.
- 서버 실행 후 정적 서빙 확인:
  - `GET /board.html` -> `200`
  - `GET /setting.html` -> `200`
  - `GET /setting.css` -> `200`
  - `GET /setting.js` -> `200`
- `/tmp/acs_board.html`에서 `href="/setting.html"` 링크 렌더링 확인.

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
