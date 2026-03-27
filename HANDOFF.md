# HANDOFF

## 2026-03-26

### 추가 작업 요약 (cave 게임 종료 대형 알림)
- `cave/index.html` 보드 영역에 승리 오버레이 요소(`winnerNotice`)를 추가함.
- `cave/style.css`에 `board-wrap`, `winner-notice` 스타일을 추가해 게임 종료 시 보드 중앙에 큰 승리 문구가 보이도록 구성함.
- `cave/script.js`에 `setWinnerNotice`를 추가하고 `updateUi`에서 호출해 `gameOver` 상태일 때만 `흑 승리!`/`백 승리!` 알림을 표시하도록 연결함.
- 라운드 시작/준비 대기 상태에서는 오버레이가 자동으로 숨겨지도록 처리함.
- `cave/SPEC.md` UI 규칙에 게임 종료 대형 알림 표시를 반영함.

### 추가 검증 메모
- `node --check /workspaces/mil/cave/script.js` 통과.

### 추가 작업 요약 (acs start 변수 script 상단화 + allowedMembers 강제 갱신)
- `acs/server.ps1`에서 `Start-AcsServer`에서 선언되던 주요 런타임 변수(`AppRoot`, `LogPath`, `AllowedIds`, `SerialToMember`, `Prefix`)를 script 상단 변수로 선언하고 시작 시 값 할당 후 사용하도록 정리함.
- 기존 path 흐름은 유지하고(`ListPath` 포함), 이미 있는 경로 변수 구조를 제거하지 않고 최소 수정으로 적용함.
- `acs/setting.js`에 `forceRefreshAllowedMembers()`를 추가하고 CRUD/reissue 공통 후처리에서 해당 함수를 호출해 `allowedMembers`를 강제로 재조회 + 즉시 테이블 렌더링하도록 변경함.

### 추가 검증 메모
- `pwsh` 파서 검사: `acs/server.ps1` -> `PARSE_OK`
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (acs ListPath 공용 변수화)
- `acs/server.ps1` 최상단에 `$script:ListPath`를 선언하고, 시작 시 1회 설정해 script 범위 공용 변수로 사용하도록 변경함.
- setting 함수들(`Import-Members`, `Save-Members`, `Invoke-SettingApiRoute`)에서 `ListPath` 인자 전달을 제거하고 내부에서 `$script:ListPath`를 직접 참조하게 정리함.
- 호출 체인(`Invoke-Request` -> `Invoke-ApiRoute` -> `Invoke-SettingApiRoute`)에서 `ListPath` 파라미터를 제거해 함수 시그니처를 단순화함.

### 추가 검증 메모
- `pwsh` 파서 검사: `acs/server.ps1` -> `PARSE_OK`
- `rg -n "ListPath|\\-ListPath" /workspaces/mil/acs/server.ps1` 확인: 인자 전달(`-ListPath`) 경로 제거 완료.

### 추가 작업 요약 (cave 차례 문구/배경색 조정)
- `cave/script.js`의 진행 상태 문구를 내 기준 표현으로 조정함.
- 현재 턴이 내 돌 색과 같으면 `내 차례`, 아니면 상대 색(`흑`/`백`) 차례로 표시하도록 `turnLabelForMe`를 추가함.
- `cave/style.css`에서 페이지 배경색을 회색(`#d9d9d9`)으로 지정함.
- `cave/SPEC.md` UI 규칙의 배경 정책을 현재 동작(회색 페이지 배경) 기준으로 갱신함.

### 추가 검증 메모
- `node --check /workspaces/mil/cave/script.js` 통과.

### 추가 작업 요약 (cave ready 게이트/메뉴 색/outline 보강)
- `cave/script.js`에 `roundActive` 게이트를 추가해 접속 직후 자동 시작을 막고, 양측(`black`, `white`) ready가 모두 true일 때만 시작하도록 변경함.
- 초기 시작과 승리 후 재시작 모두 동일하게 ready handshake를 요구하도록 통일함.
- 진행 중 플레이어 이탈(`peer leave`) 시 라운드를 비활성화하고 해당 색 ready를 해제해 단독 진행을 방지함.
- `cave/index.html`의 상단 메뉴에 역할 색 클래스 훅(`role-black`, `role-white`, `role-neutral`)을 추가함.
- `cave/style.css`에서 상단 메뉴 역할 색 스타일을 추가해 내 돌 색을 상단 메뉴 색으로 구분 가능하게 함.
- `cave/style.css`에서 `body`, 상단 패널, 로그 패널/로그 박스 배경 지정을 제거함(보드 배경은 유지).
- 보드 outline을 더 명확히 보이도록 border/box-shadow 강도를 상향함.
- `cave/SPEC.md`에 초기 시작도 ready handshake가 필요함을 반영하고 UI 규칙(메뉴 색, 배경 정책, outline 강화)을 갱신함.

