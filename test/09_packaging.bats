#!/usr/bin/env bats
# Packaging/install regression checks

load test_helper

@test "make install/uninstall to temp prefix ships expected artifacts" {
  command -v make >/dev/null 2>&1 || skip "make not installed"

  local repo_root
  repo_root="$BATS_TEST_DIRNAME/.."
  local prefix
  prefix="$(mktemp -d)"

  run make -C "$repo_root" install PREFIX="$prefix"
  [ "$status" -eq 0 ]

  [ -x "$prefix/bin/scode" ]
  [ -f "$prefix/lib/scode/no-sandbox.js" ]
  [ -f "$prefix/share/scode/LICENSE" ]

  [ -f "$prefix/share/scode/examples/sandbox.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-strict.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-paranoid.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-permissive.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-cloud-eng.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-grok.yaml" ]

  # Derive the expectation from the source launcher so that bumping
  # PROGRAM_VERSION does not require editing this test. The invariant under
  # test is that `make install` ships the version in the working tree.
  local source_version
  source_version="$("$repo_root/scode" --version)"

  run "$prefix/bin/scode" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$source_version" ]

  printf 'user-owned\n' > "$prefix/share/scode/examples/unrelated.yaml"

  run make -C "$repo_root" uninstall PREFIX="$prefix"
  [ "$status" -eq 0 ]
  [ ! -e "$prefix/bin/scode" ]
  [ ! -e "$prefix/lib/scode/no-sandbox.js" ]
  [ ! -e "$prefix/share/scode/LICENSE" ]
  [ -f "$prefix/share/scode/examples/unrelated.yaml" ]

  rm -rf "$prefix"
}

@test "make rejects filesystem-root PREFIX" {
  command -v make >/dev/null 2>&1 || skip "make not installed"
  local repo_root="$BATS_TEST_DIRNAME/.."

  run make -C "$repo_root" install PREFIX=/
  [ "$status" -ne 0 ]
  [[ "$output" == *"PREFIX=/ is unsafe"* ]]
}

@test "make rejects an unexpanded tilde PREFIX" {
  command -v make >/dev/null 2>&1 || skip "make not installed"
  local repo_root="$BATS_TEST_DIRNAME/.."

  run make -C "$repo_root" install 'PREFIX=~/.local'
  [ "$status" -ne 0 ]
  [[ "$output" == *'use PREFIX=$HOME/.local'* ]]
}
