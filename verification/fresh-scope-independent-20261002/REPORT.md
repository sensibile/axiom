# Fresh independent resource-scope validation — 2026-10-02

Outcome: no validated product defect in the exercised contract. Six independently authored actual-PostgreSQL probes pass. This is bounded correctness evidence, not full security certification.

## Independence and environment

Acceptance expectations were derived from the delegated requirements, public API/docs and inspected production implementation, before reading existing scope tests. Writer reports/counts were not acceptance oracles. The existing scope test was later inspected for regression setup only. No applicable AGENTS.md exists in Axiom or its ancestor directories; sibling project guidance is outside this scope. README describes pure Domain/Scope and PostgreSQL Store/service shell FCIS separation. No network research was necessary for local code acceptance.

Only Axiom files were written: this verification directory and ordinary local build/cache outputs. No production, original tests, Akashic files, Git state, credentials, role/security settings or global installs were modified. SHA256 before/after covers lib, original test, priv, Mix/formatter configuration and public design/validation docs; `preservation.json` records equality.

The harness reads existing designated connection configuration without putting credentials in evidence. Before any DDL it makes a read-only identity query and checks database `axiom_test`, role `axiom_test`, internal port 5432, PG17 (170010). Connection endpoint is the configured loopback port 55439; PostgreSQL reports container address 192.168.215.2/32. An initial overly restrictive server-address assertion stopped before DDL; subsequent acceptance uses the designated identity checks. Own DDL/fixtures use schema `axiom_independent_scope_20261002`. Per-run fixture namespace is recorded in raw output (final: `5ad449b9188c75f6`). Existing public rows are serialized and compared before/after each successful run; final comparison is true. Fixtures remain for review. Standard regressions use their existing identity-verified dedicated scope schema and unique tenant fixtures.

## Actual results and commands

All commands run from `/Users/tonton/Documents/workspace/alaya/axiom`, with existing tools/deps. Local TCP lock/PG connectivity required sandbox escalation; it was approved. No external service connection was made.

| Check | Exact command | Final result | Evidence |
|---|---|---|---|
| Independent probes | `MIX_ENV=test mix run verification/fresh-scope-independent-20261002/probe.exs` | 6 pass, seed 20261002 | probe-final.raw |
| Production format | `MIX_ENV=test HEX_OFFLINE=1 mix format --check-formatted` | pass | check-0.raw |
| Probe format | `mix format --check-formatted verification/fresh-scope-independent-20261002/probe.exs` | pass | probe-format-final.raw |
| Compilation | `MIX_ENV=test HEX_OFFLINE=1 mix compile --force --warnings-as-errors` | pass | check-2.raw |
| Credo | `MIX_ENV=test HEX_OFFLINE=1 mix credo --strict` | pass | check-3.raw |
| Existing regression | `MIX_ENV=test HEX_OFFLINE=1 mix test --warnings-as-errors` | 26 pass, seed 469153 | check-4.raw |
| Dialyzer | `MIX_ENV=test HEX_OFFLINE=1 mix dialyzer` | pass, zero errors | check-5.raw |

Initial independent-probe formatting failed (check-1.raw); only the new probe was reformatted, with final passing evidence. Harness development also exposed a linked identity-process lifetime issue and repeat-run collisions from VM-local fixture IDs. Both were corrected in the harness, not production. `probe.raw` preserves the earlier five-pass run. Final six-probe execution exits 0 and public preservation succeeds. `checks.json` retains original check exit codes, including the superseded formatting failure. Existing dependency deprecation warnings appear in raw output and did not fail production checks.

## Independent assertions and event traces

- Exact namespace: same local ID in different spaces/scenarios/tenants remains separate; fork/other-space facts are empty. Scope returned exactly matches the request; assignment scope and relation object are full tuples. Other-resource ETag cannot yield not-modified.
- Negative input: nil/empty/missing scope, missing scenario, wildcard, empty ID, over-64-byte ID, uppercase normalization input, atom value and extra physical field reject. Registration, scoped assignment, relation and query reject invalid tuples. Unknown registered identity fails rather than defaulting. QueryCut/unknown/duplicate options reject.
- References: unknown role and wrong relation kind fail; a principal present only in another tenant fails. Legacy snapshot supplied a scope from another tenant fails; foreign tenant policy release fails.
- Authority history: grant at revision 4, revoke at 5, suspend at 6; rollback keeps revision 6, revoked assignment and suspended status. Event revisions are independently asserted as 1..6. Conditional read with pre-revocation ETag returns current data, then exact current ETag returns not-modified.
- Policy selection: a newer deny/write release becomes head while an explicitly selected older allow/read release remains selected. Returned selected release, newer head, generation 2, current revision 5 and revoked fact are individually asserted. Old publish retry returns original result; changed actor/reason payload on reused request ID conflicts.
- Concurrent CAS: six tasks submit the same expected revision 3; exactly one succeeds, five conflict, final revision is 4 and exactly one revision-4 event exists.
- Concurrent API read: a separate transaction locks the releases table. The real resource_snapshot proceeds through tenant/principal reads and blocks on release lookup; pg_stat_activity confirms that precise lock wait. Revocation/suspension then commit at revision 6 before the release lock opens. The blocked API returns coherent revision 4/active principal/active grant, while the next API returns revision 6/suspended/revoked. Thus response freshness is at its read snapshot; a concurrent completed revoke need not appear in an already-running read.
- Bigint: final successful scoped write at 9223372036854775807 is readable. Next scoped assignment and registration atomically reject exhaustion; negative, oversized, float, string and nil revisions reject. Before/after response equality proves these rejected operations did not change returned facts.

## Security boundary and candidate counterexamples

No authentication, management authorization, decision evaluation, context issuance, data-cut binding or external cache enforcement is implemented here. The local PAP/PRP trusted-caller boundary is explicit. `consumer_contract.decision=not_evaluated` and `knowledge_cut=external_not_verified` are returned descriptive fields; they do not prove a consumer checked anything.

The cache-misbinding candidates exercised were reuse across space/scenario, stale ETag after revoke/suspension and historical release against a newer head. Those produce distinct/current authority facts as expected. A true TOCTOU remains possible outside this service: obtain revision-4 data, revoke at revision 5, then use the earlier response without revalidation. Even the gated test legitimately returns the earlier read snapshot after a revoke has committed. The docs correctly give no offline lifetime, expiry or revocation SLA; consumers must establish freshness at use. This is an integration obligation, not a validated defect in this stated PAP/PRP contract.

Legacy APIs remain trusted and expose internal node IDs; they are not an authenticated external resource adapter. Direct SQL privileges can bypass service input validation and are outside the declared trusted API boundary. Digest-collision protection compares the full stored tuple/key; cryptographic collision resistance itself was not empirically established.

## Unrun and limits

No bounded mutation copies, exhaustive randomized event exploration, cryptographic collision search, hostile direct-DB actor assessment, resource incarnation/deletion/reuse, external Akashic QueryCut/retention integration, Arbiter/PDP/PEP enforcement, credential/authentication assessment, network/deployment security, consumer caches, latency/load/stress or crash/recovery testing were run. Scoped bigint coverage here is assignment/registration; draft/publication generation exhaustion is covered by the passing existing regression, not a newly independent exhaustive oracle. Snapshot schedule covers a confirmed intervening authority commit, not every possible publication/read interleaving. No validated defect requiring a minimal product repro was found. No remaining execution blocker.

Completed; stop editing product and verification artifacts after final hash capture.