### 추가 검증 메모
- `node --check /workspaces/mil/cave/script.js` 통과.

### 추가 작업 요약 (acs setting 서버 인라인 통합)
- 사용자 요청에 따라 `setting.psm1` 분리 방식을 제거하고 setting API 구현을 `acs/server.ps1` 내부로 인라인 통합함.
- `server.ps1`에 `###### setting begin ######` / `###### setting end ######` 경계 주석을 두고 setting 전용 로직 구역을 분리함.
- `Import-Members`, `Save-Members`, `Sync-MemberCaches`, `Invoke-SettingApiRoute` 등을 `server.ps1`로 이동해 모듈 import 의존을 없앰.
- `Read-JsonPayload` 공용 파서를 도입해 `/access`와 setting API가 같은 JSON 파싱 경로를 사용하도록 정리함.
- `acs/setting.psm1` 파일은 제거함.

### 추가 검증 메모
- `pwsh` 파서 검사: `acs/server.ps1` -> `PARSE_OK`
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (acs setting 서버/JS 실동작 연동)
- `acs/setting.psm1`를 신규 추가해 설정 CRUD/재발급 API 구현을 서버 본문에서 분리함.
  - `POST /setting/member/create`
  - `POST /setting/member/update`
  - `POST /setting/member/delete`
  - `POST /setting/member/reissue`
- `setting.psm1`에서 `list.json` 로드/저장, 6자리 serial 발급, `serialLastReissuedAtKst`(KST) 갱신, `AllowedIds`/`SerialToMember` 캐시 동기화를 처리함.
- `acs/server.ps1`는 설정 API를 직접 구현하지 않고 `Import-Module ./setting.psm1` + `Invoke-SettingApiRoute` 위임 구조로 변경함.
- `acs/server.ps1` 시작 시 `Sync-SettingMemberCaches`를 호출해 허용 ID/serial 캐시를 초기화하도록 변경함.
- `acs/setting.js`의 CRUD/reissue 스텁을 실제 API 호출로 교체함.
  - `create -> /setting/member/create`
  - `update -> /setting/member/update`
  - `delete -> /setting/member/delete`
  - `reissue -> /setting/member/reissue`
- `acs/setting.js` CRUD 성공 메시지를 `완료` 기준으로 정리함.
- `acs/SPEC.md`에 setting CRUD API 연동 반영(정적 리소스 섹션/제외 범위 문구 보정).

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.
- `pwsh` 파서 검사:
  - `acs/server.ps1` -> `PARSE_OK`
  - `acs/setting.psm1` -> `PARSE_OK`
- 샌드박스 권한으로 `http://+:8888/` 리스너 시작 시 `Permission denied`가 발생해 런타임 HTTP 호출 검증은 완료하지 못함.

### 추가 작업 요약 (acs setting serial 시각 UI 전환)
- `acs/setting.html`에서 serial 숫자 입력 필드와 `6자리 숫자 발급` 안내 문구를 제거함.
- serial 영역을 `마지막 재발급 시각` + `serial 재발급` 버튼의 단일 행으로 재구성해 같은 맥락 UI로 배치함.
- `acs/setting.js`는 `serial` 값 표시를 제거하고 `serialLastReissuedAtKst` 필드를 읽어 정보 패널에 표시하도록 변경함.
- `serialLastReissuedAtKst` 값이 없으면 `-`를 표시하도록 기본값 처리를 추가함.
- 재발급 버튼 핸들러는 기존과 동일하게 인터페이스만 유지(`pending` 스텁)하고 실동작은 연결하지 않음.
- `acs/setting.css`에 serial 메타 한 줄 레이아웃 스타일과 모바일 줄바꿈 스타일을 추가함.
- `acs/list.json` 샘플 데이터에 `serialLastReissuedAtKst`(KST 문자열) 필드를 추가함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (acs setting serial-line 레이아웃 깨짐 수정)
- `acs/setting.css`의 `.stg-serial-line`을 `flex`에서 `grid(minmax(0,1fr) auto)`로 변경해 텍스트/버튼이 같은 라인에서 안정적으로 배치되도록 조정함.
- `.stg-serial-meta`에 `flex-wrap`을 추가하고 재발급 시각 텍스트에 `overflow-wrap:anywhere`를 적용해 좁은 폭에서 aside 영역 밖으로 튀어나오던 문제를 완화함.
- 모바일 구간에서도 동일한 2열 grid를 유지하고 내부 텍스트만 줄바꿈되도록 정리함.

