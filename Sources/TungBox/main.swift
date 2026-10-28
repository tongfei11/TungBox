import AppKit

// 入口导航（路径相对 Sources/TungBox）：
// AppDelegate.swift 管理启动、重开、退出，并持有 MainWindow/MainWindowController.swift；
// 主控制器管理窗口、页面及共享 UI 状态。页面交互位于 MainWindow 下的页面扩展。
// 配色与主题刷新见 Views/MD3Theme.swift，普通按钮见 Views/MD3Buttons.swift；
// 输入与选择控件见 Views/MD3Inputs.swift，状态指示器见 Views/MD3Indicators.swift；
// 表格与滚动见 Views/MD3TableViews.swift，业务组件见 Views/MD3BusinessViews.swift；
// 遮罩弹窗及交互边界见 Views/MD3Dialog.swift。
//
// 开关链路：MainWindow/MainWindowController+Home.swift 或
// MainWindow/MainWindowController+Tray.swift → MainWindow/MainWindowController+Runtime.swift
// 的 reconcileRuntime → Services/RuntimeCoordinator.swift → 注入的系统操作
// → handleRuntimeEvent → 页面状态。协调器管理代次、串行启停、重载与退出。
// 开关意图同步接受，旧后台结果按代次失效；不要用测速或刷新状态禁用开关。
// 控件快照与回传在主线程；阻塞系统操作由协调器串行放到后台执行。
//
// 配置适配：MainWindow/MainWindowController+Configuration.swift 连接编辑器和存储，调用
// Core/ConfigCodec.swift、Core/ProxyModeConfig.swift、Core/TUNRuntimeConfigBuilder.swift；
// Core/ConfigInspection.swift 负责展示解析。Core 配置模块不依赖窗口。
// 系统服务：Services/Runner.swift、Services/TunServiceManager.swift 管理两个独立 Core；
// Services/SystemProxyManager.swift、Services/RuntimePortProbe.swift、Services/SystemCommand.swift
// 封装系统操作。Core/Store.swift 管理配置、订阅、规则和日志路径，Runner 复用同一个 Store。
// Store 保存持久配置与规则来源/投影；Runner 和 TUNRuntimeConfigBuilder 派生临时运行配置。
// 设置入口与公共布局见 MainWindow/MainWindowController+Settings.swift；
// MainWindow/MainWindowController+CoreSettings.swift 管理 Core 更新、安装与导入；
// MainWindow/MainWindowController+TUNService.swift 管理 TUN 服务设置、启动校验、唤醒与心跳；
// MainWindow/MainWindowController+Appearance.swift 管理配色、主题与状态栏图标样式。
// 窗口固定尺寸与全屏边界见 MainWindow/ConsoleWindowDelegate.swift、MainWindow/FixedSidebarLayout.swift；
// 首页卡片布局见 Views/HomeDashboardLayout.swift，规则列宽见 MainWindow/RuleTableLayout.swift。
// 规则页面呈现与缓存见 MainWindow/MainWindowController+Rules.swift；单条规则弹窗、选择器和
// 添加/编辑回调见 MainWindow/MainWindowController+RuleEditor.swift；规则集文件与应用回滚见
// MainWindow/MainWindowController+RuleSets.swift。Core/RuleConfigProjector.swift 用显式订阅快照
// 和独立规则来源重建配置，返回待保存的投影；Store 负责持久化，运行重载仍走控制器/协调器。
// 订阅导入刷新见 MainWindow/MainWindowController+Subscriptions.swift，节点与模式见
// MainWindow/MainWindowController+Nodes.swift；连接、日志和应用更新分别见
// MainWindow/MainWindowController+Connections.swift、MainWindow/MainWindowController+Logs.swift、
// MainWindow/MainWindowController+AppUpdate.swift。

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
