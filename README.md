# axiom — 첫 PAP/PRP 수직 기능

로컬 Git의 필수 검사는 [LOCAL_GIT.md](LOCAL_GIT.md)의 `scripts/check precommit`과
`scripts/check review`를 따른다. Credo/Dialyzer 및 최초 staging 정책과 최종 검증 근거도 이 문서에 연결했다.


Elixir + PostgreSQL의 로컬 서비스 경계다. 정책 draft 검증·발행·현재/버전 고정 조회와 직접 역할/관계 관리, 주체 정지, 독립 revision·이력을 구현했다. gateway는 외부 소비자다. HTTP 서버·UI·토큰·서명·사용자 인증 미들웨어·인가 평가·하위 집행은 없다.

## 재현

기존 Elixir 1.20/OTP 29, `psql`, Docker가 필요하다. 의존성은 기존 Hex 캐시에서 가져온 프로젝트 내부 `vendor/` 소스를 사용한다. 전역 설치와 네트워크 패키지 다운로드는 없다.

```sh
cd /Users/tonton/Documents/workspace/alaya/axiom
# 최초 생성에만 실행. 이미 이 이름의 컨테이너가 있으면 새로 만들지 않는다.
docker run --detach --name axiom-dev-test-pg-20261002 \
  --publish 127.0.0.1:55439:5432 \
  --env POSTGRES_USER=axiom_test \
  --env POSTGRES_PASSWORD=axiom_local_only \
  --env POSTGRES_DB=axiom_test postgres:17-alpine
# 기존 전용 컨테이너가 중지돼 있을 때만:
# docker start axiom-dev-test-pg-20261002
mix deps.compile
mix axiom.db.setup
mix check
mix xref graph --format stats
mix axiom.measure
```

고정 테스트 주소는 `127.0.0.1:55439/axiom_test`다. 테스트 setup은 이 DB에만 비파괴 CREATE를 실행한다. 기존 5432/5433 DB는 사용하지 않는다. 테스트는 무작위 tenant 이름을 사용하고 감사·release는 보존한다. 실패 주입 테스트는 전용 DB에 임시 trigger를 생성하고 `after`에서 제거하므로 같은 전용 DB에 여러 테스트 프로세스를 동시에 실행하지 않는다. 컨테이너 정리·DB 삭제는 자동 수행하지 않는다.

sandbox에서 Mix 로컬 TCP 잠금이나 Docker/루프백 접근이 막히면 해당 로컬 실행 권한이 필요하다. 실행 권한은 전역 설정 변경을 뜻하지 않는다. 서비스 리스너는 생성하지 않는다.

## 정책 형식과 선택 근거

```elixir
body = %{
  "schema_version" => 1,
  "rules" => [%{
    "effect" => "allow", "role" => "reader",
    "actions" => ["read"], "resource_kind" => "document"
  }]
}
```

v1은 정해진 키만 허용한다. rule 1..100개, action 1..32개, 식별자 1..64 byte의 소문자 ASCII 이름을 허용한다. 역할은 같은 tenant의 등록된 역할이어야 한다. effect는 allow/deny, resource_kind는 document/project다. 지원하지 않는 조건·코드·schema는 거부한다. 이는 저장·참조 검증 형식이며 rule 순서·allow/deny 우선순위 등 **평가 의미는 미정**이다. 범용 DSL·PDP를 만들지 않기 위한 보수적인 초기 선택이다. map 입력만 수용하여 JSON 중복 키 문제를 wire API에 숨기지 않는다. 추후 JSON parser 도입 시 중복 키 거부를 따로 설계해야 한다.

정책 digest는 v1의 재귀 키 정렬 JSON과 SHA-256이다. 외부 canonicalization 표준을 구현했다는 주장은 하지 않는다.

## 서비스 계약

`Postgrex.start_link(Axiom.TestDatabase.options())`로 얻은 conn을 첫 인자로 전달한다. 모든 함수는 정상 처리 시 `{:ok, result}`, 검증/충돌/조회 실패 시 `{:error, reason}`을 반환한다. DB 연결 자체의 장애·timeout은 호출자 프로세스 오류가 될 수 있고 프로덕션 재시도/장애 응답 계약은 미정이다.

