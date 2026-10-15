import AppKit
import Darwin
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController?
    private var terminationReplyTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        controller = MainWindowController()

        let startSilently = UserDefaults.standard.bool(forKey: "startSilently")
        if isLaunchedAtLogin() && startSilently {
            NSApp.setActivationPolicy(.accessory)
            controller?.appendLog("[启动] 检测到开机自启动且已勾选“静默启动”，只在状态栏运行，已隐藏控制台窗口。\n")
        } else {
            controller?.showConsoleWindow()
        }
        controller?.applyStartupProxyPreference()
    }

    func isLaunchedAtLogin() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getppid()]
        let junk = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        if junk == 0 {
            let name = withUnsafeBytes(of: &info.kp_proc.p_comm) { bytes -> String in
                if let baseAddress = bytes.baseAddress {
                    return String(cString: baseAddress.assumingMemoryBound(to: CChar.self))
                }
                return ""
            }
            return name == "launchd"
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showConsoleWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        if terminationReplyTask == nil {
            let cleanup = controller.stopServiceFromDelegate()
            terminationReplyTask = Task { @MainActor in
                await cleanup.value
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stopServiceFromDelegate()
    }

    @MainActor
    func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(NSMenuItem(
            title: "退出 \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
