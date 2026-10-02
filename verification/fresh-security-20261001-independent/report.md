# 독립 source-backed 보안 검증

검증 식별자: fresh-security-20261001-independent. 대상: `/Users/tonton/Documents/workspace/alaya/axiom`. 실행 환경이 제공한 날짜는 2026-10-01이며 파일시스템 날짜와 일치한다고 가정하지 않는다. 구현 대화, 기존 verification 보고서, VALIDATION.md의 검토 결론을 사용하지 않았다. 현재 소스, 서비스 계약 README/PAP_PRP_DESIGN, 테스트 소스만 읽었다. 실제 읽은 소스의 SHA-256은 `source-sha256.txt`에 보존했다.

## 결론과 완료 수준

요청 범위와 신뢰된 로컬 호출 전제에서 재현 가능한 보안 취약점을 확정하지 못했다. 이것은 전체 보안 안전 보장이나 공식 Codex Security Standard scan 완료가 아니다. PostgreSQL 런타임의 격리·원자성·경쟁은 이번 실행에서 검증하지 못했다. 순수 domain 검증 7건은 실제 실행되어 통과했다.

`codex-security:security-scan` SKILL.md를 읽었다. 해당 skill이 지정한 `../../references/scan-prologue.md`, `../../references/core-scan.md`는 skills.read에서 `failed to read skill resource`가 발생했다. 사용 가능한 도구 목록에는 `start_codex_security_standard_scan`, capability preflight, 보안 전용 audit/record/complete 도구가 없었다. 따라서 preflight `ready`, host 등록, canonical contract finalize를 수행하지 못했다. skill 지침을 준수한 공식 완료로 표시하지 않고 사용자 요청의 수동 fallback만 수행했다. 보안 워커는 실행하지 않았다. 토큰 계측도 제공되지 않았다.

프로젝트 및 상위 경로 `/`, `/Users`, `/Users/tonton`, `/Users/tonton/Documents`, `/Users/tonton/Documents/workspace`, `/Users/tonton/Documents/workspace/alaya`의 AGENTS.md/SECURITY.md를 확인했고 해당 파일은 없었다. 프로젝트 파일 목록에도 없었다. 상위 `.agents`와 `.codex` 디렉터리는 존재하지 않았다. 형제 프로젝트 지침은 이 대상에 적용하지 않았다.

## 신뢰 모델

자산은 tenant별 정책 본문, head/generation, 역할·직접 관계·할당·정지, 감사 이력이다. `lib/axiom.ex:2`와 `README.md:50`의 계약에 따라 conn을 가진 로컬 관리자/조회 adapter는 신뢰한다. tenant 및 actor는 이 경계에서 검증된 인증 주체가 아니라 caller가 권한 확인 후 제공하는 식별자다. 원격 listener/application server는 mix.exs와 lib에 구현되어 있지 않다. Gateway, 인증, 인가 context 발급, PDP/PEP는 외부다.

같은 VM의 임의 Elixir 실행 또는 DB 소유자 권한을 가진 주체는 `Axiom.Store.query/3` 및 Postgrex로 직접 DB를 변경할 수 있다. 이는 현재 API의 보안 격리 대상이 아니다. owner/superuser와 trusted caller를 공격자로 바꾸어 발생하는 우회를 현재 원격 취약점으로 계산하지 않았다.

## 경로별 증거

