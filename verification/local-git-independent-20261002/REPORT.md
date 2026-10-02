# 독립 로컬 Git/gate 검증 (2026-10-02)

## 결론

axiom: 새 review exit 0. 빠른 Domain 3 passed, 실제 PostgreSQL 전체 회귀 16 passed. vendor DBConnection의 deprecated xref 설정 경고는 남는다.

작성중 format 명령, 커밋전 format 확인·compile/static·빠른 테스트, 리뷰 실제 I/O·전체 회귀의 연결은 확인했다. staged snapshot 보장과 비밀/런타임 파일 ignore 범위에는 누락이 있다. Hook 통과는 보안 검증 완료를 뜻하지 않는다.

## 범위와 보존

대상은 akashic/axiom뿐이다. Atheum 및 형제 Alaya는 읽거나 수정하지 않았다. 상위 alaya는 Git 저장소가 아니며 두 프로젝트는 각각 자체 .git 디렉터리를 갖는 독립 저장소다. 두 index 파일은 존재하지 않고 git ls-files는 빈 결과다. 기존 index staging, commit, remote, local/global Git 설정 변경은 하지 않았다. 임시 Git init/config/add는 /tmp fixture에만 수행했다. 제품 소스는 변경하지 않았다. 이 보고서와 증거만 사용자 허용 verification 경로에 추가했다. 빌드 캐시/akashic artifacts 및 요청된 전용 테스트 DB에는 검사 실행의 부수효과가 있다.

akashic/AGENTS.md를 읽었다. axiom/AGENTS.md 및 상위 cwd/AGENTS.md는 존재하지 않는다. scripts/check, .githooks/pre-commit, .gitignore, formatter, manifests, LOCAL_GIT.md와 실제 테스트 경계를 읽었다. source-hashes.json은 검증 대상 제품/설정/테스트의 SHA-256이며 verification-metadata.json의 재확인 불일치는 []이다. 캐시/build/Git/보고서 디렉터리는 hash 대상에서 제외했다.

## 실제 정적 분석 분류

- Rust: cargo clippy --workspace --all-targets --locked -- -D warnings는 실제 lint 정적 분석이며 rustc compile/type checking을 동반한다. precommit은 기본 feature, review는 io feature Clippy도 실행한다. cargo test/build는 compile 및 동적 실행으로, 그 자체를 lint라고 부르지 않는다.
- Elixir: dev/test mix compile --force --warnings-as-errors는 compiler 정적 검사/경고 gate다. mix format은 포맷 검사이며 lint 또는 타입 분석이 아니다. ExUnit은 동적 테스트다.
- 두 Elixir 프로젝트 모두 Credo와 Dialyzer/Dialyxir는 의존성/호출 미구성이다. 독립 lint/타입 분석을 제공한다고 볼 수 없다. axiom에는 Rust가 없으며 LOCAL_GIT.md의 Rust Clippy 문구는 적용 대상 없는 복사 문구다.
- 사용자 정적 분석 요구가 compiler warning gate 이상(Elixir lint/타입 분석)을 의미한다면 현재 미충족이다. 수정안만 제시한다: 버전/오프라인 의존성 및 PLT 저장 범위를 먼저 결정한 뒤 Credo strict를 precommit에, Dialyzer를 적어도 review에 연결하고 도구/PLT 부재를 비영 종료한다. 임의 설치는 하지 않았다.

## Hook/실패/root 격리 검증

두 프로젝트 로컬 core.hooksPath=.githooks이며 scripts/check와 pre-commit은 실행 권한 0755다. 복사한 실제 hook을 임시 Git 저장소 하위 폴더에서 git hook run pre-commit으로 실행했다. stub check가 물리 cwd=root와 인자 precommit을 검증하며 성공 0, 실패 7은 hook에서도 각각 0/7이다.

