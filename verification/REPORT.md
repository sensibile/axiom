# axiom 첫 기능 독립 검증

판정: 신뢰된 로컬 PAP/PRP 경계의 주요 불변식은 실제 PostgreSQL에서 반례를 찾지 못했다. 그러나 bigint 마지막 전이에서 다음 명령에 쓸 수 없는 revision/generation을 성공 반환하는 경계 결함 1건(세 경로)을 발견했다. 따라서 무조건적인 전체 통과 판정은 하지 않는다. 보안 전체 검증은 수행하지 않았다.

## 범위와 원본 보존

검증 시작 전에 [MODEL.md](MODEL.md)에 상태 모델과 불변식을 기록했다. 구현 문서의 성공 문장은 oracle로 쓰지 않았다. 코드와 SQL을 읽고 요구를 독립 상태 기계로 재구성한 후 실제 API/PG 결과를 비교했다. 적용 가능한 ancestor/axiom AGENTS.md는 발견되지 않았다. worktree-first-dev 스킬을 읽었으며, 명시적 사용자 지시인 Git 금지/axiom 안 검증 산출물 추가가 우선되어 Git/worktree 작업은 하지 않았다. 별도 보안 스킬은 이번 기능 검증의 범위가 아니어서 실행하지 않았다.

[원본 manifest](evidence/original-manifest.json)는 lib/priv/test/config/문서/vendor 등 기존 파일 152개를 SHA-256으로 고정한다. 빌드 산출물 `_build`는 제외했다. [종료 확인](evidence/source-preservation.json)에서 기존 파일 변경/삭제 0, verification 밖 신규 source 파일 0이다. 생산 코드·기존 테스트·기존 README/VALIDATION/PAP_PRP_DESIGN·vendor를 수정하지 않았다. 기존 원시 문서/증거를 보존했다. 새 파일은 verification 안에만 있다. Git, 설치, 배포, 상위/형제 파일 변경은 하지 않았다.

[컨테이너 증거](evidence/container.log): `axiom-dev-test-pg-20261002`, running, `127.0.0.1:55439 -> 5432`. [DB identity/정리 확인](evidence/database-identity-cleanup.log): database/user `axiom_test`, PostgreSQL 17.10. 다른 DB에 접근하지 않았다. 새 무작위 tenant의 검증 데이터·불변 이력은 전용 DB에 보존한다. 임시 결함 복사본은 제거했고, 늦은 실패 trigger/function은 after에서 제거했다. 확인 시 테스트용 fault trigger는 0개다. DB/컨테이너 삭제·reset은 하지 않았다.

## 주장별 실행 증거

| 주장 | 독립 실행과 반례 탐색 | 결과/한계 |
|---|---|---|
| draft schema·참조·CAS | empty/101 rules, 33 actions, 중복 actions, effect/kind/unknown field, 64/65 byte ID, 잘못된 revision, unknown role; 100 rules × 32 actions 수용; 12개 동시 draft 쓰기 | 거부 후 draft/revision 보존. 경합 1 성공/11 conflict. 실제 JSONB 저장 |
| release·head·감사 원자 발행 | 무작위 publish/rollback; 감사 INSERT 직전 PG check_violation; 실패 후 같은 요청/actor로 재시도 | release/head/publication/fact 부분 커밋 없음. 실패가 멱등 키를 점유하지 않음 |
| 발행 멱등 | 동일 요청 12개 barrier 경합; head가 이동한 뒤 최초 요청 재시도; actor/operation 변경 충돌 | 동일 결과 12회, release 1개. 최신 head로 옛 응답을 치환하지 않음 |
| 응답 유실 재시도 | 실제 rollback commit 후 caller가 결과를 consumer에 전달하지 않고 종료; 모니터로 종료 확인 후 동일 요청 재시도 | 원 결과 반환, publication 중복 없음. 전송 계층의 TCP ACK/COMMIT 응답 유실을 재현한 것은 아님 |
| 개인 역할·관계·정지 독립 revision/이력 | seed 20261002의 240단계 상태 기계. 매 단계 현재 값, revision, 이력 연속성, 모든 이전 release body와 현재 사실을 비교 | 성공 시 사실 revision +1, 정책 generation 독립. stale/invalid 명령은 상태 보존. 한 seed의 유한 탐색 |
| rollback이 회수/정지를 복원하지 않음 | 무작위 revoke/regrant/suspend/reactivate/rollback 조합 + 기존 명시적 rollback 테스트 | 정책만 전환하고 현재 개인 사실 보존. 임시 rollback revival mutation도 기존 suite가 탐지 |
| 동일 PG 읽기 snapshot | 실제 Axiom.snapshot이 tenant head를 읽은 후 node SELECT에서 ACCESS EXCLUSIVE lock으로 대기. pg_stat_activity에서 대기 확인 후 writer가 정책 generation/정지를 같이 커밋 | 대기 중 API 응답은 old generation 1 / assignment 4 / active; 다음 응답은 2 / 5 / suspended. 호출 내부 첫 SELECT부터 커밋 교차를 결정적으로 검증 |
| 현재·고정버전 조회 | 240단계마다 누적된 모든 release를 다시 조회해 body 불변성과 현재 개인 사실 비교 | 고정 정책 + 현재 assignment/status/head generation 계약과 일치 |
| tenant 경계 | 동일 principal/role/request ID인 다른 tenant, foreign release, ETag 재사용, 기존 복합 FK 테스트 | foreign release 거부, ETag 분리, 다른 tenant 사실/이력 보존. 인증·관리자 권한 검증은 별도 |
| 저장 불변성 | releases/assignment_events/publications 각각 UPDATE와 DELETE | 모든 테이블 check_violation, 행 유지. owner/superuser TRUNCATE/trigger 제거 등 관리 우회 미검증 |

