# TungBox 功能待办（sing-box 特性覆盖）

> 盘点日期：2026-06-26 · 基线版本 **0.2.1(0156)**
> 说明：每条写清楚「这个功能在 sing-box 里具体控制什么」，方便后续决定做不做、怎么做。
> 状态标记：✅ 已支持 / 🟡 部分支持 / ❌ 未支持 / 🚧 进行中
> 大项标记：每个一级章节标题后跟整体状态，反映该章节核心待办的完成度。

---

## 1. 协议解析（订阅） ✅

| 协议 | 状态 | 备注 |
|---|---|---|
| Shadowsocks (ss) | ✅ | method + password |
| VMess | ✅ | uuid + alterId + cipher |
| VLess | ✅ | uuid + flow + **packet_encoding(xudp)** [0122] |
| Trojan | ✅ | password |
| Hysteria2 (hy2) | ✅ | password + **obfs/salamander 混淆** + up/down 带宽 |
| TUIC | ✅ | uuid + password + **alpn(默认h3) + congestion_control + udp_relay_mode** [0122] |
| SOCKS / SOCKS5 | ✅ | username + password（socks5→socks 修正）[0122] |
| HTTP | ✅ | username + password |
| Hysteria v1 | ✅ [0122] | auth_str + 字符串 obfs + 整数 mbps |
| Naive | ✅ [0122] | username + password + 强制 TLS |
| AnyTLS | ✅ [0122] | password + 强制 TLS（padding 由服务端协商） |
| **Mieru** | ❌ 内核不支持 | sing-box 没有 mieru outbound，跑不了 |
| **xhttp 传输** | ❌ 内核不支持 | Xray 专有，sing-box 不实现 |

**传输层**：tcp / ws / grpc / h2(http) / **httpupgrade** [0123] · 嵌套 *-opts 解析（ws-opts/grpc-opts/h2-opts/httpupgrade-opts/reality-opts/ech-opts）
**TLS**：enabled / SNI / insecure / **ALPN（数组+逗号串+带括号）** / uTLS / Reality / **ECH** [0123]
**Multiplex**：smux → multiplex [0123]，仅 vmess/vless/trojan/ss，含 protocol/streams/padding/brutal
**YAML 解析器**：手写零依赖 YAML 子集解析器 [0123]，支持嵌套块映射/序列/flow/带逗号引号标量，已用 8 节点混合 fixture 通过 `sing-box check`

**信息伪节点过滤** [0133]：默认开启，匹配「剩余流量/套餐/到期/官网/客服群/expire/traffic」等关键词的节点自动跳过。
**UA 回退拉订阅** [0132]：sing-box / clash-verge / ClashMeta / Clash 四个 UA 依次试，挑第一个能解析到节点的版本（机场后端按 UA 返回不同内容）。
**订阅 metadata** [0133]：解析响应头 `subscription-userinfo` → 卡片显示流量已用/总量、到期日期。

**导入跳过节点提示** [0150]：Clash YAML 转换时按 raw type 计数跳过节点（mieru/xhttp/未知 type 等），导入/刷新订阅完成后在日志和 Toast 显示「X 个节点协议不支持已跳过（mieru 2, xhttp 1）」。覆盖订阅刷新 / 文件导入 / 剪贴板导入三个入口。

---

## 2. DNS 设置 ✅

> 设置 → DNS：国内/国外上游 + 策略 + Fake-IP（开关 / 网段 / 跳过域名）。改动落 `UserDefaults`，下次刷新订阅或重启代理时由 `DNSConfig.buildSingBoxDNS()` 拼进新配置。

