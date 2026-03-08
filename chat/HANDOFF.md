# HANDOFF

## 2026-03-08

### 작업 요약
- `/chat` 신규 구현.
- `eX-chat`의 WebSocket 경로에서 드러난 Codespaces/Linux 호환성 문제를 피하기 위해 HTTP-only 채팅 방식으로 전환함.
- `/chat/SPEC.md` 신규 작성: long polling 기반 단일 채팅방, 최근 200개 메모리 보존, `lastId` 기준 조회 흐름을 명시함.
- `chat/server.ps1` 신규 작성: `HttpListener` 기반 정적 파일 서빙 + JSON API 구현.
- `chat/index.html`, `chat/script.js`, `chat/style.css` 신규 작성: HTTP polling 기반 채팅 UI 구현.
- 후속 수정: `Cleanup-RequestHandlers`가 시작 직후 빈 `ArrayList`를 받을 수 있도록 `AllowEmptyCollection`을 추가함.
- 후속 수정: `GET /messages`가 메시지 1건일 때도 항상 JSON 배열을 반환하도록 보정함.
- 후속 수정: 프론트 `pollLoop`도 단일 객체 응답을 배열로 정규화하도록 방어 코드를 추가함.
- 후속 수정: 순수 HTTP polling 구조에 맞춰 상단 연결 상태 배지를 제거하고, poll 재시도는 조용히 처리하며 초기화/전송 실패만 브라우저 알림으로 노출하도록 조정함.
- 후속 수정: `chat/script.js`의 함수들을 모두 top-level 선언으로 올리고, IIFE 없이 `handleSubmit`/`start`를 직접 연결하는 구조로 정리함.
- 후속 수정: 문서 타이틀과 헤더 타이틀을 `7136 Chat`으로 변경하고, 전체 UI를 엑셀 워크시트 느낌의 녹색/그리드 기반 스타일로 개편함.
- 후속 수정: 시각 톤이 과하지 않도록 장식 요소를 줄이고, 평평하고 깔끔한 엑셀형 미니멀 스타일로 다시 정리함.
- 후속 수정: 메시지 내부 헤더/본문 경계를 없애고, 각 채팅 항목 전체가 하나의 셀처럼 보이도록 메시지 패딩과 메타 영역 스타일을 단순화함.
- 후속 수정: 메시지 영역 `messages` 컨테이너 패딩을 `0`으로 조정해 셀들이 시트 영역 경계와 바로 맞닿도록 변경함.
- 후속 수정: `.msg`의 하단 마진을 제거해 메시지 셀들이 서로 붙어 보이도록 조정함.
- 후속 수정: 헤더의 `HTTP-only single room chat` 보조 문구를 제거하고 관련 `.sub` 스타일도 정리함.

### 산출물
- `chat/SPEC.md`
  - HTTP-only 단일 채팅방 스펙
  - `GET /messages/latest`, `GET /messages?after=...`, `POST /messages` 정의
  - 최근 200개 메모리 보존, 15초 long polling, 초기 히스토리 미표시 정책 포함
- `chat/server.ps1`
  - `http://+:8888/` 고정 바인드
  - 정적 파일 서빙
  - 최신 ID 조회 API
  - `after` 기준 long polling 메시지 조회 API
  - JSON POST 메시지 등록 API
  - 요청별 runspace 처리로 long polling 요청과 다른 요청을 동시에 처리
  - 빈 handler 목록으로도 시작 가능하도록 바인딩 보정
- `chat/index.html`
  - `7136 Chat` 타이틀 반영
  - 단일 채팅 UI
  - 헤더 보조 문구 제거
- `chat/script.js`
  - `GET /messages/latest`로 초기 기준점 설정
  - `GET /messages?after=...` long polling 반복
  - `POST /messages` 전송
  - 서버 `createdAt` 표시
  - polling 응답을 배열 기준으로 정규화
  - 연결 상태 배지 제거, 실패 시 최소 알림 처리
  - 모든 함수가 top-level에 선언되도록 구조 단순화
- `chat/style.css`
  - 엑셀 워크시트 톤의 채팅 UI
  - 연결 상태 배지 스타일 제거
  - 장식 요소를 줄인 미니멀 시트 스타일
  - 메시지 하나가 단일 셀처럼 보이도록 내부 분리선 제거
  - `messages` 컨테이너 패딩 제거
  - 메시지 셀 간 하단 간격 제거
  - 미사용 `.sub` 스타일 제거

### 다음 세션 인계 포인트
- 현재 구현은 WebSocket/SSE 없이 순수 HTTP만 사용한다.
- 초기 페이지 로드 시 과거 메시지는 가져오지 않고, `/messages/latest`를 기준으로 이후 새 메시지만 본다.
- 서버 메모리에는 최근 200개만 남는다.
- long polling 대기 시간은 15초, 내부 대기 루프는 250ms sleep polling 방식이다.
- 발신자 표시는 요청 IPv4 마지막 두 옥텟 `C.D`이며, 파싱 실패 시 `unknown`.
- 실제 Windows PowerShell 환경에서 `HttpListener`의 `+` 바인딩 권한 또는 URL ACL 이슈가 있을 수 있다.
- 현재 프론트는 상시 연결 상태를 별도 배지로 표시하지 않는다.
- 현재 `chat/script.js`는 IIFE 없이 top-level 함수 선언 + 하단 초기화 호출 패턴을 사용한다.
- 현재 화면 타이틀은 `7136 Chat`이며, 시각 톤은 엑셀형 그리드 레이아웃을 따른다.
- 현재 스타일 방향은 화려함보다 간결함과 가독성을 우선한다.
- 현재 메시지 UI는 메타/본문이 별도 박스로 나뉘지 않고, 항목 전체가 하나의 셀처럼 보이는 방향이다.
- 현재 `messages` 영역은 내부 패딩 없이 시트 경계부터 바로 메시지가 시작된다.
- 현재 메시지 셀들은 하단 마진 없이 연속해서 붙어 보인다.
- 현재 헤더는 `7136 Chat` 제목만 남긴 단순 형태다.

### 추가 검토 메모
- `2026-03-08` 추가 감사에서, `chat/server.ps1`는 `eX-chat`보다 유틸리티 분리가 더 자연스럽게 되어 있다고 판단함.
- 다만 `Try-ParseAfterId`는 현재 한 번만 호출되는 얇은 `TryParse` 래퍼라서 단독 함수 이득이 작고, 인라인 후보로 기록함.
- 반대로 `Handle-Request`는 정적 파일, latest, long polling, POST 처리가 한 함수에 몰려 있어 길이가 커졌다. 이후 수정이 이어지면 endpoint별 작은 함수 분리가 더 읽기 쉬운 방향일 수 있다.
- `InitialSessionState`에 함수들을 등록하는 이름 목록과 등록 루프는 한 번만 쓰이지만 길고 의도가 뚜렷하므로, 필요 시 등록 유틸리티로 빼는 편이 읽기 부담을 줄일 수 있다.
