#!/usr/bin/env bash
#
# Rewrite (or verify) the release pins in README.md.
#
# The README documents a source install and a manual install that both pin the
# exact released commit plus SHA-256 hashes of the shipped artifacts. Those
# values can only be known once the release tag exists, so they are derived from
# the tag here instead of being edited by hand.
#
# Pins always reference the commit that tag v<PROGRAM_VERSION> points at -- not
# HEAD -- because that is the tree a user actually checks out and verifies.
#
# Usage:
#   scripts/release-pins.sh update   # rewrite README.md pins from the release tag
#   scripts/release-pins.sh check    # exit non-zero if README.md is out of date
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly README="${REPO_ROOT}/README.md"
readonly ARTIFACTS=(scode lib/no-sandbox.js LICENSE)

die() {
  printf 'release-pins: %s\n' "$1" >&2
  exit 1
}

# Version comes from the launcher; it is the single source of truth.
program_version() {
  local version
  version="$(sed -n 's/^readonly PROGRAM_VERSION="\(.*\)"$/\1/p' "${REPO_ROOT}/scode")"
  [ -n "$version" ] || die "could not read PROGRAM_VERSION from scode"
  printf '%s' "$version"
}

release_tag() {
  printf 'v%s' "$(program_version)"
}

release_commit() {
  local tag
  tag="$(release_tag)"
  git -C "$REPO_ROOT" rev-list -n 1 "$tag" 2>/dev/null ||
    die "tag ${tag} does not exist yet; tag the release commit first"
}

# Hash the artifact as it exists at the release tag, not in the working tree.
artifact_sha() {
  local tag="$1" path="$2"
  git -C "$REPO_ROOT" show "${tag}:${path}" | shasum -a 256 | cut -d' ' -f1
}

# Emit the README with current pins substituted in.
render() {
  local version tag commit
  version="$(program_version)"
  tag="$(release_tag)"
  commit="$(release_commit)"

  local -a sed_args=(
    -e "s|^> \*\*Beta software (v[0-9][^)]*)\.\*\*|> **Beta software (v${version}).**|"
    -e "s|^EXPECTED_COMMIT=\"[0-9a-f]*\" # v.*$|EXPECTED_COMMIT=\"${commit}\" # v${version}|"
    -e "s|^COMMIT=\"[0-9a-f]*\" # v.*$|COMMIT=\"${commit}\" # v${version}|"
  )

  local artifact basename hash
  for artifact in "${ARTIFACTS[@]}"; do
    basename="${artifact##*/}"
    hash="$(artifact_sha "$tag" "$artifact")"
    # Match the manual-install checksum lines: "  <hash> <basename> \"
    sed_args+=(-e "s|^  [0-9a-f]\{64\} ${basename} \\\\$|  ${hash} ${basename} \\\\|")
  done

  sed "${sed_args[@]}" "$README"
}

main() {
  local tmp
  case "${1:-}" in
    update)
      tmp="$(mktemp)"
      trap 'rm -f "$tmp"' EXIT
      render > "$tmp"
      if cmp -s "$tmp" "$README"; then
        echo "release-pins: README.md already current ($(release_tag) @ $(release_commit))"
      else
        cat "$tmp" > "$README"
        echo "release-pins: README.md updated to $(release_tag) @ $(release_commit)"
      fi
      ;;
    check)
      if ! render | cmp -s - "$README"; then
        die "README.md pins are stale; run 'make release-pins'"
      fi
      echo "release-pins: README.md pins match $(release_tag) @ $(release_commit)"
      ;;
    *)
      die "usage: $0 {update|check}"
      ;;
  esac
}

main "$@"
