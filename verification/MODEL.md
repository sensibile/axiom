# 독립 검증 모델 (실행 전 고정)

요구의 신뢰된 로컬 호출 경계만 대상으로 한다. 구현자의 성공 문장은 oracle로 사용하지 않는다.

각 tenant 상태는 D=(draft revision, body), R=불변 release 집합, H=(generation,release), F=(assignment revision, nodes, roles, assignments, relations), EA/EP=추가 전용 이력이다.

1. 유효한 draft CAS만 D를 한 단계 올린다. schema/크기/참조 실패와 stale CAS는 모든 상태를 보존한다.
2. publish는 현재 D와 H CAS를 만족할 때만 R 추가/H 전환/EP 추가를 한 번에 커밋한다. 같은 요청과 fingerprint 재시도는 원 결과를 반환하며 부수효과가 없다. 다른 fingerprint는 충돌한다.
3. 사실 변경은 F revision을 정확히 1 올리고 사실과 EA를 같이 커밋한다. H/D/R는 보존한다.
4. rollback은 H/EP만 변경한다. 회수·정지·관계·F revision은 현재 값 그대로다.
5. 고정 버전 조회는 선택 R + 현재 F + 현재 head generation이다. 현재 조회는 H의 R + F다. 한 응답은 동일 PG snapshot에서 나온다.
6. 모든 참조/조회/멱등 키/경합은 tenant 안에서만 연결된다.
7. release와 이력은 UPDATE/DELETE에 대해 불변이다. raw SQL의 임의 INSERT/관리자 우회는 이 로컬 API 계약 밖이다.

실행 계획: seed 20261002 무작위 상태 기계, 경계 입력, barrier 경합, DB late failure와 응답 폐기 후 재시도, API snapshot 격리, 기존 suite의 소수 mutation 민감도. 원본 source 수정 금지. 전용 PG 외 DB 금지. 독립 검증 결과와 비용 수치는 실행 후 별도 REPORT에 기록한다.
