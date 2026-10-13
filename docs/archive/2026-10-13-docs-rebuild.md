# Documentation rebuild — 2026-10-13

Historical snapshot of the uncommitted `docs-rebuild` worktree based on
`73c385b70226797b2f6a5d4aab9d5b33f56e605f`. No version bump, commit, push,
code-review run, or external publication was performed.

The tested launcher SHA-256 is
`841da3c94fd019688510051648dc4375ebeddcdd93056209f444fa7e960cf902`.
The release-version authority remains `PROGRAM_VERSION="0.6.0"`.
Changed behavior is identified under Unreleased and in the policy guide.

## Audit disposition

| Work item | Status and result |
|---|---|
| README boundary, positioning, navigation | Complete: short introduction, exceptions before quickstart, guide index |
| Installation and release selectors | Complete: fail-fast procedures, prefix/PATH/version checks, pre-tag selector generation and Git-ref validation |
| CLI/parser/help and path resolution | Complete: all options, repetition, parsing limits, account-home distinction, exit statuses |
| Policy and examples | Complete: platform matrix, scalar/path precedence, project and automatic-grant exceptions |
| Linux allow contract | Fixed with regression: existing explicit paths absent from initial mounts are now bound |
| Privilege-command masks | Fixed with regressions: final restrictions follow grants and command auto-allows on both platforms |
| Harnesses and credentials | Complete documentation: canonical aliases, state grants, Claude decision table/backups, Antigravity authentication limits |
| Logging and accounting | Complete: separate schemas, units, replacement, sensitivity, parsing, completion and failure limits |
| Environment and browser preload | Complete: exact-name exemptions, wildcard configuration effects, six APIs, unsupported shell syntax |
| Signals and platforms | Complete documentation; runtime evidence limitations retained |
| Metadata/license/notices | Complete: private development identity and license added; license attribution unchanged; no bundled third-party implementation identified |
| Historical reports and changelog | Complete: dated snapshots, immutable evidence links, correction labels, consolidated released behavior |
| Release process and hook prerequisites | Complete local procedures; merged coverage, credential checks, bottle lifecycle, publication ordering |
| Full local gate and English checks | Passed; final exact output recorded below |
| Remote release-note backfill | Prepared locally; not published |
| Live macOS/Linux and Keychain verification | Not performed: outer sandbox unavailable; no disposable Keychain test account provided |

## Verification

Environment: macOS 27.0.1 (26A434), arm64; Bash 3.2.57; Node 26.10.0;
Bats 1.14.0; ShellCheck 0.11.0. The sandbox-exec path exists, but the runtime
probe cannot create a sandbox in this session.

The initial `make test && make lint` exited 2. The JavaScript suite passed
101 tests. Bats had 580 cases and four failures: three outer-sandbox denials
of harmless sudo fixtures, and one inherited `SCODE_SANDBOXED` assumption.
The latter now clears its activation variable. Fixture execution denial now
produces a specific skip; other fixture failures still fail.

The first corrected full gate exited 0:
JavaScript 101 passed, 0 failed, 0 skipped; Bats 586 total, 471 passed,
0 failed, 115 skipped. The Bats count increased by six.
The TAP plan was `1..586`; Node printed `ℹ pass 101` and `ℹ fail 0`.
The command ended with `shellcheck scode`.

Final stable-tree `make test && make lint` rerun exited 0 with the same counts:
JavaScript 101 passed, 0 failed, 0 skipped; Bats 586 total, 471 passed,
0 failed, 115 skipped. Exact output: `ℹ pass 101`, `ℹ fail 0`, and `1..586`.
The command ended with `shellcheck scode`.

Other checks:

- `make check-pins`: exit 0;
  `release-pins: documentation selects v0.6.0 (working tree)`.
- `shellcheck scode scripts/release-pins.sh`, `bash -n scode`, and
  `node --check scripts/check-node.js`: exit 0.
- `npm audit --audit-level=low`: exit 0; `found 0 vulnerabilities`.
- American English checker over 41 source/doc/test files: exit 0;
  `American English: CLEAN`.
