# TungBox Security Scan Report

Scan id: 20260603T080239Z-d91424b
Repo: /Users/thomastung/Documents/Codex/TungBox
Commit: d91424b
Build verification: swift build passed

## Findings

### C1 High - TUN root daemon reads user-writable config and enable flag

Evidence:
- Sources/TungBox/Core/Store.swift:37-46 creates tun-daemon.json and tun-enabled under the user's Application Support directory.
- Sources/TungBox/Services/TunServiceManager.swift:137-138 writes the active TUN config and enable flag there from the user app process.
- Sources/TungBox/Services/TunServiceManager.swift:145-150 embeds those user-domain paths into the root LaunchDaemon script.
- Sources/TungBox/Services/TunServiceManager.swift:167-169 starts root-owned sing-box using that user-writable config whenever the user-writable flag exists.

Impact:
After one administrator-approved TUN service installation, any same-user local process can modify the active TUN config/flag and influence a root-running sing-box process. At minimum this allows unauthorized start/stop and root-level network routing changes. Depending on supported sing-box config options, this can also create root-owned files or bind privileged resources.

Recommendation:
Move the active daemon config and enable flag to a root-owned directory such as /Library/Application Support/TungBox with strict ownership and permissions. The UI should update daemon state through an authorized helper or a narrowly scoped privileged action. The daemon should reject config/flag files that are user-writable, symlinks, not root-owned, or outside the root-owned directory.

### C2 Medium - LaunchDaemon stdout/stderr use predictable /tmp paths

Evidence:
- Sources/TungBox/Services/TunServiceManager.swift:211-214 sets StandardOutPath and StandardErrorPath to /tmp/com.tung.tungbox.tun.*.log.

Impact:
/tmp is world-writable. Root daemons should not open predictable files in /tmp because local users can pre-create files or symlinks and potentially cause root-owned log creation/truncation/writes in unintended locations.

Recommendation:
Write daemon stdout/stderr to a root-owned log directory such as /Library/Logs/TungBox or the existing /Library/Application Support/TungBox directory, with files created and owned by root:wheel before launchd loads the plist. Avoid /tmp for root daemon logs.

### C3 Medium - sing-box Core updater installs downloaded binaries without cryptographic verification

Evidence:
- Sources/TungBox/Services/CoreUpdater.swift:36-53 downloads a GitHub release asset, extracts it, finds a sing-box binary, and copies it to the Core directory without verifying a checksum/signature.
- script/package_app.sh:88-101 builds packaging Core from github.com/sagernet/sing-box/cmd/sing-box@latest, which is not pinned for reproducible release builds.

Impact:
A compromised upstream release, GitHub account, release asset, or build dependency path could result in TungBox installing or bundling a malicious Core. If that Core is later installed into the TUN service, it may run as root.

Recommendation:
Pin release-build Core versions. For in-app Core update, verify an official checksum or signature before replacing the executable. Show the version and digest to the user and fail closed on mismatch. For release packaging, pin the module version/tag instead of @latest and record the expected SHA256 in the release notes.

## Hardening Notes

### C4 Low - Local Clash API has no random secret

Evidence:
- Sources/TungBox/Core/Models.swift:113-114 defines 127.0.0.1:9090.
- Sources/TungBox/Networking/SubscriptionImporter.swift:132 and 293-296 generate clash_api external_controller without a secret.

Risk:
The API is local-only, but any same-user local process can control proxy groups and connections. Adding a random secret reduces accidental or malicious local access, and may help against some browser/localhost request scenarios.

Recommendation:
Generate a per-install secret, write it into sing-box clash_api config, and send Authorization from TungBox's ClashAPI client.

### C5 Low - Subscription credentials are stored in plaintext user config

Evidence:
- Sources/TungBox/Core/Models.swift:10-17 stores subscription URL fields.
- Sources/TungBox/Core/Store.swift:63-70 persists subscriptions.json under Application Support.
- Sources/TungBox/Networking/SubscriptionFormatParser.swift:186-201 maps proxy passwords into generated config.

Risk:
This is common for local proxy clients, but Xboard subscription URLs and proxy credentials are sensitive. They can be exposed by backups, support bundles, or accidental sharing of the config directory.

Recommendation:
Document that the config directory contains credentials. Avoid logging subscription URLs. Consider Keychain storage for subscription URLs or tokens later.

## Non-findings

- Shell command execution generally uses Process arguments rather than string interpolation. The privileged TUN install path quotes shell and AppleScript strings.
- App update detection only checks releases and opens GitHub in the browser; it does not auto-install app binaries.
- Rule-set download/decompile writes to a sanitized cache filename and runs sing-box with argument arrays, not shell text.

## Artifacts

- Threat model: artifacts/01_context/threat_model.md
- Candidate list: artifacts/02_discovery/candidates.csv
- Coverage receipts: artifacts/03_coverage/coverage_receipts.md
- Validation ledger: artifacts/04_reconciliation/validation_ledger.md