### 추가 작업 요약 (acs 마지막 재발급 시각 표시 포맷)
- `acs/setting.js`에 KST 시각 문자열(`YYYY-MM-DD HH:mm:ss KST`)을 상대 일수로 변환하는 `toDaysAgoText`를 추가함.
- 사용자 정보 패널의 `마지막 재발급 시각` 값은 원문 시각 대신 `N일전` 포맷으로 표시되도록 변경함.
- 값이 비어있거나 형식이 다르면 `-`를 표시하도록 처리함.

### 추가 작업 요약 (cave 오목 MVP)
- `cave/` 디렉토리를 신규 추가하고 `server.ps1`, `worker.psm1`, `index.html`, `script.js`, `style.css`, `SPEC.md`를 작성함.
- `cave/server.ps1`는 `http://+:4608/`에서 정적 파일(`/`, `/index.html`, `/script.js`, `/style.css`)과 `/ws` WebSocket 업그레이드를 처리함.
- 서버는 게임 판정 없이 브로드캐스트 중심으로 동작하고, 접속 시 `welcome` 메시지와 `peer join/leave` 시스템 메시지를 전송함.
- 역할은 첫 2명에 대해 `black/white`를 랜덤 1회 배정하고, 이후 접속자는 `spectator`로 할당함.
- `cave/worker.psm1`에서 클라이언트 수신 메시지를 전체 브로드캐스트하고, 연결 종료 시 `peer leave` 메시지를 브로드캐스트하도록 구성함.
- `cave/script.js`는 15x15 자유룰 오목(턴 교대, 5목 승리)을 FE에서 처리하고, 승리 후 `ready` 양측 true일 때만 새 판을 시작하도록 구현함.
- `cave/SPEC.md`에 현재 MVP 계약(브로드캐스트 서버, FE 규칙 처리, 관전자/랜덤 역할/수동 재시작)을 문서화함.

### 추가 검증 메모
- `node --check /workspaces/mil/cave/script.js` 통과.
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/cave/server.ps1' -Raw)); 'PARSE_OK'"` 확인.
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/cave/worker.psm1' -Raw)); 'PARSE_OK'"` 확인.
- 서버 실행 후 정적/엔드포인트 확인:
  - `GET /` -> `200`
  - `GET /script.js` -> `200`
  - `GET /style.css` -> `200`
  - `GET /ws`(일반 HTTP 요청) -> `400`

### 추가 작업 요약 (cave Socket Test UI 재구성)
- `cave/index.html`, `cave/style.css`, `cave/script.js`를 수정해 화면을 `좌측 aside 로그 + 우측 보드` 구조로 재배치함.
- 상단 상태 영역에 `연결 상태`, `준비 상태(흑/백)`, `내 돌 색`을 한국어로 고정 표시하도록 변경함.
- 로그는 `[접속]`/`[착수]` 두 종류로 정리하고, 착수 시 `흑/백 + 좌표` 형식으로 누적 표시하도록 변경함.
- 보드 outline 색으로 현재 차례를 표시하도록 변경함(흑 차례/백 차례별 테두리 색상 전환).
- UI 문자열을 한국어로 통일하고, 타이틀/헤더의 `Omok` 표기를 `Socket Test`로 교체함.
- `cave/SPEC.md` 제목과 UI 규칙 섹션을 갱신해 현재 화면 계약(aside 로그/턴 outline/상단 상태/한국어)을 반영함.

### 추가 검증 메모
- `rg -n "Omok|omok" /workspaces/mil/cave` 결과 없음 확인.
- `node --check /workspaces/mil/cave/script.js` 통과.
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/cave/server.ps1' -Raw)); 'PARSE_OK'"` 확인.
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/cave/worker.psm1' -Raw)); 'PARSE_OK'"` 확인.
- `rg -n "Task\.Run|Task|InitialSessionState|ImportPSModule|BeginInvoke" /workspaces/mil/cave/server.ps1`로 `Task` 미사용, `$iss + BeginInvoke` 경로 사용 확인.

