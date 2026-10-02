# 첫 기능 단위 검증 증거

대상: `axiom` 로컬 Elixir 서비스 및 전용 PostgreSQL. 구현자 검증 기록이며 독립 리뷰/보안 체크 완료를 의미하지 않는다. 테스트 개수·커버리지를 충분성의 근거로 사용하지 않는다.

## 실행 결과

- Elixir 1.20.4 / OTP 29, 전용 `postgres:17-alpine` 컨테이너 `axiom-dev-test-pg-20261002`.
- 전용 DB `127.0.0.1:55439/axiom_test`, pool size 6. 기존 Docker DB 5432/5433은 사용하지 않았다.
- 최종 `mix check`: format check, axiom compile warnings-as-errors, 실제 PostgreSQL ExUnit 회귀 통과. seed 134507, 11 passed, 약 0.9초.
- `mix xref graph --format stats`: application 6개 파일, runtime edge 7개, cycle 0개. Domain에서 Store 의존 없음. 이는 기능 정확성·보안의 증명은 아니다.
- 캐시 원본 DBConnection의 deprecated xref 설정 경고가 발생한다. axiom compiler 경고는 없으며 제3자 소스는 수정하지 않았다. Dialyzer·Credo·외부 취약점 DB 검사는 수행하지 않았다.

## 주장별 oracle·증거·한계

| 주장 | 정답/불변식 및 실제 증거 | 미검증·한계 |
| --- | --- | --- |
| 제한 정책 구조·참조 검증 | Domain 테스트가 unknown key/schema/role, 잘못된 rule/action, 중복 action을 거부. 서비스에서 실패 draft가 저장되지 않음 확인. canonical JSON의 고정 문자열 oracle 사용 | 외부 JSON parsing, duplicate key, 평가 의미·정책 효과는 없음. 전 입력 공간 fuzzing은 미수행 |
| 낙관적 동시성·정확 재시도 | stale draft/assignment/generation 거부. 실제 pool의 두 경쟁 publish와 두 assignment CAS에서 각각 성공 1개/충돌 1개. 같은 request ID·명령은 원래 결과, 다른 인자는 idempotency_conflict. SQL release count=1 확인 | 장기 lock 경합·deadlock·연결 장애·request 유실을 네트워크에서 실제 주입한 검증은 없음. 응답 유실은 동일 요청 재전송으로 모사 |
| release·감사 불변 | 실제 SQL UPDATE/DELETE가 immutable trigger로 거부됨 | owner/superuser가 trigger 제거/TRUNCATE 하는 공격, 운영 최소권한·RLS·백업은 범위 밖 |
| 할당 독립 변경 및 rollback 안전성 | 정책 generation=2인 상태에서 할당·관계를 부여/회수하고 정지 후 rollback. assignment revision=9, revoked 2종, suspended 유지; policy generation만 3으로 증가. 이력 행수와 값 확인 | 과거 정책의 넓은 권한이 현 구성원에 적용되는 실제 효과는 평가 엔진이 없어 검증 불가. 승인·영향 diff 미구현 |
| 원자 실패 복구 | 실제 PG before-insert trigger로 assignment audit와 publication audit에서 늦은 check violation 주입. 앞서 실행된 주체 변경/revision 증가, release 삽입/head 변경이 모두 취소되는지 새 조회와 SQL count로 확인. 같은 request ID 재시도 성공 | kill/재시작·디스크 오류·COMMIT 응답 유실·장애 복구는 미검증 |
| 동일 snapshot 조회 | 결정적 barrier로 repeatable read snapshot을 먼저 고정하고 외부 writer의 정책/정지 커밋 후에도 이전 head·revision·상태 유지 확인. 별도 production `Axiom.snapshot` 호출 80회와 atomic paired writer 40회를 경합: `assignment_revision = policy_generation + 3`, generation parity와 principal status 일치라는 독립 데이터 불변식 사용 | 앞의 barrier 테스트는 기존 read transaction 안의 중첩 호출이라 그 단독으로 production snapshot 경계의 충분한 증거가 아니다. paired 경합 회귀를 보완했으나 scheduler 모든 interleaving 증명·격리 변경 mutation sensitivity는 아직 독립 reviewer 과제 |
| tenant 격리·잘못된 입력 | 모든 fixture에서 tenant 2개. 외부 tenant release 조회/rollback 거부, 외부에만 존재하는 scope 사용 거부. raw SQL head FK와 assignment FK도 cross-tenant 입력 거부. injection 형태 식별자, nil/큰 정수 revision, invalid UTF-8 reason 거부·변경 이력 불변 확인 | 신뢰된 서비스의 tenant parameter 격리만 검증. 호출자 인증·tenant 소유권·관리 권한은 구현하지 않아 외부 공개하면 안 됨. raw DB 사용자가 원하는 tenant를 직접 조회하는 것을 막는 권한 모델은 미구현 |
| 버전 고정/ETag | 이전 policy release를 선택해도 현재 assignment revision 반환. 같으면 not_modified, 회수/정지 뒤 ETag 변경. tenant/주체/데이터 schema와 정책·할당 데이터를 digest에 반영 | 시간 구간 할당·HTTP caching·pagination·expiry는 지원하지 않음. 토큰 TTL/gateway 동작은 외부 책임 |

## 측정 가능한 비용

