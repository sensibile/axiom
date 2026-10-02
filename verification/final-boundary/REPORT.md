# 독립 최종 bigint 경계 검증

판정: 요청된 revision 경계와 주변 기능에 대해 재현된 생산 코드 결함 없음. 실제 PostgreSQL 17.10에서 aggregate 28/28, 추가 독립 경계 3/3, 별도 랜덤 reference 모델 3 seed × 200단계, 원본 PG 보안 probe 1/1 통과. 전체 보안 또는 운영 준비 완료 판정이 아니다.

## 실행 범위와 고정 근거

현재 `lib/axiom.ex`, Domain, Store 및 schema를 직접 읽어 검증 설계를 만들었다. ancestor AGENTS.md 후보(`/AGENTS.md`부터 현재 경로까지)는 없었다. worktree-first-dev SKILL은 읽었으며 사용자 Git 금지가 우선하여 Git/worktree/설치/배포 없이 현재 소스를 검증했다. 생산 코드 수정 없음. 시작 시 기존 파일 191개의 SHA256을 `before.json`에 고정했고 `after.json`과 `source-preservation.json` 비교에서 changed_or_missing=[]다. 기존 verification 증거와 테스트도 이 고정에 포함된다.

Docker inspect는 `/axiom-dev-test-pg-20261002 true`, host `127.0.0.1:55439` → container `5432`를 확인했다. 연결에서 database/user 모두 axiom_test, server port 5432와 PostgreSQL 17.10을 확인했다. 다른 DB·형제·상위 데이터에 연결하지 않았다. 원시 identity는 aggregate.log 앞부분에 있다. Docker 소켓·PG 연결·Mix TCP lock이 sandbox에서 막혀 승인된 escalated 실행으로 진행했다.

새 임의 tenant만 생성·seed했고 원래 데이터는 삭제하지 않았다. fixture는 보존했다. aggregate runner는 test_helper의 schema prepare를 호출하지 않고 기존 schema를 사용한다. 기존 aggregate의 late-fault 테스트는 지정 테스트 DB에 임시 trigger/function을 생성하고 after에서 제거한다. 기존 row 전부를 JSON 문자열로 스냅샷하고 끝에 포함 여부를 비교하여 9개 테이블 모두 기존 row 보존을 확인했다(`db-before.json`, `db-preservation.json`, aggregate.log). 이는 전체 schema/sequence의 완전 동일성 판정은 아니다. 새 releases 생성에 따른 전용 DB identity sequence 증가는 정상이다.

## 독립 reference와 경계표

수학적 reference는 정수 0≤r≤M이면 유효, CAS가 다르면 conflict, 일치하며 r<M이면 r+1, r=M이면 revision_exhausted다. M=9223372036854775807. publish의 draft는 양수이고 증가시키지 않는다. publication receipt의 동일 fingerprint는 새 증가 검사 전에 원래 결과를 반환한다. reference 기대값 생성은 제품 Domain.next_revision을 호출하지 않는다.

| API 입력/상태 | 독립 기대값 | 실제 검증 |
| --- | --- | --- |
| 0, 1, 2^53−1, 2^53, M−2, M−1 | 정확한 +1 정수, DB·출력 일치 | 경계 fixture 및 JSON 왕복 |
| M 저장·조회·expected | 유효; 새 증가만 exhaustion | snapshot/draft, 모든 assignment 변경 API |
| M draft, generation<M | publish 성공, 정확 retry 동일 | 독립 경계 및 원본 counter suite |
| M−1 generation → M | publish/rollback 성공, DB receipt와 반환값 동일 | aggregate 및 별도 terminal rollback |
| 최종 성공의 원 expected로 exact retry | 동일 결과, 추가 row 없음 | full-row 비교·랜덤 retry |
| 같은 request의 변경된 actor/reason | idempotency_conflict | terminal/일반 경계 |
| M에서 새 publish/rollback/save/assignment | exhaustion; 9개 테이블 전체 row 동일 | 독립 full-row 비교 |
| −1, M+1, nil, float, 문자열, map/list/bool expected | invalid_revision; row 동일 | 새 입력표 |
| M stale expected | conflict | 기존 독립 oracle 수정 검토/aggregate |
| invalid UTF8/map/list/nil/float/overflow publish argument | invalid_argument; row 동일 | 별도 입력표 |

32개 revision fixture: 위 7개 고정값과 PRNG `:exsss {811,2026,991}`의 M 부근 25개 값. draft 0은 schema상 불허이므로 zero case draft는 1로 분리했다. 초기 노드·역할은 새 tenant에 SQL seed하여 카운터 0/1과 기존 이벤트 PK가 충돌하지 않도록 했다. 큰 카운터는 긴 실행 prefix의 압축 fixture이며 수십억 회 실제 증가를 실행한 것이 아니다.

별도 랜덤 모델은 seeds 20261003/20261004/20261005, `:exsss {seed,317,817}`, 각각 200단계. assignment=M−15, generation=M−11, draft=M−9에서 시작한다. 상태·개인할당·draft·publish·rollback·정확 retry·stale CAS를 선택하고 매 단계 snapshot 정책/개인 사실, draft body/revision, DB event/publication/release 수를 reference와 비교한다. 모두 M에 도달한 후 고갈 및 retry를 검증했다. 600단계 원시 선택과 결과는 random.log에 있다. 기존 240단계 seed 모델은 aggregate에서 추가 실행했다.

