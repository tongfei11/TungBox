# TungBox

当前版本：`0.1.0(0035)`

TungBox 是一个面向 macOS 的 sing-box 图形客户端。当前阶段的目标是先完成日常可用的代理、订阅、规则、节点、TUN 和 Core 管理能力，再进入正式打包发布。

## 当前已完成

- 首页仪表盘：系统代理开关、TUN 开关、出站模式切换、当前节点、实时上传/下载、连接数和流量统计入口。
- 左侧一级菜单：首页、节点、规则、订阅、连接、日志、设置。
- 订阅功能：支持添加、编辑、删除、刷新订阅，并基于订阅生成托管 sing-box 配置。
- 默认规则配置：支持规则、全局、直连三种模式，并生成基础分流规则。
- 自定义规则：支持按订阅单独保存自定义规则，刷新订阅后自动合并。
- 规则展示：支持规则列表、搜索、规则集内容展开、右键删除自定义规则。
- 节点页面：支持代理分组展示、节点切换、URLTest 延迟测试和自动选择最快节点。
- 运行控制：支持启动、停止、配置保存、配置检查、格式化、日志查看。
- Core 管理：支持检测 sing-box Core、导入 Core、安装最新 Core、安装旧版 Core 测试、检查 Core 更新。
- TUN 设置：支持安装/卸载 TUN 服务，首页 TUN 开关只负责启用状态，不再临时弹管理员密码启动。
- 状态栏菜单：支持系统代理、TUN 模式、显示控制台、出站模式、代理组快速切换、打开配置目录和退出。
- 开机自启动与静默启动：设置页已提供开关。
- 工程拆分：主窗口逻辑已从单个 `main.swift` 拆分到 `Sources/TungBox/MainWindow/` 下的多个扩展文件。

## 当前未完成的重要事项

优先级待办已放在 [TODO.md](TODO.md)。发布前重点是：

- Core 随包策略：发布包需要内置 `sing-box` Core，避免用户没有安装 Core 时无法启动。
- 打包与签名：需要生成 `.app`，拷贝资源与 Core，并执行 ad-hoc 签名。
- GitHub Release：需要写清 Gatekeeper 打开方式、TUN 管理员授权、Core 来源和更新方式。
- TUN 全流程回归：安装、卸载、启用、禁用、日志展示、未安装提示都需要再跑一轮。
- 订阅协议覆盖：需要用 Xboard 增加更多协议节点测试，例如 vmess、vless、trojan、shadowsocks、hysteria2、tuic。
- 自动选择稳定性：需要确认 urltest 定时触发后会切到最快节点，并断开旧连接让出口 IP 立即变化。
- 规则命中计数：当前规则列表展示为主，真实命中数还未完整接入。
- 自定义规则增强：后续需要支持编辑、启用/禁用、排序。
- UI 冒烟测试：需要形成最小流程测试，覆盖启动、切页、订阅刷新、节点切换、启动代理、退出。

## 本地运行

开发阶段直接使用 SwiftPM：

```bash
swift run TungBox
```

只构建不启动：

```bash
swift build
```

当前数据目录：

```text
~/Library/Application Support/TungBox
```

订阅信息保存在：

```text
~/Library/Application Support/TungBox/subscriptions.json
```

自定义规则保存在：

```text
~/Library/Application Support/TungBox/custom-rules.json
```

## 版本策略

- 发布版本使用 `x.y.z`，当前第一个发布线为 `0.1.0`。
- 内部构建号使用四位数字，例如 `0.1.0(0035)`。
- 重要功能、结构调整、发布前变更需要同步提交并推送到 GitHub，便于回退和版本管理。

## 发布说明草案

当前计划采用低成本开源分发方式：

- 使用 ad-hoc 签名保证 App bundle 内部结构完整。
- 不使用付费 Apple Developer ID，不做 notarization。
- GitHub Release 中明确说明 Gatekeeper 限制，用户首次打开可能需要手动允许。
- TUN 服务安装需要管理员授权，这是 macOS 网络权限要求，与 ad-hoc 签名方案不冲突。

## 备注

`Sources/TungBox/main.swift.bak` 是本地备份文件，已在 `Package.swift` 中排除，不参与构建。后续稳定后应删除或移出 `Sources` 目录。
