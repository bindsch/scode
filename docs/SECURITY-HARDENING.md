# Security hardening and research

Last reviewed: 2026-07-16

This document records the threat model behind scode's hardened defaults and `grok_defense`. It distinguishes kernel-enforced controls from vendor settings that may change without notice.

## Threat model

An AI coding harness is a networked command runner processing untrusted natural language, repository content, tool output, project rules, and MCP data. scode assumes any of those inputs may induce unintended commands or data access.

The policy aims to:

- keep credentials, SSH/signing keys, browser sessions, personal files, histories, and other harness state outside the readable filesystem view;
- treat repository-owned `.scode.yaml`, agent instructions, hooks, MCP configuration, and tool output as untrusted;
- keep project configuration restrictive-only;
- scrub ambient credentials and shell/runtime injection variables;
- make strict, read-only, and no-network modes composable and non-bypassable by broader allows;
- resolve sandbox engines through fixed system paths rather than caller-controlled `PATH`.

It does not claim to stop a kernel exploit, a sandbox-engine vulnerability, or exfiltration of data deliberately made readable to a networked cloud service.

On Linux, `--no-net` creates a new network namespace and omits the default
`XDG_RUNTIME_DIR` bind. Nonstandard inherited descriptors are closed before
launch, but pathname Unix sockets explicitly reintroduced with `--allow` and
standard streams are not network-namespace resources and remain potential authority channels. On macOS,
`sandbox-exec` is deprecated and scode imports Apple's private `system.sb` for
runtime compatibility; strict mode still requires broad Mach service lookup.
Treat both engines as policy primitives, not complete sandboxes.

## Grok Build incident

The primary public investigation reproduced Grok Build v0.2.93 sending repository data through two paths:

1. File content read during agent operation appeared in `/v1/responses` traffic.
2. A separate collector created and sent a complete Git bundle, including tracked files and history, through `/v1/storage`.

