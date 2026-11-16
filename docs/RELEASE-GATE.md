# Release gate

The canonical checklist is [Release procedure](releases.md).

| Rule | Required evidence |
|---|---|
| scode never reads, copies, changes, or guesses a harness login. It must not invoke a Keychain tool, write a credential file, or initiate a password dialog. | Static launcher checks plus offline fake-harness runs in normal, strict, legacy-flag, and untrusted modes: zero fake security calls, no state writes, existing synthetic mirrors and backups unchanged, no login refusal. |
| Login-store access is opt-in; a harness uses its own store. | macOS profiles deny access by default. CLI/user opt-in grants eligible claude/agy the keychain directory read-write and existing security preferences read-only. Opt-outs, custom blocks, and untrusted suppress the whole grant. Synthetic kernel tests deny preference writes, replacement, and creation when absent. System security remains executable and securityd stays reachable. |
| Empty retained environment values stay empty, not unset. | Runtime assertions with and without scrubbing and with explicit keep-env exemptions. |

The first rule governs scode's behavior. It does not prohibit a harness from
using its own Keychain item through `/usr/bin/security`, and it cannot guarantee
that a harness or macOS will never display a password dialog. Do not describe
offline fixture success as live authentication verification.