- Local Markdown links/anchors and home-path check: exit 0 across 27 files.
- External URLs: exit 0; 18 passed, 0 failed.
- Rendered README and reference tables: inspected with Pandoc/XeLaTeX and PNG
  previews. Browser automation was unavailable. Preview artifacts and raw local
  gate output remain in the ignored repository scratch directory.

Skips cover unavailable runtime sandbox execution, Linux-only tests on macOS,
the three denied sudo fixtures, and unavailable ionice.
They are not passing runtime evidence. No new merged coverage claim is made.

## Deferred code changes

- Separate engine process groups, terminal ownership, and stopped-child handling
  to resolve signal-source ambiguity and the PID-directed QUIT surviving-child case.
- Authenticated audit artifacts and comprehensive kernel-denial collection.
  Current logs are stderr capture with heuristic parsing.
- General Claude credential reachability checks and fail-closed handling of
  unavailable credential inspection, including project-grant and Python limits.
- Native Antigravity credential mirroring in scode. Recognition alone does not
  expose its macOS Keychain login.
- Full shell-grammar browser rewriting. Substitutions and heredocs remain
  preserved; documented manual browser flags are the fallback.

These need broader design or runtime verification than the bounded policy fixes.
The current guides state the real behavior.

## External follow-ups

Public v0.5.0 and v0.6.0 bodies were confirmed through GitHub's release API to
contain only comparison links. Corrected local bodies are under
`docs/release-notes/`, with publication commands in [releases](../releases.md).
The v0.5.0 API publication date is 2026-10-08.
No release body, old tag, tap formula, or bottle was changed.

The audit's July report lacked an exact audited revision and raw logs.
Its first committed snapshot is preserved by an immutable link; missing
evidence is labeled unknown rather than reconstructed.

## New documentation structure

The README gives the purpose, boundary, quickstart, common commands, and links.
The index separates user guides, contract references, contributor procedures,
security, and dated archives. Policy precedence has one reference; logging and
accounting each have their own schema. Authentication and platform behavior are
separate guides. The old release/security filenames are navigation pointers.
Examples refer to these contracts instead of making stronger independent claims.

## Changed files

Deleted old paths are listed alongside their archive replacements.
The license file is unchanged because its attribution was already consistent.

- `.gitignore`
- `CHANGELOG.md`
- `HOOKS.md`
- `Makefile`
- `README.md`
- `docs/CODE-AUDIT-2026-07-16.md`
- `docs/RELEASE-GATE.md`
- `docs/SECURITY-HARDENING.md`
- `docs/TODO.md`
- `docs/accounting.md`
- `docs/align-0.6-report.md`
- `docs/archive/2026-02-25-v0.2.0-release.md`
- `docs/archive/2026-07-16-code-audit.md`
- `docs/archive/2026-10-10-harness-alignment.md`
- `docs/archive/2026-10-13-docs-rebuild.md`
- `docs/archive/index.md`
- `docs/browsers.md`
- `docs/cli.md`
- `docs/configuration.md`
- `docs/development.md`
- `docs/environment.md`
- `docs/grok-defense.md`
- `docs/harnesses.md`
- `docs/index.md`
- `docs/installation.md`
- `docs/logging.md`
- `docs/plans/2026-02-25-v0.2.0-release.md`
- `docs/platforms.md`
- `docs/policy.md`
- `docs/release-notes/v0.5.0.md`
- `docs/release-notes/v0.6.0.md`
- `docs/releases.md`
- `docs/security.md`
- `examples/sandbox-cloud-eng.yaml`
- `examples/sandbox-paranoid.yaml`
- `examples/sandbox-strict.yaml`
- `examples/sandbox.yaml`
- `lib/no-sandbox.js`
- `package-lock.json`
- `package.json`
- `scode`
- `scripts/check-node.js`
- `scripts/release-pins.sh`
- `test/06_preload.bats`
- `test/12_documented_contracts.bats`
- `test/test_helper.bash`