| 选项 | 状态 | 备注 |
|---|---|---|
| **国内 DNS 上游** | ✅ [0151] | 默认 `223.5.5.5`，接收裸 IP/host 或 `udp/tcp/tls/https/quic/h3` 前缀 |
| **国外 DNS 上游** | ✅ [0151] | 默认 `https://1.1.1.1/dns-query`，自动 `detour: 节点选择` |
| **DNS 策略** | ✅ [0151] | 仅 IPv4(默认) / 仅 IPv6 / 偏好 v4 / 偏好 v6；写进 `dns.strategy` |
| **Fake-IP 开关** | ✅ [0151] | 默认**开**，加 `dns.servers[type=fakeip]` + 顶层 `dns.fakeip` + `independent_cache` |
| **Fake-IP 网段** | ✅ 高级 | 默认 `198.18.0.0/15`，跟 TUN 端 `198.18.0.2` OS resolver 共存（sing-box 不会重复分配） |
| **Fake-IP 跳过域名** | ✅ 高级 | 多行文本框，默认 lan/local/arpa/ntp/msftncsi 等；走 `domain_suffix` → dns-local |
| **重置为默认值** | ✅ [0151] | 一键回滚所有 DNS 字段 |
| **即时保存 + 热重启** | ✅ [0152] | 每个控件失焦/变更后保存到 `UserDefaults`，500ms 防抖后 patch 当前 profile 的 `dns` 段；代理运行时自动 `reconcileRuntime(forceRestart: true)` |
| **分流规则** | 隐式 | 跟 `basicDNS` 一致：`geosite-cn/private→dns-local`、`geolocation-!cn→dns-fakeip/dns-proxy` |
| **bootstrap / 节点域名 / 直连域名 DNS** | 隐式 | 跟着国内上游自动配，UI 不暴露 |
| **fallback + GeoIP/CIDR/Domain 过滤** | ❌ 不做 | Clash 历史包袱，sing-box 用 rule_set 分流更干净 |
| **/etc/hosts 读取** | ✅ [0152] | 开关：开启时 `DNSConfig.collectHostsEntries()` 读 `/etc/hosts` 并拼成 `type:"hosts"` server，按域名精确匹配，未命中走后续规则 |
| **自定义 hosts 表** | ✅ [0152] | 多行文本框，格式 `域名=IP[;IP2]`；自定义条目覆盖同名系统 hosts 条目 |
| **DNS 缓存** / **client_subnet** | ❌ 不暴露 | 进阶，无明显收益 |

**TUN 端改动** [0151]：删掉 `applyTunRuntimeRouteExclusions` 里硬写 `strategy = "ipv4_only"` 的那段（[main.swift:1815](Sources/TungBox/main.swift:1815)），改成尊重用户设置 + 仅在日志里输出当前策略。

---

## 3. TUN 高级选项 ✅

> 设置 → TUN 设置：原「服务管理」面板下面新增「协议栈 / 网络参数 / 路由排除 / 高级」四个 panel + 重置。改动落 `UserDefaults`，500ms 防抖；TUN 开启时 `reconcileRuntime(forceRestart: true)` → daemon 通过 `tunRequestConfigURL` 文件比对（`REQUEST_CONFIG -nt CONFIG`）1-2s 内热重载 sing-box 子进程，免 sudo。

| 选项 | 状态 | 备注 |
|---|---|---|
| **协议栈** (`stack`) | ✅ [0155] | 下拉：System / GVisor / Mixed(默认) |
| **MTU** (`mtu`) | ✅ [0155] | 数字输入，默认 9000（hint「卡顿可改 1500」），校验 576-65535 |
| **严格路由** (`strict_route`) | ✅ [0155] | checkbox，默认关 |
| **端点独立 NAT** (`endpoint_independent_nat`) | ✅ [0155] 高级 | checkbox，默认关（P2P/游戏/语音才需要） |
| **路由排除** (`route_exclude_address`) | ✅ [0155] | 多行 CIDR 文本框，预填 9 段私有 + 链路本地 + 回环 |
| **包含/排除接口** (`include/exclude_interface`) | ✅ [0155] 高级 | 单行逗号分隔，多网卡场景用 |
| **DNS 劫持** | 隐式 | 路由规则里硬编码 `protocol: dns, action: hijack-dns`，不暴露 |
| **设备名称** (`interface_name`) | ❌ 不暴露 | 固定 utun29/utun99，改了和 daemon 冲突 |
| **白名单路由 (Fake-IP 旁路)** | ❌ 不做 | 跟 auto_route 哲学相反 |
| **UDP 超时 / 自动路由 / 自动检测出口** | ❌ 不暴露 | 默认值已最佳，关掉 TUN 会废 |
| **mihomo 私有：RecvMsgX / 禁用 ICMP** | ❌ | sing-box 无对应字段 |
| **重置为默认值** | ✅ [0155] | |