### 추가 작업 요약 (acs access serial -> id 처리)
- `acs/server.ps1`의 `Import-Members`에 `SerialToMember` 매핑 생성을 추가함.
- `POST /access` 요청 본문 입력을 `id` 대신 `serial`로 읽도록 변경함.
- `/access`에서 `serial`로 멤버를 찾고, 해당 멤버의 `id`를 꺼내 `AllowedIds` 허용 여부를 검증하도록 변경함.
- 로그 append(`logs/access-log.csv`)는 기존과 동일하게 `id` 컬럼 기준으로 기록되도록 유지함.
- `Invoke-ApiRoute`/`Invoke-Request`/`Start-AcsServer`에 `SerialToMember` 전달 경로를 추가해 요청 처리 체인을 연결함.
- `list.json` 정적 응답은 변경하지 않아 FE 일괄 조회 시 `serial` 포함 응답을 유지함.

### 추가 검증 메모
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/acs/server.ps1' -Raw)); 'PARSE_OK'"` -> `PARSE_OK`.

### 추가 작업 요약 (acs setting serial UI/핸들러 인터페이스)
- 사용자 요청으로 서버 변경은 전부 원복하고(`acs/server.ps1`), 작업 범위를 `acs/setting.html`, `acs/setting.css`, `acs/setting.js`로 한정함.
- 설정 폼 상단에 readonly `serial` 필드(`stg-serial`)와 안내 문구를 추가해 "추가 시 자동 발급 예정" 레이아웃을 반영함.
- 사용자 정보 모드에서 사용할 `serial 재발급` 버튼(`stg-reissue-btn`)을 추가함.
- `setting.js`에서 `list.json`의 `serial` 값을 정규화/표시하도록 연결하고, 모드별 버튼 표시 제어에 `reissue` 플래그를 추가함.
- `setting.js`에 `reissueMemberSerial`/`handleReissue` 이벤트 핸들러 인터페이스를 연결하되, 기존 CRUD와 동일하게 `pending` 스텁으로 유지해 실제 동작은 수행하지 않음.
- `stg-form-actions`에 `flex-wrap`을 적용하고 안내문 스타일(`.stg-hint`)을 추가해 버튼/문구 레이아웃이 좁은 폭에서도 깨지지 않게 정리함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.
- `git status --short` 기준 이번 범위 변경은 `acs/setting.html`, `acs/setting.css`, `acs/setting.js`만 반영됨(서버 파일 제외).

### 작업 요약
- `acs/setting.html`, `acs/setting.css`, `acs/setting.js`를 2차로 확장해 설정 페이지 UI를 실제 동작 상태로 정리함.
- 설정 페이지에서 `allowedMembers`(`list.json`) 기준 사용자 목록 렌더와 검색(`군번/이름/소속`)을 지원함.
- CRUD UI(`추가/수정/삭제`) 이벤트를 연결하되, API 호출은 제외하고 시그니처만 유지함.
- CRUD 액션 이후에는 공통 후처리로 `allowedMembers` 재조회(`/list.json`)를 수행해 목록을 다시 렌더하도록 고정함.
- `acs/SPEC.md`에서 설정 페이지 설명을 기존 1차 레이아웃 전용에서 UI 렌더/검색/재조회 단계로 갱신함.

### 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (ping UI 다크 테마/스크롤)
- `ping/style.css`를 다크 테마 중심 색상 토큰으로 교체해 화면 전반을 관제용 어두운 톤으로 전환함.
- `body`의 `radial-gradient`와 `meta`의 `linear-gradient`를 제거해 복잡한 시각 효과를 단색 기반으로 단순화함.
- 버튼/토글/테이블 헤더/행 hover와 상태 배지(`success/timeout/error`)를 다크 배경 대비에 맞게 조정함.
- 결과 영역 `.tw`에 `max-height`와 `overflow-y: auto`를 적용해 데이터 증가 시 테이블 본문만 스크롤되도록 고정함.
- 모바일 구간(`max-width: 820px`)에서는 `.tw` 높이를 축소해 화면 가용 영역을 유지함.

### 추가 검증 메모
- `rg -n "gradient" /workspaces/mil/ping/style.css` 결과 없음 확인.

### 추가 작업 요약 (volleyball 리시브 충돌)
- `volleyball/server.ps1`에서 공-사각형 충돌 함수(`Resolve-BallRectCollision`)가 충돌 여부를 `bool`로 반환하도록 조정함.
- 플레이어 전용 충돌 처리 함수 `Resolve-BallPlayerCollision`를 추가해 리시브 시 공 반사에 플레이어 위치 오프셋/상단 히트 업리프트를 반영함.
- 게임 틱에서 좌/우 플레이어 충돌 호출을 공용 사각형 충돌 대신 `Resolve-BallPlayerCollision` 호출로 교체함.
- 추가 보강: 충돌 누락 완화를 위해 접촉 경계 판정을 `>=`에서 `>`로 조정해 정확히 맞닿은 경우도 충돌로 처리함.
- 추가 보강: 플레이어 충돌 반사를 절대속도 대신 상대속도(`ball - body`) 기준으로 계산해 이동 중 리시브 반응을 개선함.
- 추가 보강: 볼 이동/충돌 검사를 틱당 2회 서브스텝으로 나눠 빠른 이동 시 충돌 스킵을 줄임.