최종 `mix axiom.measure` 실제 결과. warm-up 10회 후 로컬 직렬 실행이며 transaction·loopback IO를 포함한다. publish는 직전 draft 저장 시간을 제외한다. 데이터는 rule 1, role 1, principal 1, assignment 1, JSONB body 160 byte. 단순 비용 baseline이며 처리량·확장성 또는 production SLA 주장으로 사용하지 않는다.

| 호출 | n | 최소 | 중앙값 | p95 | 최대 |
| --- | --- | --- | --- | --- | --- |
| snapshot | 100 | 1.304 ms | 2.410 ms | 3.395 ms | 10.411 ms |
| publish | 20 | 2.695 ms | 3.280 ms | 4.823 ms | 5.215 ms |

명령이 fresh tenant와 불변 release들을 생성하므로 반복 측정의 DB 크기는 누적된다. 측정 task는 결과를 stdout으로 반환하고 서비스 리스너를 열지 않는다. 대규모 관계·JSONB, 느린 디스크, 다중 client, tenant별 serialization 병목, 메모리·CPU·EXPLAIN 비용은 미측정이다.

## 다음 독립 검증을 위한 경계

구현자는 여기서 코드 변경을 멈춘다. 새 reviewer/security checker가 구현 대화 없이 소스·README·불변식으로 독립 oracle과 반례를 구성할 예정이며 아직 수행하지 않았다. 권장 mutation 축은 tenant predicate 제거, 정책 rollback의 assignment 복원, assignment audit 트랜잭션 분리, snapshot 격리 약화, idempotency fingerprint 제거다. mutation은 원본을 수정하지 않는 격리된 복사본에서만 수행해야 한다. 어떤 mutation을 기존/새 검증이 탐지했는지와 미탐지 사례를 별도 보고한다.

구현자 검증의 주요 불확실성은 서비스 호출 권한이 외부 adapter 책임이라는 전제, 동시 조회 경합의 scheduler 범위, DB owner 권한과 테스트 실패 trigger의 shared 자원 범위, production 장애 응답이다. 이 문서는 이를 완료된 보안 증거로 바꾸지 않는다.

## 로컬 의존성 출처

기존 Hex 캐시 tar를 읽기 복사·전개한 원본 패키지다. 아래 SHA-256은 재현/출처 확인용이며 publisher 서명 검증·취약점 감사의 증거는 아니다. license·metadata는 vendor 각 디렉터리에 포함한다.

| 패키지 | 캐시 tar SHA-256 |
| --- | --- |
| postgrex 0.22.4 | `4aae45a2d60e35b04eea2602440be152fae332901f1fc7a60fc7cb7f0f9a9c5a` |
| db_connection 2.10.2 | `510b14482330f1af6490a2fa0efd8d4f1435d1529b165647df22ac0f2df0fa93` |
| decimal 3.1.1 | `c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6` |
| telemetry 1.4.2 | `928f6495066506077862c0d1646609eed891a4326bee3126ba54b60af61febb1` |
| jason 1.4.5 | `b0c823996102bcd0239b3c2444eb00409b72f6a140c1950bc8b457d836b30684` |

## 후속: bigint 경계 correctness 수정

독립 검증에서 찾은 마지막 성공 revision/generation의 계약 불일치를 수정했다. 저장/CAS 범위는 bigint max 포함, max에서 새 증가는 revision_exhausted로 원자 거부하며 최댓값 draft 발행과 정확한 publication 재시도는 유지한다. [수정 보고·증거](verification/bigint-fix-20261002/REPORT.md)를 참조한다. 이전 실행·측정·미검증 기록은 그대로 보존했다. 새 mix check 16 passed, 원래 bigint 재현 3 passed, 독립 240단계 모델 포함 suite 6 passed다. 새 최종 독립 확인·보안 재검증 완료를 뜻하지 않는다.

## 명시 지식 resource scope 후속 검증

2026-10-02 구현자 검증은 [resource scope 보고서](verification/resource-scope-20261002/REPORT.md)를 따른다.
최종 scripts/check review는 format, dev/test warnings-as-errors, Credo strict, 빠른 Domain,
Dialyzer 및 전용 PG 전체 26개 회귀를 포함한다. 기존 독립 bigint/240단계 모델 회귀 9개도
변경 없이 별도로 재실행했다. scope 세 단위 map oracle와 concurrency/fault/bigint 사례는
fresh 독립 reviewer의 수용 판정을 대신하지 않는다. 외부 인가/QueryCut/성능 SLA/보안 전수 검증은 미수행이다.

## PRP revision bundle implementation

Explicit resource/subject-bound revision bundle and conditional revalidation were added without
changing the existing read snapshot or ETag contract. Final format/dev+test compile/Credo strict/
Dialyzer/full PG regression: 28 passed. Existing independent bigint/240-step model regressions:
9 passed. [Raw evidence, independent oracles and limits](verification/revision-bundle-20261002/REPORT.md).
Implementation edits are stopped pending fresh independent verification.

## Bundle version type correction

Fresh independent F1 (float schema versions producing not_modified) was corrected with strict
version and bundle equality; adjacent policy version validation now also requires integer 1.
Original byte-identical probe: 4 passed. Final static/Credo/Dialyzer and isolated PG regression:
39 passed. Public rows and original independent artifacts preserved.
[Correction evidence and limits](verification/bundle-version-fix-20261002/REPORT.md).
Implementation edits stopped pending independent acceptance.