**daemon 热重载**：B 路径已验证可行。[TunServiceManager.swift:969](Sources/TungBox/Services/TunServiceManager.swift:969) 的 daemon polling 已经在比对 `REQUEST_CONFIG -nt CONFIG`；[reloadTunConfigInPlace](Sources/TungBox/MainWindow/MainWindowController+Settings.swift:986) 已经是 helper。TUN 设置改动复用现成 `reconcileRuntime(forceRestart: true)` → `enableTunServiceSafely` → `TunServiceManager.enable` 链路，免 sudo。

---

## 4. TLS / 传输 高级（透传，无需 UI） ✅

uTLS 指纹 / Reality / ECH / hy2 salamander 混淆 / insecure / httpupgrade / Multiplex 都是**节点级字段，由服务端决定是否启用**（Reality 必须服务端配对 short_id+public_key；ECH 必须服务端发布 config；uTLS 仅客户端指纹）。订阅把字段下发，TungBox 解析后透传 sing-box 即可 —— **不需要任何 UI 开关**。全部已支持解析 [0122-0123]。

---

## 5. 入站 / 本地代理 ❌

| 功能 | 状态 | 控制什么 / 待办 |
|---|---|---|
| **本地端口可配** | ❌（写死 7890） | UI 加端口输入框（校验占用） |
| **局域网共享 (Allow LAN)** | ❌ | `listen: 0.0.0.0` 让手机/电视走本机代理。UI 开关 + 显示本机 IP + 防火墙提示 |
| **入站认证** | ❌ | 本地代理加用户名/密码（`users`），配合 Allow LAN |
| **独立 SOCKS/HTTP 端口** | ❌ | mixed 已含两者，低优先 |

---

## 6. 节点 / 测速 ✅

| 功能 | 状态 | 备注 |
|---|---|---|
| 延迟测试 + 自定义测速 URL | ✅ | |
| 延迟颜色阈值 | ✅ [0121] | <400 绿 / <800 橙 / ≥800 红 |
| **测速性能优化** | ✅ [0125] | preprocessTestConfig 隔离单 outbound，冷启动从 30+ outbound 降到 1 个 |
| **TCP 直拨测速** | ✅ [0129] | 关代理时用 NWConnection 直接拨 server:port，几十 ms 完成（接近 NekoBox 速度）；hy2/tuic UDP-only 回退 sing-box fetch |
| **并发测速** | ✅ [0129] | testGroupNodes/testAllNodesClicked 改用 TaskGroup 并发 |
| **测试入口护栏** | ✅ [0126] | 过渡中（切订阅 / 启停代理）禁止测速，避免混合状态 |
| **TUN-only 测速修复** | ✅ [0149] | ClashAPI.delay 加 `port` 参数；仅 TUN 跑时路由到 9091（守护进程），避免打 9090（已停的用户代理）导致全部失败 |
| **自动测速间隔/容差** (`urltest.interval` / `tolerance`) | ✅ [0150] | 设置 → 常规 → 自动测速：间隔（1/3/5/10/30 分钟）+ 容差（0/30/50/100/150/300 ms）。`UserDefaults` 持久化，下次刷新订阅时写进 urltest outbound |
| **fallback 自动选择策略** | ✅ [0150] | sing-box 没有独立 `fallback` outbound（Clash 专有），其 fallback-on-failure 语义由 `urltest` 内置：当前节点失败→自动切到下一个可用最快节点；通过 interval+tolerance 调度，UI 已暴露 |

---

## 7. 路由 / 分流 🟡

