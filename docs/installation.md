# Installation

## Requirements

The launcher uses Bash and standard Unix tools. macOS needs
`/usr/bin/sandbox-exec`; Linux needs `/usr/bin/bwrap` and permission to create
user namespaces. Production checks engine existence, then attempts launch.
It does not run the test suite's capability probe.

Signal restoration uses `/usr/bin/python3`, with `/usr/bin/perl` as fallback.
Without both, scode warns and leaves inherited ignored signal dispositions in
place; a launch-window Ctrl-C can be lost. macOS Claude credential processing
requires `/usr/bin/python3` and `security`. Without working Python, credential
inspection and rewriting are unavailable; do not rely on mirrored-refresh-token
refusal. See [harnesses](harnesses.md#claude-code-on-macos).
Node is needed for the browser preload when running Node applications, and for
development tests, not for every sandbox command.

```sh
# Debian/Ubuntu
sudo apt install bubblewrap
# Fedora/RHEL
sudo dnf install bubblewrap
```

## Homebrew

```sh
brew install bindsch/tap/scode
scode --version
```

The formula is maintained in [bindsch/homebrew-tap](https://github.com/bindsch/homebrew-tap).
It installs the launcher, preload, MIT license, and six example configurations.

## Verified source installation

The tag below is updated from `PROGRAM_VERSION` before a release is tagged.
It therefore selects the same release from a tagged copy of this guide.
The commands run in a fail-fast subshell.

```sh
(
  set -eu
  RELEASE_TAG="v0.6.1"
  git clone --filter=blob:none --branch "$RELEASE_TAG" https://github.com/bindsch/scode.git
  cd scode
  release_commit="$(git rev-parse "$RELEASE_TAG^{commit}")"
  git checkout --detach "$release_commit"
  test "$(git rev-parse HEAD)" = "$release_commit"
  test "$(./scode --version)" = "scode ${RELEASE_TAG#v}"
  sudo make install
  /usr/local/bin/scode --version
)
```

Existing tags through v0.6.0 are unsigned. Resolving and comparing a tag verifies
checkout consistency, not publisher authenticity. For independent verification,
obtain the expected commit from a trusted channel and compare it with
`git rev-parse HEAD` before installation. Do not treat two values fetched from
the same server as independent evidence. Future signed releases should use
`git verify-tag "$RELEASE_TAG"` with an independently verified signing key.

The old tagged READMEs from v0.3.1 through v0.6.0 select the previous release.
Those immutable documents are not repaired by editing the current branch.
Use this guide and select the intended tag explicitly for those versions.

## Manual installation from a verified checkout

First complete the clone, checkout, and verification steps above. Then run this
instead of `make install`; it installs the same artifacts:

```sh
(
  set -eu
  git diff --exit-code HEAD -- scode lib/no-sandbox.js LICENSE examples
  install -d "$HOME/.local/bin" "$HOME/.local/lib/scode" "$HOME/.local/share/scode/examples"
  install -m 755 scode "$HOME/.local/bin/scode"
  install -m 644 lib/no-sandbox.js "$HOME/.local/lib/scode/no-sandbox.js"
  install -m 644 LICENSE "$HOME/.local/share/scode/LICENSE"
  install -m 644 examples/sandbox.yaml examples/sandbox-strict.yaml \
    examples/sandbox-paranoid.yaml examples/sandbox-permissive.yaml \
    examples/sandbox-cloud-eng.yaml examples/sandbox-grok.yaml \
    "$HOME/.local/share/scode/examples/"
  "$HOME/.local/bin/scode" --version
)
```

If using downloaded artifacts instead, obtain the matching checksum manifest
from the release, verify it with `shasum -a 256 -c SHA256SUMS` inside a
`set -eu` subshell, and install only after that succeeds. Checksums detect
corruption; unsigned checksums from the same source do not authenticate it.
Do not assume older releases supply such a manifest.

## Custom prefix, upgrades, and uninstall

From the verified checkout:

```sh
make install PREFIX="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
"$HOME/.local/bin/scode" --version
```

Add the PATH export to `~/.zshrc` or `~/.bashrc` for interactive use.
The default prefix is `/usr/local`. Pass an expanded absolute prefix, not a
quoted literal tilde. Root and empty prefixes are rejected.

For Homebrew upgrades and removal, use `brew upgrade scode` and
`brew uninstall scode`. For source upgrades, verify the new release and
install to the same prefix. To remove a source installation, use
`make uninstall PREFIX="$HOME/.local"` or `sudo make uninstall` for the
default prefix. Uninstall removes packaged files, not user configuration,
credentials, logs, or accounting records.
