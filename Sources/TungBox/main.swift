import AppKit
import Foundation

struct ConfigProfile: Codable, Equatable {
    var id: UUID
    var name: String
    var fileName: String
    var updatedAt: Date
}

final class Store {
    let baseURL: URL
    let profilesURL: URL
    let logURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = appSupport.appendingPathComponent("TungBox", isDirectory: true)
        profilesURL = baseURL.appendingPathComponent("profiles.json")
        logURL = baseURL.appendingPathComponent("sing-box.log")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func loadProfiles() -> [ConfigProfile] {
        guard let data = try? Data(contentsOf: profilesURL) else { return [] }
        return (try? JSONDecoder().decode([ConfigProfile].self, from: data)) ?? []
    }

    func saveProfiles(_ profiles: [ConfigProfile]) {
        guard let data = try? JSONEncoder.pretty.encode(profiles) else { return }
        try? data.write(to: profilesURL, options: .atomic)
    }

    func configURL(for profile: ConfigProfile) -> URL {
        baseURL.appendingPathComponent(profile.fileName)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

final class Runner: @unchecked Sendable {
    private var process: Process?
    private var outputPipe: Pipe?
    private let store: Store
    var onOutput: ((String) -> Void)?
    var isRunning: Bool { process?.isRunning == true }

    init(store: Store) {
        self.store = store
    }

    func findSingBox() -> String? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("sing-box").path,
            "/opt/homebrew/bin/sing-box",
            "/usr/local/bin/sing-box",
            "/usr/bin/sing-box"
        ].compactMap { $0 }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    func check(config: URL) throws -> String {
        guard let binary = findSingBox() else {
            throw NSError.user("找不到 sing-box。请先安装：brew install sing-box")
        }
        let result = runAndWait(binary, ["check", "-c", config.path])
        if result.status != 0 {
            throw NSError.user(result.output.isEmpty ? "配置检查失败" : result.output)
        }
        return result.output.isEmpty ? "配置检查通过" : result.output
    }

    func start(config: URL) throws {
        if isRunning { return }
        guard let binary = findSingBox() else {
            throw NSError.user("找不到 sing-box。请先安装：brew install sing-box")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["run", "-c", config.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.onOutput?(text) }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.onOutput?("\n[sing-box exited: \(proc.terminationStatus)]\n")
            }
        }

        try process.run()
        self.process = process
        outputPipe = pipe
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
    }

    private func runAndWait(_ binary: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, error.localizedDescription)
        }
    }
}

extension NSError {
    static func user(_ message: String) -> NSError {
        NSError(domain: "TungBox", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store = Store()
    private lazy var runner = Runner(store: store)
    private var profiles: [ConfigProfile] = []
    private var selectedIndex: Int?

    private let table = NSTableView()
    private let editor = NSTextView()
    private let logs = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "未启动")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TungBox"
        window.center()
        self.init(window: window)
        setup()
    }

    private func setup() {
        profiles = store.loadProfiles()
        runner.onOutput = { [weak self] text in
            self?.appendLog(text)
            self?.refreshStatus()
        }

        guard let content = window?.contentView else { return }

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)

        let sidebar = NSView()
        let main = NSView()
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(main)
        split.setPosition(260, ofDividerAt: 0)

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        setupSidebar(sidebar)
        setupMain(main)