### 추가 검증 메모
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/volleyball/server.ps1' -Raw)); 'PARSE_OK'"` 확인.

### 추가 작업 요약 (acs setting 폼 통합)
- `acs/setting.html`의 상단 안내 박스를 제거함.
- `acs/setting.html`, `acs/setting.js`에서 사용자 수정 흐름을 별도 모달이 아닌 좌측 폼 재사용 방식으로 변경함.
- 좌측 폼은 `추가/수정` 모드 전환을 지원하고, 수정 취소 시 즉시 추가 모드로 복귀함.
- CRUD 액션 후 `allowedMembers` 재조회(`/list.json`) 규칙은 유지함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (acs setting 처리 결과 박스 제거)
- `acs/setting.html`의 `처리 결과` 박스를 제거함.
- `acs/setting.css`에서 관련 메시지 박스 스타일을 제거함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (acs setting Info 중심 전환)
- `acs/setting.html`, `acs/setting.js`를 수정해 목록 행 클릭 시 좌측이 사용자 세부 Info 창으로 동작하도록 변경함.
- 좌측 Info에서 `수정`을 누르면 좌측이 수정 form으로 전환되고, `삭제` 버튼으로 삭제 흐름을 수행하도록 정리함.
- 우측 툴바에 `사용자 추가` 버튼을 추가하고, 버튼 클릭으로 좌측 추가 form이 나타나도록 구성함.
- 목록은 `작업` 컬럼을 제거하고 행 선택 중심으로 단순화했으며, CRUD 이후 `allowedMembers` 재조회 규칙은 유지함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (acs setting 빈 안내 박스 제거)
- `acs/setting.html` 좌측의 `목록에서 사용자를 선택해 주세요` 안내 박스를 제거함.
- `acs/setting.js`/`acs/setting.css`에서 해당 박스 관련 참조와 스타일을 정리함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (acs setting Info/Form 중복 노출 수정)
- `acs/setting.css`에서 `hidden` 속성 우선 규칙을 추가해 좌측 Info/form이 동시에 보이던 문제를 수정함.
- `.stg-form { display: grid; }`와의 충돌을 해소해 모드 전환 시 한 화면만 보이도록 정리함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.

### 추가 작업 요약 (acs setting 단일 영역 전환)
- `acs/setting.html`, `acs/setting.js`를 수정해 좌측을 단일 입력 영역으로 통합하고, 모드별(readonly/info/edit/create) 상태 전환만 수행하도록 변경함.
- 사용자 row 선택 시 같은 입력 영역이 info 형태(readonly)로 보이고, 수정 시 동일 영역에서 곧바로 편집 가능하도록 UX를 정리함.
- `acs/setting.css`에서 readonly 입력 시각을 info 카드처럼 보이게 보강함.

### 추가 검증 메모
- `node --check /workspaces/mil/acs/setting.js` 통과.

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
- 추가 수정: 공 움직임 동기화를 위해 `ball_update` 브로드캐스트를 복구함.
  - 서버 틱은 유지하고, `ball_update`를 약 15Hz(66ms)로 브로드캐스트하도록 추가함.
  - `ball_update` 페이로드에 `phase`, `round`, `ball(x,y,vx,vy)`를 포함함.
  - FE는 `ball_update`를 수신해 공 좌표 및 라운드/phase 표시를 갱신함.
  - `volleyball/SPEC.md`에 `ball_update` 계약을 추가함.

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
- 추가 검증: `node --check /workspaces/mil/volleyball/script.js` 재확인 통과.

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

## 2026-03-27

### 작업 요약 (radiolog 신규)
- `radiolog/` 디렉토리를 신규 추가하고 `index.html`, `style.css`, `script.js`, `SPEC.md`를 작성함.
- UI를 보고서형 표 중심으로 구성하고, 송신/수신 감명도 및 상대 교신자 관등/성명 입력을 행 단위로 관리하도록 구현함.
- 날짜별 `localStorage` 키(`radiolog:journal:<YYYY-MM-DD>`)와 마지막 선택 날짜 키(`radiolog:selectedDate`)를 사용하도록 구현함.
- 선택 날짜 데이터가 없으면 고정 템플릿 34건(사단망 4건 + 여단망 CF 25건 + 여단망 F 5건)을 자동 생성하도록 구현함.
- 행 입력 변경 시 즉시 자동 저장, 완료/미완료 집계를 즉시 갱신하도록 구현함.

