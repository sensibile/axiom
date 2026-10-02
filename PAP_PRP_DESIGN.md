# axiom PAP/PRP 설계 초안

상태: 검토용 제안. 구현·스키마 확정 문서가 아니다.

## 1. 방향과 확정 수준

**사용자 확정사항**

- 권한 관리는 별도 트랙인 axiom에서 준비한다.
- 중심 범위는 PAP(정책 관리)와 PRP(정책 저장·조회)이며 PIP는 옵션이다.
- 정책과 개인의 역할·관계를 함께 관리한다.
- 외부 게이트웨이가 인가 컨텍스트를 구성·발급·부여하고 하위 서비스가 소비한다. 게이트웨이는 axiom에 포함하지 않는다.
- FC/IS, pure domain, 외곽 로직 테스트, mock 지양·fake 선호, 실제 IO 테스트 원칙을 반영한다.

**기본 제안**: Elixir + PostgreSQL로 시작한다. 현재 범위의 관리, 저장, 불변 버전, 원자 발행을 표현하기에 적합한 기본 구성이다. 예상 부하·관계 깊이·가용성 목표는 아직 없으므로 처리량이나 지연을 보장하는 결론은 아니다. Elixir 채택은 사용자의 질문에 대한 제안이며 확정사항으로 취급하지 않는다.

**초기 권고**: 공동 관리는 공동 발행 승인을 뜻하지 않는다. 정책은 불변 policy release로 발행하고, 개인 역할·관계 할당과 주체 정지는 별도 현재 상태·이력·assignment revision으로 관리한다. 첫 범위는 동기 조회와 revision/ETag이며 outbox·push·consumer ACK는 선택 후속이다.

**미정사항**: 정책 언어, 테넌트 경계, 관리 주체, 발행 승인 절차, 관계 추론 범위, 컨텍스트 운반 방식, TTL, 회수 SLA, PIP 필요 여부.

**axiom 범위**는 PAP/PRP의 정책·할당·관계·주체 상태 관리와 데이터·버전 조회 API까지다. 게이트웨이 구현, 컨텍스트 토큰 구성·발급·서명, 최종 사용자 인증 미들웨어와 하위 집행은 외부 책임이다. axiom 자체 관리·조회 API의 접근 통제와 tenant 격리는 axiom 책임으로 유지한다.

이 문서는 PDP/PEP 구현을 다루지 않는다. 컨텍스트를 만들기 위해 필요한 정책 평가의 담당자와 결과 표현은 별도 계약으로 결정한다. 역할이나 관계가 담겼다는 사실 자체가 특정 요청의 허용 결정을 뜻하지 않는다.

## 2. 책임과 흐름

| 구성 | 책임 | 경계 |
| --- | --- | --- |
| PAP | 정책 draft 편집·검증·발행·rollback, 개인 역할·관계·주체 상태 관리, 감사 조회 | 정책 발행과 할당 변경의 명령·관리 권한은 독립. 런타임 평가와 분리 |
| PRP | 불변 policy release와 policy head, 현재 할당·관계·주체 상태 및 이력 저장·조회 | 게이트웨이의 요청별 컨텍스트 발급과 분리 |
| 선택적 PIP | 외부 속성 조회·정규화·출처와 신선도 기록 | axiom 소유 역할·관계의 원장과 분리 |
| 외부 게이트웨이 | axiom API 데이터를 소비하여 컨텍스트 구성·발급·서명·부여 및 사용자 인증 연동 | axiom 외부 구현. 데이터 조회 일관성은 axiom, 컨텍스트 신뢰·수명은 외부 책임 |
| 외부 하위 서비스 | 검증된 컨텍스트를 계약에 따라 소비 | tenant·주체·버전·유효기간 준수. 평가 결과와 resource binding은 미정 |

정책 흐름은 `policy draft → 검증 → 불변 policy release → policy head 전환`이다. 개인 역할·관계·주체 정지 변경은 정책 발행 없이 별도 트랜잭션으로 현재 상태·이력·assignment revision을 갱신한다. axiom API는 두 상태를 일관되게 조회해 반환하고, 외부 게이트웨이는 그 응답을 소비한다. 비동기 전파를 선택한 후속 단계에서만 outbox·push·consumer ACK와 적용 상태 보고를 추가한다.

