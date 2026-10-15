import AppKit

// 入口导航（路径相对 Sources/TungBox）：
// AppDelegate.swift 管理启动、重开、退出，并持有 MainWindow/MainWindowController.swift；
// 主控制器管理窗口、页面及共享 UI 状态。页面交互位于 MainWindow 下的页面扩展。
// 配色与主题刷新见 Views/MD3Theme.swift，普通按钮见 Views/MD3Buttons.swift；
// 其余控件暂留 MD3Views.swift，按后续步骤迁移。
//
// 开关链路：MainWindow/MainWindowController+Home.swift 或
// MainWindow/MainWindowController+Tray.swift → MainWindow/MainWindowController+Runtime.swift
// 的 reconcileRuntime → Services/RuntimeCoordinator.swift → 注入的系统操作
// → handleRuntimeEvent → 页面状态。协调器管理代次、串行启停、重载与退出。
// 开关意图同步接受，旧后台结果按代次失效；不要用测速或刷新状态禁用开关。
//
// 配置适配：MainWindow/MainWindowController+Configuration.swift 连接编辑器和存储，调用
// Core/ConfigCodec.swift、Core/ProxyModeConfig.swift、Core/TUNRuntimeConfigBuilder.swift；
// Core/ConfigInspection.swift 负责展示解析。Core 配置模块不依赖窗口。
// 系统服务：Services/Runner.swift、Services/TunServiceManager.swift 管理两个独立 Core；
// Services/SystemProxyManager.swift、Services/RuntimePortProbe.swift、Services/SystemCommand.swift
// 封装系统操作。Core/Store.swift 管理配置、订阅、规则和日志路径，Runner 复用同一个 Store。

let app = NSApplication.shared
// 工厂在 applicationDidFinishLaunching 中执行，避免事件循环启动前访问存储或创建窗口。
let delegate = AppDelegate {
    MainWindowController(
        store: Store(),
        systemProxyManager: SystemProxyManager(),
        runtimePortProbe: RuntimePortProbe(),
        runtimeCoordinator: RuntimeCoordinator(),
        makeRunner: { Runner(store: $0) }
    )
}
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
