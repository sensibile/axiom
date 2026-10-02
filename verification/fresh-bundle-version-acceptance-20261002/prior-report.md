# Fresh 독립 revision bundle 검증

판정: 조건부 조회의 상태 변경/ABA/과거 정책/current 사실/snapshot 경계에서 관찰된 false not_modified 없음. **잘못된 float schema version을 받아 not_modified로 반환하는 계약 위반 1건 재현. 수정하지 않았다. 수용 완료 판정은 보류한다.**

## 독립 기대 계약과 발견

README의 Resource revision bundle conditional retrieval 및 Axiom.resource_snapshot, Scope, Store, SQL을 읽어 기대값을 도출했다. 작성자 보고 수치나 기존 테스트 assertion을 독립 oracle로 사용하지 않았다. 적용 가능한 ancestor/axiom AGENTS.md를 찾지 못했다. Domain/Scope의 순수 검증과 Store/service의 PostgreSQL shell 분리는 유지된다. 한국어 보고서를 작성했다. 읽기 검증만 수행하므로 worktree 생성/제품 편집 skill은 적용하지 않았다.

완전한 map은 tenant, 정확한 4필드 scope, principal, current/explicit release 선택에 묶인다. 동일 snapshot에서 freshly constructed map과 같을 때만 not_modified, 다르면 changed+새 데이터다. tenant-wide assignment revision은 역할/주체/scope 등록, assignment/relation grant·revoke·no-op, principal suspension·resume 모두에서 증가한다. publish/rollback은 policy generation을 증가시키며 같은 내용 재발행도 새 release를 갖는다. draft 저장만으로 현재 PRP bundle은 바뀌지 않는다. release 선택은 고정해도 head/generation 및 현재 사실은 계속 반영한다.

**F1 — strict version 타입 검증 누락 (낮은 correctness 심각도):** lib/axiom/scope.ex:56–57은 `== 1`, `== 2`를 사용한다. lib/axiom.ex:530의 전체 map 비교도 `==`다. 정상 조회의 bundle에서 `Map.put(bundle, "bundle_schema_version", 1.0)` 또는 `Map.put(bundle, "data_schema_version", 2.0)`를 전달하면 두 경우 모두 `{:ok, %{ "status" => "not_modified", ...}}`다. 문서의 wrongly typed → invalid_revision_bundle 계약과 다르다. float 값 자체가 권한 상승이나 인증 우회를 의미하지는 않는다. 정상 데이터의 반환 타입은 정수다. probe.exs의 별도 float 테스트와 probe-final-2.raw에 두 최소 재현이 있다. 최초 발견 즉시 알렸고 제품 수정 없음.

## 실환경 및 격리

읽기 전용 docker inspect로 `/axiom-dev-test-pg-20261002`, postgres:17-alpine, running, 127.0.0.1:55439→5432 확인. DDL 전 실제 연결에서 database/user axiom_test, server port 5432, server_version_num 170010 확인. 실제 주소는 container 192.168.215.2/32이다. 모든 새 DDL/fixture 및 기존 회귀는 새 `axiom_independent_bundle_20261002` schema에서만 수행했다. fixture는 random run namespace로 분리했고 raw에 기록했다. 기존 test_helper는 호출하지 않고 테스트 모듈만 원본 그대로 load하며 :test_conn에 독립 연결을 주입했다. 지정 외 DB/기존 schema/public fixture 쓰기, Git 설정/commit, global install, credentials/권한 변경, NAS/sibling 수정 없음. 연결 credential 값을 보고서에 기록하지 않았다.

각 실행 전후 public 모든 테이블의 정렬된 JSON 행을 비교했다. raw의 public_preserved는 모두 true다. 기존 schema에는 DML/DDL을 수행하지 않았다. before.json 및 preservation.json으로 lib/test/priv/scripts/vendor/주요 문서 원본 hash 보존을 확인한다. _build/PLT는 기본 검사에서 생성되는 로컬 cache다.

## 검증과 정확한 명령

cwd는 /Users/tonton/Documents/workspace/alaya/axiom. seed는 모든 새 ExUnit 실행 20261002이며 기존 reference 모델도 고정 seed 20261002/240 steps를 raw로 기록한다. Elixir 기존 로컬 의존성만 사용했다. sandbox의 Docker/Mix TCP/PG 접근 차단 후 승인된 require_escalated 실행을 사용했다.

