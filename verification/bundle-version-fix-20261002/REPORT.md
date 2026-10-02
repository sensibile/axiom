# Revision bundle strict version fix — 2026-10-02

Fresh validator F1 is fixed. Implementation edits stopped pending independent acceptance.

## Change and adjacent boundary review

Scope bundle_schema_version and data_schema_version now use === 1 and === 2; complete
conditional bundle equality uses ===. Float 1.0/2.0 can no longer produce not_modified.
Adjacent Domain.policy had the same loose version comparison; it now requires integer 1
using !==. Its established unsupported_schema error and all valid integer behavior remain.

Revision, generation and selected/head release already require Domain.revision's is_integer
and bigint range check. Nullable release IDs remain intentional for no published policy;
positive releases still reject zero. Status, selection, principal, tenant and scope fields
already require exact strings/maps/keys. No additional loose numeric acceptance was found.

Added pure policy version/CAS boundaries and real-PG bundle numeric tests: integral floats,
fractional floats, booleans, strings, lists and malformed maps across both schema versions,
assignment revision, policy generation and selected/head releases. Valid integer bundles,
ETag API and integer release selection remain covered. Contract expectations were not relaxed.
Only three implementation files and two tests changed; no TestDatabase/store/SQL/schema edits.

## Final evidence

All runs use existing local dependencies and approved local execution permission for Mix TCP
and the dedicated PG. No global install, Git change, sibling, gateway or authentication work.

- [Static gate](static.raw): scripts/check check completed format check, forced dev/test
  compile warnings-as-errors, Credo strict (94 mods/funs, no issues).
- [Dialyzer](dialyzer.raw): zero errors, passed successfully.
- [Original probe rerun](probe.raw): 4 passed, seed 20261002, including unchanged float rejection
  expectations and real-PG snapshot lock barrier. Probe source is a byte-identical copy of the
  original, verified in [preservation](preservation.json); original probe and evidence unmodified.
- [Related full regression](regression.raw): 39 passed (30 current suite + 9 preexisting independent
  model/bigint), seed 20261002. Copied original regression runner also byte-identical.
- Both PG runs print verified axiom_test database/user, server port 5432, version 170010 and
  public_preserved true. Original runner targets axiom_independent_bundle_20261002 and generates
  a new random fixture namespace each run. This approved original runner was rerun unchanged;
  it reuses its existing dedicated isolated schema, without deleting preexisting fixtures.
- [Preservation](preservation.json) identifies exactly the five intended changed code/test files;
  all original independent artifacts and priv/scripts/vendor files remain hash-identical.
  Each runner snapshots sorted public rows before/after; [before](public-before.json) and
  [after](public-after.json) are equal. Their output files are isolated in this new evidence folder.

## Limits

This repairs representation correctness, not authentication or permission evaluation.
Check/use TOCTOU remains a consumer responsibility. The independent negative READ COMMITTED
mutation was not rerun; unchanged production snapshot barrier passed in the original probe.
No new network outage/COMMIT-loss, exhaustive schedule or security scan was performed.
Vendor DBConnection xref deprecation warning remains. Fresh validator acceptance is still pending.
