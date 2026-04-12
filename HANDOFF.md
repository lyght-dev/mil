# HANDOFF

## Global Rules

- 루트 `HANDOFF.md`는 저장소 전역 규칙, 공용 인프라 변화, 팀 전체가 알아야 하는 cross-project 메모만 기록한다.
- 단일 프로젝트 기능 변경, 유틸 추가, UI 수정, 1회성 검증 로그는 각 프로젝트 `HANDOFF.md`에만 기록한다.
- 프로젝트 `HANDOFF.md`에는 현재 상태, 열려 있는 주의점, 다음 세션 판단에 필요한 운영 메모만 남긴다.
- `SPEC.md`와 코드에 이미 반영되어 더 이상 판단에 영향을 주지 않는 종료 이력은 로그로 누적하지 않고 폐기한다.
- 새 프로젝트 메모가 필요하면 먼저 해당 디렉토리 `SPEC.md`를 최신화한 뒤 `HANDOFF.md`를 작성한다.

## Active Global Notes

### 2026-04-12

- `acs` 디자인 분리 작업용 git worktree가 `/workspaces/mil-acs-design`에 있다.
- 해당 worktree 브랜치는 `feat-acs-design`이고, 기준 커밋은 `d6a35c5`다.
- 위 정보는 작업 경로 선택에 직접 영향을 주므로 루트에 유지한다.
- 세션 시작 순서는 루트 `AUDIT.md` -> 작업 디렉토리 `SPEC.md` -> 필요 시 해당 프로젝트 `HANDOFF.md`다.