## 3. 관계형 모델과 JSONB 경계

아래는 논리 테이블 후보이며 migration이나 SQL 구현은 아니다. tenant_id는 멀티테넌트를 선택할 때의 격리 키다. 단일 테넌트라도 scope 경계는 명시한다.

| 테이블 후보 | 주요 필드 | 용도·불변식 |
| --- | --- | --- |
| principals | id, tenant_id, external_ref, kind, status | 개인/서비스 식별과 현재 정지 상태. 정책 release에 고정하지 않음. 인증 자격증명은 별도 시스템 소유 |
| roles | id, tenant_id, key, description | 역할의 안정적인 식별자. 부여 사실과 구분 |
| resources | id, tenant_id, kind, external_ref | 관계·할당 scope의 참조 대상. 업무 데이터 복제는 최소화 |
| policy_drafts | id, tenant_id, policy_key, body_jsonb, schema_version, revision | 편집 가능 정책. revision으로 낙관적 동시성 제어 |
| role_assignments | id, tenant_id, principal_id, role_id, scope_id, valid_from, valid_until, status, revision | 현재 역할 할당·회수 상태 및 유효 구간. 정책 발행과 독립 |
| relations | id, tenant_id, subject_id, relation_type, object_id, valid_from, valid_until, status, revision | 현재 방향성 관계·회수 상태. 정책 발행과 독립 |
| policy_workspaces | tenant_id, workspace_id, revision | 정책 draft 세대. 개인 할당 변경과 독립 |
| policy_releases | id, tenant_id, sequence, source_revision, schema_version, digest, created_by, created_at | 불변 정책 발행 단위. 개인 할당·관계·주체 정지 상태는 포함하지 않음 |
| release_policies | release_id, policy_key, body_jsonb, body_digest | release의 정책 본문 복사본 |
| assignment_heads | tenant_id, revision | 초기에는 tenant별 단조 증가 revision. 할당·관계·주체 상태 변경마다 갱신 |
| assignment_events | id, tenant_id, assignment_revision, entity_type, entity_id, before, after, actor, reason, request_id, occurred_at | 개인 할당·관계·정지/재활성화의 불변 변경 이력 |
| policy_heads | tenant_id, channel, release_id, generation | 환경/channel별 활성 포인터. generation은 항상 증가 |
| publication_events | id, tenant_id, channel, from_release_id, to_release_id, generation, kind, actor, reason, request_id, occurred_at | publish/rollback 이력. 이전 행 수정 금지 |
| outbox_events (선택 후속) | id, publication_event_id, payload, delivered_at, attempts | DB 발행과 알림 생성의 원자성. 전달 상태만 변경 가능 |
| revocation_epochs (선택) | tenant_id, principal_id 또는 scope_id, epoch, updated_at | 긴급 회수의 단조 증가 기준. rollback 대상에서 제외 |

정책 식별자·테넌트·역할·관계·할당·유효기간·버전은 정형 컬럼으로 관리한다. 가변 정책의 조건·액션·효과·확장 속성은 JSONB 본문에 둔다. JSONB가 유효 JSON임을 보장하는 것과 정책의 의미·참조가 유효한 것은 별개다. 허용 필드, 크기·깊이 제한, schema_version, 지원 연산자를 domain validator로 검증한다. 임의 Elixir 코드나 SQL을 본문에서 실행하지 않는 형식을 제안한다.

JSONB는 원문 공백·키 순서를 보존하지 않는다. digest는 저장 표현의 출력 문자열이 아니라 정해진 canonical serialization으로 계산한다. 중복 키는 입력 파싱 단계에서 거부하는 안을 제안한다. 정책 DSL과 canonicalization 규약은 미정이다.