| 검증 항목 | 소스 증거와 판단 | 검증 수준 |
|---|---|---|
| 입력 → SQL | Axiom 명령/조회 SQL은 값에 `$1` 등 매개변수를 사용한다. `lib/axiom/store.ex:5`, `:36`의 유일한 SQL 문자열 결합은 내부 boolean에서 선택한 고정 `FOR UPDATE`. 정책 JSON은 JSONB 값이며 SQL/Elixir 코드로 실행하지 않는다. raw Store SQL은 내부 trusted interface다. | 모든 3개 핵심 모듈 정적 검토, domain SQL 형태 식별자 거부 실행 |
| 입력 → 명령/파일 | `lib/axiom/test_database.ex:19`의 유일한 System.cmd는 고정 `psql`과 argv, 고정 local DB 및 `__DIR__` 기반 schema 파일. Axiom 사용자 입력이 명령이나 파일 경로에 전달되는 경로 없음. Mix setup/measure도 fixed fixture만 사용. PATH 실행파일 교체는 로컬 실행환경 침해 전제다. | 정적 |
| tenant 읽기/쓰기 | `lib/axiom.ex:57`, `:66`, `:98`, `:260`, `:359`, `:370`, `:380`, `:421`, `:427`은 tenant 조건을 포함한다. role/node 존재 검증도 같은 tenant. `priv/schema.sql:38`, `:48`, `:59`, `:85`의 복합 FK는 참조 tenant 일치를 보강한다. 글로벌 release ID가 다른 tenant에 존재해도 필터 후 release_not_found가 된다. | 정적; 실제 PG 재현 안 됨 |
| CAS 및 TOCTOU | assignment 변경 `lib/axiom.ex:150`, draft 저장 `:159`, publish/rollback `:276`은 tenant 행 FOR UPDATE 후 기대 revision/generation 확인. 모든 지원 writer가 같은 tenant 잠금을 선행해 role 조회·draft 재검증·head 전환 사이 동시 수정 창을 직렬화한다. create_tenant는 conflict-ignore bootstrap이며 기존 상태를 갱신하지 않는다. | 정적; 경쟁 런타임 미검증 |
| 원자 발행/감사 | `lib/axiom.ex:228`, `:314`, `:320`은 release insert/head update/publication insert를 한 transaction 안에서 수행. assignment 상태와 revision/event도 `:152` 및 `store.ex:69`에서 같은 transaction. SQL 오류는 `store.ex:14`에서 안정 category로 변환한다. | 정적; late SQL fault 미실행 |
| 재시도 충돌 | `lib/axiom.ex:287`의 fingerprint는 kind, args, 기대 generation, actor를 모두 포함한다. `:297`은 tenant/request ID 범위 조회; 동일 digest만 원래 결과 반환, 다른 digest는 idempotency_conflict. `schema.sql:84`도 유일성 보강. 과거 재시도 결과가 최신 head가 아닌 것은 README 계약과 일치한다. | 정적; 동일 요청 경쟁 미실행 |
| rollback과 할당 분리 | `lib/axiom.ex:245` rollback은 tenant 소유 release 검증 후 policy head/generation만 바꿈. assignment, relation, node status 및 assignment_revision을 갱신하는 SQL 없음. 역사 정책으로 권한이 넓어질 수 있음은 외부 평가/승인 계약 위험이며 회수 복원과 다르다. | 정적 |
| versioned 조회·ETag | `lib/axiom.ex:348`은 정책 release만 선택; 할당/관계/정지는 현재 읽기 snapshot. `store.ex:11`에서 read-only REPEATABLE READ. `axiom.ex:387` ETag 자료에 tenant, principal, 상태, policy/body/digest, generation, assignment revision과 사실 포함. suspended/revoked 사실도 관리 데이터로 반환하며 허용 판단 아님. | 정적; canonical digest 실행 |
| 불변 감사 | `priv/schema.sql:88` UPDATE/DELETE trigger와 release/event/publication 테이블 적용. TRUNCATE/trigger disable/DB owner 우회까지 보장하지 않으며 schema에서 RLS/최소권한을 구성하지 않는다. trusted DB 전제의 한계다. | 정적; PG trigger 미실행 |

## 재현 증거와 전제

프로젝트 root에서 `elixir verification/fresh-security-20261001-independent/domain_probe.exs` 실행. 저장소 소스 Domain을 직접 로드하고 이미 존재하는 dev Jason beam을 사용했으며 의존성 설치/컴파일 변경은 하지 않았다. `domain_probe.log`는 정상 정책, unknown role, executable field, SQL 형태 식별자, 101개 rule, 잘못된 typed relation, canonical map order를 검증한 실제 출력이다. invalid UTF-8 및 65-byte 식별자도 false였다. schema_version 1.0은 받아들이지만 결과를 정수 1로 정규화하므로 unsupported schema 저장 우회로 판정하지 않았다.