The second path did not depend on model file reads or the user's prompt. In the researcher's 12 GB canary repository, storage upload traffic was about 5.10 GiB while model traffic was about 192 KiB. Disabling “Improve the model” did not stop collection. The behavior later stopped on the same client build after server settings changed, demonstrating that the observed mitigation was server-controlled and reversible. See the [primary technical investigation](https://gist.github.com/cereblab/dc9a40bc26120f4540e4e09b75ffb547), [reproduction repository](https://github.com/cereblab/grok-build-exfil-repro), and [privacy opt-out retest](https://github.com/cereblab/grok-build-exfil-repro/blob/main/PRIVACY_OPTOUT.md).

The retest found that `/privacy opt-out` affected retention semantics, not whether trace traffic was transmitted. Independent reporting also described customer-data deletion requests after disclosure: [Axios](https://www.axios.com/2026/07/14/spacexai-grok-customer-data) and [The Hacker News](https://thehackernews.com/2026/07/grok-build-uploads-entire-git.html).

As of this review, xAI had not published a root-cause advisory explaining the collector, affected versions, server-side remediation guarantees, or deletion scope.

## What `grok_defense` enforces

With `grok_defense: true`, a directly detected `grok` command runs strict and scrubbed. scode blocks the project's Git metadata and common dotenv paths at the OS sandbox boundary. Without `.git`, the demonstrated full-history Git-bundle channel cannot read repository objects. Strict mode also prevents Grok from reading other harness directories and the rest of the user's home, except its default `~/.grok` state directory. A custom `GROK_HOME` needs an explicit user/CLI allow; environment-controlled roots are never auto-authorized.

scode additionally pins the current Grok telemetry, trace, workspace collection/queue, relay-sync, compatibility-scanner, memory, subagent, tool-search, web-fetch, Git-ignore, and updater controls to their restrictive values. The documented settings include `GROK_RESPECT_GITIGNORE`, `GROK_DISABLE_AUTOUPDATER`, `GROK_WEB_FETCH`, `GROK_MEMORY`, `GROK_SUBAGENTS`, and `GROK_TOOL_SEARCH`; see the [xAI settings reference](https://docs.x.ai/build/settings/reference). Collection/telemetry variables were confirmed by local inspection of Grok v0.2.101 but are not all documented vendor contracts.

xAI's enterprise policy supports system/user requirements files and documents `/etc` as the highest-precedence location. Its network guide separates core, sync, asset, update, and storage hosts; see [xAI enterprise deployment](https://docs.x.ai/build/enterprise). Host filtering is useful but insufficient for this incident because inference and storage routes may share an allowed service origin. Path-aware filtering would require a trusted TLS-intercepting proxy, with its own operational and trust cost.

An independent hardening test reported that `[harness] disable_codebase_upload = true` prevented the v0.2.93 Git-bundle upload even when telemetry was enabled: [grok-build-privacy-hardening](https://github.com/wetlink/grok-build-privacy-hardening). scode treats this vendor setting as defense in depth, not as the primary boundary.

## SOTA policy rationale

The refreshed defaults follow recurring guidance across current agent-security work:

- [OWASP Secure Coding with AI](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Coding_with_AI_Cheat_Sheet.html) recommends OS sandboxing, blocking credential/SSH/cloud locations, constraining egress, ephemeral credentials, and avoiding auto-approval for untrusted inputs.
- [VS Code agent security](https://code.visualstudio.com/docs/agents/security) describes OS sandboxing as the strongest local boundary and notes that command approval parsing is necessarily limited.
- [OpenAI's agent approvals and security guidance](https://learn.chatgpt.com/docs/agent-approvals-security) emphasizes scoped permissions and approval boundaries.
- [Anthropic Sandbox Runtime](https://github.com/anthropic-experimental/sandbox-runtime) combines OS filesystem sandboxing with network mediation, illustrating why domain-aware egress requires more infrastructure than a zero-daemon wrapper.
- [MCP security best practices](https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices) and the [NSA MCP security guide](https://www.nsa.gov/Portals/75/documents/Cybersecurity/CSI_MCP_SECURITY.pdf?ver=bmgiSbNQLP6Z_GiWtRt6bg%3D%3D) treat tool metadata, authorization, confused-deputy behavior, and prompt-driven tool use as security boundaries.

Recent coding-agent vulnerabilities reinforce several concrete rules:

- project settings and instructions must not weaken user policy: [Claude Code settings trust bypass](https://github.com/anthropics/claude-code/security/advisories/GHSA-mmgp-wc2j-qcv7);
- path containment must handle symlinks and worktrees: [symlink escape](https://github.com/anthropics/claude-code/security/advisories/GHSA-vp62-r36r-9xqp) and [worktree escape](https://github.com/anthropics/claude-code/security/advisories/GHSA-7835-87q9-rgvv);
- host approval alone is not sufficient egress control: [preapproved-hostname exfiltration](https://github.com/anthropics/claude-code/security/advisories/GHSA-fg94-h982-f3mm);
- approval UIs can disagree with actual execution authority: [GhostApproval](https://www.wiz.io/blog/ghostapproval-a-trust-boundary-gap-in-ai-coding-assistants).

These findings motivated restrictive-only project config, final block/read-only reassertion, fixed sandbox-engine lookup, broader credential/history blocks, no broad macOS Library carve-outs, and expanded environment scrubbing.

## Operational guidance

- Use `--trust untrusted` for unknown repositories: strict, read-only project, scrubbed environment, and no network.
- Prefer short-lived, narrowly scoped credentials injected only for a single command. Avoid exposing SSH-agent or browser-session sockets.
- Keep consequential actions behind human approval even when a sandbox is active.
- Treat MCP servers, repository rules, hooks, and third-party skills as code with the same authority as the agent.
- After any Grok update, run `grok inspect` and a canary repository while monitoring network traffic. Vendor flags and endpoints are not a stable security boundary.
- If a repository may have been collected, rotate secrets present in current files or Git history, review Grok's local unified log/upload queue, and pursue vendor-side deletion. Deleting local queue data cannot recall a completed remote upload.

## Non-negotiable limitation

A cloud coding CLI cannot both read source and be cryptographically guaranteed never to send that source to its required service. scode can block unrelated files, Git history, secrets, and normal IP network access. It cannot distinguish legitimate inference payloads from an unwanted upload when both use the same encrypted service connection, nor revoke standard streams or explicitly allowed local sockets. Use `net: off` with no authority-bearing stream/socket opt-ins, or an independently isolated offline/local model, when no source may leave the host.
