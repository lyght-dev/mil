# HANDOFF

## Current State

- 스캐너 입력은 `EN`/`EX` 접두어 뒤 값을 `serial`로 해석해 `/access`에 보낸다. 서버는 `public/list.json`의 `serial`로 멤버를 찾고, 로그와 응답은 계속 `id`를 사용한다.
- 현황판(`public/board.html`) 갱신은 polling이 아니라 `GET /event` SSE 기반이다. `access` 이벤트 수신 시 `public/list.json`, `public/location.json`, `logs/access-log.csv`를 다시 읽어 재렌더한다.
- 현황판은 진입 시 Notification 권한이 `default`면 요청하고, 권한이 `granted`일 때만 `입영`/`퇴영` 시스템 알림을 띄운다.
- 설정 페이지 CRUD/reissue 후에는 `allowedMembers`를 강제 재조회한다. `public/list.json`이 설정 화면의 SOT다.
- `acs/public/script.js`의 문자열 기본값 처리는 `toText(value, fallback)` 경로로 통일돼 있다. 같은 종류의 정규화는 이 유틸을 우선 사용한다.
- `serialLastReissuedAtKst`는 `public/list.json`에 저장되고 설정 화면에서는 상대 일수 텍스트로 표시된다.
- 정적 HTML/CSS/JS/JSON는 `acs/public/` 아래에 있다. 루트에는 서버 스크립트, `logs/`, 작업 문서만 남기고, 브라우저가 읽는 경로는 `/public/*`와 `/logs/*`로 나뉜다.
- 로그 원본 CSV는 `acs/logs/access-log.csv`에 있고, 브라우저는 `/logs/access-log.csv`로 읽는다.
- `acs/app.ps1`는 `milkit/milkit.psm1` 기반 대체 엔트리포인트다. `/`는 `public/index.html`을 직접 응답하고, 정적 자원은 `Use-Static '/public' './public'`와 `Use-Static '/logs' './logs'`로 서빙한다.
- `acs/app.ps1`는 로컬 모듈 `acs/milkit-utils.psm1`의 `Test-Blank`로 문자열 blank 체크를 감싼다. blank 유틸은 현재 ACS 로컬 범위이며 공용 `milkit` 모듈에는 넣지 않았다.
- `acs/app.ps1`의 SSE는 `milkit` 응답 wrapper 위에서 `$res.Context.Response`를 직접 다뤄 유지한다. SSE 경로 수정 시 `$res.IsSent` 처리 여부를 함께 확인한다.
- `milkit/milkit.psm1`는 `.csv`를 `text/csv; charset=utf-8`로 매핑한다. 그래서 `GET /logs/access-log.csv`는 별도 수동 라우트 없이 static으로 응답한다.
- `acs/app.ps1`의 `Read-JsonPayload`는 직접 `ConvertFrom-Json`하지 않고 `req.Json()`을 사용한다. JSON 파싱 캐시는 `milkit`에 맡기고, ACS 쪽에서는 malformed JSON과 빈 바디만 400으로 거부한다.

## Open Notes

- `/public/PretendardJP-*.woff2` 경로는 연결돼 있지만 현재 워크스페이스에는 실제 폰트 파일이 없다.
