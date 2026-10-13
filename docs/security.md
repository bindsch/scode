# Security model

scode limits the OS authority of commands processing untrusted repositories,
prompts, tool output, hooks, and MCP data. A compromised harness is treated as
a command runner. Its readable files, writable files, credentials, network
connections, and open streams are the relevant authority.

| Protection | When it applies |
|---|---|
| Named personal/credential path blocks | Default and strict modes, subject to [path precedence](policy.md#precedence) |
| Deny-default filesystem view | Strict mode, including the untrusted preset; system/runtime exceptions remain |
| Restrictive-only project config | All modes |
| Ambient credential scrub | Explicit `--scrub-env`, untrusted preset, or detected Grok defense |
| No automatic harness-state grants or Claude copy | Untrusted preset |
| Read-only project | `--ro`, config `fs_mode: ro`, or untrusted preset |
| IP network restriction | `--no-net`, config `net: off`, or untrusted preset |
| Fixed engine lookup and closed nonstandard inherited descriptors | All launched runs |

Default mode exposes harness state and ambient environment credentials unless
separately restricted. Strict mode grants detected harness state read-write.
An allow, project choice, environment exemption, or socket grant can transfer
credentials or broad service authority. Configuration is not an authenticity
check on the command.

A cloud CLI can transmit anything it can read while its network is available.
scode cannot distinguish inference traffic from an unwanted upload to the same
encrypted origin. For no outbound source transfer, use an offline tool with
network disabled and no authority-bearing stream or socket grants.

The wrapper does not defend against kernel/engine vulnerabilities.
macOS uses deprecated sandbox-exec and broad compatibility allowances.
Linux depends on user namespaces and mount ordering. Disabling browser inner
sandboxes is another [explicit tradeoff](browsers.md#security-tradeoff).
[Logs](logging.md) and [accounting](accounting.md) are operational records,
not authenticated proof against a child that can modify their destinations.

Report vulnerabilities through the [disclosure policy](../.github/SECURITY.md).

## Research references

Links checked on 2026-10-13; these sources provide context, not additional
scode guarantees.

- [VS Code agent security](https://code.visualstudio.com/docs/agents/run/security)
- [Anthropic Sandbox Runtime](https://github.com/anthropics/sandbox-runtime)
- [MCP security best practices, 2026-07-28](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices)
- [Grok incident evidence and version limits](grok-defense.md)

The July report's Axios and NSA links returned access failures during the
documentation audit. That did not establish that they were dead. They are
not required evidence for the guarantees here; accessible primary references
above and in the Grok guide replace that dependency.
