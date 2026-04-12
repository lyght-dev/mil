# HANDOFF

## Current State

- 스캐너 입력은 `EN`/`EX` 접두어 뒤 값을 `serial`로 해석해 `/access`에 보낸다. 서버는 `list.json`의 `serial`로 멤버를 찾고, 로그와 응답은 계속 `id`를 사용한다.
- 현황판(`board.html`) 갱신은 polling이 아니라 `GET /event` SSE 기반이다. `access` 이벤트 수신 시 `list.json`, `location.json`, `logs/access-log.csv`를 다시 읽어 재렌더한다.
- 현황판은 진입 시 Notification 권한이 `default`면 요청하고, 권한이 `granted`일 때만 `입영`/`퇴영` 시스템 알림을 띄운다.
- 설정 페이지 CRUD/reissue 후에는 `allowedMembers`를 강제 재조회한다. `list.json`이 설정 화면의 SOT다.
- `acs/script.js`의 문자열 기본값 처리는 `toText(value, fallback)` 경로로 통일돼 있다. 같은 종류의 정규화는 이 유틸을 우선 사용한다.
- `serialLastReissuedAtKst`는 `list.json`에 저장되고 설정 화면에서는 상대 일수 텍스트로 표시된다.
- `acs/app.ps1`는 `milkit/milkit.psm1` 기반 대체 엔트리포인트다. HTTP 계약은 `server.ps1`와 같고, 루트 텍스트 자원은 명시 라우트로 응답하고 `/public/*`만 `Use-Static`로 서빙한다.
- `acs/app.ps1`의 SSE는 `milkit` 응답 wrapper 위에서 `$res.Context.Response`를 직접 다뤄 유지한다. SSE 경로 수정 시 `$res.IsSent` 처리 여부를 함께 확인한다.
- `GET /logs/access-log.csv`는 `milkit` 기본 content-type 매핑에 `.csv`가 없어 `acs/app.ps1`에서 직접 `text/csv; charset=utf-8`로 응답한다.

## Open Notes

- `acs/style.css`와 `server.ps1`에는 `/public/PretendardJP-*.woff2` 경로가 연결돼 있지만 현재 워크스페이스에는 `acs/public/` 및 실제 폰트 파일이 없다.