[baseline.log](evidence/baseline.log): 원본 suite 11 passed. [independent-final.log](evidence/independent-final.log): 독립 6 passed. 최초 독립 4항목 실행 로그도 [independent.log](evidence/independent.log)에 보존했다. 개수 자체가 기능의 완전성을 증명하지 않으며 위 불변식/오류 후 상태 비교가 근거다.

## 발견 결함: 카운터 마지막 성공이 호출 계약 밖 값을 반환

낮은 우선순위의 bigint 경계 결함이다. `Axiom.Domain.revision/1`은 `0 <= n < 9223372036854775807`만 수용하지만 save_draft/change/publication은 마지막 허용 입력 `9223372036854775806`에 +1을 적용하고 성공한다. PostgreSQL bigint와 테이블 CHECK는 결과 `9223372036854775807`을 허용한다.

새 검증 tenant에 SQL fixture로 해당 경계 상태를 seed한 결과:

- assignment 변경: 성공 결과 revision=9223372036854775807. 다음 역할 등록은 `{:error, :invalid_revision}`.
- draft 저장: 성공 결과 revision=9223372036854775807. 그 draft 발행은 `{:error, :invalid_argument}`; 다음 draft 편집도 허용 revision 밖이다.
- publish: 성공 결과 generation=9223372036854775807. 다음 publish는 `{:error, :invalid_revision}`. 기존 request의 정확한 재시도는 원래 기대 generation으로 가능하지만 신규 전이는 막힌다.

세 property 실패는 [counter-boundary.log](evidence/counter-boundary.log), 재현은 [counter_boundary_test.exs](counter_boundary_test.exs)에 있다. 예상한 실패를 통과로 위장하지 않았고 명령 exit=2였다. 정상 호출만으로 이 상태에 도달하려면 거의 2^63번 전이가 필요하므로 현재 운영에 즉각적인 차단 위험은 낮다. SQL fixture는 이 거대한 실행 prefix를 압축하며 일반 caller가 카운터를 직접 설정할 수 있다는 주장은 아니다. 상한 도달 시 성공 전에 명시적으로 exhaustion을 거부하거나 terminal 상태/복구 계약을 정의하는 것이 수정 방향이다. 요청대로 구현은 수정하지 않았다.

## 기존 테스트 민감도

[mutation_runner.py](mutation_runner.py)가 axiom/verification/mutation-copy에 소스·vendor·기존 build를 복사해 아래 한 변경씩 적용하고 원본 suite만 실행했다. mutation은 생산 원본이나 DB schema를 수정하지 않았다. 실행은 순차적이고 끝에 임시 복사본을 제거한다. [정확한 before/after와 exit](evidence/mutation-summary.json)를 보존했다.

