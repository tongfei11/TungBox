# Coverage receipts

Git-tracked source files: all 31 files listed in git_files.txt were covered at either full-file or hotspot level.

Full/high-risk review:
- Sources/TungBox/Services/TunServiceManager.swift
- Sources/TungBox/Services/CoreUpdater.swift
- Sources/TungBox/Services/Runner.swift
- Sources/TungBox/Networking/SubscriptionImporter.swift
- Sources/TungBox/Networking/SubscriptionFormatParser.swift
- Sources/TungBox/Networking/ClashAPI.swift
- Sources/TungBox/Services/AppUpdater.swift
- Sources/TungBox/Core/Store.swift
- Sources/TungBox/Core/Models.swift
- Sources/TungBox/main.swift hotspot ranges for start/stop/TUN/system proxy/process execution
- Sources/TungBox/MainWindow/MainWindowController+Settings.swift hotspot ranges for Core import/TUN settings/rule-set URL settings
- Sources/TungBox/MainWindow/MainWindowController+Rules.swift hotspot ranges for remote rule-set cache/decompile
- script/package_app.sh

UI-only/layout review:
- Sources/TungBox/MD3Views.swift
- Sources/TungBox/MainWindow/MainWindowController+Home.swift
- Sources/TungBox/MainWindow/MainWindowController+Nodes.swift
- Sources/TungBox/MainWindow/MainWindowController+Subscriptions.swift
- Sources/TungBox/MainWindow/MainWindowController+Connections.swift
- Sources/TungBox/MainWindow/MainWindowController+Logs.swift
- Sources/TungBox/MainWindow/MainWindowController+Tray.swift
- Sources/TungBox/MainWindow/MainWindowController+AppUpdate.swift
- Sources/TungBox/MainWindow/MainWindowController+TableView.swift
- Sources/TungBox/Core/AppMetadata.swift
- Sources/TungBox/Core/Utilities.swift
- Package.swift
- README.md
- .gitignore
- tray png resources

Untracked/local-only files checked for secret indicators:
- .claude/settings.json
- .claude/settings.local.json
- cache.db
- .DS_Store files ignored as metadata

Verification command:
- swift build: passed
