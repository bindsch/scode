# Release procedure

This is an operator checklist. Preparing documentation does not authorize
commits, tags, pushes, release publication, or tap changes.

## Prepare before tagging

1. Choose the version and update `PROGRAM_VERSION` in `scode`.
   It is the only release-version authority. The private npm manifest has no
   package release version or npm bin.
2. Finalize all user-visible changes under a dated changelog release heading.
   Leave an empty `[Unreleased]` heading for subsequent work.
3. Run `make release-pins` before committing. It updates the README banner
   and installation tag selector without requiring the tag to exist.
   Run `make check-pins`.
4. Review help against the parser, examples against [policy](policy.md), and
   all local/external links. Run the American English checker on changed prose:
   `python ~/.claude/skills/humanizer/scripts/check_american.py <files>`.
5. Run `make test && make lint`, syntax checks, and
   `npm audit --audit-level=low`. Record exit codes and pass/fail/skip counts.
   Obtain real sandbox execution on both [CI platforms](platforms.md).
6. Collect matching macOS/Linux coverage XMLs and source-hash sidecars.
   Follow [coverage collection and transfer](development.md#coverage), then run:
   `make coverage-gate COVERAGE_REPORTS="coverage/shell-darwin.cobertura.xml coverage/shell-linux.cobertura.xml"`.
7. Complete the controlled credential checks below and inspect packaged files.

Do not publish a release based only on dry-run or nested-sandbox skips.

## Behavioral and artifact checks

The full suite covers parser rejection, path precedence, project config,
logging metadata, audit/watch, install/uninstall, preload behavior, and signals.
Also inspect `./scode --help`, `./scode --version`, and default/strict/untrusted
dry-runs for the selected revision.

For a manual audit fixture, use paths such as `/fixture/default` and
`/fixture/custom`; they are parser data and need not exist. Negative checks
must negate a positive match:

```sh
! printf '%s\n' "$out" | grep -q -- '--allow /fixture/custom'
```

Do not use `grep -vq`: one unrelated line would make the check pass.

Install into an isolated prefix with `make install PREFIX="$release_prefix"`.
Compare the launcher, preload, license, and each of the six examples against
source using `cmp` or SHA-256. Run `"$release_prefix/bin/scode" --version`,
a dry-run, and a real sandbox smoke test. Verify uninstall removes only the
packaged files and preserves an unrelated fixture.

## Controlled Claude credential verification

Use a disposable macOS account or VM with a separate Keychain and fake tokens.
Do not modify the operator's Keychain or call a provider with fixture tokens.
Record the scode revision, OS/build/architecture, system Python version,
installed Claude version, and Keychain state. Disable unrelated user/project
config and network access.

Create an executable fixture named `claude` outside the fixture project. It
must only inspect the JSON file and report Boolean assertions, never token
values. Create `~/.claude` in that disposable account.
Using Keychain Access or `security add-generic-password`, create service
`Claude Code-credentials` with a synthetic JSON object whose
`claudeAiOauth` has an access token, future `expiresAt` in milliseconds, and
refresh token. A synthetic credential file can have a different refresh token.
Use `security delete-generic-password -s Claude Code-credentials` only in
that disposable account when testing the absent-item case.

Run `scode --no-net --cwd "$fixture_project" -- "$fixture_bin/claude"`
for each row. Reset fixtures between rows and record assertions and exit codes:

| Case | Required result |
|---|---|
| Readable Keychain and mirrored file | File access token matches; refresh token empty; refresh-token expiry absent; mode 0600 |
| Mirrored refresh token replaced | Backup contains original fixture; backup dir/file 0700/0600; older backups pruned only after success |
| Keychain absent | File-only refresh credential preserved |
| Locked/denied Keychain plus mirrored refresh token | Launch refused with status 1; file preserved |
| `--no-credential-sync` plus mirrored refresh token | Launch refused |
| Opt-out plus existing access-only file | Launch allowed; no copy |
| Wrapper or project-local binary | Copy skipped with warning; mirrored token causes refusal |
| Symlinked file | Link target not rewritten; mirrored-token check may read it and refuse |
| Expired Keychain plus access-only file | File unchanged |
| Dry-run or blocked credential | No copy |
| Untrusted preset | No automatic copy or state grant |

This procedure verifies scode's file handling, not live Claude authentication.
If live authentication is also tested, use a disposable vendor account and
record Claude's exact version and results separately. Keep private raw evidence
outside the repository; commit only redacted assertions and environment data.
No controlled Keychain verification was performed by the documentation rebuild.

## Commit, tag, and validate the tagged tree

After approval, commit the prepared source and documentation. Prefer an annotated
signed tag and document the trusted key distribution. Existing tags through
v0.6.0 are unsigned; do not claim signatures where none exist.

Before any push or public release, validate the actual tag:

```sh
release_tag="v$(sed -n 's/^readonly PROGRAM_VERSION="\(.*\)"$/\1/p' scode)"
./scripts/release-pins.sh check "$release_tag"
git diff --exit-code "$release_tag" -- scode lib/no-sandbox.js README.md docs/installation.md CHANGELOG.md LICENSE examples
```

Also export the tagged tree into an isolated directory and run its installation
procedure there. Check the installed version against the tag. Do not tag then
repin: a later branch commit cannot fix immutable tagged documentation.
Old tags without the new guide/checker need manual inspection and retain the
[known installation correction](installation.md#verified-source-installation).

Generate an artifact checksum manifest from the finalized tagged source.
Verify every download against it before installing. A signed manifest or
signed tag gives provenance only when the signing key is independently trusted.

## Homebrew bottle lifecycle

Set `TAP_CHECKOUT` to a separately reviewed checkout of
[bindsch/homebrew-tap](https://github.com/bindsch/homebrew-tap). Do not assume
a maintainer-specific directory. Update `Formula/scode.rb` there to the
approved tag/revision or archive checksum.

On each supported bottle platform:

```sh
brew install --build-bottle "$TAP_CHECKOUT/Formula/scode.rb"
brew test scode
brew bottle --json scode
```

Keep the generated bottle and JSON together. Merge the bottle metadata into the
formula with the tap's current workflow, using the intended release root URL.
A source revision or packaged-content change requires fresh bottles and
checksums. Do not copy prior bottle checksums.

Extract each bottle in isolated storage. Compare its preload, license, and six
examples byte-for-byte with the release. Compare the launcher after accounting
for Homebrew prefix relocation; investigate every other difference.
Run the installed bottle's version, dry-run, and real sandbox checks on its
platform. Recompute each bottle SHA-256 and match the JSON/formula.
Before publication, record filenames, platform tags, source commit, and hashes.

## Publication order and release-note corrections

After operator approval:

1. Push the reviewed source commit and verified tag.
2. Create the GitHub release with its changelog section as the release body,
   plus source checksums/signatures. Verify the release tag and latest marker.
3. Publish verified bottles to the tap's release location, then publish the
   formula with matching URLs and checksums.
4. Download the published artifacts again, verify checksums and packaged
   contents, and test installation from the public formula.
5. If backfilling older release bodies, keep the intended current release
   marked latest. Do not change old tags.

The v0.5.0 and v0.6.0 public bodies originally contained only comparison links.
Prepared bodies are in [v0.5.0 notes](release-notes/v0.5.0.md) and
[v0.6.0 notes](release-notes/v0.6.0.md). The operator can publish them with:

```sh
gh release edit v0.5.0 -R bindsch/scode --notes-file docs/release-notes/v0.5.0.md
gh release edit v0.6.0 -R bindsch/scode --notes-file docs/release-notes/v0.6.0.md
```

These are external publication steps, not part of the local documentation gate.
