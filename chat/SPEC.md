# Simple LAN Chat (PowerShell 5) - SPEC

## 1. Goal

내부 단독망(LAN)에서 네트워크 확인 용도로 사용하는 간단한 멀티 채팅을 구현한다.

- 서버: `server.ps1` (`HttpListener`, long polling, port `9999`)
- 클라이언트: `client.ps1` (콘솔)
- 채팅방: 단일 공용 room 1개
- 영속 저장: 없음(메모리만 사용)

## 2. Files

```
/chat
 ├─ server.ps1
 ├─ client.ps1
 ├─ tiktok-server.ps1
 ├─ tiktok-clinet.ps1
 ├─ tiktok-stream-server.ps1
 ├─ tiktok-stream-client.ps1
 ├─ SPEC.md
 └─ HANDOFF.md
```

## 3. Design (Simple)

- 서버는 다음 상태만 유지한다.
  - 접속 사용자 목록(`clientId -> name, lastSeenAt`)
  - 최근 메시지 버퍼(최대 `MaxMessages`, 기본 200)
  - 증가 메시지 ID(`NextId`)
- 클라이언트는 `cursor`(마지막 수신 메시지 ID)만 기억한다.
- `/poll`은 `cursor` 이후 메시지가 생기면 즉시 반환, 없으면 timeout까지 대기 후 빈 배열 반환.

복잡한 브로커/DB/큐 시스템은 사용하지 않는다.

## 4. API

### `POST /join`

Request:

```json
{ "name": "alice" }
```

Response `200`:

```json
{
  "clientId": "guid",
  "name": "alice",
  "joinedAt": "ISO8601"
}
```

Rules:

- 이름 1~20자
- 중복 이름 허용

### `POST /send`

Request:

```json
{
  "clientId": "guid",
  "text": "hello"
}
```

Response `202`:

```json
{
  "accepted": true,
  "messageId": 1,
  "serverTime": "ISO8601"
}
```

Rules:

- 메시지 1~500자
- `clientId`가 유효해야 함

### `GET /poll?clientId={guid}&cursor={long}&timeoutSec={int}`

Response `200`:

```json
{
  "messages": [
    { "id": 1, "senderName": "alice", "text": "hello", "sentAt": "ISO8601" }
  ],
  "nextCursor": 1,
  "serverTime": "ISO8601"
}
```

Rules:

- `cursor` 이후 메시지 반환
- 기본 timeout 20초, 최대 30초

### `POST /leave`

Request:

```json
{ "clientId": "guid" }
```

Response `200`:

```json
{ "left": true }
```

### `GET /health`

Response `200`:

```json
{ "status": "ok", "serverTime": "ISO8601" }
```

## 5. Error Contract

오류 응답:

```json
{
  "error": { "code": "invalid_text", "message": "text must be 1 to 500 characters." },
  "serverTime": "ISO8601"
}
```

Status:

- `400` bad request
- `401` invalid/inactive client
- `404` endpoint not found
- `405` method not allowed
- `500` internal error

## 6. CORS

- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type`
- `OPTIONS` -> `204`

## 7. LAN Usage

서버 PC의 내부망 IP를 사용해 실행한다.

예:

```powershell
pwsh -File .\server.ps1 -Port 9999 -BindAddress 192.168.0.10
```

다른 PC 클라이언트:

```powershell
pwsh -File .\client.ps1 -ServerUrl http://192.168.0.10:9999
```

## 8. Test Checklist

1. 클라이언트 2개 이상 동시 접속
2. A가 보낸 메시지를 B에서 수신
3. `/poll` timeout 시 빈 `messages` 반환
4. 잘못된 `clientId`로 `/send` 시 `401`
5. `/leave` 후 재송신 실패 확인

## 9. TikTok Utility

간단 연결 확인용 스크립트를 포함한다.

- `tiktok-server.ps1`: `POST /tiktok` 본문이 `tick`이면 `tock` 반환
- `tiktok-clinet.ps1`: 서버에 `tick` 전송 후 응답 출력
- `tiktok-stream-server.ps1`: `GET /stream` SSE 연결 유지, `POST /tick` 본문이 `tick`이면 모든 스트림에 `tock` 이벤트 전송
- `tiktok-stream-client.ps1`: SSE 스트림에 연결하고, 옵션으로 `tick`을 전송한 뒤 첫 이벤트를 출력
