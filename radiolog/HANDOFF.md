# HANDOFF

## Current State

- 편집/조회의 SOT는 `localStorage`다. 핵심 키는 `radiolog:selectedDate`, `radiolog:journal:<YYYY-MM-DD>`, `radiolog:author:<YYYY-MM-DD>`다.
- `server.ps1`는 얇게 유지한다. 현재 구조는 `Use-Static $app "/" "./"`에 `GET /health`, `GET /view`만 명시 라우트로 얹은 형태다.
- `utils.js`는 공용 전역 유틸 모듈이며 `index.html`, `view.html`에서 항상 `script.js`, `view.js`보다 먼저 로드돼야 한다.
- 현재 템플릿/조회 기준 총 행 수는 `71`이다. 과거 로그의 `34`, `69`, `74` 기준 메모는 모두 폐기 대상으로 본다.
- `/view`와 인쇄 레이아웃은 함께 유지해야 한다. A4 세로 기준, `시간`/`구분` 64px 고정폭, 인쇄 시 제목 -> 서명란 -> 메타 순서를 현재 계약으로 본다.

## Open Notes

- 인쇄 레이아웃 변경 시 `radiolog/SPEC.md`, `view.html`, `view.css`, `view.js`를 같이 확인한다. 한 파일만 수정하면 쉽게 어긋난다.
