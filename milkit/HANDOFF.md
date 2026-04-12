# HANDOFF

## Current State

- 현재 공용 모듈은 `milkit.psm1`과 `milkit-io.psm1` 두 개다.
- `Use-Static`는 등록된 루트 아래의 직접 요청 파일 전체를 서빙하고, `DefaultDocuments`는 디렉토리 요청일 때만 적용된다.
- `milkit.psm1`의 정적 파일 content-type 매핑에는 이미지(`.svg`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.ico`)와 폰트(`.woff`, `.woff2`)가 포함된다.
- 빠른 확인용 스크립트는 `smoke-test.ps1`, `smoke-test-io.ps1`, `example-io-crud.ps1`에 있다.

## Open Notes

- `Use-Static` 동작을 바꾸면 `milkit`을 쓰는 하위 프로젝트 라우팅 계약에 바로 영향이 간다. 변경 전 호출처를 먼저 확인한다.
