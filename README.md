# scode

> **Beta software (v0.6.1).** Defaults and compatibility may change.

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
grants and credential copying, scrubs the environment, disables IP networking,
and makes the project read-only. Explicit flags and path grants can change this
policy. Neither mode protects data you deliberately make accessible.

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
