# Axiom exact resource scope — 구현자 검증 (2026-10-02)

로컬 한 기능 단위 구현·검증 완료, 편집 중단. fresh 독립 수용 검증은 pending이다.
소스는 `/Users/tonton/Documents/workspace/alaya/axiom`, branch main, committed HEAD 없음.
worktree-first-dev SKILL.md를 읽었고 사용자 예외 승인대로 최초 commit/worktree 없이 기존 checkout에서 진행했다.
Git stage/index/commit/config/remote/push/merge/배포/전역 설치, credential/권한 변경은 하지 않았다.
형제 Alaya/Akashic/Atheum에는 쓰지 않았다. 기존 untracked 파일을 보존한 상태의 변경 목록은 source-change-manifest.json에 있다.

## 선택 단위와 구현

PAP 명시 자원 등록 + 현재 직접 할당/관계 변경 + PRP 명시 scope snapshot이다.
`{tenant_id, space_id, scenario_id, local_id}` 전체 문자열 tuple을 immutable registry에 저장한다.
missing/type/unknown-key/noncanonical/wildcard/physical-field 입력을 거부하며 default/inheritance/cross-scope grant가 없다.
기존 node adapter key는 canonical tuple SHA-256 앞 63 hex에 `r` 접두사를 붙인 내부 값이다.
registry의 전체 tuple unique, tenant/node unique, node FK와 매 lookup의 예상 key 일치 검증을 사용한다.
기존 node와 digest adapter key 충돌 시 원자 거부하며 alias/overwrite하지 않는다. 실제 암호학적 collision을 생성한 시험은 아니다.

신규 공개 API: `register_resource_scope/5`, `put_resource_assignment/7`, `put_resource_relation/7`,
`resource_snapshot/4`(기본 opts 생략 시 /3). 등록·변경은 기존 tenant CAS/audit/bigint 규약을 재사용한다.
등록의 node+registry+revision+audit는 같은 transaction이다. registry UPDATE/DELETE는 immutable trigger가 거부한다.
할당/관계의 원래 audit payload는 내부 node key를 유지하고 명시 조회 응답의 scope/object는 전체 tuple로 반환한다.
정책 DSL schema 1, 기존 publication CAS/idempotency/immutable release는 변경하지 않았다.
PAP가 scope를 등록했다는 사실은 특정 정책 효과의 승인이나 평가가 아니다.

명시 조회는 schema 2와 `resource_scope`, `policy_head_release_id`, `consumer_contract`를 반환한다.
같은 repeatable-read snapshot에서 선택한 immutable `policy.release_id`, **현재** head generation 및 assignment revision,
회수 facts와 주체 정지를 반환한다. 선택 정책이 과거여도 현재 authority facts를 과거로 되돌리지 않는다.
한 scope의 직접 할당/관계만 포함하며 다른 resource나 team membership으로 권한을 추론하지 않는다.
QueryCut/데이터 snapshot version은 입력 옵션으로 받지 않고 Axiom revision과 대응시켜 인증하지 않는다.

수정 파일: lib/axiom.ex, lib/axiom/store.ex, lib/axiom/test_database.ex, priv/schema.sql,
README.md, PAP_PRP_DESIGN.md, VALIDATION.md. 신규: lib/axiom/scope.ex, test/resource_scope_test.exs.
Domain, 기존 test/verification 모델, scripts/check, mix.exs, vendor는 before/after SHA-256이 동일하다.
`before-sha256.json`/`after-sha256.json`은 정확한 파일 hash, `artifact-sha256.json`은 산출물 hash다.

## 최종 실행 증거

Elixir/Mix 1.20.4, OTP 29. Docker inspect에서 전용 axiom-dev-test-pg-20261002,
postgres:17-alpine, running, 127.0.0.1:55439→5432를 확인했다.
prepare 전에 DB/user/server port/PostgreSQL major identity를 확인하며 실패하면 schema DDL을 실행하지 않는다.
최종 실측 identity는 database-identity.json: axiom_test/axiom_test, PostgreSQL 17.10,
server port 5432, current schema axiom_resource_scope_20261002, head FK 1, scope immutable trigger 1.
기존 DB/fixture를 reset/drop하지 않고 runtime search_path로 새 namespace에 전체 회귀를 격리했다.
schema.sql의 FK/trigger 존재 검사를 current schema/table로 제한해 public의 동명 객체로 검사가 생략되지 않게 했다.
DB/role 설정·인증 변경은 없다. namespace는 독립 reviewer를 위해 보존한다.

