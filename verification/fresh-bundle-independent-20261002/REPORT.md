# Fresh independent acceptance — revision bundle version types (2026-10-02)

**Bounded acceptance: PASS.** The previous F1 reproducer now rejects `bundle_schema_version: 1.0` and `data_schema_version: 2.0` with `invalid_revision_bundle`. No reproducible defect found in this scoped rerun. Product editing stopped; no product fixes or original test rewrites performed.

## Independent contract and source

Read README resource revision bundle contract, Axiom snapshot response and option handling, Scope bundle validation, Domain policy validation, Store snapshot transaction, TestDatabase identity guard and scripts/check. No applicable ancestor or axiom AGENTS.md was found. Expectations came from the API contract: version integers are exact; malformed complete maps are invalid; valid different bindings mismatch; equal freshly read bundles return not_modified; revoke/publish invalidate prior bundles. Nullable selected/head release IDs remain deliberate for unpublished policy; forging nil against a published current bundle returns changed, not invalid. Freshness equality is not authorization.

Accepted source SHA-256:

- lib/axiom.ex: `049ad17b413d1281a7e93d2324e9ef1fe27ebd206adb511c05cab1e118d54719`
- lib/axiom/scope.ex: `e18cd09366e1a2c50b04d4e255d89862d82c00632fbfa10ad598516a609de223`
- lib/axiom/domain.ex: `88041f7f680eb8b06475f97b0a7ae59968cdc5af46ee3c04b6eb8d63a0b5c16b`

## Exact commands and fresh evidence

cwd: /Users/tonton/Documents/workspace/alaya/axiom. Evidence directory: ../fresh-bundle-version-acceptance-20261002 relative to this report. All completed commands exited 0. Existing local dependencies only; restricted Docker access required approved local escalation.

- `docker inspect --format '{{.Name}} {{.Config.Image}} {{.State.Running}} {{json .NetworkSettings.Ports}}' axiom-dev-test-pg-20261002`: running postgres:17-alpine, 127.0.0.1:55439 -> 5432.
- `MIX_ENV=test mix run verification/fresh-bundle-version-acceptance-20261002/probe.exs > verification/fresh-bundle-version-acceptance-20261002/probe.raw 2>&1`: **4 passed**, seed 20261002. Byte-identical original probe, including original float expectations and real PostgreSQL lock barrier.
- `MIX_ENV=test mix run verification/fresh-bundle-version-acceptance-20261002/boundary.exs > verification/fresh-bundle-version-acceptance-20261002/boundary.raw 2>&1`: **5 passed**, seed 20261002. Independent additional matrix tests integral/fractional floats, booleans, strings, lists/maps across both bundle schema versions, revisions/generation and release IDs. Null is rejected for schemas/counters; nullable releases have the behavior above. Policy integer 1 is accepted; integral/fractional float, boolean, null, string, collection and other integer versions return unsupported_schema. Missing/extra policy fields return invalid_policy.
- `MIX_ENV=test mix run verification/fresh-bundle-version-acceptance-20261002/regression.exs > verification/fresh-bundle-version-acceptance-20261002/regression.raw 2>&1`: **39 passed**, seed 20261002. Original byte-identical regression runner loads current tests unchanged, bypassing original helper to retain isolated connection.
- `scripts/check check > verification/fresh-bundle-version-acceptance-20261002/static.raw 2>&1`: format check, forced dev/test compile warnings-as-errors, Credo strict **PASS**, 0 issues.
- `mix dialyzer > verification/fresh-bundle-version-acceptance-20261002/dialyzer.raw 2>&1`: **PASS**, 0 errors.

Original probe also checks every missing bundle field, collection types, extra fields, principal/tenant/scope/selection mismatches, conflicting conditional options, assignment/relation ABA/no-op, suspension, pinned historical publish/rollback, tenant isolation and conservative invalidation. New matrix independently checks valid integer unchanged reads, changed reads on revoke/publish, and legacy ETag: equal -> not_modified without data; stale or revoked/published representation -> ok with data, preserving the legacy status contract.

## Isolation and preservation

Each runner independently verifies database/user axiom_test, server port 5432, version 170010, address 192.168.215.2/32 before DDL. Byte-identical original runners use their existing dedicated axiom_independent_bundle_20261002 schema without deleting prior fixtures. New boundary runner uses axiom_fresh_bundle_version_20261002. Random fixture namespaces are in raw logs. Only the designated local test DB was connected; no production connection or write occurred.

Every PG runner compared sorted public rows before/after and printed public_preserved: true. Final public-before.json/public-after.json match. before.json/after.json and preservation.json show no changes to lib/test/priv/scripts/vendor, README/mix.exs, or any preexisting original independent artifact at completion of tests. Original probe and regression copies are byte-identical. This requested REPORT.md is subsequently updated; its prior bytes are retained as prior-report.md in the new evidence directory. No Git/settings/install/sibling/NAS/credential changes. Build and PLT caches are ordinary local check outputs.

## Limits and stopping point

Acceptance covers the version-type fix and exercised conditional retrieval/legacy regressions at the hashes above. The original production snapshot barrier passed; negative READ COMMITTED mutation was not rerun. Exhaustive interleavings, outages/commit ambiguity, PDP/PEP and check/use TOCTOU guarantees are outside this task. Freshness checking grants no authorization. Existing xref deprecation warning remains, without gate failure. No remaining blocker for this bounded acceptance. Report complete; editing stopped.
