# 독립 보안 검증 — PostgreSQL 보완 결과

이 문서는 최초 `report.md`를 보존하면서 그 문서의 PostgreSQL 런타임 미완료 부분을 보완한다. 공식 Codex Security Standard preflight/전용 도구 부재, 수동 fallback이라는 완료 수준은 유지한다. 기존 검토 결론이나 기존 verification 증거를 참고하지 않았다. 사용자 추가 지시로 기존 **프로젝트 전용** 테스트 컨테이너 사용이 명시적으로 허용됐다.

## 대상 확인 및 접근

README.md:10-27의 컨테이너/포트 계약과 `lib/axiom/test_database.ex:4`의 고정 설정을 확인했다. 읽기 전용 `docker inspect` 결과: `/axiom-dev-test-pg-20261002`, `postgres:17-alpine`, `5432/tcp`는 `127.0.0.1:55439`로만 publish. 임의 기존 DB에 연결하지 않았다.

첫 sandbox Docker 소켓 접근은 permission denied, 첫 DB 연결은 `:eperm`으로 실패했다. 승인된 require_escalated 실행으로 해당 제한을 해소했다. 자동 승인 거부는 없었다. 읽기 전용 `pg_identity.exs`로 current_database/current_user가 모두 `axiom_test`이고 PostgreSQL 17.10이며 public axiom 테이블 9개가 존재함을 확인했다. 포트/주소의 DB 내부 출력은 container 내부 `192.168.215.2/32:5432`; 외부 client 접속은 고정 `127.0.0.1:55439`였다. DB 이름·사용자·schema 이름만 조회했고 기존 사용자 행은 읽지 않았다.

원시 증거는 실패한 `pg_identity.log`, 성공한 `pg_identity_authorized.log`, `pg_probe.log`이다. 최초 initdb 실패 로그도 보존한다.

## 실행 방식

`elixir verification/fresh-security-20261001-independent/pg_probe.exs`를 프로젝트 root에서 실행했다. 기존 dev dependency beam과 현재 세 핵심 소스를 직접 로드했다. 설치, Mix compile/setup/test_helper, 공유 fault trigger, schema/설정 변경은 수행하지 않았다.

이 fixture의 새 tenant는 아래 두 개이며 삭제하지 않았다:

- `sec-fresh-9d9f943003834099cf633aec`
- `sec-fresh-9c69217ceb794f58bd0e6f0a`

모든 데이터 변경과 실패 시도는 이 두 tenant 조건으로 제한했다. 불변 release UPDATE/DELETE 시도는 새 fixture에만 수행되어 DB가 거부했으며 기존 행 삭제는 없었다. fixture 감사 이력은 최종 assignment 30건/publication 24건이다. test는 실제 Postgrex connection pool을 통한 여러 Task로 실행했고 DB fake/mock을 사용하지 않았다. 단일 ExUnit scenario에 여러 독립 invariant assert를 묶었으며 결과는 `1 passed`다.

## 실제 검증으로 보완한 항목

| 항목 | 최소 재현과 관찰 | 근거 위치 |
|---|---|---|
| SQL/tenant 입력 | role `x';DROP TABLE axiom_tenants;--`, tenant `x' OR 1=1--` 호출 모두 invalid_identifier. 테이블 유지와 후속 정상 명령 성공 확인. | lib/axiom.ex:15, store.ex:36, domain.ex:6 |
| tenant 역할/노드 격리 | B에만 role/node 생성, A draft의 해당 role 거부 unknown_role, assignment/relation의 해당 object 거부 node_not_found. | lib/axiom.ex:66, :98, :171 |
| tenant release 격리 | A release ID로 B snapshot/rollback 거부 release_not_found. B head를 A release로 바꾸는 직접 SQL도 실제 composite FK 오류. | lib/axiom.ex:260, :359; schema.sql:38 |
| 불변 release | A 신규 release UPDATE actor/DELETE 모두 Postgrex.Error. | schema.sql:88-96 |
| 동일 publication 재시도 | 같은 request/actor/generation의 Task 8개 모두 동일 결과; release count=1. actor만 바꾸면 idempotency_conflict. 이후 다른 head로 진행한 뒤 동일 원본 retry도 최초 결과 반환. | lib/axiom.ex:287-307 |
| publication CAS | 서로 다른 request ID 두 개, 같은 draft/generation으로 경쟁: 정확히 1 success + 1 conflict. | lib/axiom.ex:276, :307 |
| assignment CAS | 같은 expected revision=29로 active/suspended 두 Task 경쟁: 정확히 1 success + 1 conflict. | lib/axiom.ex:146-153 |
| policy rollback/현재 사실 분리 | assignment와 member relation 회수, principal suspended, 이전 read policy로 rollback; assignment revision=9, revoked 두 사실 및 suspended 유지. release 고정 조회도 현재 사실 반환. | lib/axiom.ex:245, :348, :367-396 |
| ETag | 위 snapshot의 ETag로 재조회해 not_modified. | lib/axiom.ex:399-404 |
| late 실제 SQL 실패 | outer Store transaction 안에서 성공한 assignment 변경 또는 publish 뒤 새 fixture에 존재하지 않는 scope FK INSERT. 실제 SQL constraint 오류로 outer rollback; assignment snapshot 동일, release count=2 유지. 실패 publication request ID로 다음 정상 publish 성공해 멱등 레코드도 남지 않았음을 확인. | store.ex:9-29; axiom.ex:152, :228, :314, :320 |
| 동일 snapshot 일관성 | writer가 같은 outer transaction에서 policy generation 변경, 2ms 지연, principal status/revision 변경을 20회 commit. 동시에 80개 snapshot에서 assignment_revision=generation+5 및 generation parity와 상태 일치. 한쪽만 보인 사례 없음. | store.ex:11; axiom.ex:340-407 |

## 결과 및 남은 한계

실행한 범위에서 취약점을 확정하지 못했다. 새로운 중요한 재현 가능한 발견은 없었다. 최초 보고서의 tenant 격리·경쟁·rollback·읽기 일관성에 대한 정적 판단은 위 실제 PG 증거로 보완됐지만 전체 안전을 보장하지 않는다.

late failure 검증은 실제 FK 오류를 **서비스 호출을 감싼 outer transaction의 뒤쪽**에 주입했다. publication audit INSERT 자체에 fault trigger를 주입하거나 네트워크 단절/commit 결과 불확실성을 재현하지 않았다. 공유 schema 변경 금지 범위를 지켰으며 이 차이를 숨기지 않는다. release UPDATE/DELETE trigger는 실행했지만 assignment_event/publication 각 trigger를 별도 공격하지 않았다. 다른 tenant에 영향을 주는 raw SQL은 사용하지 않았다.

고정 release 선택 이후 head 변경에 대한 versioned 조회 전 조합, nested READ COMMITTED transaction의 SET TRANSACTION 실패, draft-save/publish 동시 경쟁의 모든 순서, deadlock/timeout/취소/프로세스 종료/commit 불확실성과 리트라이는 별도 미검증이다. 이력/조회 대규모 자원 고갈 임계값, production RLS·최소권한/마이그레이션·백업, 최신 의존성 advisory/전체 vendor 감사, 외부 Gateway/PDP/PEP도 미검증이다. 신뢰된 caller 경계 및 공개 전 adapter 권한·quota 조건은 최초 보고서와 같다.

이 보완 작업은 제품 코드·의존성·설정·Git·배포를 변경하지 않았다. 기존 증거 파일을 덮어쓰지 않았으며 새 PG fixture/script/log와 이 addendum만 추가했다.