참조는 같은 tenant 안에서만 유효하도록 복합 FK/제약을 설계한다. 정책 의미에 필요한 역할 정의·리소스 유형은 policy release 내부 또는 불변 버전 참조에 고정한다. 개인의 현재 할당·관계와 주체 정지 상태는 고정하지 않는다. 과거 정책을 현재 역할의 가변 정의로 해석하지 않으며, rollback 타깃에 없는 현재 역할·관계의 취급은 호환성 계약으로 정한다.

assignment revision은 policy release와 독립적인 현재 사실의 세대다. 초기에는 주체 정지 변경도 같은 tenant별 revision을 올린다. 현재 상태·변경 이력·revision은 함께 커밋한다. 행별 revision은 편집 충돌을, 전체 revision은 조회 결과의 변경을 감지한다.

관계는 일단 직접 edge를 저장한다. 팀 중첩·상속·전이 추론은 명시적 요구가 있을 때 선택한다. 선택 시 허용 relation_type, 방향, 최대 깊이, cycle 허용 여부, 여러 경로의 중복 처리부터 계약으로 정한다. 역할 할당의 scope도 전역/테넌트/리소스를 구분한다. 동일 할당·관계의 유효기간 중첩을 허용할지는 결정 필요하다. 시간 구간은 UTC `[valid_from, valid_until)`을 기본 제안으로 한다.

조회 인덱스 후보는 `(tenant_id, principal_id)`, 관계의 subject/object 양방향, `(release_id, policy_key)`, 활성 포인터 키다. JSONB GIN은 실제 관리 검색 패턴이 필요할 때 추가한다. 초기부터 모든 JSONB에 인덱스를 붙이는 전제는 두지 않는다.

## 4. 독립 변경, 원자 정책 발행과 rollback

1. 정책 draft는 기대 revision으로 편집하고 policy workspace revision을 올린다. 검증 결과를 source revision과 validator/schema version에 묶고 이후 정책 변경 시 재검증한다.
2. 발행 트랜잭션에서 workspace와 policy head의 기대 세대를 확인한다. 정책 편집과 발행은 같은 잠금 규약 또는 동등한 격리를 따라 일관된 정책 내용을 고정한다.
3. policy release·본문·head 전환·publication event를 하나의 트랜잭션에 저장한다. 실패하면 모두 취소한다. 개인 할당·관계·주체 상태를 복사하거나 발행하지 않는다.
4. 할당·관계·주체 상태 변경은 별도로 현재 행·assignment revision·assignment event를 하나의 트랜잭션에 저장한다. 회수·정지는 정책 발행을 기다리지 않는다.
5. 각 명령 범위에서 request_id로 멱등 처리하고 기대 revision/generation 충돌을 반환한다.

policy release와 감사 이력에는 UPDATE/DELETE를 허용하지 않는 저장 경계를 제안한다. DB 권한·제약과 보존 정책은 후속 설계한다. 현재 참조에 의존하는 정책 검증은 참조 호환성을 확인하되 개인 할당 전체를 공동 승인 대상으로 묶지 않는다.

**rollback 불변식**: 정책 rollback은 policy head만 이전 불변 release로 전환한다. generation을 증가시키고 rollback 이력을 추가한다. 현재 할당·관계·assignment revision·주체 정지 상태를 복원하거나 감소시키지 않는다. 이미 회수된 할당은 회수 상태로, 정지된 주체는 정지 상태로 남는다. 재부여·재활성화는 명시적인 별도 변경이다.

**별도 위험**: 이전 정책이 더 넓은 권한을 정의하면 현재 유효한 구성원의 권한은 넓어질 수 있다. 이는 회수된 할당을 복원하는 것과 다른 위험이다. 정책 rollback 비교에서 확대되는 정책·영향 범위·호환성을 표시하고 승인 절차를 정한다. 평가 구현은 범위 밖이다.

outbox·push·consumer ACK는 선택 후속이다. 비동기 전파를 채택할 때만 outbox 원자 저장, 중복·역순 처리, 재동기화와 적용 상태를 설계한다. DB commit은 이미 발급된 컨텍스트를 갱신하지 않는다.

## 5. axiom 데이터·버전 조회 API 계약

