# HANDOFF

## Current State

- 서버는 WebSocket 메시지 중계만 담당하고, 준비 상태/착수 가능 여부/승패 판정은 모두 프론트엔드가 가진다.
- `/self.html`은 WebSocket 없이 같은 보드/승패 로직을 로컬 단독 플레이로 돌리는 별도 진입점이다.
- 온라인 모드는 첫 시작과 재시작 모두 `black`, `white` 양측 ready가 참일 때만 진행된다. 플레이어 이탈 시 ready 게이트도 함께 풀린다.
- 현재 UI 계약은 좌측 로그 aside, 역할 색을 반영하는 상단 바, 현재 차례를 나타내는 보드 outline, 게임 종료 시 대형 승리 알림이다.

## Open Notes

- 현재 추가 인수인계는 없다. 서버 쪽 검증을 늘리기 전에는 `cave/SPEC.md`의 FE authority 전제를 유지한다.
