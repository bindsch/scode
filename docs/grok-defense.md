# Grok defense

Vendor behavior reviewed on 2026-07-16: public Grok Build v0.2.93 incident
evidence and local inspection of v0.2.101 compatibility controls.
Links were checked again on 2026-10-13. That link check is not a new runtime
verification of current Grok versions.

Enable in a trusted user config:

```yaml
grok_defense: true
```

Then run `scode grok`, or use
`scode --config examples/sandbox-grok.yaml grok`.

## Kernel policy

For a detected Grok command, including supported wrappers, defense forces
strict mode and environment scrubbing. It rejects `--keep-env` and a project
root equal to `/`, effective HOME, or account home.
It blocks these exact names at the selected project root:

```text
.git
.grok
.env
.envrc
.env.local
.env.development
.env.development.local
.env.production
.env.production.local
.env.staging
.env.staging.local
.env.test
.env.test.local
```

This is not a recursive search for nested repositories or nested dotenv files.
Overlapping explicit grants are refused. The normal harness-state grant is
`~/.grok`; custom roots such as `GROK_HOME` need user authorization.
Project and other explicit grants can still expose data. Network stays enabled
unless disabled separately, so readable source can be transmitted.

## Vendor controls

When defense is configured, scode exports restrictive collection, telemetry,
trace, queue, relay-sync, Git-ignore, updater, scanner, memory, subagent,
tool-search, and web-fetch controls. These also reach nested Grok processes.
Strict mode and project blocks require direct detection of Grok.

The exact exported variable assignments are in the Grok-defense environment
block in [scode](../scode). They were inspected against v0.2.101, and not all
are documented vendor contracts. `XAI_API_KEY` is scrubbed for detected Grok;
a working file/OAuth login is required for authenticated cloud use.

The following vendor requirements were documented during the July review:

```toml
[harness]
disable_codebase_upload = true
[features]
telemetry = false
[telemetry]
trace_upload = false
[tools]
respect_gitignore = true
[cli]
auto_update = false
```

Review the [settings reference](https://docs.x.ai/build/settings/reference)
before applying these to `~/.grok/requirements.toml` or a system requirements
file. Vendor settings are defense in depth and may change across versions.

## Incident evidence

The [primary wire analysis](https://gist.github.com/cereblab/dc9a40bc26120f4540e4e09b75ffb547)
reported v0.2.93 uploading a Git bundle independently of model file reads.
It also observed behavior changing through server settings on the same client.
The [reproduction repository](https://github.com/cereblab/grok-build-exfil-repro)
contains canary fixtures and evidence.
The [privacy opt-out retest](https://github.com/cereblab/grok-build-exfil-repro/blob/main/PRIVACY_OPTOUT.md)
distinguished retention controls from transmission.
A separate [hardening test](https://github.com/wetlink/grok-build-privacy-hardening)
reported `disable_codebase_upload` blocking the v0.2.93 bundle path.

As of the 2026-07-16 review, the report had not identified a public vendor
root-cause advisory. This is a dated observation, not a statement about later
advisories or current clients.

After upgrades, record the exact Grok version, inspect its effective settings,
and repeat a canary network test with fake secrets. Do not use a live sensitive
repository. If data was already collected, local deletion cannot recall a
remote upload; follow the organization's incident process and vendor deletion
procedure.