초기안은 axiom이 PostgreSQL **동일 읽기 snapshot**에서 policy head/release, assignment revision, 현재 유효한 역할·관계, 주체 상태와 필요한 로컬 사실을 조회해 동기 API 응답으로 반환하는 방식이다. 외부 gateway는 API 소비자이며 axiom DB에 직접 접근하는 구성이 아니다. axiom 응답은 권한 관리 데이터이며 인가 컨텍스트 토큰이나 허용 결정이 아니다.

여러 SELECT를 사용하면 read-only REPEATABLE READ 등 같은 snapshot을 보장하는 경계를 제안한다. 기본 READ COMMITTED 트랜잭션에 쿼리를 묶는 것만으로 같은 snapshot이라고 가정하지 않는다. 동일 snapshot은 커밋된 일관된 조합을 제공하며 독립적인 정책·할당 변경을 공동 커밋으로 만들지는 않는다.

첫 조회 계약은 동기 응답과 revision/ETag다. 검증자에는 policy release/head generation, assignment revision, tenant·주체·조회 scope·표현 schema를 반영하고 같은 snapshot에서 비교·응답한다. 시간 경과만으로 할당 효력이 달라질 수 있으므로 revision만 같다고 무기한 304/캐시 재사용하지 않는다. 다음 유효기간 경계와 TTL로 재사용 한계를 정하거나 유효 사실을 재계산한다. 시간 의존 로컬 사실도 재검증 조건에 반영한다.

| axiom 조회 응답 후보 | 의미 |
| --- | --- |
| data_schema_version | 관리 데이터 응답 형식 버전 |
| subject_id, tenant_id, 조회 scope | 요청한 주체·tenant·관리 데이터 범위 |
| policy_release_id, policy_generation, policy_schema_version | 조회한 불변 정책과 head 세대 |
| assignment_revision, principal_status | 같은 snapshot의 할당·관계·주체 상태 세대와 현재 상태 |
| role_assignments, relations, 필요한 로컬 facts | 관리 데이터·유효기간·출처. 허용 결정으로 해석하지 않음 |
| revision/ETag, observed_at, 재검증 경계 | 표현 검증자와 조회 시각·시간 의존 사실의 캐시 한계 |

이 API는 issuer/audience, 서명 키, 토큰 issued_at/expires_at, authorization 결과를 발급하지 않는다. API 필드 이름·오류·페이지 조회 시 snapshot 유지 방식은 후속 명세로 정한다.

## 6. 외부 컨텍스트 연동 정보와 미정 협의사항

이 절은 외부 gateway·하위 서비스 담당자와의 협의 자료이며 axiom 기능이나 자체 수용 기준이 아니다. 컨텍스트 구성·토큰 발급·서명·사용자 인증 미들웨어·하위 집행은 외부에서 구현한다. axiom은 필요한 정책·할당 데이터와 버전을 제공한다.

외부 컨텍스트의 운반·신뢰 방식, 평가 결과 포함 여부, resource binding은 미정이다. 아래 필드는 외부 컨텍스트 계약 후보이며 axiom API 발급 필드가 아니다.

| 필드 | 의미 |
| --- | --- |
| context_schema_version | 컨텍스트 형식 버전. 정책 schema와 별개 |
| issuer, audience, key_id | 외부 신뢰 발급자, 소비 서비스, 검증 키 식별 |
| subject_id, tenant_id, actor_id (선택) | 인증 주체 및 위임 시 실제 actor |
| policy_release_id, policy_generation, policy_schema_version | 조회한 정책 버전·head 세대 |
| assignment_revision, principal_status | 같은 snapshot에서 읽은 현재 할당·관계·주체 상태 세대와 정지 상태 |
| principal_epoch / scope_epoch (선택) | 긴급 회수 비교 기준 |
| issued_at, not_before, expires_at | 발급·유효 시간. 허용 clock skew 명시 |
| request_id | 추적 식별자. 자체로 재사용 방지를 보장하지 않음 |
| action, resource_ref (미정) | resource binding 계약 확정 후 결정 |
| roles / relation_claims / attributes | 소비에 필요한 최소 사실. 출처·조회시점·버전도 필요한 경우 포함 |
| authorization (선택) | 별도 평가 계약으로 나온 action/resource별 결과 또는 제한 scope |

