# HANDOFF

## Current State

- 현재 전송 계약은 `welcome` + `event` + 변경 시점의 `input_update` + 고정 주기의 `ball_update`다.
- 주기적 `state` 브로드캐스트는 현재 운영 계약에서 제외됐다. 클라이언트의 `state` 분기는 호환용 잔존 경로로만 본다.
- 서버 권한 물리 시뮬레이션과 최소 브로드캐스트 정책을 함께 유지한다. 입력 polling이나 전체 상태 spam을 다시 넣기 전에는 `volleyball/SPEC.md`를 먼저 갱신한다.

## Open Notes

- 전송 구조를 건드린 뒤 검증할 때는 `server.ps1` 재시작과 브라우저 하드 리로드가 사실상 필수다. 구버전 JS 캐시가 있으면 판단이 흔들린다.