임시 PG는 새 증거 디렉터리의 pgdata로만 생성하려 했고 `initdb -D verification/fresh-security-20261001-independent/pgdata -A trust -U axiom_verify --no-locale`가 실패했다. 설치된 `/opt/homebrew/Cellar/libpq/18.6/bin/initdb` 옆에 postgres 서버 바이너리가 없다는 메시지를 `initdb.log`에 보존했다. pg_ctl도 pgdata 부재로 실패했다. DB 생성/연결, network listener, 기존 DB/형제 DB 변경은 없었다. 기존 test_helper가 고정 기존 test DB의 schema를 준비하므로 `mix test`를 실행하지 않았다. 테스트 코드의 assert는 독립적으로 실행한 증거로 계산하지 않았다.

## 가용성 관찰 — 취약점 확정 아님

1. `lib/axiom.ex:411` history는 모든 이벤트를 반환하고 `:367`/`:377` snapshot은 전체 할당/관계 반환 후 canonical digest를 생성한다. `store.ex:64`는 모든 역할 목록을 읽는다. 반복된 정상 no-op 상태 변경도 이력과 revision을 늘릴 수 있다. 신뢰된 로컬 caller가 대량 데이터를 생성해 조회 메모리·DB 시간·감사 저장공간을 소비하는 경로는 소스상 존재한다. 원격/비신뢰 주체 도달 가능성 및 장애 임계량은 확인하지 못했으므로 severity는 정보성, 공격 취약점 confidence는 미확정. 공개 adapter에 quota/pagination/rate limit/timeout 계약이 필요하다.
2. `domain.ex:24`, `:30`, `:44`, `:59`는 거부 전 전체 map key sort/list length를 계산한다. `save_draft`는 이미 tenant lock을 획득한 뒤 validator를 부른다. 거대한 잘못된 로컬 term이면 validation 비용 동안 tenant writer를 지연시킬 수 있다. 1,000/100,000 rule list 거부를 실행했으며 log의 측정값은 단일 실행 microseconds, capacity나 DoS 실증이 아니다. 정당한 accepted 정책은 최대 100 rules × 32 actions, 각 identifier 최대 64 bytes로 제한된다. 입력 자체의 할당 비용/adapter request byte limit은 별도다. 정보성; 비신뢰 호출 경로 없음.
3. `store.ex:9`가 기본 driver timeout을 사용하고 연결/queue 오류는 Postgrex.Error 외 예외일 수 있다. 문서도 프로세스 오류 가능성을 명시한다. 신뢰 caller의 장애 처리/backoff 전제이며 오류 폭주와 부하 영향은 미검증이다.

## 공개 전 조건과 미검증

외부 노출 adapter에는 tenant/actor를 인증된 권한에서 도출하는 접근 제어, tenant별 읽기/쓰기 권한 분리, 명령별 관리자 권한, transport 보호, request 크기/빈도와 response pagination/쿼리 시간 한도, 감사 actor의 신뢰 근거가 필요하다. rollback 확대 영향 비교와 승인도 제품 계약으로 결정해야 한다. 실제 production DB role 최소권한·migration namespace·immutable trigger 상태, read consistency/경쟁/late fault의 새로운 전용 PG 실행, backup/restore는 검증하지 않았다.

nested transaction은 `vendor/db_connection/lib/db_connection.ex:1082`에서 outer transaction을 재사용한다. `SET TRANSACTION`이 이미 질의한 outer READ COMMITTED transaction에서 호출되면 PG의 제한으로 실패할 가능성이 있으며, 성공하지 않은 조회를 정상 consistent snapshot으로 간주하면 안 된다. 실제 PG 재현은 못 했으므로 별도 취약점으로 확정하지 않았다.

vendored Postgrex 0.22.4/DBConnection 2.10.2/Jason 1.4.5/Decimal 3.1.1의 사용 경계 및 transaction 재사용 코드를 확인했다. 전체 vendor 소스 감사, 최신 advisory 조회, 공급망 원본 비교는 수행하지 않았다. 네트워크를 사용하지 않았으며 최신 CVE 안전성을 주장하지 않는다. credentials 파일을 읽거나 설치/Git/배포/기존 증거 덮어쓰기/제품 소스 수정은 하지 않았다. 이 새 디렉터리의 보고서·재현 fixture·로그만 생성했다.