이 경계의 caller는 **신뢰된 관리자 또는 조회 adapter**다. tenant·actor는 호출자가 권한 확인 후 제공해야 한다. 현재 라이브러리에 사용자 인증/관리 권한 검증이 구현되었다는 뜻은 아니다. 외부 HTTP에 직접 노출할 수 있는 API가 아니다. 이후 axiom adapter 자체의 접근 통제는 axiom의 책임이며 gateway의 최종 사용자 인증과 구분한다. Store/raw SQL 접근은 내부·테스트용이다.

| 함수 | 명령·조회 |
| --- | --- |
| `create_tenant(conn, tenant)` | 신뢰된 bootstrap. 존재하면 같은 식별자 반환 |
| `register_role(conn, tenant, role, assignment_revision, actor)` | 안정적인 역할 이름 등록 |
| `register_node(conn, tenant, key, kind, assignment_revision, actor)` | person/service/team/document/project 등록 |
| `save_draft(conn, tenant, body, draft_revision)` | 생성 기대 revision=0. 저장마다 증가. schema·역할 참조 검증 |
| `draft(conn, tenant)` | 현재 draft 조회 |
| `publish(conn, tenant, draft_revision, policy_generation, request_id, actor)` | 불변 release·head·감사를 원자 저장 |
| `rollback_policy(conn, tenant, release_id, policy_generation, request_id, actor, reason)` | policy head만 전환. 할당·정지를 복원하지 않음 |
| `put_assignment(conn, tenant, principal, role, scope, status, assignment_revision, actor)` | person/service의 document/project 한정 직접 역할 할당. active/revoked |
| `put_relation(conn, tenant, subject, relation, object, status, assignment_revision, actor)` | person/service→team의 member 또는 →document/project의 owner |
| `set_principal_status(conn, tenant, principal, status, assignment_revision, actor)` | active/suspended. 정책 발행과 독립 |
| `snapshot(conn, tenant, principal, opts)` | 현재 또는 `release_id:` 고정 정책 + 현재 할당·관계·정지 상태 |
| `history(conn, tenant)` | 해당 tenant의 정책 발행·rollback 및 assignment 변경 이력 |

assignment revision은 tenant 전체 세대이며 역할·node 등록과 할당·관계·정지 변경 모두 증가시킨다. 각 변경과 이력을 한 transaction에 쓴다. 같은 기대 세대의 경쟁 변경은 하나만 성공한다. 정책 generation은 독립적이다. no-op 상태 변경도 감사와 새 revision을 남긴다. 회수는 원본 행을 삭제하지 않고 revoked로 표시한다. 재부여·재활성화는 명시적인 새 명령이다.

publish/rollback의 request_id는 tenant 안에서 유일하다. 동일 operation·인자·actor·기대 generation의 재시도는 **원래 결과**를 반환한다. 이미 더 최신 head가 있어도 최초 결과를 반환하므로 caller는 최신 head가 필요하면 다시 조회한다. 같은 request_id의 다른 명령·인자는 idempotency_conflict다. 할당 명령에는 요청 ID 멱등 캐시가 없고 기대 revision으로 중복 변경을 거부한다.

snapshot은 read-only REPEATABLE READ transaction에서 head, release, assignment revision, 현재 사실을 읽는다. 응답의 `data_schema_version`, `policy_generation`, `assignment_revision`, body/digest, 주체 상태와 모든 active/revoked 할당·관계는 **관리 데이터**다. suspended 상태여도 할당 사실을 숨기거나 허용 결정으로 바꾸지 않는다. `release_id:`는 **정책만** 고정하며 역사 시점의 할당 조회가 아니다. 외부 tenant release는 release_not_found다. `if_none_match:`가 같으면 status=not_modified와 ETag를 반환한다. 시간 지정 할당은 이번 구현에서 지원하지 않아 시간 경과에 따른 재계산은 아직 필요하지 않다.

policy rollback은 회수·정지·assignment revision을 변경하지 않는다. 이전 정책이 넓으면 현재 유효 구성원의 권한이 확대될 가능성은 남는다. 실제 평가·영향 분석·관리자 승인 workflow는 미구현이므로 외부 평가 주체와 후속 axiom 변경 비교 기능의 계약이 필요하다.

## FC/IS와 검증

`Axiom.Domain`은 DB/HTTP/process IO 없는 구조·참조·관계 검증과 canonical digest를 제공한다. `Axiom.Store`는 parameterized SQL·transaction·tenant 조회·현재 상태 이력을 담당하며 `Axiom`이 서비스 명령을 조정한다. 시각·난수는 core에 숨겨 넣지 않았다. 메모리 DB fake나 mock으로 PostgreSQL의 동시성·FK·원자성을 대체하지 않았다. 실제 PG 실패/경쟁/읽기 snapshot 회귀는 `test/service_test.exs`에 있다. 정답 불변식·증거와 미검증은 [VALIDATION.md](VALIDATION.md)에 정리했다.

