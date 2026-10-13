#!/usr/bin/env bash
# Update release selectors before tagging, or validate a working/tagged tree.
# PROGRAM_VERSION is authoritative; no release commit embeds its own hash.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

die() {
  printf 'release-pins: %s\n' "$1" >&2
  exit 1
}

read_file() {
  if [[ -n "${REF:-}" ]]; then
    git -C "$REPO_ROOT" show "${REF}:$1"
  else
    cat "$REPO_ROOT/$1"
  fi
}

main() {
  local action="${1:-}" version banner install rendered file
  REF="${2:-}"
  [[ $# -le 2 ]] || die "usage: $0 {update|check} [git-ref]"
  case "$action" in update|check) ;; *) die "usage: $0 {update|check} [git-ref]" ;; esac
  [[ "$action" != update || -z "$REF" ]] || die "update cannot modify a git ref"
  version="$(read_file scode | sed -n 's/^readonly PROGRAM_VERSION="\(.*\)"$/\1/p')"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid PROGRAM_VERSION"
  banner="> **Beta software (v${version}).** Defaults and compatibility may change."
  install="  RELEASE_TAG=\"v${version}\""

  if [[ "$action" == update ]]; then
    for file in README.md docs/installation.md; do
      rendered="$(sed \
        -e "s|^> \\*\\*Beta software (v[0-9][^)]*)\\.\\*\\*.*$|$banner|" \
        -e "s|^  RELEASE_TAG=\"v[0-9][^\"]*\"$|$install|" "$REPO_ROOT/$file")"
      printf '%s\n' "$rendered" > "$REPO_ROOT/$file"
    done
  fi
  [[ "$(read_file README.md | grep -Fxc "$banner")" == 1 ]] ||
    die "README banner is stale or missing; run make release-pins before tagging"
  [[ "$(read_file docs/installation.md | grep -Fxc "$install")" == 1 ]] ||
    die "installation selector is stale or missing; run make release-pins before tagging"
  if read_file README.md | grep -Eq '^(EXPECTED_COMMIT|COMMIT)='; then
    die "README contains obsolete self-referential commit pins"
  fi
  printf 'release-pins: documentation selects v%s (%s)\n' "$version" "${REF:-working tree}"
}

main "$@"
