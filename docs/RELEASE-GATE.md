# Release Gate

Use this checklist before tagging a new `scode` release.

## 1) Version consistency

- [ ] `scode` version constant matches release target:
  - `scode` (`PROGRAM_VERSION`)
- [ ] Homebrew formula points to the same version tag:
  - `Formula/scode.rb` (`url ..., tag: "vX.Y.Z"`)
- [ ] README beta/version banner matches:
  - `README.md`
- [ ] Manual install section uses parameterized `VERSION` variable:
  - `README.md` — verify the example comment (`e.g. v0.1.1`) matches the release target

## 2) Automated checks

- [ ] Prerequisites installed:

  ```bash
  # Test runner
  brew install bats-core   # or: apt install bats
  # Linter
  brew install shellcheck  # or: apt install shellcheck
  # JS tests
  brew install node        # or: apt install nodejs npm
  npm install
  ```

- [ ] Test suite passes:

  ```bash
  SCODE_REQUIRE_JS_TESTS=1 make test
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
  make uninstall PREFIX=/tmp/scode-release-test
  ```

## 7) Homebrew tap

- [ ] Update the Homebrew formula in the `bindsch/homebrew-tap` repository:

  ```bash
  # In ~/Programming/homebrew-tap
  # Update Formula/scode.rb tag to the new version
  # Commit and push
  ```

- [ ] Verify the in-repo `Formula/scode.rb` tag matches the release target.

## 8) Release notes/changelog

- [ ] Move user-visible items from `## [Unreleased]` into a new release section:
  - `## [X.Y.Z] - YYYY-MM-DD`
- [ ] Ensure `[Unreleased]` remains at the top for the next cycle.
- [ ] Remove placeholder-only text for the released version and include concrete user-visible changes.

## 9) GitHub releases

Create GitHub releases **in chronological order** (oldest first) so that the
`Latest` badge lands on the newest release. If you create them out of order,
manually fix with `gh release edit <tag> --latest`.

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