## 의도적으로 남긴 제한

- 단일 정책 bundle/draft/head per tenant. 여러 channel, policy key 편집, 승인 workflow, 정책 영향 diff, draft 감사는 미구현.
- 직접 관계와 리소스 한정 역할만 지원. tenant/global scope, 상속·전이·cycle, 시간 구간 할당은 미정·미지원.
- 역할 정의와 node kind는 등록 후 수정/삭제 API가 없다. 활성 참조의 의미 변경을 보수적으로 제한한다.
- DB trigger는 UPDATE/DELETE를 막지만 관리 superuser의 TRUNCATE·trigger 제거·권한 우회까지 막지 않는다. 테스트 연결은 전용 DB owner이며 production 최소권한/RLS/백업/마이그레이션 운영은 미검증.
- 표준 DB 오류 category만 반환한다. 연결 장애 응답·backoff·관측성은 후속. 이력/조회 pagination·대규모 tenant revision 경합은 미검증.
- PIP 실연동·outbox/push/ACK·gateway/context/PEP/PDP·UI는 없다.

## 변경 파일

새 파일: `mix.exs`, `.formatter.exs`, `.gitignore`, `lib/axiom.ex`, `lib/axiom/domain.ex`, `lib/axiom/store.ex`, `lib/axiom/test_database.ex`, `lib/mix/tasks/axiom.db.setup.ex`, `lib/mix/tasks/axiom.measure.ex`, `priv/schema.sql`, `test/test_helper.exs`, `test/domain_test.exs`, `test/service_test.exs`, `README.md`, `VALIDATION.md`.

`vendor/`는 기존 캐시의 Postgrex 0.22.4, DBConnection 2.10.2, Decimal 3.1.1, Telemetry 1.4.2, Jason 1.4.5 원본 패키지 소스·라이선스다. 생성 `_build/`는 검사 산출물이며 소스 변경 목록에서 제외한다. 기존 설계 문서는 보존했다. 형제/상위 파일·Git·기존 DB·전역 설치·배포는 변경하지 않았다.

## bigint 카운터 경계 수정

revision/generation의 저장·조회·CAS 값은 PostgreSQL bigint 범위인 `0..9223372036854775807`이다. 마지막 값도 정상 조회·ETag·정책 버전 참조에 사용할 수 있다. draft revision 최댓값은 정책 발행 입력으로도 유효하다.

최댓값에서 **새 증가 명령**은 `{:error, :revision_exhausted}`로 변경 전에 원자 거부한다. 잘못된 범위/타입은 invalid_revision, 유효하지만 다른 기대 세대는 conflict다. assignment·draft·policy generation의 고갈은 각각 독립적이며 값을 초기화하거나 wrap하지 않는다. 최종 성공한 publish/rollback의 동일 요청은 캐시된 원 결과를 반환한다. 같은 request ID의 변경된 인자는 idempotency_conflict다. assignment에는 request ID 멱등 캐시가 없으므로 최댓값에서의 새 명령은 exhaustion이다.

회귀는 `test/counter_exhaustion_test.exs`이며 변경 증거·미검증은 [bigint 수정 보고](verification/bigint-fix-20261002/REPORT.md)에 있다. 카운터 고갈의 운영 복구/새 tenant 전환은 이번 correctness 수정 범위에 포함하지 않았다.

## Exact knowledge resource scope (local PAP/PRP)

`Axiom.register_resource_scope(conn, scope, kind, assignment_revision, actor)` registers a resource
with all four explicit string fields: `tenant_id`, `space_id`, `scenario_id`, `local_id`.
Only existing `document`/`project` kinds are supported. Identifiers use the existing lowercase
ASCII grammar, maximum 64 bytes; missing fields, extra physical/cut fields, wildcard and normalization
inputs are rejected. No default tenant/space/scenario, scenario inheritance or cross-scope grant exists.
Registration is immutable and consumes current tenant assignment revision, with audit and node creation
in one transaction. Duplicate identity/internal adapter key collision is an error; no replacement occurs.