### 추가 작업 요약 (milkit 서버)
- `radiolog/server.ps1`를 추가해 `milkit/milkit.psm1` 기반으로 서버를 실행하도록 구성함.
- `GET /`, `GET /index.html`, `GET /style.css`, `GET /script.js`, `GET /health`를 명시 라우트로 등록함.
- 사용자 보고 `not found` 이슈 대응으로 `/` 및 정적 파일을 `Send-LocalTextFile`로 직접 응답하도록 조정함.
- `localhost:9070`에서 `Not Found`가 뜨는 문제를 재현하고, 기본 바인딩을 `127.0.0.1`에서 `localhost`로 변경함.
- 이후 기본 실행 프리픽스를 `http://+:{PORT}/`로 전환해 Host 헤더(`localhost`/`127.0.0.1`) 차이 없이 같은 라우트로 수신되게 정리함.

### 검증 메모
- `node --check /workspaces/mil/radiolog/script.js` 통과.
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/radiolog/server.ps1' -Raw)); 'PARSE_OK'"` 확인.
- 샌드박스 제한으로 기본 환경에서는 로컬 포트 바인딩이 `Permission denied`가 발생할 수 있음.
- 권한 상승 재현에서 확인:
  - 수정 전: `curl http://localhost:9070/` -> `404 Not Found`, `curl http://127.0.0.1:9070/` -> `200`
  - 수정 후(`http://+:{PORT}/`): `curl http://localhost:9070/` -> `200`, `curl http://127.0.0.1:9070/` -> `200`

### 추가 작업 요약 (radiolog 블록형 UI 재구성)
- `radiolog/index.html`을 단일 테이블에서 3개 블록(`사단망`, `여단망 CF`, `여단망 F`) 구조로 변경함.
- 사단망은 `망(행) x 오전/오후(열)` 교차표로 렌더링하도록 전환함.
- 여단망은 `시간(행) x 대대(열)` 매트릭스로 렌더링하도록 전환하고, `CF`/`F`를 별도 표로 분리함.
- 각 셀에서 기존 입력 방식(`송신/수신/관등 select + 성명 input`)을 그대로 유지함.
- `radiolog/script.js` 렌더러를 재구성해 블록별 tbody(`division/cf/f`)를 생성하고, 기존 로컬스토리지 저장 스키마는 유지함.
- 셀 단위 변경 시 즉시 저장/요약 갱신/셀 상태(pending/complete)/최종 수정 시각 갱신이 동작하도록 정리함.
- `radiolog/style.css`를 블록형 표 레이아웃에 맞게 조정해 보고서형 시각 톤을 유지함.
- `radiolog/SPEC.md`의 UI 규칙을 블록 분리 및 매트릭스 구조 기준으로 갱신함.

### 추가 검증 메모
- `node --check /workspaces/mil/radiolog/script.js` 통과.
- 선택자 점검: `#journal-blocks`, `#division-body`, `#brigade-cf-body`, `#brigade-f-body`가 `index.html`/`script.js`에서 일치함을 확인.

### 추가 작업 요약 (radiolog 셀 입력 2줄 고정 / 수정시각 제거)
- 셀 입력 배치를 `송신/수신` 1줄, `관등/성명` 1줄 구조로 변경함.
- `radiolog/script.js`에서 셀 하단 `최신 수정 시각` 출력(`.updated-at`)을 제거함.
- 입력 변경 시 `row.updatedAt`를 갱신하던 로직을 제거함.
- `radiolog/style.css`에서 `.name-field`, `.updated-at` 관련 스타일을 제거해 2x2 그리드 입력 배치를 고정함.
- `radiolog/SPEC.md`에 2줄 입력 고정 및 수정시각 미표시 규칙을 반영함.

### 추가 검증 메모
- `node --check /workspaces/mil/radiolog/script.js` 통과.
- `rg -n "updated-at|name-field|row.updatedAt" /workspaces/mil/radiolog/script.js /workspaces/mil/radiolog/style.css` 결과 제거 확인.

