# 로컬 개발 검사

각 프로젝트 루트는 독립 로컬 Git 저장소다. 커밋과 원격은 설정하지 않았다.
새 checkout에서는 `git config --local core.hooksPath .githooks`로 hook을 연결한다.

- 작성 중: `./scripts/check format`
- 커밋 전: `./scripts/check precommit` (pre-commit hook이 같은 명령 실행)
- 리뷰 전: `./scripts/check review`

검사 명령은 working tree 전체를 대상으로 한다. Hook은 unstaged tracked 변경이나
ignore되지 않은 untracked 파일이 있으면 비영 종료한다. 따라서 부분 staging은 지원하지 않는다.
파일의 추적 여부와 staging은 사용자가 직접 결정하며 hook은 stage/stash/파일 수정을 하지 않는다.
ignore된 캐시와 전용 테스트 DB는 index snapshot 밖의 실행 의존성이다. 검사 중 동시 편집은 피한다.
직접 `scripts/check`를 실행하면 index 일치 검사는 수행하지 않는다. 이는 hook에서만 수행한다.
강제 추가한 ignore 파일을 Git이 숨겨주지는 않으며 ignore 자체는 비밀 스캐너가 아니다.
실패/도구 누락은 비영 종료한다.
FC/IS와 테스트 더블 지양, 필요한 경우 mock보다 fake 및 실제 구현 공통 계약이라는 기존 기준을 유지한다.
Elixir compiler warnings-as-errors 및 Credo strict를 precommit에서 실행한다.
review에서는 Dialyxir/Dialyzer 타입 분석과 실제 I/O/전체 회귀를 추가한다.
Credo 1.7.19, Dialyxir 1.4.7 및 관련 의존성은 공식 Hex 캐시를 프로젝트 vendor에 복사한 dev/test 의존성이다.
Hex 공개 API 체크섬과 비교하고 패키지 내부 CHECKSUM도 검증했다.
PLT는 프로젝트 `.cache/plt` 아래에만 생성하며 처음 실행은 수십 초가 걸린다.
새 checkout에서는 dev/test 환경의 `mix deps.compile`을 먼저 실행한다. gate는 패키지를 다운로드하지 않는다.
기존 증거/재현 문서는 보존한다. 캐시, DB, 비밀 설정은 ignore하고 파일을 삭제하지 않는다.

빠른 테스트는 기존 Domain ExUnit 파일을 직접 실행하여 DB setup을 실행하지 않는다.
리뷰 전체 회귀는 기존 test_helper와 전용 127.0.0.1:55439/axiom_test를 사용한다.
이 테스트 DB의 기존 fixture 방식과 임시 trigger 정리를 유지하며 다른 DB는 사용하지 않는다.
vendor는 오프라인 재현 의존성이므로 추적 대상이다.

## 최초 설정 검증 기록 (Credo 추가 전, 2026-10-02)

임시 격리 Git 저장소에서 `git hook run pre-commit`으로 동일 hook을 실행했다.
검사 fixture 성공(0)을 통과하고 실패(7)를 그대로 반환했다. 제품 소스와 실제 커밋은 변경하지 않았다.
초기 sandbox에서는 Mix TCP 잠금이 EPERM으로 차단되어 로컬 실행 권한으로 재검사했다.

실제 검사: precommit 포맷/dev·test 컴파일/Domain 3개 통과. review 동일 검사와 전용 PostgreSQL 전체 16개 통과.
벤더 DBConnection의 기존 deprecated xref 설정 경고는 남아 있으며 앱 컴파일 경고는 없었다.

## Credo 정리 전 보완 결과

Credo 정리 전 precommit/review는 지적에서 실패했다. Dialyzer는 별도 실행에서 오류 0개로 통과했다.
상세 결과와 미실행 stage는 [보완 보고서](verification/local-git-followup-20261002/REPORT.md)를 따른다.

## 현재 gate와 최초 staging 정책

동작 보존 정리 후 현재 결과는 [최종 검증](verification/local-git-final-20261002/REPORT.md)을 따른다.
기존 실패 증거는 역사 기록으로 유지했다. 초기 저장소에는 모든 제품/설정 파일이 untracked이므로
지금 `git hook run pre-commit`은 의도적으로 거부한다. 추적할 파일을 사용자가 검토하여 stage한 뒤,
비ignore untracked/unstaged 파일이 없는 상태에서 hook을 실행해야 한다. 검사 대상 working tree가
실제 커밋 index와 다를 수 있는 첫 커밋/부분 staging을 자동으로 통과시키지 않는다.
이 작업은 실제 index를 생성·변경하지 않았다. 의존성 cache/DB와 실행 중 편집까지 포함한 atomic
staged-only sandbox는 제공하지 않는다. Git 숨김 플래그는 사용하지 않아야 한다.

최종 결과: precommit/review의 모든 필수 stage가 통과했다. 현재 설정에 남은 gate 실패 blocker는 없다.
초기 untracked 상태의 hook 거부는 별도의 의도한 staging 정책이다.