`Axiom.put_resource_assignment(conn, scope, principal, role, status, revision, actor)` and
`Axiom.put_resource_relation(conn, scope, principal, relation, status, revision, actor)` reuse current
CAS, type, audit and bigint protections. The existing direct relation types apply; this is no new grant
or policy effect. The same local ID in another tuple is a separate resource. A scenario fork never copies
authority facts. No resource deletion, ID reuse/incarnation mapping or automatic Akashic discovery is implemented.

`Axiom.resource_snapshot(conn, scope, principal, release_id: id, if_none_match: etag)` explicitly reads
one registered resource. Both options are optional, unique and the only accepted options. It returns
schema 2 in the existing snapshot envelope, with the exact `resource_scope`, tuple-valued assignment
`scope` and relation `object`, and only direct facts for that resource. Team membership/other resources
are excluded; absence means no facts, never an inferred allow. The tenant policy body is still the existing
schema 1 kind-based policy; no scope-specific policy DSL or permission evaluation is added.

`data.policy.release_id` selects an immutable historical policy or current head; `policy_head_release_id`
and `policy_generation` always describe the current head in the same PostgreSQL repeatable-read snapshot.
`assignment_revision`, revoked facts and `principal_status` are always current at that snapshot, even for
historical policy reads or rollback. Registration is not shared publication of policy and assignments.
ETag includes exact identity, subject, policy selection/current head and current authority facts. A
`not_modified` result only answers this fresh Axiom query; it grants no offline cache lifetime.

The response `consumer_contract` is descriptive, not an authorization decision or token. Arbiter/PDP/PEP
consumers must verify the authenticated tenant/subject, exact scope, selected policy/schema compatibility,
current head policy-selection rules, current assignment/revocation revision, current suspension and freshness
at use. Consumers must choose their revalidation/TTL/clock/failed-query policy; Axiom supplies no expiry or
revocation SLA and does not refresh issued contexts. Missing policy, unknown schema, lookup/database failure
or binding mismatch cannot become broad/default authority. Historical policy choice does not restore grants.

Akashic QueryCut/Iceberg snapshot/source/recovery/manifest versions and retention/coverage are external,
unverified and independent of all Axiom revisions. Passing a QueryCut as an Axiom option is rejected.
Logical scope contains no physical table/shard/transaction-domain mapping. External integration and
credential/authentication/management-authorization changes remain outside this unit. Existing trusted
legacy APIs remain available and external adapters must use the explicit resource API for this contract.

Tests now verify dedicated PostgreSQL identity before DDL and use runtime search path
`axiom_resource_scope_20261002`; existing public data is preserved. No database/role configuration changes
or destructive reset are performed. This namespace remains for review. Evidence: `verification/resource-scope-20261002/`.

## Resource revision bundle conditional retrieval

Scoped responses now include `revision_bundle` (bundle schema 1, data schema 2). It binds the exact
four-field resource scope, tenant, principal, policy selection (`current` or explicit `release`),
selected policy release, current policy head release/generation, tenant assignment revision,
principal status and representation ETag. Assignment revision covers assignments, relations,
revocations and suspension together; it is independent of policy generation and scope identity.

Pass that complete map as `if_revision_bundle:` to `resource_snapshot`, preserving the original
`release_id:` selection. `not_modified` means the bundle equals the freshly read bundle;
`changed` includes fresh data and its replacement bundle. Missing, wrongly typed or unknown fields
return `invalid_revision_bundle`; a different tenant/scope/principal/selection returns
`revision_bundle_binding_mismatch`. Combining it with `if_none_match:` is `invalid_options`.
The existing ETag option remains supported. Comparison and all result fields share the existing
read-only REPEATABLE READ snapshot. Historical policy selection still reads current revocation and
suspension. Same-content publication, rollback and state ABA consume monotonic generations/revisions,
so an old bundle cannot regain validity through these commands. No-op state commands also consume revision.

This is equality revalidation of trusted PRP data, not authentication evidence or permission approval.
The opaque digest can be forged and does not authenticate the supplied map. Consumers must include
all bundle bindings in cache keys and enforce their own authority and policy selection rules.
Changes after the query snapshot, including between check and actual use, remain a consumer enforcement
obligation. This does not provide an execution lease, cross-service transaction or offline cache lifetime.

Tests for this feature use only the new `axiom_revision_bundle_20261002` schema in the existing
verified dedicated PostgreSQL 17 test container. Earlier schemas and fixtures are retained.