### 추가 작업 요약 (radiolog 레이블 헤딩 계층 전환)
- `journal-blocks` 구조에서 카드/박스형 래퍼를 제거하고 `헤딩 + 매트릭스` 연속 배치로 전환함.
- 레이블 체계를 `h1: 사단망/여단망`, `h2: CF/F` 계층으로 변경함.
- `style.css`에서 기존 전역 `h1` 스타일을 `.title-block h1`로 스코프 제한해 문서 제목과 섹션 헤딩 스타일 충돌을 분리함.
- 섹션 헤딩용 `.matrix-major`, `.matrix-minor` 스타일을 추가해 헤딩 계층 시각 구분을 명확히 함.
- `radiolog/SPEC.md` UI 규칙을 헤딩 계층 기반 레이블 규칙으로 갱신함.

### 추가 검증 메모
- `index.html` 기준 `h1.matrix-major` 2개(사단망/여단망), `h2.matrix-minor` 2개(CF/F) 구조 반영 확인.
- 테이블 `tbody` id(`division-body`, `brigade-cf-body`, `brigade-f-body`) 유지 확인.

### 추가 작업 요약 (radiolog Desktop 고정폭 매트릭스)
- 매트릭스가 Desktop 화면 폭을 넘지 않도록 `table-layout: fixed` 기반으로 조정함.
- `.division-table`, `.brigade-table`, `.cell-editor`의 `min-width` 의존을 제거함.
- 표 헤더/행 라벨/셀 내부 입력 컨트롤 크기를 축소해 0FA~4FA 컬럼이 한 화면에 들어오도록 조정함.
- `table-shell`의 수평 스크롤 의존을 제거(`overflow-x: visible`)함.
- 불필요한 반응형 미디어쿼리(`@media (max-width: 900px)`)를 제거함.
- `radiolog/SPEC.md`에 Desktop 전용 고정 레이아웃/미디어쿼리 미사용 규칙을 반영함.

### 추가 검증 메모
- `style.css`에서 `@media`, `min-width: 1520px`, `min-width: 228px` 제거 확인.
- `matrix-table`에 `table-layout: fixed` 적용 확인.

### 추가 작업 요약 (summary 제거 / 작성자 기록 / Skyblue+Slate)
- `radiolog/index.html`에서 summary 영역(총 건수/입력 완료/미완료/저장 상태)을 제거함.
- summary 위치에 `작성자 기록` 섹션을 추가하고 `오전`, `오후` 작성자 입력 필드를 배치함.
- `radiolog/script.js`에서 summary 관련 DOM/함수(`updateSummary`, `setSaveStatus`)를 제거함.
- 작성자 저장을 날짜별로 추가함: `radiolog:author:<YYYY-MM-DD>` (`am`, `pm`).
- 날짜 전환 시 해당 날짜 작성자 값을 로드하고, 작성자 입력 변경 시 즉시 localStorage에 저장하도록 연결함.
- `radiolog/style.css` 색상 토큰을 Toss 스타일의 `Skyblue + Slate` 계열로 재정의하고 버튼/헤딩/표 헤더에 반영함.
- `radiolog/SPEC.md`에 작성자 저장 키/summary 미사용/작성자 기록/컬러 테마 규칙을 반영함.

### 추가 검증 메모
- `node --check /workspaces/mil/radiolog/script.js` 통과.
- `rg -n "summary|total-count|done-count|pending-count|save-status|updateSummary|setSaveStatus" /workspaces/mil/radiolog/index.html /workspaces/mil/radiolog/script.js /workspaces/mil/radiolog/style.css` 결과 없음 확인.
- `rg -n "author-am|author-pm|radiolog:author:" /workspaces/mil/radiolog/index.html /workspaces/mil/radiolog/script.js /workspaces/mil/radiolog/SPEC.md` 확인.

### 추가 작업 요약 (현대적 Document 스타일 리디자인)
- 기존 레이아웃 구조(`작성자 기록` + `헤딩 + 매트릭스`)는 유지한 채 시각 스타일만 전면 재정리함.
- 디자인 톤을 Notion/Toss/Vercel 계열의 문서형 미니멀 스타일로 조정함.
- 색상 팔레트는 Skyblue + Slate 기반 토큰으로 재구성하고 헤더/버튼/표 헤더/포커스 상태에 일관 적용함.
- 표/입력 컴포넌트에 라운드/섀도우/포커스 링을 추가해 현대적 UI 톤을 보강함.
- 타이포는 `1rem(16px)` 기준, 간격/크기는 4px 스케일 기준을 유지함.

### 추가 검증 메모
- `node --check /workspaces/mil/radiolog/script.js` 통과.
- `style.css`에서 `@media` 미사용 상태 유지 확인.
- `style.css`에서 `font-size: 1rem` 기준 및 4px 스케일 간격 적용 확인.

