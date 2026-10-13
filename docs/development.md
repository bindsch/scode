# Development and verification

Use Bash, Bats, ShellCheck, and Node major 22, 24, or 26 with npm.
[package.json](../package.json) is the supported Node policy.
The Makefile checks it before JavaScript tests and coverage.
The existing npm lockfile remains authoritative for development dependencies.

```sh
npm ci
make test && make lint
make check-pins
bash -n scode
node --check lib/no-sandbox.js
npm audit --audit-level=low
```

There is no separate type-check target. `make test` runs ShellCheck, all Node
tests, and the full unfiltered Bats suite. `make lint` runs ShellCheck again.
Do not describe a filtered run as the full gate.

## Skips and runtime evidence

Bats prints `# skip` with a reason. Count passed, failed, and skipped tests
separately; an `ok ... # skip` line is not an executed passing test.
Tests skip unsupported platforms, missing optional tools, or an unavailable
runtime sandbox. The three sudo-wrapper preload tests probe their harmless
fixture and skip only when the outer environment denies executing it.
The inactive-preload test clears its inherited activation marker.

A green local gate with runtime skips is not runtime verification. Before a
release, obtain real macOS and Linux runs with their corresponding sandbox
tests executing. Linux CI enables user namespaces and probes bubblewrap.
Record revision, platform/architecture, engine/OS versions, command, exit code,
test totals, and skip reasons. Compare totals with the previous run.

## Coverage

`make coverage` collects this platform's shell report under
`coverage/shell-<platform>.cobertura.xml`, plus a
`.source-sha256` sidecar. It also enforces 80% JavaScript coverage.
The local shell floor defaults to zero because each platform skips the other's
runtime tests. The merged shell floor is 80%.

Collect on both platforms at exactly the same source revision. Download CI
artifacts from one run, or transfer each XML and sidecar together from the
other host. For CI:

```sh
gh run download RUN_ID -R bindsch/scode -n shell-coverage-macos-15 -D coverage
gh run download RUN_ID -R bindsch/scode -n shell-coverage-ubuntu-24.04 -D coverage
make coverage-gate COVERAGE_REPORTS="coverage/shell-darwin.cobertura.xml coverage/shell-linux.cobertura.xml"
```

Replace `RUN_ID` with the run for the source being released.
The gate rejects absent or mismatched source-hash sidecars. Do not combine
reports from different source trees or lower the merged floor to hide missing
runtime coverage. CI performs the collection/download/merge in the
[workflow](../.github/workflows/ci.yml).

The descriptor-closing engine launcher is excluded because it closes kcov's
reporting descriptor and execs. Declarative tables and marked macOS
profile/credential blocks are also excluded from the denominator.
Both platforms collect coverage; excluded macOS code is not measured just
because macOS has a coverage job. Exact signal tests skip under kcov because
its extra process changes signal delivery.

## Package metadata and notices

The npm manifest is private and development-only. It identifies scode, its
repository, description, and MIT license. It intentionally has no npm release
version or bin mapping: npm is not the delivery mechanism.
`PROGRAM_VERSION` in [scode](../scode) is the release-version authority.
The Makefile and Homebrew install the executable as `bin/scode`.

The [MIT license](../LICENSE) credits Laurent Bindschaedler. The launcher,
preload, and examples are project source; no bundled third-party implementation
was identified in this audit. c8, fast-check, and their transitive dependencies
are development-only, retain their own licenses in npm packages, and are not
installed by the package recipes.

## Optional contributor tools

[HOOKS.md](../HOOKS.md) describes hookrun and code-review prerequisites.
They are not scode runtime or full-gate dependencies.
Use [the release procedure](releases.md) for publication.