## 주변 회귀와 기존 검증 보존

aggregate는 기존 domain/service/counter_exhaustion, 원본 counter_boundary, independent suite를 삭제·skip 없이 모두 load했다(25개). 새 3개 독립 검증을 합쳐 28 passed. 보강한 모든 terminal assignment API 전체-row 검사도 focused.log에서 3 passed. 정책 release 고정 조회도 현재 개인 사실을 반환하고, rollback은 revoked assignment/relation 및 suspended principal을 복원하지 않는다. assignment 고갈과 정책 발행, 정책 고갈과 개인 변경은 독립적이다. tenant별 동일 식별자·foreign release/role/node·CAS 경쟁·동일 request 경쟁·repeatable snapshot·실제 late SQL rollback도 통과했다.

`original-comparison.json`은 초기 original-manifest의 SHA와 현재 파일을 비교한다. 기존 파일 중 차이는 README, VALIDATION 및 production 세 파일뿐이며 original test/schema/vendor hash는 동일하다. initial manifest만으로 이전 production 내용 전체를 복원할 수는 없다. 수정 전 independent 파일은 기존 bigint-fix/independent_test.before.txt와 현재를 직접 diff했다(`oracle-change.diff`). 변화는 exclusive-max invalid 입력을 M+1로 바꾸고 M 유효성과 stale M conflict assertion 두 개를 추가한 것뿐이다. 240단계 모델과 다른 assertion의 삭제/완화는 없다. 요구 계약에서 M은 valid이므로 이 기대값 변경은 정당하며 새 full-row 경계 검증으로 보강했다. counter_boundary 원본은 그대로 실행했다.

첫 aggregate 27/28 실패는 검증 fixture 자체가 초기 event revision 1을 둔 채 카운터를 0으로 낮춰 발생시킨 unique constraint였다. 생산 결함으로 판정하지 않았다. 실패 script/log를 independent.fixture-error.txt 및 aggregate.fixture-error.log에 보존하고 초기 사실을 직접 seed하는 새 fixture로 수정했다. 그 후 aggregate 28/28 및 focused 3/3이 통과했다. 첫 실행 로그의 기존 row 보존도 전부 true였다.

## 보안 입력 검증과 미검증

수정하지 않은 기존 fresh-security domain_probe와 pg_probe를 재실행했다. SQL형 identifier, foreign tenant role/node/release, immutable DB row, 동일 retry 8개, CAS/publication race, 현재 개인 사실 rollback, late FK transaction failure, 80회 원자 snapshot 검사가 통과했다. Domain probe에서 `schema_version: 1.0`은 1로 수용하는 기존 동작을 다시 관측했다. 정수 schema_version의 엄격 타입 요구가 별도로 있다면 보완이 필요하다. 이것을 이번 bigint 성공으로 해결됐다고 주장하지 않는다.

trusted-local 경계 밖 외부 사용자 인증·tenant 소유권·관리 권한은 미구현/미검증이다. production least privilege/RLS, rate/quota/resource exhaustion, TLS/네트워크, COMMIT 응답 손실과 장애 복구, 장기 soak/모든 경쟁 interleaving, release identity sequence 고갈, 운영 counter 복구는 이번 범위 밖이다. 보안 probe는 전체 security audit가 아니다. 새 mutation/cost 측정은 수행하지 않았다.

format --check-formatted 통과, MIX_ENV=test compile --warnings-as-errors 통과(기존 vendor DBConnection xref deprecation warning은 compile.log에 보존). `mix check` alias 자체는 실행하지 않고 formatter/compiler 및 동일 기존 ExUnit tests를 custom runner로 실행했다. test helper의 schema 재적용을 피하기 위한 것이다.

## 재현

설치·DB setup·reset 명령은 필요 없다. 현재 전용 컨테이너와 기존 dependency/build 환경에서 다른 writer 없이 실행한다. 새 랜덤 fixture 이름은 매 실행 바뀌며 PRNG 선택은 seed로 재현한다. 새 증거 경로를 사용하여 기존 로그를 덮어쓰지 않는다.

```sh
run_dir="verification/final-boundary/replay-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$run_dir"
AXIOM_FINAL_EVIDENCE_DIR="$run_dir" MIX_ENV=test mix run verification/final-boundary/runner.exs > "$run_dir/aggregate.log" 2>&1
MIX_ENV=test mix run verification/final-boundary/focused.exs > "$run_dir/focused.log" 2>&1
MIX_ENV=test mix run verification/final-boundary/random.exs > "$run_dir/random.log" 2>&1
elixir verification/fresh-security-20261001-independent/pg_probe.exs > "$run_dir/security-pg.log" 2>&1
elixir verification/fresh-security-20261001-independent/domain_probe.exs > "$run_dir/security-domain.log" 2>&1
mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
```

검증 실패/오류를 지나치지 말고 각 명령 exit status와 ExUnit 결과를 확인한다. runner의 post-suite 보존 결과도 함께 확인한다. 실행 fixture와 reference case는 원시 로그에 남는다.
