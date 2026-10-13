# Environment policy

## Always removed or controlled

Before launch, scode removes inherited `BASH_ENV`, `ENV`, `CDPATH`,
`SSH_AUTH_SOCK`, and `SSH_AGENT_PID`. It uses a fixed system PATH internally
and resolves the command using the caller's PATH. Accounting variables are
consumed privately and removed from the child environment.
Caller-supplied internal scratch/preload/accounting state is cleared.

The caller's SSH-agent socket is added to the default blocks. Forwarding needs
an explicit path grant and an environment assignment on the launched command,
for example `scode --allow "$SSH_AUTH_SOCK" -- env SSH_AUTH_SOCK="$SSH_AUTH_SOCK" command`.
That deliberately transfers signing authority.

Browser compatibility sets or adjusts `SCODE_SANDBOXED`,
`ELECTRON_DISABLE_SANDBOX`, `PLAYWRIGHT_MCP_NO_SANDBOX`,
`CHROMIUM_FLAGS`, and `NODE_OPTIONS`; see [browsers](browsers.md).
`XDG_RUNTIME_DIR` is removed in Linux no-network mode. Strict mode omits its
automatic bind but does not itself remove the variable.
Interpreter startup carriers preserve selected caller values across
the trusted signal-restoration launcher; they are not extra scrub exemptions.

## Optional scrubbing

`--scrub-env` removes exported variables matching `SCRUB_PATTERNS` in
[scode](../scode). That table is the exact pattern reference.
It covers cloud, AI/provider, subscription, CI/CD, deployment, package, database,
SSH, and process-injection variables. The untrusted preset enables scrubbing.
Detected Grok defense forces it and refuses `--keep-env`.

Wildcard families remove configuration as well as secrets. For example,
`GOOGLE_*` removes `GOOGLE_CLOUD_PROJECT`, and `AZURE_*` removes
`AZURE_OPENAI_ENDPOINT`. Scrubbing is a name-based list, not semantic detection
of all credentials.

These enumerated routing/configuration names survive the current optional
scrub: `OPENAI_API_BASE`, `LLM_BASE_URL`, `LLM_MODEL`,
`GOOSE_PROVIDER`, `GOOSE_MODEL`, `PI_CODING_AGENT_DIR`,
`OPENCODE_CONFIG`, `CURSOR_API_ENDPOINT`, `ANTHROPIC_BASE_URL`, and
`KIMI_MODEL_*` except `KIMI_MODEL_API_KEY`.

`CODEMUX_*` variables also survive, including the credential
`CODEMUX_CODEX_PROVIDER_API_KEY`. Export that key only for runs that need it.
`LLM_API_KEY` is scrubbed. A command can receive new variables through its
arguments after scode's scrub; the scrub does not prevent deliberate reinjection.

## Exact-name exemptions

```sh
scode --scrub-env --keep-env ANTHROPIC_AUTH_TOKEN claude
scode --scrub-env --keep-env KIMI_MODEL_API_KEY,ZAI_API_KEY kimi
```

Names must match `[A-Za-z_][A-Za-z0-9_]*`. Empty entries, whitespace,
assignments, and patterns fail. Repeated names are deduplicated.
The parser does not classify credential names: `--keep-env PATH` is valid.
Without scrubbing, exemptions warn and have no effect. Dry-run shows names,
never values.

The refusal list is `LD_*`, `DYLD_*`, `NODE_OPTIONS`, `BASH_ENV`,
`ENV`, `ZDOTDIR`, `PYTHONPATH`, `PYTHONHOME`, `RUBYOPT`,
`PERL5OPT`, `PERL5LIB`, `PERLLIB`, `JAVA_TOOL_OPTIONS`,
`_JAVA_OPTIONS`, `GIT_CONFIG_*`, `GIT_ASKPASS`, and `SSH_*`.
Exemptions do not restore names removed unconditionally before scrubbing.