### 추가 작업 요약 (milkit-io 모듈 추가)
- `milkit/milkit-io.psm1`를 신규 추가하고 `New-Store` 기반 객체형 FILE I/O 모듈을 구현함.
- 텍스트 API를 추가함: `$store.ReadText(fileName)`, `$store.WriteText(fileName,text)`, `$store.EditText(fileName, transform)`.
- 읽기는 UTF-8 BOM/BOMless 자동 호환으로 처리하고, 쓰기는 기본 UTF-8 BOMless(`-WriteBom $false`)로 고정함.
- CSV를 테이블처럼 다루는 체이닝 DSL을 추가함: `$store.From(table).Select(...).Where(@{...}).Find()/Insert()/Update()/Delete()`.
- `Where`는 정확히 일치 + AND만 지원하고, `Update/Delete`는 매칭된 전체 행을 대상으로 처리함.
- `Insert`는 파일 미존재 시 `<table>.csv`를 자동 생성하고, 기존 헤더 기준 저장(없는 컬럼 빈값/추가 키 무시) 규칙을 적용함.
- `milkit/SPEC.md`에 `milkit-http`/`milkit-io` 분리 개념과 `milkit-io` Public API를 추가함.
- `milkit/smoke-test-io.ps1`를 추가해 UTF-8/BOM, EditText, CSV Find/Insert/Update/Delete 동작을 검증함.

### 추가 검증 메모
- `pwsh -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -LiteralPath '/workspaces/mil/milkit/milkit-io.psm1' -Raw)); 'PARSE_OK'"` -> `PARSE_OK`.
- `pwsh -NoLogo -NoProfile -File /workspaces/mil/milkit/smoke-test-io.ps1` -> `OK`.
- 회귀 점검: `pwsh -NoLogo -NoProfile -File /workspaces/mil/milkit/smoke-test.ps1` -> `OK`.

### 추가 작업 요약 (cave style.css 토큰/스케일 정리)
- `cave/style.css`에 `:root` 색상 토큰을 추가하고 기존 컬러 리터럴 사용을 전부 `var(--color-...)` 참조로 치환함.
- 폰트 크기를 `rem` 단위로 통일함(`body`, `h1`, `h2`, `.status-row p`, `#phase`, `.log div`, 모바일 `h1`).
- 4px 스케일 기준에 맞게 크기 값을 정리함(예: `gap 6/14 -> 8/16`, `min-width 138 -> 140`, `log 538 -> 540`, 보드 턴 강조 `6 -> 8`).
- `winner-notice`의 폰트 범위를 `clamp(2rem, 7vw, 3.5rem)`로 조정해 16px 기반 폰트 스케일을 유지함.

### 추가 검증 메모
- `awk` 기반 점검으로 `cave/style.css` 내 `px` 값 중 4의 배수가 아닌 항목이 없음을 확인함.
- `awk` 점검으로 `:root` 블록 외부에 `#hex`/`rgb`/`rgba`/`hsl` 컬러 리터럴이 없음을 확인함.
- `rg -n "font-size:\\s*[^;]*px" cave/style.css` 결과 없음으로 폰트 px 단위 제거를 확인함.
- 후속 보정: CSV `Update`에서 `[ordered]` 입력 키 매칭을 안정화했고, `.`/`..` 파일명 입력은 거부하도록 보강함.
- 사용 예시 추가: `milkit/example-io-crud.ps1`를 추가해 `id`, `access_type`, `time` 컬럼 CSV에 대해 Create/Read/Update/Delete 흐름을 한 파일에서 실행 가능하도록 제공함.
- 예시는 `$store.From('access_records')` 기준으로 Insert 2건 -> Where+Select Find -> Where Update -> Where Delete -> 최종 조회 순서로 동작함.
- 검증: `pwsh -NoLogo -NoProfile -File /workspaces/mil/milkit/example-io-crud.ps1` 실행 시 `UPDATED_COUNT=1`, `DELETED_COUNT=1` 및 최종 1행 유지 출력 확인.

### 추가 작업 요약 (cave 밝은 톤 보정)
- 사용자 피드백(전체 톤이 어두움)에 따라 `cave/style.css`의 `:root` 컬러 토큰 값을 밝은 팔레트로 재조정함.
- 페이지/보드/버튼/경계/오버레이 색상을 고명도 기준으로 조정하고, 기존 토큰 참조 구조는 유지함.
- 구조/레이아웃/폰트 rem/4px 스케일 규칙은 변경 없이 유지함.

### 추가 검증 메모
- `:root` 외부 컬러 리터럴 미사용 상태 유지 확인.
- `px` 값 4배수 규칙 유지 확인.
