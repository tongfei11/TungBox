# Validation ledger

C1 validated. Store creates tun-daemon.json and tun-enabled in user Application Support. TunServiceManager writes those user-domain paths into the root LaunchDaemon script and the root script executes sing-box with that config whenever the flag exists.

C2 validated. LaunchDaemon plist uses StandardOutPath and StandardErrorPath under /tmp with predictable names. /tmp is world-writable; root daemons should not write predictable root-opened logs there.

C3 validated. CoreUpdater downloads the tar.gz, extracts it, finds the first sing-box binary, and copies it into the app Core directory without a digest/signature check. package_app.sh also builds latest upstream core via go install @latest for release packaging.

C4 validated as hardening issue. The generated config binds Clash API to 127.0.0.1:9090 with no secret. This is local-only but any same-user local process can control proxy selection/connections.

C5 validated as hardening issue. Subscription model stores URL string and imported node credentials in user Application Support JSON/config files without encryption. This is expected for many desktop clients but should be documented and ideally protected from accidental sharing/logging.