- 최종 `scripts/check review`: exit 0. format check, dev/test warnings-as-errors compile,
  Credo strict 지적 0, 빠른 Domain 3 passed, Dialyzer errors 0, 실제 PG 전체 26 passed.
  final-review.log: 전체 회귀 seed 579845, 2.4초. 시간은 suite 실행 관찰이며 성능 SLA/처리량 측정이 아니다.
- `mix test verification/counter_boundary_test.exs verification/independent_test.exs --seed 20261002 --warnings-as-errors`:
  exit 0, 9 passed, bigint 원래 3 재현+기존 240단계 PRNG oracle 유지. legacy-independent-regression.log.
  기존 독립 검증을 재실행한 것이며 이번 변경에 대한 fresh 독립 reviewer 결과는 아니다.
- 초기 scope suite 23 passed는 initial-tests.log, 첫 Credo 실패(복잡도 11>9)는 initial-credo-failure.txt.
  scope lookup/binding helper 분리 후 해결했으며 lint/type 억제는 추가하지 않았다.
- sandbox의 Mix TCP lock EPERM과 Docker socket 접근 거부는 승인된 로컬 실행 권한으로 해소했다.
  자동 승인 review가 action을 거절한 사건은 없다. 기존 vendor DBConnection xref deprecation은 그대로 남았다.
- public의 axiom 테이블 9개에 대해 row count와 정렬된 row-text digest가 전후 동일하다(public-preservation.json).
  baseline은 첫 **격리 schema** suite 이후, final gate/legacy 회귀 전이다. initial run 이전 전체 DB fingerprint를
  보유했다고 주장하지 않는다. raw 비교의 최초 실패는 before 파일의 Mix compile stdout 때문이며 원본 raw와
  JSON 비교를 함께 보존했다. final 전체 실행 후에도 기존 public contents가 동일하다.

## 주장별 oracle / 한계

| 주장 | 목적별 실행 증거 | 한계 |
| --- | --- | --- |
| scope 타입·정규 입력 | 공개 등록/변경/조회에 missing/extra field, nil/int/invalid UTF-8, uppercase/whitespace/65 bytes/wildcard를 제출, history 불변 확인 | opaque lower ASCII ID 규약. Unicode/URL path normalization, parser duplicate JSON key는 미지원 |
| logical identity 분리 | 동일 local ID의 두 tenant, 두 space, fork scenario 조회. 정확 tuple facts/ETag 분리, 다른 tuple empty | scenario 자체를 만들거나 Akashic incarnation을 확인하지 않음 |
| collision·immutability | 기존 node에 예상 adapter key를 선점한 후 등록 거부, history/node 확인. duplicate 등록 실패, registry raw UPDATE 실패 | 실제 digest collision·DB owner trigger 우회 미검증 |
| 과거 policy/현재 회수 | 두 release 후 assignment/relation revoke+principal suspend; 이전 release 조회, rollback 모두 current revision=8/revoked/suspended 유지 | 과거 정책의 권한 확대/호환성 판단은 외부 PDP 책임 |
| ETag와 소비자 계약 | scope별 ETag 차이, 과거 정책 pin 상태에서도 회수/정지 뒤 ok+새 ETag, fresh 동일 조회만 not_modified | TTL, clock, 발급된 컨텍스트 무효화·실제 consumer 검증 미구현 |
| stale CAS/concurrency | 공개 scoped assignment 경쟁 2개: 성공 1/conflict 1; stale relation 오류, unknown scope/role mutation 0 | 모든 scheduler interleaving/장기 경합은 아님 |
| 원자 오류 | 실제 PG tenant별 audit trigger가 등록 마지막 단계에서 23514/XX000 주입: constraint/database, node+registry+revision+history 모두 rollback; trigger 제거 후 동일 CAS 재시도 성공 | 네트워크 COMMIT 응답 유실/kill/fsync/power-loss의 unknown은 미주입. database 오류를 확정 미커밋으로 일반화하지 않음 |
| bigint/기존 멱등성 | max-1→max scoped assignment 성공; max에서 revoke/register exhaustion, max+1 invalid. 현재 facts 조회 유지. 기존 counter/publication retry suite 포함 | sequence exhaustion, 실제 수십억 increment, 운영 복구 미검증 |
| 독립 scope oracle | 3 scope에 60 step 변경, 매 step 전체 3 scope 직접 map 기대값과 current revision 비교(180 조회). oracle는 생산 SQL/digest/Scope helper를 재사용하지 않음 | 유한 결정 trace, fresh reviewer나 exhaustive proof 아님 |
| 같은 snapshot | scoped paired writer 30 transaction(current assignment+principal) vs reader 90회: revision parity/status 독립 관계 검사; publisher 20회 vs current/historical reader 70쌍: head-release/body parity 확인 | scheduler 전부, 강제 모든 경합, mutation sensitivity는 fresh 독립 검증 대기 |
| 기존 계약 보존 | 기존 16개 service/domain/counter suite와 별도 bigint+240단계 모델 재실행 | 외부 API/HTTP adapter/authz는 기존에도 없고 이번에도 추가하지 않음 |

