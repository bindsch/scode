# Code and security audit — 2026-07-16

Historical report. This is a summary of a dated working-tree audit, not current
security guidance. Consolidated on 2026-10-13.

## Revision and evidence limits

The original report did not record its exact audited working-tree revision.
Its first durable source snapshot is commit
[7c6d185](https://github.com/bindsch/scode/blob/7c6d185c0a4cbdcc8bf4823247c0d3c7f7ae6341/docs/CODE-AUDIT-2026-07-16.md),
committed on 2026-08-02. That commit preserves the complete findings and old
line references. It is evidence of the report's contents, not proof that the
July worktree was identical.

The report claimed 101 Node tests, 505 Bats tests, 83.97% shell line coverage,
and a clean dependency audit. Raw logs and complete environment details were
not committed, and Bats pass/skip counts were not separated. Those totals
cannot be verified as executed passes. They are not the current gate result.

## Recorded findings and shipped follow-up

The audit recorded fixes to mount ordering, Grok blocks, project config
validation, command resolution, descriptor isolation, logging, preload
rewriting, and packaging. It left release authenticity, local permission
grants, repository protections, deprecated sandbox interfaces, and structural
decomposition as operator or design concerns.

Its temporary-directory claim applies to macOS strict mode: shared temp is
denied there while private per-run scratch is granted. macOS default mode
remains allow-default and can expose shared temporary paths.

The old Formula path and local ignored permissions file describe that snapshot.
Use the immutable report above for those references. The active Homebrew
formula now belongs to the external tap; local permission files were not
published evidence.

## Resolution update — 2026-10-13

- Active remote CI and real Linux sandbox tests are implemented in the
  [workflow at the audited HEAD](https://github.com/bindsch/scode/blob/73c385b70226797b2f6a5d4aab9d5b33f56e605f/.github/workflows/ci.yml).
  [Run 38410548712](https://github.com/bindsch/scode/actions/runs/38410548712)
  reports success for that commit. The recommendation to add Linux runtime CI
  is resolved.
- Required branch protection and repository security settings were not verified.
  Successful CI does not establish that those controls are required.
- Release signatures, macOS private sandbox interfaces, and source-file
  decomposition remain separate concerns. No new resolution is asserted here.

Current contracts are in [security](../security.md), [policy](../policy.md),
and [development](../development.md).
