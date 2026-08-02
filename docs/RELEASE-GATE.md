# Release Gate

Use this checklist before tagging a new `scode` release.

## 1) Version consistency

`PROGRAM_VERSION` in `scode` is the single source of truth. Everything else is
derived from it, so there is exactly one version string to edit by hand.

- [ ] Bump the version constant to the release target:
  - `scode` (`PROGRAM_VERSION`)
- [ ] Move `[Unreleased]` changelog entries under the new version heading:
  - `CHANGELOG.md`

The README banner, the pinned install commit, and the manual-install SHA-256
hashes are rewritten by `make release-pins` in step 7. The packaging test and
the Homebrew formula both derive the expected version, so neither needs editing.

The Homebrew formula lives only in the
[`bindsch/homebrew-tap`](https://github.com/bindsch/homebrew-tap) repository.
This repository intentionally does not carry a copy: two copies drifted in the
past, and the tap is what users actually install from.

## 2) Automated checks

- [ ] Prerequisites installed:

  ```bash
  # Test runner
  brew install bats-core   # or: apt install bats
  # Linter
  brew install shellcheck  # or: apt install shellcheck
  # JS tests
  brew install node kcov   # use Node.js 22+; install equivalents on Linux
  npm ci
  ```

- [ ] Test suite passes:

  ```bash
  make test
  make coverage
  npm audit --audit-level=low
  ```

- [ ] Shell lint passes:

  ```bash
  shellcheck scode
  ```

## 3) Behavioral smoke tests

- [ ] Help/version still work:

  ```bash
  ./scode --help >/dev/null
  ./scode --version
  ```

- [ ] Dry-run default mode/profile generation works:

  ```bash
  ./scode --dry-run -C . -- true
  ```

- [ ] Dry-run strict + no-net works:

  ```bash
  ./scode --dry-run --strict --no-net -C . -- true
  ```

- [ ] Config parser fail-fast checks (unknown key/section) work:

  ```bash
  tmp="$(mktemp)"
  printf 'unknown_key: true\n' > "$tmp"
  ./scode --dry-run --config "$tmp" -C . -- true && exit 1 || true
  rm -f "$tmp"
  ```

- [ ] Trust presets work:

  ```bash
  ./scode --trust untrusted --dry-run -C . -- true
  ./scode --trust trusted --dry-run -C . -- true
  ```

- [ ] Project config is loaded:

  ```bash
  tmp="$(mktemp -d)"
  printf 'strict: true\n' > "$tmp/.scode.yaml"
  # macOS emits "deny default" in SBPL; Linux emits "# Mode: strict"
  ./scode --dry-run -C "$tmp" -- true | grep -qE "deny default|Mode: strict"
  rm -rf "$tmp"
  ```

- [ ] Audit subcommand parses denial patterns:

  ```bash
  tmp="$(mktemp)"
  printf 'deny(file-read-data) /tmp/test-path\n' > "$tmp"
  ./scode audit "$tmp" | grep -q "/tmp/test-path"
  rm -f "$tmp"
  ```

- [ ] Audit metadata-aware categorization works (`# blocked:` + `# allowed:` headers):

  ```bash
  tmp="$(mktemp)"
  cat > "$tmp" <<'EOF'
#json:{"version":1,"session":"2026-02-15T10:00:00-0800","command":"true","cwd":"/tmp","blocked":[{"source":"default","path":"/home/user/.aws"},{"source":"cli","path":"/opt/internal/secrets"}],"allowed":["/tmp/allowed-path"]}
# scode session: 2026-02-15T10:00:00-0800
# blocked: default /home/user/.aws
# blocked: cli /opt/internal/secrets
# allowed: /tmp/allowed-path
#---
deny(file-read-data) /home/user/.aws/credentials
deny(file-read-data) /opt/internal/secrets/token
EOF
  head -1 "$tmp" | grep -q '^#json:'
  out="$(./scode audit "$tmp")"
  echo "$out" | grep -q "Blocked by scode defaults"
  echo "$out" | grep -q "Blocked by custom policy"
  echo "$out" | grep -q -- "--allow /home/user/.aws"
  echo "$out" | grep -vq -- "--allow /opt/internal/secrets"
  rm -f "$tmp"
  ```

- [ ] Audit watch mode reports appended denials and deduplicates:

  ```bash
  log="$(mktemp)"
  out="$(mktemp)"
  ./scode audit --watch "$log" > "$out" 2>&1 &
  pid=$!
  # wait for watcher startup
  for _ in $(seq 1 20); do grep -q "watching" "$out" && break; sleep 0.1; done
  printf 'deny(file-read-data) /tmp/watch-a\n' >> "$log"
  printf 'deny(file-read-data) /tmp/watch-a\n' >> "$log"
  printf 'deny(file-read-data) /tmp/watch-b\n' >> "$log"
  for _ in $(seq 1 40); do [[ "$(grep -cE '^\[.*\] DENIED:' "$out" || true)" -ge 2 ]] && break; sleep 0.1; done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ "$(grep -cE '^\[.*\] DENIED:' "$out" || true)" -eq 2 ]
  rm -f "$log" "$out"
  ```

## 4) Platform-specific runtime checks

- [ ] macOS runtime check (when `sandbox-exec` is available):

  ```bash
  ./scode -C . -- true
  ```

- [ ] Linux runtime check (on Linux with `bubblewrap` installed):

  ```bash
  ./scode -C . -- true
  ```

## 5) Docs/examples consistency

- [ ] README examples reference files that exist under `examples/`.
- [ ] README example configs table matches files under `examples/`.
  Spot-check scalar values in paranoid config (`strict: true`, `net: off`,
  `fs_mode: ro`, `scrub_env: true`). If a path appears in both an example
  config's `blocked:` list and the built-in defaults (e.g. `~/Videos` is
  a Linux default but also in `sandbox-paranoid.yaml` for macOS coverage),
  verify the duplication is intentional and noted in the example's comments.