외부 담당자는 신뢰 방식을 다음 후보 중 선택한다.

- **서명 envelope**: 서비스가 issuer/key/audience/시간을 검증하고 resource binding 채택 시 함께 검증한다. 키 배포·rotation·폐기, 서명 알고리즘 허용 목록이 필요하다. 서명은 기밀성을 제공하지 않으므로 민감 속성을 최소화한다.
- **내부 헤더 + 인증된 전송 경계**: 게이트웨이 우회 경로를 차단하고 hop마다 발신자를 인증한다. 외부의 동일 이름 헤더를 게이트웨이가 제거·덮어쓴다. 여러 hop 또는 별도 진입점에서 이 조건을 유지할 수 있는지 먼저 확인한다.
- **참조 핸들**: 서버에서 컨텍스트를 조회한다. 빠른 회수에 유리하지만 조회 가용성과 지연 의존이 생긴다.

하위는 unknown schema, 잘못된 issuer/audience/서명, 만료, tenant·주체 불일치를 수용하지 않는다. resource binding을 채택하면 그 불일치도 검증한다. 컨텍스트 부재·조회 실패를 익명 또는 광범위 권한으로 대체하지 않는 안을 제안한다. 지원 schema 범위와 전환 기간을 명시한다. 과거 release 허용은 별도 정책이며 generation 수치만으로 현재 활성 버전을 알 수는 없다.

roles/relation_claims는 사실이며 범용 allow 값이 아니다. 결과를 넣는다면 적용 action/resource, 제약, 평가 시점, 사실의 신선도와 책임 주체를 계약에 고정한다. 하위에서 상세 리소스가 결정되는 경우 게이트웨이의 거친 scope만으로 최종 권한을 확정할 수 없으므로 별도 평가 책임을 결정한다. 이 문서에서는 그 구현을 만들지 않는다.

### 외부 컨텍스트 유효기간과 회수 협의

| 선택지 | 효과 | 비용·한계 |
| --- | --- | --- |
| 짧은 TTL + 다음 동기 조회에 현재 상태 적용 | 단순한 기본안 | 기존 컨텍스트는 만료까지 유효할 수 있음 |
| epoch 조회/캐시 비교 | 주체·scope 긴급 회수 | 캐시 신선도·조회 장애 정책 필요 |
| push 무효화 + 주기적 재동기화 (선택 후속) | 빠른 전파와 복구 | push 유실만으로 회수 완료를 보장하지 못함 |
| 요청별 온라인 검증/핸들 조회 | 최신 상태 확인 | 가용성·지연 의존 증가 |

axiom 동기 API는 회수·정지 커밋 후 새로 시작한 snapshot에서 현재 상태를 반환한다. 조회 중 커밋된 회수는 다음 snapshot부터 보이며 이미 발급된 컨텍스트는 별도 회수 계약이 필요하다. TTL 수치는 아직 정하지 않는다. 허용 가능한 회수 지연을 먼저 정하고 TTL·캐시 갱신 간격·전파 지연을 함께 맞춘다. TTL 방식의 회수 한계는 마지막 stale 발급 가능 시간, TTL, clock skew를 포함한다. epoch 캐시도 최대 stale 구간을 명시해야 한다. 로그아웃·계정 비활성화·역할 회수·관계 회수·키 폐기를 같은 사건으로 취급하지 않는다.

장시간 작업·스트리밍·큐 메시지는 최초 컨텍스트 유효기간 이후 처리 규칙이 필요하다. 권한 재확인 시점 또는 별도 작업용 위임 계약을 선택한다. 외부 컨텍스트 감사에는 사용한 policy release/generation, assignment revision과 컨텍스트 식별자를 남기되 전체 개인 속성을 무조건 저장하지 않는다.

## 7. PIP 옵션

초기에는 axiom 소유 정책·역할·관계만으로 필요한 사실이 충족되는지 확인한다. 외부 조직 정보, 리소스 소유권, 계정 상태 등 최신 사실이 필요하면 PIP adapter를 추가한다.