        if profiles.isEmpty {
            createProfile(named: "默认配置", content: defaultConfig())
        } else {
            selectProfile(at: 0)
        }
        refreshStatus()
    }

    private func setupSidebar(_ view: NSView) {
        let title = NSTextField(labelWithString: "配置")
        title.font = .boldSystemFont(ofSize: 20)
        title.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 36
        table.target = self
        table.action = #selector(tableClicked)
        scroll.documentView = table

        let newButton = NSButton(title: "新建", target: self, action: #selector(newClicked))
        let importButton = NSButton(title: "导入", target: self, action: #selector(importClicked))
        let deleteButton = NSButton(title: "删除", target: self, action: #selector(deleteClicked))
        let buttons = NSStackView(views: [newButton, importButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(scroll)
        view.addSubview(buttons)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func setupMain(_ view: NSView) {
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveClicked))
        let checkButton = NSButton(title: "检查配置", target: self, action: #selector(checkClicked))
        let startButton = NSButton(title: "启动", target: self, action: #selector(startClicked))
        let stopButton = NSButton(title: "停止", target: self, action: #selector(stopClicked))
        toolbar.addArrangedSubview(saveButton)
        toolbar.addArrangedSubview(checkButton)
        toolbar.addArrangedSubview(startButton)
        toolbar.addArrangedSubview(stopButton)
        toolbar.addArrangedSubview(statusLabel)

        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.tabViewType = .topTabsBezelBorder

        let dashboardItem = NSTabViewItem(identifier: "dashboard")
        dashboardItem.label = "仪表盘"
        dashboardItem.view = makeDashboardView()
        tabs.addTabViewItem(dashboardItem)

        let configItem = NSTabViewItem(identifier: "config")
        configItem.label = "配置"
        configItem.view = makeConfigView()
        tabs.addTabViewItem(configItem)

        let logItem = NSTabViewItem(identifier: "logs")
        logItem.label = "日志"
        logItem.view = makeLogsView()
        tabs.addTabViewItem(logItem)

        let settingsItem = NSTabViewItem(identifier: "settings")
        settingsItem.label = "设置"
        settingsItem.view = makeSettingsView()
        tabs.addTabViewItem(settingsItem)

        view.addSubview(toolbar)
        view.addSubview(tabs)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            toolbar.heightAnchor.constraint(equalToConstant: 32),

            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tabs.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }

    private func makeDashboardView() -> NSView {
        let view = NSView()

        let title = NSTextField(labelWithString: "TUNGBOX")
        title.font = .boldSystemFont(ofSize: 28)
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "管理 sing-box 配置、运行状态和日志")
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let upload = metricCard(title: "上传", value: "0 KB/s", detail: "当前版本先显示运行状态，流量统计后续接 Clash API")
        let download = metricCard(title: "下载", value: "0 KB/s", detail: "启动后可在日志页查看实时输出")
        let status = metricCard(title: "状态", value: statusLabel.stringValue, detail: "使用官方 sing-box 二进制运行")

        let cards = NSStackView(views: [upload, download, status])
        cards.orientation = .horizontal
        cards.distribution = .fillEqually
        cards.spacing = 12
        cards.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(subtitle)
        view.addSubview(cards)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),

            cards.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cards.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cards.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),
            cards.heightAnchor.constraint(equalToConstant: 130)
        ])

        return view
    }

    private func makeConfigView() -> NSView {
        let view = NSView()
        let editorScroll = NSScrollView()
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.hasVerticalScroller = true
        editorScroll.documentView = editor
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        view.addSubview(editorScroll)

        NSLayoutConstraint.activate([
            editorScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            editorScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            editorScroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            editorScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        return view
    }

    private func makeLogsView() -> NSView {
        let view = NSView()
        let logTitle = NSTextField(labelWithString: "日志")
        logTitle.font = .boldSystemFont(ofSize: 15)
        logTitle.translatesAutoresizingMaskIntoConstraints = false

        let logScroll = NSScrollView()
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.hasVerticalScroller = true
        logScroll.documentView = logs
        logs.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logs.isEditable = false

        view.addSubview(logTitle)
        view.addSubview(logScroll)

        NSLayoutConstraint.activate([
            logTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            logTitle.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            logScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            logScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            logScroll.topAnchor.constraint(equalTo: logTitle.bottomAnchor, constant: 6),
            logScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        return view
    }

    private func makeSettingsView() -> NSView {
        let view = NSView()
        let binary = runner.findSingBox() ?? "未找到，请先 brew install sing-box"
        let storage = store.baseURL.path
        let text = NSTextField(labelWithString: """
        sing-box 路径
        \(binary)

        配置保存目录
        \(storage)

        当前限制
        TUN 模式通常需要管理员权限或 Network Extension。第一版优先支持 mixed/socks 本地代理模式。
        """)
        text.font = .systemFont(ofSize: 14)
        text.lineBreakMode = .byWordWrapping
        text.maximumNumberOfLines = 0
        text.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            text.topAnchor.constraint(equalTo: view.topAnchor, constant: 24)
        ])

        return view
    }

    private func metricCard(title: String, value: String, detail: String) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = 8

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(valueLabel)
        view.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            detailLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 8)
        ])

        return view
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        profiles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: profiles[row].name)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func tableClicked() {
        guard table.selectedRow >= 0 else { return }
        selectProfile(at: table.selectedRow)
    }

    @objc private func newClicked() {
        let name = "配置 \(profiles.count + 1)"
        createProfile(named: name, content: defaultConfig())
    }

    @objc private func importClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url) {
            createProfile(named: url.deletingPathExtension().lastPathComponent, content: text)
        }
    }

    @objc private func deleteClicked() {
        guard let index = selectedIndex else { return }
        let profile = profiles[index]
        try? FileManager.default.removeItem(at: store.configURL(for: profile))
        profiles.remove(at: index)
        store.saveProfiles(profiles)
        table.reloadData()
        selectedIndex = nil
        editor.string = ""
        if !profiles.isEmpty { selectProfile(at: min(index, profiles.count - 1)) }
    }

    @objc private func saveClicked() {
        do {
            try saveCurrent()
            appendLog("[TungBox] 已保存\n")
        } catch {
            showError(error)
        }
    }

    @objc private func checkClicked() {
        do {
            let url = try saveCurrent()
            let output = try runner.check(config: url)
            appendLog("[check] \(output)\n")
        } catch {
            showError(error)
        }
    }

    @objc private func startClicked() {
        do {
            let url = try saveCurrent()
            if editor.string.contains("\"type\"") && editor.string.contains("\"tun\"") {
                appendLog("[TungBox] 检测到 TUN 配置。如启动失败，请用管理员权限运行 sing-box，或先改成本地 mixed/socks 代理模式。\n")
            }
            try runner.start(config: url)
            appendLog("[TungBox] 已启动\n")
            refreshStatus()
        } catch {
            showError(error)
        }
    }

    @objc private func stopClicked() {
        runner.stop()
        appendLog("[TungBox] 已停止\n")
        refreshStatus()
    }

    private func selectProfile(at index: Int) {
        guard profiles.indices.contains(index) else { return }
        selectedIndex = index
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        let url = store.configURL(for: profiles[index])
        editor.string = (try? String(contentsOf: url)) ?? ""
    }

    private func createProfile(named name: String, content: String) {
        let profile = ConfigProfile(id: UUID(), name: name, fileName: "\(UUID().uuidString).json", updatedAt: Date())
        profiles.append(profile)
        try? content.write(to: store.configURL(for: profile), atomically: true, encoding: .utf8)
        store.saveProfiles(profiles)
        table.reloadData()
        selectProfile(at: profiles.count - 1)
    }

    @discardableResult
    private func saveCurrent() throws -> URL {
        guard let index = selectedIndex else { throw NSError.user("请先选择一个配置") }
        let data = editor.string.data(using: .utf8) ?? Data()
        _ = try JSONSerialization.jsonObject(with: data)
        profiles[index].updatedAt = Date()
        let url = store.configURL(for: profiles[index])
        try editor.string.write(to: url, atomically: true, encoding: .utf8)
        store.saveProfiles(profiles)
        table.reloadData()
        return url
    }

    private func appendLog(_ text: String) {
        logs.textStorage?.append(NSAttributedString(string: text))
        logs.scrollToEndOfDocument(nil)
    }

    private func refreshStatus() {
        statusLabel.stringValue = runner.isRunning ? "运行中" : "未启动"
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func defaultConfig() -> String {
        """
        {
          "log": {
            "level": "info"
          },
          "inbounds": [
            {
              "type": "mixed",
              "tag": "mixed-in",
              "listen": "127.0.0.1",
              "listen_port": 7890
            }
          ],
          "outbounds": [
            {
              "type": "direct",
              "tag": "direct"
            }
          ],
          "route": {
            "final": "direct"
          }
        }
        """
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MainWindowController()
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