- `docker inspect --format '{{.Name}} {{.Config.Image}} {{.State.Running}} {{json .NetworkSettings.Ports}}' axiom-dev-test-pg-20261002` — 신원 PASS (응답 위 기술; 첫 sandbox 시도는 permission denied).
- `scripts/check check` — format check, dev/test force compile warnings-as-errors, Credo strict. **PASS**, final command exit 0, Credo 0 issues. static-final.raw.
- `mix dialyzer` — **PASS**, final command exit 0, total errors 0. dialyzer-final.raw.
- `MIX_ENV=test mix run verification/fresh-bundle-independent-20261002/regression.exs` — 기존 전체 suite 28 + 독립 모델/경계 9개, **PASS 37**, final command exit 0, public_preserved true. regression-final.raw. helper 우회 이유는 기존 데이터 변경 금지다. scripts/check review 원문은 기존 helper DDL을 호출하므로 대신 동일 단계들을 독립 schema에서 실행했다.
- `MIX_ENV=test mix run verification/fresh-bundle-independent-20261002/probe.exs` — 최종 **3/4 PASS, 1 FAIL**, exit 2, probe-final-2.raw. FAIL은 F1.
- `MIX_ENV=test mix run verification/fresh-bundle-independent-20261002/negative.exs` — **2/4 PASS, 2 FAIL**, exit 2, negative-final.raw. F1 및 snapshot barrier가 FAIL. 원본 Store 소스 문자열을 읽어 실행 중 VM에서만 READ COMMITTED로 재컴파일한다. 제품 파일/beam 저장 수정 없음.

probe.raw은 최초 3테스트 PASS, probe-final.raw는 float 경계 추가 후 1 FAIL을 보존했다. negative.raw의 최초 barrier는 writer가 독자 조회 완료 후의 필드를 바꾸지 않아 snapshot 약화를 탐지하지 못했다. 이를 충분한 증거로 삼지 않았다. 최종 barrier는 reader가 scope registry SELECT의 실제 PG Lock wait 상태에 도달한 후 writer가 publish + assignment revoke + suspension을 하나의 transaction으로 커밋한다. 현재 RR 구현은 old bundle과 not_modified; 약화된 READ COMMITTED는 old generation과 새 revoked assignment가 혼합되어 changed, 기대 assertion 실패다. barrier를 보완한 final 실행만 snapshot 탐지력 증거다.

## 범위별 결과

- 독립 10단계 event trace: assignment grant/revoke/regrant/no-op, relation grant/revoke/regrant, suspension/resume/no-op은 매 단계 revision +1과 changed+동일 새 데이터 PASS. 같은 내용 재발행/rollback은 pinned release 유지, head/generation 변화 PASS. historical 선택에서 현재 revoked/suspended PASS.
- missing 모든 필드, 각 필드 list 타입, nil/빈/추가/음수/잘못된 etag, input binding principal/tenant/scope/selection 변조, 조건 조합 거부 PASS. schema float 타입은 F1 FAIL.
- 같은 local ID의 다른 space/scenario/tenant 및 다른 principal binding 거부 PASS. 다른 tenant 주체 변경은 not_modified PASS. 다른 주체의 assignment 변경은 데이터 grant가 동일해도 tenant revision 때문에 changed PASS: 이는 문서상 보수적 false invalidation이며 주체 변경의 false not_modified와 구분한다.
- 기존 atomicity/CAS/동시 publish 및 paired reader 회귀는 새 schema에서 수행했다. 전 interleaving, 장기 soak, 네트워크 장애/COMMIT ambiguity는 UNRUN.
- bundle은 인증토큰/권한 승인/서명 자료가 아니다. forged version/counter가 허용되는지와 현재 데이터 같음 여부만 검증한다. README의 check 이후 실제 use TOCTOU는 consumer enforcement obligation이라는 설명이 정확하다. 실제 사용 TOCTOU 해결 주장은 없다. Akashic QueryCut·데이터 버전·외부 PDP/PEP·production 인가/권한/RLS는 UNRUN/범위 밖.

검증 산출물 완료 후 편집 정지. 남은 수용 blocker는 F1이며 수정 권한을 사용하지 않았다.
