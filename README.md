# scode

> **Beta software (v0.6.8).** Defaults and compatibility may change.

scode runs commands inside an OS sandbox on macOS or Linux. It uses a shared
policy for coding tools without a daemon or container service.

The default policy blocks selected personal and credential paths. It still
permits a writable project, network access, inherited credentials, and readable
harness state. Explicit grants and the selected project can reopen protected
locations. macOS starts with allow-default; Linux exposes selected mounts.
Read the [policy reference](docs/policy.md) before relying on either boundary.

## Quickstart

```sh
brew install bindsch/tap/scode
scode claude
scode codex
scode --strict opencode
scode --trust untrusted goose
```

Linux requires bubblewrap. See [installation](docs/installation.md) for source
and manual installation, verification, runtime dependencies, and custom prefixes.

`--strict` limits filesystem access but automatically grants detected harness
state read-write access. `--trust untrusted` also disables those automatic
grants, scrubs the environment, disables IP networking,
and makes the project read-only. Explicit flags and path grants can change this
policy. Neither mode protects data you deliberately make accessible.

On macOS, login-store access is off by default. `--login-store` or user-config
`login_store: true` opts in for normal and strict `claude` and `agy` runs.
The grant makes `~/Library/Keychains` read-write so the harness can refresh its
own item. `~/Library/Preferences/com.apple.security.plist` is read-only when it
exists. The invoked name must be the harness name (optionally `.exe`), resolving
to a regular executable outside the project. Native version-number targets
qualify; interpreter entry scripts and shell `-c` wrappers do not.
Both modes report the granted paths.
Every process in that sandbox can read Keychain items whose access list trusts
`/usr/bin/security` without a dialog. This includes the harness's login and
refresh token, and tokens other tools stored through `security`, such as a
GitHub CLI token. Every process can read and copy out `login.keychain-db`,
encrypted under the account's login password, which can then be attacked offline.
It can create, modify or delete files in the keychain directory. It cannot change
the default keychain or search list through the read-only preference file.
Other Library paths stay blocked.
Use `--no-login-store` (user config: `no_login_store: true`), an overlapping
`--block`, or `--trust untrusted` to suppress the grant even after opt-in.
Project config cannot enable it; project `no_login_store: true` can suppress it.
Without access, the harness cannot use a Keychain login. A sandboxed `claude` on
macOS falls back to `~/.claude/.credentials.json` if one exists and is accessible;
scode does not inspect that file. Explicit `--allow` retains its authority.
See [security](docs/security.md) for the exposure and precedence.
scode never reads, copies, changes, or checks a harness login; each harness uses
one login store, so scode cannot create a stale refresh-token copy.
Existing credential files and backups are left alone. `--no-credential-sync`
is a compatibility no-op for 0.6.8.

macOS `--allow-staged PATH` (user config: `allowed_staged`) grants the base file
and `.tmp.<8 hex digits>` siblings for atomic replacement. Symlinked base files
are refused. Matching ignores case across the whole staged path, including
directory and base names, even on case-sensitive volumes. See [policy](docs/policy.md).

## Common commands

```sh
scode --cwd ./project --ro codex
scode --allow ~/Documents/reference claude
scode --scrub-env --keep-env ZAI_API_KEY claude
scode --config examples/sandbox-strict.yaml opencode
scode --log session-001.log codex
scode audit session-001.log
scode -- npm test
```

Logging captures command stderr and replaces an existing destination. Use unique
paths and protect logs as sensitive data. See [logging](docs/logging.md).

An alias such as `alias sclaude='scode claude'` saves typing in an interactive
shell. It does not cover absolute executable paths, other shells, scripts, or
subprocess launches.

A writable project can be damaged. A networked command can transmit readable
data. Standard streams and explicitly allowed local sockets can carry authority
even with IP networking disabled. Browser compatibility disables Chromium's
inner sandbox; the outer policy then limits a compromised renderer.
See [security](docs/security.md) for the threat model.

## Documentation

Start at the [documentation index](docs/index.md).

- [CLI and exit statuses](docs/cli.md), [policy](docs/policy.md), and [configuration](docs/configuration.md)
- [Harness detection and authentication](docs/harnesses.md), [environment](docs/environment.md), and [browsers](docs/browsers.md)
- [Logging](docs/logging.md), [accounting](docs/accounting.md), and [platforms and signals](docs/platforms.md)
- [Development](docs/development.md), [releases](docs/releases.md), and [changelog](CHANGELOG.md)
- [Security disclosure](.github/SECURITY.md) and [historical reports](docs/archive/index.md)

## License

[MIT](LICENSE). Copyright 2026 Laurent Bindschaedler.
