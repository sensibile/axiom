# 독립 최종 수용 검증 — 2026-10-02

대상: `/Users/tonton/Documents/workspace/alaya/axiom`. 실제 Git root, main, local core.hooksPath=.githooks 확인. HEAD/main 커밋 없음. 원격 없음. 실제 index/commit/remote/global config 변경 없이 검사했다.

Source 및 보호 파일 SHA-256 전후 동일: True / True. 전체 per-file source hash와 ignore 판정은 metadata.json, 실제 명령·exit·raw는 results.json 및 *.raw에 보존했다.

## 실행 결과

- `./scripts/check precommit`: exit 0.
- `./scripts/check review`: exit 0.
- hook `/Users/tonton/Documents/workspace/alaya/axiom`: exit 1; 상세 raw는 results.json.
- hook `/var/folders/qp/t82xjwzj40scks9jv1nwlhv00000gn/T/axiom-staged-wx41coye`: exit 1; 상세 raw는 results.json.
- hook `/var/folders/qp/t82xjwzj40scks9jv1nwlhv00000gn/T/axiom-staged-wx41coye`: exit 0; 상세 raw는 results.json.
- hook `/var/folders/qp/t82xjwzj40scks9jv1nwlhv00000gn/T/axiom-staged-wx41coye`: exit 1; 상세 raw는 results.json.
- hook `/var/folders/qp/t82xjwzj40scks9jv1nwlhv00000gn/T/axiom-staged-wx41coye`: exit 7; 상세 raw는 results.json.

격리 복사본은 동일한 최종 소스와 hook을 복사하고 자체 index만 staging했다. 깨진 제품 파일을 stage한 뒤 working tree만 정상 파일로 돌려놓은 상태는 거부했다. 정상 전체 staging 상태의 hook 실행, 비ignore untracked 거부, 실제 hook의 child exit 7 전달도 확인했다. 실제 프로젝트의 모든 소스는 아직 untracked이므로 실제 hook은 의도적으로 1을 반환한다. 직접 scripts/check는 index 일치를 검증하지 않는다.

Rust 빌드는 `.cache/independent-acceptance-local-20261002/target`, Mix 빌드는 `.cache/independent-acceptance-local-20261002/mix-build`를 사용했다. 기존 캐시를 APFS clone으로 복제했으며 기존 실행 바이너리 hash가 유지됐다. 설치 없이 기존 오프라인 의존성을 사용했다.

격리되지 않은 첫 sandbox 실행은 Mix TCP 잠금 EPERM에서 비영 종료했다. `../independent-acceptance-20261002`에 해당 실패 raw와 미실행 후속 stage를 보존한다. 로컬 실행 권한으로 재실행한 이 결과와 구분해야 한다.

## 동작·검사 범위

최종 scripts/check의 실제 precommit/review 명령을 실행했다. format은 소스를 쓰는 `format` 모드 대신 cargo fmt --check / mix format --check-formatted로 검사했다. Rust Clippy -D warnings(akashic만), Elixir dev/test warnings-as-errors, Credo --strict, Dialyzer 및 빠른/실제 IO/전체 회귀의 실행 증거는 raw에 있다. 정적 코드 검토에서 제품의 무차별 lint 억제, Dialyzer ignore 파일 또는 test skip을 발견하지 않았다. integration 태그 제외는 빠른 gate에만 사용하고 review에서 실제 실행한다.

기존 minimal-cleanup.patch와 실제 최종 코드를 비교했다. Request guard·검증 순서를 보존한 helper/alias, Axiom policy 검증 helper 및 같은 transaction handle/SQL의 publish_release 추출이다. 기존 순수 module snapshot과 현재 소스를 로드한 독립 비교 결과는 equivalence-recheck.json에 있다. 처음 module을 로드하지 않은 재현 실패도 results.json에 보존하며 수정 재실행 결과로 대체해서 해석한다. 동등성은 샘플 입력 범위의 증거이며 전체 공간의 증명이 아니다.

DB, credential 파일, cache/artifact ignore와 정상 JSON/key/certificate fixture 및 .env.example의 비ignore를 git check-ignore --no-index로 확인했다. 이는 fixture가 현재 실제 index에 추적되고 있음을 뜻하지 않으며, 최초 stage 여부는 사용자 결정이다. ignore는 비밀 scanner가 아니며 강제 stage를 방지하지 않는다.

## 수용 및 미검증

hook 정책은 정상 index/working-tree 일치 상태의 검사이며 atomic staged snapshot은 아니다. 동시 편집, assume-unchanged/skip-worktree 같은 숨김 플래그, ignored runtime dependency 무결성, 보안 전수 감사·배포/운영 준비는 미검증이다. 현재 실제 index는 없으므로 숨김 플래그가 적용된 tracked file도 없다. 실제 PostgreSQL/RocksDB 테스트 통과를 무조건 보안/운영 준비 완료로 확대하지 않는다.

Axiom 특이점: gate fast()는 `_build/test`를 hardcode하여 MIX_BUILD_PATH override를 따르지 않는다. 원래 경로의 빌드를 교체하지 않았다. 별도 최종 build 경로에서 Domain 빠른 테스트를 추가 실행한 fresh-build-fast.json으로 보완해야 한다. mix check alias는 Credo/Dialyzer를 포함하지 않으므로 scripts/check가 공식 완전 gate이다. Rust는 프로젝트에 없으므로 Clippy 해당 없음.

별도 최종 build fast: exit 0, Domain 3개 통과. 전체 review raw의 실제 PostgreSQL 전체 회귀 테스트 요약: Result: 3 passed; Total errors: 0, Skipped: 0, Unnecessary Skips: 0; Result: 16 passed

격리 저장소의 index와 working tree 모두 깨진 동일 소스로 만든 실제 format 오류도 hook exit 1로 전달됐다 (actual-format-failure.json).

최종 수용: 필수 precommit/review 및 정상 staged hook은 모두 exit 0. 깨진 staged/수정된 working tree, nonignored untracked, 실제 formatter 오류는 거부, child exit 7은 보존했다. 위 명시된 제약 안에서 개발 gate를 수용한다. Axiom 별도 build의 빠른 테스트는 추가 검증으로 보완했으며 hardcoded 경로를 고치지는 않았다. 보안/운영 준비 완료 판정은 하지 않는다.

Raw 보존: Akashic child tool의 잘리지 않은 전체 stdout/stderr와 command/exit는 precommit-stages 및 review-stages 폴더에 보존했다. Axiom shell의 전체 출력은 precommit.raw/review.raw에 있다.