| 방식 | 장점 | 필요한 계약 |
| --- | --- | --- |
| 요청 시 외부 조회 | 원본의 최신 사실 활용 | timeout, missing/error 구분, 장애 처리, 호출 예산 |
| 로컬 projection | 반복 조회 비용 감소 | source version, 동기화 지연, 삭제·회수 전파 |
| 외부 gateway 주입 속성 (연동 협의) | 외부 컨텍스트 구성 시 조회 감소 | 신뢰 issuer, 출처, observed_at, 최대 age |

외부 사실은 PostgreSQL 동일 snapshot에 자동으로 포함되지 않는다. 로컬 projection은 그 DB 상태를 함께 읽을 수 있으나 원본 신선도는 별도 보장한다. 속성은 `{value, source, source_version, observed_at, expires_at}` 같은 구조로 신선도를 표시한다. 값 없음, 조회 실패, 명시적 false를 구분한다. 사실의 원장 소유권을 정하고 외부 속성과 axiom 할당 간 충돌 규칙을 명시한다. 외부 실시간 사실을 사용하면 policy release와 assignment revision만으로 과거 결과를 재현할 수 없으므로 사용한 사실 버전 또는 감사용 최소 증거가 필요하다. 외부 호출을 DB 발행 트랜잭션 안에 오래 유지하지 않는다.

## 8. Elixir 구조: FC/IS와 테스트 경계

**Functional Core / pure domain**은 명시적으로 받은 정책·현재 할당·관계·주체 상태·시각·식별자·기대 세대로 검증 결과, 독립 할당 변경 계획, 유효 사실, 정책 발행·rollback 계획, 충돌 사유를 계산한다. Repo/HTTP, Process 메시지, 시스템 시각, 난수, 암묵적 전역 상태를 domain에서 직접 사용하지 않는다. 정책 언어의 구조·참조 검증과 발행 상태 전이가 중심이다.

**Imperative Shell**은 관리 API, 인증된 관리자 식별, Repo adapter, transaction/잠금, 동일 snapshot PRP 조회, ETag 응답, 선택적 PIP 호출을 담당한다. domain 결과를 수행하고 실제 IO 오류·재시도를 처리한다. outbox·전파 worker·consumer ACK는 후속 선택 시 추가한다. 프로세스는 worker·연결·전달 조정에 사용하되 정책마다 상태ful process를 두는 전제는 두지 않는다. DB를 영속 원장으로 둔다.

fake는 clock, ID 공급, 외부 속성 공급, event transport처럼 명확한 경계의 계약을 재현하는 데 사용한다. 호출 순서·횟수만 검증하는 mock은 지양한다. 메모리 fake가 PostgreSQL FK·잠금·동시성·트랜잭션 의미를 검증했다고 보지 않는다. 외곽 테스트는 반환된 결과·저장 상태·이벤트·오류 복구를 확인하고, 실제 PostgreSQL과 axiom 관리·조회 API의 직렬화·전송 경계 IO 검증을 별도로 둔다.

## 9. axiom 자체 수용 기준: 최소 검증 후보

아래는 후속 검증 계획이며 이번 작업에서 코드 작성이나 테스트 실행은 하지 않았다.

1. **독립 할당 변경**: 정책 head/release를 바꾸지 않고 역할 부여·회수, 관계 변경, 주체 정지를 수행한다. 현재 상태·이력·assignment revision이 함께 바뀌고 axiom API의 새 snapshot 조회 응답에 반영되는지 확인한다. gateway의 컨텍스트 생성 동작은 외부 검증 범위다.
2. **회수 후 정책 rollback 안전성**: 할당·관계 회수와 주체 정지 후 policy head를 이전 버전으로 돌린다. 회수·정지·assignment revision이 유지되는지 확인한다. 더 넓은 과거 정책의 확대 가능성은 변경 비교에서 표시한다. 실제 유효권한 평가·집행 검증은 외부 범위다.
3. **동시 변경 일관성**: 정책 head와 할당/정지 변경 중 여러 쿼리로 조회해 동일 PostgreSQL snapshot의 policy release·assignment revision·현재 사실만 반환하는지 실제 IO로 확인한다. axiom API의 ETag가 데이터 변경을 놓치지 않고 시간 경계의 조건부 조회를 올바르게 처리하는지 확인한다. 소비자 캐시·토큰 운용은 외부 수용 기준이다.
4. **실제 PostgreSQL 원자성·tenant 격리**: 정책 발행 및 할당 변경의 실패를 각각 주입해 부분 상태·이력이 남지 않는지 확인한다. 경쟁 변경·멱등 재시도와 cross-tenant 참조/조회 차단을 실제 제약·조회 경계로 검증한다.

