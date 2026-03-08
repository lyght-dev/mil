# HANDOFF

## 2026-03-08

### 작업 요약
- `eX-chat/SPEC.md` 신규 작성.
- `eX-chat`을 내부망용 임시 단일 채팅방 프로그램으로 정의하고, 서버 최소 책임 원칙을 명시함.
- `index.html`, `script.js`, `style.css`를 별도 파일로 두는 구조를 스펙과 구현에 반영함.
- 사용자 식별 규칙을 요청 IPv4 마지막 두 옥텟 `C.D` 사용으로 고정함.
- 빈 문자열 차단, timestamp 표시, 메시지 렌더링은 클라이언트 JS 책임으로 명시하고 구현함.
- `server.ps1` 신규 작성: `HttpListener` 기반 정적 파일 서빙 + `/ws` WebSocket 브로드캐스트 서버 구현.
- 서버는 메시지를 저장하지 않고, 접속/종료 시스템 메시지와 일반 채팅 메시지를 JSON 텍스트 프레임으로 브로드캐스트함.
- 후속 리뷰 반영으로 `server.ps1`와 `script.js`를 최소 구현 방향으로 단순화함.
- 브로드캐스트 경로 중복 제거, `SemaphoreSlim` 제거, JS 자동 재연결 제거, JSON parse fallback 제거를 반영함.
- 추가 정리: `server.ps1`의 handler runspace 실행부에서 문자열 스크립트 `$script` 사용을 제거하고, top-level 함수 `Invoke-ClientHandler`를 runspace pool에 등록해 `AddCommand(...)`로 호출하도록 변경함.

### 산출물
- `eX-chat/SPEC.md`
  - 임시성/내부망/단일방/무저장 정책 정의
  - 서버 책임과 클라이언트 책임 분리
  - WebSocket 메시지 형식과 최소 검증 시나리오 포함
- `eX-chat/server.ps1`
  - `/`, `/index.html`, `/script.js`, `/style.css` 정적 파일 서빙
  - `/ws` WebSocket 연결 수락
  - 접속 IP 기반 `C.D` 표기 생성
  - 전체 접속자 브로드캐스트
  - 접속/종료 시스템 메시지 전송
  - 후속 정리: 브로드캐스트 함수를 단일 경로로 유지하고 과한 동시성 제어 제거
  - 후속 정리: handler 코드를 top-level 함수로 승격하고 runspace `InitialSessionState`에 함수 등록
- `eX-chat/index.html`
  - 단일 채팅 화면 구성
- `eX-chat/script.js`
  - WebSocket 연결
  - 빈 문자열 전송 방지
  - 클라이언트 기준 timestamp 표시
  - 시스템/일반 메시지 렌더링
  - 서버 메시지를 JSON 고정 프로토콜로만 처리
- `eX-chat/style.css`
  - 간단한 패널형 채팅 UI 스타일

### 다음 세션 인계 포인트
- 현재 서버는 `HttpListener` 기반이며 기본 바인드는 `http://+:8888/`.
- IP 표기는 IPv4 주소 문자열에서 마지막 두 옥텟 `C.D`만 잘라 쓰는 단순 구현이다.
- timestamp는 서버가 아니라 브라우저 수신 시점 기준으로 표시됨.
- WebSocket 브로드캐스트는 단일 방 전제의 간단한 runspace 기반 구현이다.
- 실제 Windows PowerShell 환경에서 `HttpListener`의 `+` 바인딩 권한 또는 URL ACL 이슈가 있을 수 있으므로, 필요 시 `BindAddress`를 `localhost` 또는 특정 IP로 바꿔 검증하면 된다.

### 추가 검토 메모
- `2026-03-08` 추가 리뷰에서 지적된 과한 일반화 요소는 정리 완료.
- 현재 구현은 정적 파일 서빙, 단일 JSON 브로드캐스트 경로, 기본 연결 종료 처리 정도만 남긴 최소 형태다.
- 문자열 기반 handler 스크립트는 제거됐고, 편집기 자동완성이 가능한 top-level 함수 구조로 정리됐다.