## 하위 소비자 계약과 미검증

`consumer_contract`는 token/decision이 아니다. 소비자는 신뢰된 authenticated tenant/principal과 정확 tuple,
선택한 policy.release_id/schema/현재 head 선택 허용 규칙, current policy_generation 및 assignment_revision,
현재 suspension을 검증해야 한다. ETag를 가진 과거 response만으로 freshness를 승인할 수 없다.
회수 이후 새로 시작한 snapshot은 새 사실을 반환하나 이미 진행 중인 snapshot/발급된 context에는
별도 revalidation/TTL/clock/failure contract가 필요하다. missing policy, lookup/database failure,
unknown schema와 binding mismatch를 default allow로 바꾸면 안 된다.

Akashic의 table snapshot/source/recovery/manifest/data cut, reservation/retention/coverage 확인은
외부 책임이며 이번 response에 확인한 cut으로 넣지 않는다. logical tenant/space/scenario는 physical DB/table/shard/domain과 무관하다.
제품 의미가 필요한 후속 질문: 어떤 과거 policy 선택을 실제 소비자가 허용할지, resource local ID와 incarnation을
어떻게 연결할지, context의 revalidation/TTL/회수 SLA를 얼마로 정할지. 이 작은 관리·조회 단위의 완료를 막는 질문은 아니다.

scope-specific policy DSL, scenario inheritance, 권한의 제품 효과/PDP/PEP, Arbiter/context issuance/signing,
credential/authentication/management-authority 변경, Akashic 연동/수정, HTTP/운영 노출, RLS/DB least privilege,
분산 cut/대규모/장애 복구/성능 보장/전면 보안 검증은 수행하지 않았다.

읽은 지침/자료: worktree-first-dev SKILL.md, Axiom PAP_PRP_DESIGN.md/README/VALIDATION 및 verification final,
읽기 참조한 Akashic AGENTS.md/docs/elixir.md/docs/work-loop.md(FC/IS),
/tmp/akashic-iceberg-first-snapshot-delta-contract-20261002.md,
/tmp/akashic-fri24-large-storage-architecture.md. Axiom/상위 경로에 적용할 AGENTS.md나 .agents/docs가 없음을 확인했다.
이 보고서·hash 작성 후 편집을 멈춘다. fresh 독립 검증 수용/추가 요청 전에는 더 구현하지 않는다.

## 최종 변경 source SHA-256

| 파일 | SHA-256 |
| --- | --- |
| lib/axiom.ex | `97f2a6df29eb8f1e8b837758a24836fdd6653390c318b46bcce794f6a5ceec66` |
| lib/axiom/store.ex | `d755552700d1bf70e718d6c5f4472528c8c0bec6fd628e4263e35eae7a9dcbf4` |
| lib/axiom/test_database.ex | `91fbd7f509cbb26bf0b7e938e4c85b49ed34194e4b752378d9ddc3f431bfeb10` |
| priv/schema.sql | `47c1071eab20d26b469df1f3a07f7844c3cb83d24a20ff7e7ec5a1dda812c1a0` |
| README.md | `c16a4498fe5c5b0532d92417160ce8a3c7b678c79c2f02ab26c035cb0ab006a7` |
| PAP_PRP_DESIGN.md | `d27c2be840cbb68a8461940b53b1ea047b10d8f02393f6d7e74223d60a9a7017` |
| VALIDATION.md | `498020df3075d58e0439dea644892f9c77e49d5b027a541b1ec3d1e59df9e021` |
| lib/axiom/scope.ex | `ad06f9d6fae3ef848a51cc6d10d2bc2353a4f2b79bdca9a42ada765be2d82e94` |
| test/resource_scope_test.exs | `0ea5757d113b4440b01d423a588f89a7ee7d4493536cd039896f5cab364176ff` |
