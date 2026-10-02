# bigint 마지막 전이 수정 및 재검증

판정: 보고된 세 경로는 실제 코드의 경계 결함이었다. 저장·CAS 도메인과 증가 가능한 도메인을 구분하여 수정했다. 새 독립 최종 확인은 아직 수행하지 않았다.

## 재현 및 계약 판단

기존 `verification/REPORT.md`, 변경하지 않은 `counter_boundary_test.exs` 세 테스트, 별도 보안 `fresh-security-20261001-independent/pg-addendum.md`를 먼저 읽었다. 전용 PG에서 수정 전 재현은 3개 assertion 모두 실패했다. 원시 출력은 [before.log](before.log)에 추가 보존했다. 기존 evidence·REPORT·보안 보고는 덮어쓰지 않았다.

PostgreSQL bigint 최댓값은 기존 테이블이 허용하며, 마지막 +1 성공을 반환하는 것도 기존 코드의 실제 행위였다. 그러나 Domain.revision이 이를 거부해 draft가 발행 불가가 된 것은 실제 결함이다. terminal 값과 overflow 시도의 구분이 없었던 점을 수정했다. 최댓값을 저장 값으로 받아들이는 대신 그 뒤의 새 증가를 명확히 거부한다. 테스트를 삭제하거나 성공 조건을 낮추지 않았다.

새 계약:

- `0 <= revision <= 9223372036854775807`은 유효한 저장·조회·CAS 값이다.
- `next_revision(max-1)`은 max, `next_revision(max)`는 revision_exhausted다. 음수·잘못된 타입·max+1은 invalid_revision이다.
- CAS 일치 확인 후 증가 가능성을 확인하고 **명령의 변경 함수를 실행하기 전에** exhaustion을 거부한다.
- 정책 발행은 멱등 요청 조회를 먼저 수행한다. 따라서 terminal generation에서도 최종 성공 요청의 원래 인자·기대 세대로 정확히 재시도하면 원래 결과를 돌려준다.
- max draft를 발행하는 것은 draft 증가가 아니므로 유효하다. 고정 정책 조회도 기존과 동일하게 현재 개인 사실을 반환한다.
- 초기화·wrap·카운터 감소·할당 복원은 추가하지 않았다. tenant/actor 신뢰 계약도 바꾸지 않았다.

독립 검증 `independent_test.exs`의 invalid-input 표는 기존 exclusive-max 구현을 전제로 max를 invalid_revision으로 기대했다. inclusive-max 계약에서는 현재 세대 5와 다른 max는 **유효하지만 stale한 CAS 값**이므로 conflict다. 해당 입력을 max+1로 바꾸고 max 유효성·stale conflict assertion을 추가했다. 모든 나머지 검증과 240단계 모델은 유지했다. 수정 전 파일은 [independent_test.before.txt](independent_test.before.txt)에 보존했다. 이는 새로운 독립 reviewer의 판단을 대신하지 않으며 최종 확인에서 다시 검토할 수 있다.

## 소스 변경 목록

- `lib/axiom/domain.ex`: inclusive bigint 저장 도메인, pure next_revision 결과.
- `lib/axiom/store.ex`: next_revision 결과를 transaction rollback으로 연결; 할당 bump에 검증된 다음 값을 사용.
- `lib/axiom.ex`: assignment 변경·draft 저장·policy 발행의 증가 가능성 사전 확인. 발행 멱등 결과 반환은 사전 검사보다 먼저 유지.
- `test/counter_exhaustion_test.exs`: terminal 조회/재시도, 모든 assignment 변경 거부, draft 발행, publish/rollback 고갈·경쟁·독립성 회귀 추가.
- `verification/independent_test.exs`: 위 bigint 입력 표 계약 수정 및 assertion 보강만 수행.
- `README.md`, `VALIDATION.md`: 계약·검증 추가 기록.

SQL schema·vendor·기존 test 파일·설계 문서는 변경하지 않았다. 새 증거·수정 전 독립 test 사본은 이 디렉터리에 있다. 기존 사용자 DB·형제/상위·Git·전역 설치·배포는 변경하지 않았다. 로컬 전용 PG의 새 무작위 tenant에만 경계 fixture를 seed했다. 큰 카운터/불연속 이력은 그 fixture의 압축된 실행 prefix이며 운영 데이터를 바꿨다는 뜻이 아니다.

## 주장별 증거와 미검증

| 주장 | 실행 증거 | 한계 |
| --- | --- | --- |
| 마지막 성공 값이 유효 | 원래 독립 counter 테스트 3개를 수정 없이 재실행, 3 passed. max draft의 publish 성공; assignment/generation의 후속 새 증가가 revision_exhausted임을 출력 | 이 세 원본 테스트만으로 모든 원자성·정확 재시도를 증명하지 않음 |
| overflow 원자 거부 | 새 회귀에서 max의 역할/node/할당/관계/정지 변경 모두 exhaustion, snapshot·history 동일 및 추가 역할 없음. draft body/revision 보존, publish 실패 후 release count=1·head/history 동일·실패 request ID 미점유 | 카운터 fixture는 SQL로 긴 실행 prefix를 압축. 수십억 회 실제 누적 실행 없음 |
| 최종 정확 재시도 | max generation에 도달한 publish/rollback의 원 인자 재시도 결과 완전 일치. 바뀐 request 내용은 idempotency_conflict | COMMIT 응답 손실·연결 장애 자체를 재현한 것은 아님 |
| 독립 카운터·경쟁 | assignment 고갈 후 정책 발행, generation 고갈 후 정지 변경 성공. max-1 assignment 경쟁에서 1 success(max)/1 conflict 후 max exhaustion | scheduler 모든 interleaving 증명·장기 soak 아님 |
| 기존 기능 유지 | mix check의 format·warnings-as-errors·실제 PG suite 16 passed. 독립 suite 6 passed: 기존 240단계 PRNG 모델, 원자 실패·CAS·tenant·결정적 snapshot 등 유지 | 한 PRNG seed 및 유한 모델. 카운터 복구 운영 기능·PG identity sequence 고갈은 미검증/별도 범위 |

원시 로그: [check.log](check.log), [counter-reproduction.log](counter-reproduction.log), [independent-model.log](independent-model.log). `mix check` seed=427023, 독립 실행 seed=20261002. 기존 DBConnection xref deprecation 경고는 여전하며 제품 compiler 경고와 구분한다. 비용 측정·mutation runner·보안 probe는 이번 수정에서 재실행하지 않았으며 기존 증거를 새 소스에 대한 새 측정으로 취급하지 않는다.

## 재현

전용 컨테이너 `axiom-dev-test-pg-20261002`, `127.0.0.1:55439/axiom_test`를 사용한다. DB 초기화/삭제·설치 명령은 없다. 전용 DB의 fault trigger suite를 동시에 실행하지 않는다.

```sh
mix check
mix test verification/counter_boundary_test.exs --seed 20261002
mix test verification/independent_test.exs --seed 20261002
```

## 유지한 보안 경계

trusted-local API만 구현된 상태를 유지한다. 외부 adapter의 사용자 인증·tenant 소유권·관리 권한, production DB 최소권한/RLS, quota·대규모 자원 고갈, 네트워크/commit ambiguity는 이번 수정으로 검증되거나 해결된 것이 아니다. gateway/context/PDP/PEP·새 정책 기능은 추가하지 않았다. 기존 보안 보고의 완료 수준과 미검증을 그대로 유지하며 본 수정은 correctness 경계 보정이다.

구현자는 재검증 후 코드 수정을 멈췄다. 부모가 배정할 새 독립 최종 확인은 pending이다.