| mutation | 기존 suite가 잡은 실패 | 결과 |
|---|---|---|
| READ COMMITTED로 격리 약화 | pinned old-head/facts, concurrent paired-write snapshot | 9/11 passed, exit 2 |
| assignment CAS 무시 | stale revision, concurrent CAS 1 winner | 9/11 passed, exit 2 |
| request fingerprint 무시 | 동일 request ID의 바뀐 generation 허용 | 10/11 passed, exit 2 |
| rollback에 할당/정지 활성화 추가 | 회수/정지 보존 | 10/11 passed, exit 2 |

각 mutation 로그는 evidence/mutation-*.log에 있다. 모두 컴파일 후 해당 행위 assertion에서 실패했으며 setup/컴파일 실패를 kill로 세지 않았다. 소수의 대표 결함만 검사했으므로 mutation score 전체나 모든 실패 경로의 민감도를 주장하지 않는다. 위 카운터 문제는 원본 suite가 잡지 못했다.

## 기능적 비용

[measure.exs](measure.exs), [원시 cost.log](evidence/cost.log). warmup 10회 후 직렬 호출, snapshot n=100 / publish n=30 / 사실 변경 n=30. 실제 localhost PG network/transaction 포함, draft 저장은 publish 시간에서 제외. 큰 데이터의 100 rule은 같은 rule 반복이므로 JSONB 압축에 유리하며 일반 대형 정책의 저장비용으로 일반화하지 않는다.

| 데이터 | snapshot median/p95 | publish median/p95 | 사실 변경 median/p95 | 응답 JSON / release JSONB |
|---|---|---|---|---|
| 1 rule, 1 assignment | 2.360 / 2.928 ms | 2.995 / 3.713 ms | 2.264 / 3.634 ms | 571 / 160 bytes |
| 100 rules, 200 assignments | 3.489 / 4.087 ms | 3.911 / 5.584 ms | 2.055 / 2.722 ms | 19231 / 311 bytes |

실제 cost tenant ID는 로그에 있다. throughput, 배포 환경 p95, SLA, 다중 tenant 공정성, 고경합 capacity, CPU/메모리/총 인덱스 저장비용은 측정하지 않았다.

## 재현과 남은 미검증

아래는 프로젝트 root에서 실행한다. 지정 컨테이너가 이미 실행 중인지 확인하고 다른 DB로 연결 정보를 변경하지 않는다. fault trigger 테스트가 있어 같은 전용 DB에서 동시 suite를 실행하지 않는다. 설치/DB 초기화·파괴 명령은 없다.

```sh
cd /Users/tonton/Documents/workspace/alaya/axiom
docker inspect axiom-dev-test-pg-20261002 --format '{{.State.Status}} {{json .NetworkSettings.Ports}}'
mix test --seed 20261002
mix test verification/independent_test.exs --seed 20261002
# 알려진 경계 결함: 현재 구현에서는 3 assertion 실패 / exit 2
mix test verification/counter_boundary_test.exs --seed 20261002
python3 verification/mutation_runner.py
mix run verification/measure.exs
```

state-machine PRNG는 ExUnit 순서와 별개로 `:exsss, {20261002,71,991}`에 고정했다. tenant 이름은 충돌을 피하기 위해 crypto random이며 PG release ID는 누적 DB 데이터에 따라 달라진다. 불변식/행위 순서는 재현 가능하고 절대 ID·wall-clock latency는 동일하지 않다. runner 재실행은 해당 mutation 로그를 덮어쓰므로 이번 원시 증거가 필요하면 먼저 evidence 디렉터리를 axiom 내부 다른 경로로 보존해야 한다.

최초 sandbox 실행은 Mix의 TCP filesystem lock에서 `:eperm`으로 막혔다. 지정 로컬 테스트 자원 접근으로 escalation 승인 후 실행했고 추가 설치/외부 네트워크 접근은 하지 않았다. vendored dependency에서 xref deprecation warning이 있었으며 기능 테스트 실패와 구분했다.

연결 중단/PG 재시작/프로세스 kill 중 COMMIT ambiguity, 실제 TCP 응답 손실, deadlock/timeout 복구, 여러 seed의 장기 soak, migration/백업/운영 최소권한/RLS, 외부 인증·gateway/context·PDP/PEP, 전이 관계·시간 기반 사실은 미검증 또는 범위 밖이다. 특히 transport-level response loss를 검증했다고 주장하지 않는다. 별도 보안 검증은 후속이다. 알려진 낮은 우선순위 경계 결함 이외에 이번 관찰에서 중요한 기능 반례는 없었으며, 실행을 막는 잔여 blocker는 없다.