outbox·push·ACK, PIP, 규모 측정은 해당 기능·부하 요구를 선택한 후 검증을 확장한다.

## 10. axiom 결정사항과 외부 협의사항

1. **외부 협의**: 컨텍스트는 역할·관계 등 사실만 전달하는가, 특정 action/resource의 평가 결과도 담는가? 평가 책임자는 누구인가?
2. **외부 협의**: 허용 회수 지연과 gateway→하위 신뢰 방식은 무엇인가? 이 답으로 TTL·epoch·온라인 검증을 선택한다.
3. **axiom**: tenant/scope 경계와 직접 관계 외의 상속·전이 추론이 필요한가?
4. **axiom**: 정책 언어와 schema, 발행 권한·승인 절차, 정책 rollback의 권한 확대 영향 비교 방법은 무엇인가?
5. **PIP 경계 협의**: 최신 외부 사실이 실제로 필요한가? 필요하면 원장과 PIP 신선도·장애 계약을 정한다.

## 참고 및 작업 범위

- PostgreSQL의 [JSON Types](https://www.postgresql.org/docs/current/datatype-json.html): JSONB 특성과 관계형/JSON 병용의 근거.
- PostgreSQL의 [Transactions](https://www.postgresql.org/docs/current/tutorial-transactions.html): DB 내 변경을 하나의 단위로 적용하는 근거. 외부 소비자 적용까지 보장한다는 의미는 아니다.
- PostgreSQL의 [Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html): 동일 읽기 snapshot과 격리 수준 참고.
- Elixir의 [Process 문서](https://elixir.hexdocs.pm/Process.html): 프로세스·메시지 경계 참고. 위 구조 선택은 axiom 범위에 대한 제안이다.

axiom 디렉터리는 존재하며 작성 전 비어 있었다. 경로 상위 및 axiom에서 프로젝트 AGENTS.md를 찾지 못했고 workspace의 .agents/.codex도 없었다. /Users/tonton/.codex/AGENTS.md와 worktree-first-dev 스킬을 확인했다. 이번 명시적 문서 전용·Git 금지 요청을 우선하여 worktree나 Git 작업 없이 이 파일만 작성했다. akashic, 상위/형제 디렉터리, 기존 DB를 변경하지 않았다. 설치·배포·코드/테스트 실행은 수행하지 않았다.

## 2026-10-02 구현 단위: 명시 지식 resource scope

위 초안의 미정 인가 의미를 확정하지 않고, 로컬 PAP 등록/PRP 조회에
`tenant_id + space_id + scenario_id + local_id`의 정확한 immutable 자원 식별을 추가했다.
API/소비자 계약은 README의 Exact knowledge resource scope 절을 따른다. tenant 정책 DSL은
schema 1 그대로이며 자원에 특정 allow/deny를 평가하지 않는다. policy release 선택과 현재
head generation/current assignment revision/current suspension은 동일 read snapshot에서 구별한다.
logical scope는 physical placement, QueryCut, Iceberg snapshot version과 독립이다.
과거 policy/scenario로 권한 회수나 정지를 복원하지 않으며 scenario 권한 복사는 없다.
Akashic 데이터/retention/cut binding의 실제 확인, resource incarnation 연동, scope별 정책 DSL,
Arbiter 발급/PDP/PEP는 미구현이다. 실제 전용 PG 격리 schema의 구현자 검증 뒤 fresh 독립 검증을 기다린다.
