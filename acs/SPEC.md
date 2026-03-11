# AccessControll Service Spec

## 1. 개요

ACS는 군부대 장병의 입영 및 퇴영 기록을 중앙에서 수집하고 조회하는 가벼운 PowerShell 서버이다.

현재 단계에서 ACS는 다음 원칙으로 동작한다.

- 중앙 서버 1개가 모든 gate 요청을 받는다.
- 각 gate의 client가 바코드를 읽고 입영/퇴영을 판별한다.
- client가 `type`, `id`, `location`을 서버로 전송한다.
- 서버는 요청을 신뢰하고 기록과 현재 상태만 관리한다.
- 부수 조회와 가공은 가능하면 FE 브라우저에서 처리한다.

본 단계는 내부 시스템의 단순 작업용을 전제로 하며, 외부 조작이 없는 안전한 환경을 가정한다.

---

## 2. 개발 기준

- 구현 언어: PowerShell
- 실행 환경: Windows PowerShell 5.x
- 엔트리 파일: `server.ps1`
- 문서 기준: 본 Spec은 중앙 서버 기준의 최소 구현을 정의한다.
- 구현 원칙:
  - `AUDIT.md`의 최소 구현, 최소 검증 원칙을 따른다.
  - 서버는 가볍게 유지한다.
  - 복잡한 validation, decode, dedupe는 서버에 넣지 않는다.
  - 기록용 데이터와 현재 상태 데이터를 분리해서 관리한다.
  - FE가 직접 처리할 수 있는 조회 가공은 서버에서 다시 하지 않는다.

---

## 3. 목적

ACS의 목적은 다음과 같다.

- client가 보낸 입퇴영 요청을 중앙에서 기록한다.
- location별 현재 상태 현황을 조회할 수 있게 한다.
- FE가 정적 자원을 직접 읽어 명단 조회, location 선택, 로그 조회를 수행할 수 있게 한다.

---

## 4. 시스템 범위

### 4.1 현재 단계 포함 범위

- 중앙 HTTP 서버 1개 실행
- 정적 웹 파일 서빙(`index.html`, `board.html`, `script.js`, `style.css`)
- 정적 데이터 파일 서빙(`list.json`, `location.json`, `logs/access-log.csv`)
- 입퇴영 요청 수신
- `list.json` 기반 허용 군번 검증
- CSV append-only 기록 저장
- 메모리 기반 현재 위치 상태 유지
- 특정 location 또는 전체 현재 상태 조회
- 서버 재시작 시 CSV를 다시 읽어 현재 상태 복원

### 4.2 현재 단계 제외 범위

- 서버 측 바코드 decode
- 서버 측 entry/exit 판별
- 서버 측 location별 중복 예외 처리
- 서버 측 로그 검색, 정렬, 날짜 필터링
- 서버 측 명단 검색 UI 로직
- 인증/인가
- 외부 공개 운영
- DB 연동
- GUI

---

## 5. 책임 분리

### 5.1 Client 책임

- 바코드 입력 수신
- 바코드에서 입영/퇴영 구분
- 바코드에서 군번 `id` 추출
- 스캐너 진입 시 `location.json` 후보 중 하나 선택
- 요청에 `location` 포함
- location별 중복 예외 처리
- `list.json`을 직접 읽어 군번/이름 표시
- `location.json`을 직접 읽어 스캐너와 현황판 기준 location 구성
- `logs/access-log.csv`를 직접 읽어 일별 로그 추출
- 로그 날짜 필터링, 검색, 정렬 수행
- 현황판과 로그에서 `location.json`에 있는 location만 표시

### 5.2 Server 책임

- HTTP 요청 수신
- 정적 파일 서빙
- 요청 본문에서 `type`, `id`, `location` 읽기
- `list.json`에 있는 군번인지 확인
- 기록 CSV에 append
- 현재 상태 메모리 갱신
- location별 현재 상태 조회 응답
- 서버 시작 시 CSV 재복원

---

## 6. 신뢰 및 검증 원칙

현재 단계에서 client와 server는 내부 안전 환경에서 동작한다고 가정한다.

따라서 서버는 아래 원칙을 따른다.

- client가 보낸 `type`, `location`은 신뢰한다.
- `id`는 `list.json`에 있는 군번만 허용한다.
- `location.json`에 없는 `location`도 거부하지 않는다.
- 과도한 형식 검증을 하지 않는다.
- 복잡한 복구, fallback, 방어 로직을 넣지 않는다.
- 요청 처리 실패가 전체 서버 종료로 이어지지 않도록 얇은 보호만 둔다.

