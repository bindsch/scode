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
7. Complete the offline login-store gate below and inspect packaged files.

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

## Offline login-store verification

Run `bats test/10_credential_sync.bats test/22_login_store.bats test/23_keychain_services.bats`
with fixture-only commands and an isolated HOME. The gate checks zero calls to a fake `security` on PATH,
unchanged synthetic credential files and backups, and the generated policy
for normal, strict, legacy-flag, blocked, and untrusted runs. It verifies default
denial, CLI/user opt-in, project restrictions, opt-out precedence, native install
provenance, and read-only preferences. Kernel tests read synthetic preferences
and deny writes, replacement, and creation when absent. The keychain-services
tests check that the final Mach deny is present in every configuration without
an applied grant, and that lookups of every denied name
(`com.apple.authd`, the security agent names, and `com.apple.securityd.xpc`)
fail inside the sandbox while `com.apple.trustd` and `com.apple.SecurityServer`
succeed, that no authorization session can be made there, and that a file in
the login keychain directory cannot be read, whatever is allowed.
A bootstrap lookup sends no message to a daemon; the authorization probe asks
authd for a session with no rights, which shows nothing. Static checks
reject credential commands in the launcher because its parent process pins
PATH and cannot be intercepted by that spy.

Do not invoke a real harness, run `/usr/bin/security`, read a Keychain, or
create Keychain items for this gate, inside or outside a sandbox. The tests establish scode's policy and fixture behavior. They do
not prove live authentication, refresh behavior, per-item Keychain isolation,
or the absence of dialogs initiated by a harness or macOS. Live checks need
separate authorization and a disposable account or VM.

See [the release gate](RELEASE-GATE.md) for the login ownership rule.

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
