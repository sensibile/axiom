# 독립 검증 후 로컬 Git 설정 보완 (2026-10-02)

## 실제 결과

- 최종 precommit/review: exit 12, Credo strict 실패. 포맷 및 dev/test compiler warnings gate는 통과.
- Credo 1.7.19: 5건 (복잡도/중첩 2, 숫자 표기/moduledoc 3). 전 check를 기본 strict 정책으로 실행했으며 warning 억제/config 예외는 추가하지 않았다.
- Dialyxir 1.4.7 / Dialyzer: 별도 실제 실행 exit 0, Total errors 0, Skipped 0.
- 최종 review는 Credo에서 중단하므로 연결된 Dialyzer/회귀를 gate 내부에서 실행했다고 주장하지 않는다.
- 별도 동적 실행: Domain 빠른 3개 및 기존 전용 127.0.0.1:55439/axiom_test 전체 16개 통과. 다른 DB는 사용하지 않았다.
- 기존 vendor DBConnection deprecated xref 경고는 보존했다. 제품 로직, 테스트, 벤더 소스는 수정하지 않았다.

## Hook 검증과 한계

`.githooks/pre-commit`은 git diff로 unstaged tracked 변경 및 non-ignored untracked 파일을 검사하고 발견하면 거부한다.
부분 staging을 지원하지 않으며 실제 index를 자동 stage/stash/수정하지 않는다.
임시 격리 저장소에서 staged 문법 오류/working tree 정상 상태 거부(1), 일치한 정상 상태 통과(0),
검사 실패 전달(7), untracked 상태 거부(1)를 확인했다 (`fixture-results.json`).
실제 Elixir compiler fixture에서도 mismatch 거부, matching 정상 통과, matching 문법 오류 거부를 확인했다 (`real-hook-results.json`).
이 fixture는 hook의 경로/판정 검증이며 제품 suite 성공의 대체 근거가 아니다.
검사는 atomic snapshot이 아니므로 실행 중 동시 편집은 지원하지 않는다. Git의 assume-unchanged/skip-worktree 같은
숨김 플래그 사용은 이 정책의 보장 범위 밖이다. ignore된 의존성/PLT/전용 DB는 index 외 실행 의존성이다.
직접 scripts/check 실행은 working tree 검사이며 hook의 index 일치 검사를 수행하지 않는다.

## Ignore와 의존성

SQLite3 WAL/SHM, 프로젝트 `/data/rocksdb/`, `.aws/credentials`, `.npmrc`, 재귀 crash dump 및 프로젝트 cache를 추가했다.
fixture probes에서 예제 설정, SQL fixture, 문서, 재현 코드는 계속 보인다. 예제 certificate/key와 test fixture 예외도 추가했다.
ignore는 이미 추적되거나 강제 추가한 비밀을 보호하지 않는다. 비밀 값은 출력하지 않았다.

공식 Hex 로컬 캐시를 vendor에 추가했다. Credo/Dialyxir와 도구 의존성은 dev/test, runtime false이다.
기존 Axiom Jason 런타임 의존성은 유지했다. 패키지 내부 CHECKSUM과 공식 Hex 공개 API archive checksum을 확인했다.
버전/SHA-256는 `dependency-provenance.json`, 라이선스/원본 metadata는 vendor에 보존한다.
전역 설치, credentials/identity/보안 설정 변경, 다운로드 의존성 설치는 하지 않았다.
PLT core 및 project cache는 프로젝트 `.cache/plt` 아래만 사용한다 (`project.plt`는 설정상 디렉터리 이름).
precommit은 Credo strict, review는 추가 Dialyzer를 실행한다. 첫 PLT 생성은 수십 초, 이후는 cache를 사용한다.

## 현재 변경과 Git 상태

두 repo root는 기존 요청 경로 그대로이며 `.git`은 각 루트에 있다. main, 커밋 없음, index 없음/ls-files 비어 있음.
따라서 첫 커밋 전에 사용자가 추적할 파일을 검토·stage해야 hook이 진행된다. 지금 hook 거부는 의도한 정책이다.
이번 보완 변경: `.githooks/pre-commit`, `.gitignore`, `LOCAL_GIT.md`, `scripts/check`,
mix.exs, 새 vendor devtools, 이 evidence 경로.
기존 독립/구현 증거는 그대로 보존했다. Atheum/상위/Alaya, commit/remote/push/global config 변경 없음.

## 남은 blocker

Credo 기존 지적 때문에 커밋/리뷰 gate는 현재 실패한다. 해당 정리가 끝나기 전 gate 통과로 보고할 수 없다.
타입 오류 0개는 전 입력 정확성이나 보안 검증 완료를 의미하지 않는다.

도구 문서: [Credo](https://hexdocs.pm/credo/overview.html), [Dialyxir](https://hexdocs.pm/dialyxir/readme.html).