서버는 정상 경로 기준으로 아래 값만 기대한다.

- `type`: `entry` 또는 `exit`
- `id`: 군번 문자열
- `location`: gate 식별 문자열

---

## 7. 데이터 관리 원칙

ACS는 기록용 데이터와 현재 상태 데이터를 분리해서 관리한다.

### 7.1 기록용 데이터

- 목적: 영구 보관 및 사후 확인
- 저장 방식: CSV append-only

### 7.2 현재 상태 데이터

- 목적: 군번별 마지막 entry location 조회
- 저장 방식: 서버 프로세스 메모리

### 7.3 정적 조회 데이터

- `list.json`: FE 명단 조회와 이름 표시용
- `location.json`: FE location 선택과 화면 노출 기준용
- `logs/access-log.csv`: FE 로그 조회용 원본

### 7.4 분리 이유

- 기록은 누적 이력을 보존해야 한다.
- 현재 상태는 빠르게 조회되어야 한다.
- 로그 가공은 브라우저에서 처리하는 편이 PowerShell 서버보다 유리하다.

---

## 8. 인터페이스

### 8.1 정적 리소스

```text
GET /index.html
GET /board.html
GET /script.js
GET /style.css
GET /list.json
GET /location.json
GET /logs/access-log.csv
```

규칙:

- 서버는 위 파일을 그대로 서빙한다.
- FE는 `list.json`, `location.json`, `logs/access-log.csv`를 직접 읽어 필요한 가공을 수행한다.
- `logs/access-log.csv`는 원본 CSV 전체를 그대로 내려준다.

### 8.2 입퇴영 요청

```text
POST /access
Content-Type: application/json
```

요청 예시:

```json
{
  "type": "entry",
  "id": "a25-76000001",
  "location": "gate-1"
}
```

정상 응답 예시:

```json
{
  "status": "logged"
}
```

규칙:

- 서버는 `type`, `id`, `location`만 읽는다.
- 서버는 `id`가 `list.json`에 없으면 거부한다.
- 서버는 기록 CSV에 append 후 현재 상태를 갱신한다.

### 8.3 location별 현재 인원 조회

```text
GET /status?location=gate-1
```

정상 응답 예시:

```json
{
  "location": "gate-1",
  "ids": ["a25-76000001", "a01-1234567"]
}
```

규칙:

- 특정 location만 조회한다.
- 응답은 현재 해당 location에 남아 있는 군번 `id` 목록을 반환한다.

### 8.4 전체 현황 조회

```text
GET /status
```

정상 응답 예시:

```json
[
  {
    "location": "gate-1",
    "ids": ["a25-76000001", "a01-1234567"]
  },
  {
    "location": "gate-2",
    "ids": []
  }
]
```

규칙:

- 모든 location의 현재 상태 현황을 반환한다.
- FE는 이 응답에서 `location.json`에 있는 location만 화면에 표시한다.

---

## 9. 요청 처리 흐름

### 9.1 정적 리소스 조회

1. FE가 필요한 정적 파일을 직접 요청한다.
2. 서버는 대응 파일을 그대로 응답한다.
3. FE가 JSON/CSV를 읽어 필요한 화면 로직을 수행한다.

### 9.2 `POST /access`

1. client가 `type`, `id`, `location`을 전송한다.
2. 서버가 요청 값을 읽는다.
3. 서버가 `id`가 `list.json`에 있는지 확인한다.
4. 서버가 CSV에 한 줄 append 한다.
5. 서버가 메모리의 현재 상태를 갱신한다.
6. 서버가 `logged` 응답을 반환한다.

### 9.3 상태 갱신 규칙

- 같은 `id` 요청이 오면 이전 `location`의 현재 상태를 먼저 지운다.
- `entry`면 요청 `location`에 다시 추가한다.
- `exit`면 어떤 `location`에도 남기지 않는다.

### 9.4 `GET /status`

1. 요청 query에서 `location`을 읽는다.
2. 값이 없으면 전체 상태를 반환한다.
3. 값이 있으면 해당 location 상태만 반환한다.

---

## 10. 기록 저장

입퇴영 기록은 CSV 파일로 저장한다.

### 10.1 CSV 컬럼

| 컬럼명 | 설명 |
| --- | --- |
| time | 처리 시각 |
| type | `entry` 또는 `exit` |
| location | gate 식별값 |
| id | 군번 |

