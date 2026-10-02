# PRP revision bundle implementation evidence — 2026-10-02

Implementation is stopped pending fresh independent verification. These are implementer checks;
rerunning earlier independent tests is regression evidence, not fresh reviewer acceptance.

## Boundary and changes

Existing resource snapshot already read policy head, selected release and current facts in one
read-only REPEATABLE READ transaction and supplied an ETag. Added the missing explicit revision
bundle and strict `if_revision_bundle` conditional contract, reusing that transaction unchanged.
Pure schema/binding validation and bundle construction live in Scope; transaction/error handling
remain in the service shell. No PDP/PEP/context issuance/signing/token/key/lease was added.

Bundle separates exact logical resource identity, selected policy release, current head/generation,
current tenant assignment revision (including relation/revocation/suspension) and principal status.
Selection mode is bound so an explicit historical release cannot silently switch to current policy.
Unchanged queries return not_modified; changed queries return changed plus fresh data/bundle.
Malformed maps fail invalid_revision_bundle; valid maps with wrong query binding fail
revision_bundle_binding_mismatch. Old ETag API remains supported; combining both conditions is rejected.

No applicable ancestor or Axiom AGENTS.md was present. PAP_PRP_DESIGN FC/IS and LOCAL_GIT checks
were followed. User prohibition on Git mutations overrides worktree-first default for unborn HEAD.
No staging/commit/config/remote/sibling modifications or installations were performed.

## Actual I/O and independent oracles

Container read-only inspect confirmed `postgres:17-alpine`, running, loopback 55439 → 5432.
[DB identity](db-identity.raw) confirms axiom_test / axiom_test / 5432 / PostgreSQL 17,
and existence of the new axiom_revision_bundle_20261002 schema. All test setup, triggers and
random tenant fixtures use that schema. Earlier schemas/data were retained.

- [Final review gate](review.raw): format, forced dev/test warnings-as-errors compile, Credo strict,
  Domain fast tests, Dialyzer zero errors, complete actual-PG regression **28 passed**, seed 667166.
- [Existing independent regressions](independent-regression.raw): bigint edge checks and independent
  seeded 240-step state-machine oracle **9 passed**, seed 315988.
- New test reads a bundle, performs each mutation on a concurrent task, waits for commit, then
  conditionally rereads. Checks assignment grant/revoke, suspend, relation change, same-body publish,
  rollback and historical release selection against independently expected generations/status.
- Existing paired writer/reader PG contention oracle checks even assignment revision and parity
  of assignment/principal states. Added bundle-to-data consistency and conditional rereads during
  this contention. Existing publish contention checks head/release/body parity; existing late audit
  failure, scoped identity isolation, bigint/CAS and idempotency regressions remain passing.
- Missing/typed/unknown fields, other tenant with same local IDs, another principal, selection
  mismatch, valid scope tampering, repeated reads and no-op revision invalidation are checked.

## Limits

The equality digest is forgeable, not authentication evidence. Every binding must participate in
consumer cache keys. Equality is scoped to the query snapshot; a change after snapshot/check and
before actual use remains the consumer's enforcement obligation. No final permission decision,
execution lease, offline TTL or cross-service atomicity is promised. Tenant-wide revisions can
conservatively invalidate unrelated scopes. No time-window facts currently exist.

Contention tests sample actual scheduling, not every interleaving. New tests do not deterministically
pause the conditional read at every SELECT; prior repeatable-read barrier and production contention
regressions remain the evidence. Existing injected transaction failure checks cover rollback but
new conditional-specific disconnect/timeout/COMMIT-loss cases were not added. No fresh mutation
sensitivity/security review was performed. Vendor DBConnection xref deprecation warning remains.
