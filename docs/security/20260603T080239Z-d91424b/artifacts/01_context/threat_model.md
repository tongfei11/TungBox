# TungBox repository threat model

Scope: SwiftPM macOS desktop app that manages sing-box, subscriptions, rules, local Clash API, system proxy settings, app/core updates, and a root LaunchDaemon for TUN mode.

Primary trust boundaries:
- User-facing app process runs as the logged-in user.
- TUN LaunchDaemon runs as root after administrator authorization.
- sing-box Core may be bundled, manually imported, or downloaded from upstream release assets.
- Subscriptions and rule-set URLs are remote/untrusted inputs and may contain credentials or malicious config values.
- Local Clash API is bound to 127.0.0.1 and is intended for local UI control.

High-impact assets:
- Root execution boundary of the TUN service.
- Installed sing-box Core binary and generated config files.
- Subscription URLs and proxy credentials in local config.
- System proxy/TUN state that determines user traffic routing.

Expected attacker models:
- Malicious subscription provider or compromised subscription/rule-set URL.
- Malicious local process running as the same user after TungBox is installed.
- Upstream release asset compromise or supply-chain tampering.
- Malicious local web page or local process trying to talk to 127.0.0.1 Clash API.

Out of scope: Apple platform compromise, malicious administrator intentionally replacing root-owned files, and vulnerabilities inside sing-box itself unless TungBox configuration materially increases exposure.