- [ ] Any new or changed flags are documented in:
  - `README.md` options table
  - `scode --help` output
  - Example config files when applicable
  - `README.md` path semantics notes when behavior changes (for example `--allow` precedence)

## 6) Packaging/install sanity

- [ ] Local install works to a temp prefix:

  ```bash
  make install PREFIX=/tmp/scode-release-test
  /tmp/scode-release-test/bin/scode --version
  make uninstall PREFIX=/tmp/scode-release-test
  ```

- [ ] Node.js preload module is shipped:

  ```bash
  make install PREFIX=/tmp/scode-release-test
  test -f /tmp/scode-release-test/lib/scode/no-sandbox.js
  make uninstall PREFIX=/tmp/scode-release-test
  ```

- [ ] Example config files are shipped:

  ```bash
  make install PREFIX=/tmp/scode-release-test
  test -f /tmp/scode-release-test/share/scode/examples/sandbox.yaml
  test -f /tmp/scode-release-test/share/scode/examples/sandbox-strict.yaml
  test -f /tmp/scode-release-test/share/scode/examples/sandbox-paranoid.yaml
  test -f /tmp/scode-release-test/share/scode/examples/sandbox-permissive.yaml
  test -f /tmp/scode-release-test/share/scode/examples/sandbox-cloud-eng.yaml
  test -f /tmp/scode-release-test/share/scode/examples/sandbox-grok.yaml
  test -f /tmp/scode-release-test/share/scode/LICENSE
  make uninstall PREFIX=/tmp/scode-release-test
  ```

## 7) Tag, then repin the README

The README pins the exact released commit and the SHA-256 hash of every
manual-install artifact. Those values only exist once the tag exists, so tag
first and derive them afterwards:

```bash
git tag -a vX.Y.Z -m "scode vX.Y.Z"
git push origin vX.Y.Z
make release-pins        # rewrites README.md from tag vX.Y.Z
make check-pins          # must pass
git commit -am "docs: repin install artifacts to vX.Y.Z"
```

- [ ] `make check-pins` passes on `main` after the repin commit.

## 8) Homebrew tap

The formula lives only in `bindsch/homebrew-tap`. Its test derives the expected
version from the tag, so only `url` needs editing:

```bash
# In ~/Programming/homebrew-tap
# Formula/scode.rb: set tag: "vX.Y.Z" and revision: <commit from make check-pins>
ruby -c Formula/scode.rb
brew install --build-from-source bindsch/tap/scode
brew test scode
brew audit --strict bindsch/tap/scode
```

- [ ] Formula `tag:` matches the release target.
- [ ] Formula `revision:` resolves to the release tag commit.
- [ ] `brew test` and `brew audit --strict` both pass.
- [ ] Verify release tags are signed. If signing is not yet configured, publish
  the exact commit ID and SHA-256 hashes for every manual-install artifact.
- [ ] Verify GitHub branch/tag protection, secret scanning, and Dependabot are
  enabled before publishing.

## 9) Release notes/changelog

- [ ] Move user-visible items from `## [Unreleased]` into a new release section:
  - `## [X.Y.Z] - YYYY-MM-DD`
- [ ] Ensure `[Unreleased]` remains at the top for the next cycle.
- [ ] Remove placeholder-only text for the released version and include concrete user-visible changes.

## 10) GitHub releases

Create the target release first. If older releases must be backfilled afterward,
explicitly re-mark the target release as latest.

- [ ] Create the GitHub release for the new version **before** any backfill releases:

  ```bash
  gh release create vX.Y.Z --title "scode vX.Y.Z" --notes "..."
  ```

- [ ] Verify the new release is marked `Latest`:

  ```bash
  gh release list -R bindsch/scode
  # The new version must show "Latest"
  ```

- [ ] If backfilling older releases, create them **after** the new release and
  then re-mark the new release as latest:

  ```bash
  gh release edit vX.Y.Z --latest
  ```