### 10.2 예시

```csv
time,type,location,id
2026-03-09T08:12:11,entry,gate-1,a25-76000001
2026-03-09T17:41:53,exit,gate-1,a25-76000001
```

### 10.3 저장 방식

- 파일이 없으면 생성
- 파일이 있으면 append
- append가 쉬운 단순 구조를 유지

---

## 11. 현재 상태 관리

현재 상태는 서버 메모리에서 관리한다.

### 11.1 기본 구조

- `location`별 현재 남아 있는 `id` 목록 또는 집합

예:

```text
gate-1 -> { a25-76000001, a01-1234567 }
gate-2 -> { b12-7654321 }
```

### 11.2 서버 재시작 시 복원

- 서버 시작 시 기존 CSV를 처음부터 읽는다.
- 기록을 순서대로 적용하여 메모리 상태를 재구성한다.

### 11.3 이유

- 현재 상태 조회는 메모리에서 바로 처리하는 편이 단순하다.
- 로그 조회는 FE가 CSV 원본을 직접 읽는 편이 서버를 가볍게 유지한다.

---

## 12. FE 로그 처리 규칙

- FE는 `logs/access-log.csv` 전체를 읽는다.
- FE는 각 행의 `time`을 KST 기준 날짜로 변환한다.
- FE는 선택한 날짜의 로그만 화면에 남긴다.
- FE는 군번, 이름, 위치 기준 검색을 수행한다.
- FE는 최신순/오래된순 정렬을 수행한다.
- FE는 `location.json`에 없는 location 로그는 표시하지 않는다.

---

## 13. 오류 처리 원칙

현재 단계에서는 최소한의 오류 처리만 둔다.

- 잘못된 요청은 단순한 오류 응답으로 끝낸다.
- 한 요청 실패가 전체 서버 종료로 이어지지 않게 한다.
- CSV 저장 실패는 해당 요청 실패로 처리한다.
- 복잡한 재시도나 상세 에러 체계는 넣지 않는다.

---

## 14. 최소 구현 계약

현재 단계의 ACS는 아래를 충족해야 한다.

1. 중앙 HTTP 서버로 실행될 수 있어야 한다.
2. `list.json`, `location.json`, `logs/access-log.csv`를 정적 파일로 서빙할 수 있어야 한다.
3. `POST /access` 요청을 받을 수 있어야 한다.
4. 요청의 `type`, `id`, `location`을 읽어 CSV에 기록할 수 있어야 한다.
5. `id`가 `list.json`에 없으면 요청을 거부할 수 있어야 한다.
6. 요청에 따라 location별 현재 상태를 메모리에서 갱신할 수 있어야 한다.
7. `GET /status?location=...` 로 특정 location의 현재 상태 목록을 반환할 수 있어야 한다.
8. `GET /status` 로 전체 현재 상태를 반환할 수 있어야 한다.
9. 서버 재시작 시 CSV를 다시 읽어 현재 상태를 복원할 수 있어야 한다.

---

## 15. 예시 시나리오

### 15.1 정상 입영 요청

- 요청:

```json
{
  "type": "entry",
  "id": "a25-76000001",
  "location": "gate-1"
}
```

- 결과:
  - CSV 1건 추가
  - `gate-1` 현재 상태에 `a25-76000001` 포함

### 15.2 정상 퇴영 요청

- 요청:

```json
{
  "type": "exit",
  "id": "a25-76000001",
  "location": "gate-1"
}
```

- 결과:
  - CSV 1건 추가
  - `a25-76000001`는 현재 상태에서 제거됨

### 15.3 현재 상태 조회

- 요청:

```text
GET /status?location=gate-1
```

- 응답:

```json
{
  "location": "gate-1",
  "ids": ["a01-1234567"]
}
```

### 15.4 FE 로그 조회

- FE 입력:

```text
GET /logs/access-log.csv
```

- FE 처리:
  - CSV 전체 수신
  - KST 날짜 필터링
  - 검색/정렬 적용
  - 화면 렌더링

---

## 16. 구현 비고

- 현재 단계에서 서버는 client 요청을 신뢰한다.
- 서버는 바코드 원문을 알 필요가 없다.
- 서버는 현재 상태 조회와 기록 저장에만 집중한다.
- FE는 정적 파일을 직접 읽어 부수 조회와 가공을 수행한다.
- 로그 가공을 FE로 옮겨 PowerShell 서버의 CPU 부담을 줄인다.