| 功能 | 状态 | 备注 |
|---|---|---|
| 自定义规则（domain/ip_cidr/port/rule_set/regex/DNS模式） | ✅ | 增删改 |
| 规则集（geosite/geoip URL + 缓存） | ✅ | |
| **按进程分流** (`process_name` / `process_path`) | 🚧 用户在分支上做 | macOS 很实用，确定要做。待合主线 + 接进规则 UI |

> 「链式出站」已转入未来迭代（见第 10 节）。

---

## 8. 流量 / 统计 / 连接 ✅

| 功能 | 状态 | 备注 |
|---|---|---|
| 流量持久化（按日聚合 / 7 / 30 天）| ✅ | UserDefaults `tungbox_traffic_history` |
| **TUN-only 模式流量** | ✅ [0142] | 解耦后守护进程 clash_api 在 9091，统计同时拉 9090+9091 |
| **UDP / IPv6 / 短连接流量** | ✅ [0143] | 改用 sing-box 进程级 `uploadTotal`/`downloadTotal`，自动涵盖 QUIC/IPv6/已关闭短流（YouTube 漏算的真因） |
| 活动连接表 | ✅ | clash API /connections，按 9090+9091 合并去重 |
| **连接关闭操作** | ✅ | 单个/全部 closeConnections |

> 「clash_api 密钥 / 外部访问」已转入未来迭代（见第 10 节）。

---

## 9. UI / 体验（已完成的里程碑） ✅

- ✅ **解耦架构** [0119]：TUN 守护进程（utun29 + 9091）与用户代理（7890 + 9090）分进程独立，开关瞬时切换、互不冲突
- ✅ **Toast 通知系统** [0127-0128]：右上角 MD3 卡片，4 种风格，覆盖测速完成/订阅更新/开关/出站模式/小动作（保存/清空日志/规则操作/规则集刷新/主题切换）
- ✅ **订阅卡片重做** [0133-0141]：仿 Clash Verge，左站点名+域名+流量进度条，右刷新按钮（带自转动画）+ 上次刷新+到期；4 卡 2 列网格；intercellSpacing 横向清零对齐
- ✅ **首页节点延迟显示** [0131]：「(自动)」改成绿色 chip；延迟数字 compressionResistance required 不截断；空 name 时显示「(选择中…)」占位
- ✅ **极简悬浮滚动条** [0141]：MD3ThinScroller 7pt 宽（系统一半），无底色占位，autohides + overlay
- ✅ **灰底 #ECECEC** [0141]：MD3TightLabelCell 让 NSTextField 大字号字符紧贴 frame.x 与卡片对齐
- ✅ **切订阅原子流程** [0126]：transitioning 锁 + 关旧 connections + reconcileRuntime(forceRestart)；刷新订阅 A 不再切走当前用的订阅 B [0138]
- ✅ **托盘菜单与首页一致** [0149]：去掉"代理服务 + 接管方式(互斥单选)"，改成"系统代理 / TUN 模式"两个独立 checkbox，状态/动作与首页两个开关完全对齐
- ✅ **更新弹窗 Markdown 渲染** [0149]：自带 MarkdownParser 把 release notes 渲染成主题化 HTML（标题/列表/表格/代码/链接）

---

## 10. 其他（未来迭代） ❌

| 功能 | 控制什么 |
|---|---|
| **NTP 服务** | sing-box 内置 NTP 校时（hy2/tuic 对时间敏感时有用） |
| **配置导入/导出 / 多配置管理** | profiles 已有基础，可做更完整的多配置 UI |
| **clash_api secret / 外部访问** | secret + 外部控制器（接 Yacd/Razord/Dashboard 等第三方面板） |
| **链式出站** (`detour` / dialer 链) | 一个出站经过另一个（前置代理），进阶且少用 |

---

## 优先级建议

1. **本地端口可配 + 局域网共享**（高频，竞品标配）
2. **TUN 高级**（stack + MTU + strict_route + EIN）
3. **DNS 设置面板**（上游 + 策略 + FakeIP 开关）
4. **clash secret / 外部访问**（接 Yacd/Razord 等第三方面板）
