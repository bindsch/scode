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

  [ -f "$prefix/share/scode/examples/sandbox.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-strict.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-paranoid.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-permissive.yaml" ]
  [ -f "$prefix/share/scode/examples/sandbox-cloud-eng.yaml" ]

  run "$prefix/bin/scode" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "scode "* ]]

  run make -C "$repo_root" uninstall PREFIX="$prefix"
  [ "$status" -eq 0 ]
  [ ! -e "$prefix/bin/scode" ]
  [ ! -e "$prefix/lib/scode/no-sandbox.js" ]

  rm -rf "$prefix"
}