실제 scripts/check를 격리 복사하고 fake 도구로 stage 순서와 실패 전달을 검증했다(stage-results.json). 이는 실제 제품 테스트 통과 증거와 구분된다. axiom은 child exit 7을 그대로 전달하며 akashic run()은 child 비영 코드를 gate exit 1로 정규화한다. 어느 쪽도 실패를 성공으로 바꾸지 않는다. format/compile 실패 이후 빠른 테스트는 실행되지 않았다. format mode는 작성용 rewrite 명령이고 precommit은 --check 형식이다. root와 다른 /tmp cwd에서 직접 진입해도 stage 실행이 성립했다. akashic ROOT는 script resolve 기반, axiom cd는 script 경로 기반이다.

fixture-results.json: 동일 Elixir 파일의 staged 문법 오류/working tree 정상 fixture에서 working tree mix format --check-formatted=0, staged 내용을 materialize하면 1이다. 실제 hook은 index를 export/검증하지 않고 working tree 전체를 검사하므로 잘못된 staged 내용이 누락될 수 있다. 역으로 staging과 무관한 working tree 오류가 커밋을 막을 수 있다. 수정안: staged tracked snapshot을 별도 temp tree로 export해 gate를 실행하거나 부분 staging을 명시적으로 비영 거부한다. 의존성/빌드 캐시를 snapshot과 혼합하지 않도록 별도 경로를 사용한다. 현재 LOCAL_GIT.md의 diff 확인 안내는 자동 보장이 아니다.

## Ignore 격리 검증

.gitignore만 복사한 임시 저장소에서 git check-ignore --no-index를 사용했다. 경로만 생성/검사하고 비밀값은 기록하지 않았다. .env 및 변형, .pem/.key, 일반 .db/.db-*와 SQLite 일부, Python cache는 ignore된다. .env.example 추적 가능은 의도된 예외다. 제품별 정상 build 경로(akashic target/.cache/elixir _build·deps, axiom _build/deps)는 ignore된다.

두 프로젝트 공통 누락: local.sqlite3-wal, local.sqlite3-shm, data/rocksdb/CURRENT, data/rocksdb/000001.sst, .aws/credentials, .npmrc, nested/erl_crash.dump 및 elixir/erl_crash.dump. axiom .cache/foo도 ignore되지 않는다. 임의 RocksDB/credential 경로가 실제 사용중이라고 주장하지는 않으며 알려진 위험 경로에 대한 패턴 누락이다. akashic 전용 artifacts/demo-db는 artifacts ignore로 보호된다. 다른 언어/레이아웃의 build probe 미일치는 해당 프로젝트 실제 사용 여부와 구분해야 한다.

수정안: *.sqlite3-*와 프로젝트 런타임 DB 디렉터리, 필요한 로컬 credential 설정 경로, 재귀 erl_crash.dump, axiom 프로젝트 cache 경로를 추가하고 예제 설정 예외를 유지한다. ignore는 이미 추적된 비밀을 보호하지 못하므로 추적 대상 경로 검증도 별도 gate로 설계한다. 이번 저장소는 tracked 파일이 없다. 비밀 설정 경로는 axiom/lib/axiom/test_database.ex이며 값은 보고하지 않는다.

## 실행 근거와 한계

새 실행 stdout 로그는 /tmp/alaya-independent-gates-20261002/axiom-review-authorized.log에 있다. 초기 sandbox 실행은 Mix 로컬 TCP lock EPERM으로 실패했고 권한 승인된 로컬 재실행을 사용했다. 패키지/도구 설치는 하지 않았다. axiom full regression은 test_helper를 통해 127.0.0.1:55439의 axiom_test 전용 PostgreSQL과 schema prepare를 실제 실행한다. akashic integration은 임시 디렉터리의 실제 RocksDB 및 Elixir→Rust 프로세스 경계를 실행한다. 도구 stub fixture 성공은 실제 IO 성공을 대체하지 않는다.

실행 시점 source hash와 gate hash를 보존했으며 전역/상위 전체 파일의 사전 baseline이 없으므로 그 영역 전체의 byte-for-byte 불변을 증명했다고 주장하지 않는다. 해당 영역에 변경 명령은 수행하지 않았다. 검토 범위는 로컬 개발 gate 구성으로, 별도 exhaustive security scan 결과가 아니다.
