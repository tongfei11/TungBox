# TungBox 功能待办（sing-box 特性覆盖）

> 盘点日期：2026-06-25 · 基线版本 **0.2.0(0143)**
> 说明：每条写清楚「这个功能在 sing-box 里具体控制什么」，方便后续决定做不做、怎么做。
> 状态标记：✅ 已支持 / 🟡 部分支持 / ❌ 未支持 / 🚧 进行中

---

## 1. 协议解析（订阅）

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

**待办**：导入时提示「X 个节点协议不支持已跳过」（mieru/xhttp 当前静默丢，把丢弃计数传到导入 UI）。

---

## 2. DNS 设置

> 现状：DNS 全自动写死（TUN 用 FakeIP 198.18.0.2 + `ipv4_only`），UI 不可调。

| 选项 | 控制什么 | 建议 |
|---|---|---|
| **上游 DNS 服务器** (`dns.servers`) | `223.5.5.5` / `tls://1.1.1.1` (DoT) / `https://dns.google/dns-query` (DoH)，可指定 detour | UI「国内 DNS / 国外 DNS」两个输入框 |
| **DNS 策略** (`dns.strategy`) | `prefer_ipv4` / `prefer_ipv6` / `ipv4_only`（默认）/ `ipv6_only` | UI 下拉 |
| **FakeIP** (`dns.fakeip` + 路由 fake-ip) | 给域名分配假 IP(198.18.x.x) 让 TUN 按域名分流，省一次 DNS 往返 + 防污染 | UI 开关，默认开 |
| **DNS 分流规则** (`dns.rules`) | 国内域名→国内 DNS 直连，国外→代理 DNS 防污染 | 初版跟「出站模式」自动生成 |
| **默认 DNS** (`dns.final`) | 没命中规则时用哪个 | 跟上游设置 |
| **缓存** / **client_subnet** | DNS 缓存策略 / CDN 就近解析 | 进阶，不暴露 |

**待办**：做「DNS 设置」面板 = 国内/国外上游 + 策略下拉 + FakeIP 开关。

---

## 3. TUN 高级选项

> 现状：TUN 配置写死（auto_route + auto_detect_interface + 物理出口绑定 + ipv4_only）。

| 选项 | 控制什么 | 建议 |
|---|---|---|
| **协议栈** (`stack`) | `system` 最快但兼容性弱 / `gvisor` 兼容最好略慢 / `mixed` 折中 | UI 下拉，默认 mixed |
| **MTU** (`mtu`) | 默认 9000（高吞吐）；某些网络要 1500 防分片丢包 | UI 数字输入，提示「卡顿可试 1500」 |
| **严格路由** (`strict_route`) | 强路由防泄漏，代价：可能影响局域网/VPN 共存 | UI 开关，默认关 |
| **endpoint_independent_nat** | UDP NAT 行为，对游戏/P2P/语音友好 | UI 开关，进阶 |
| **路由排除** | 哪些 CIDR / 进程不走 TUN | 和「按进程分流」合并 |
| `auto_route` / `inet4_address` | 核心机制 / utun 虚拟 IP | 一般不暴露 |

**待办**：「TUN 设置」加 协议栈下拉 + MTU 输入 + 严格路由开关 + EIN 开关。

---

## 4. TLS / 传输 高级

| 功能 | 状态 | 备注 |
|---|---|---|
| **uTLS 指纹** (`tls.utls.fingerprint`) | 🟡 解析已支持 | 跟订阅；**UI 手动选择仍待办** |
| **Reality** (`tls.reality`) | 🟡 解析已支持 | public_key + short_id；**UI 展示/校验仍待办** |
| **ECH** (`tls.ech`) | ✅ [0123] 解析支持 | 跟订阅 ech-opts；UI 单独开关仍待办 |
| **hy2 混淆 (salamander)** | ✅ | obfs.type + obfs-password |
| **允许不安全证书** (`tls.insecure`) | ✅ 解析支持 | skip-cert-verify；可考虑 UI 全局开关 |
| **httpupgrade 传输** | ✅ [0123] | 嵌套 httpupgrade-opts |
| **Multiplex** (smux/brutal) | ✅ [0123] | 仅 TCP 协议生效 |

**待办**：uTLS 指纹 / Reality / ECH 各自的 UI 配置面板（让用户手动开关 + 填字段），不只是跟订阅。

---

## 5. 入站 / 本地代理

| 功能 | 状态 | 控制什么 / 待办 |
|---|---|---|
| **本地端口可配** | ❌（写死 7890） | UI 加端口输入框（校验占用） |
| **局域网共享 (Allow LAN)** | ❌ | `listen: 0.0.0.0` 让手机/电视走本机代理。UI 开关 + 显示本机 IP + 防火墙提示 |
| **入站认证** | ❌ | 本地代理加用户名/密码（`users`），配合 Allow LAN |
| **独立 SOCKS/HTTP 端口** | ❌ | mixed 已含两者，低优先 |

---

## 6. 节点 / 测速

| 功能 | 状态 | 备注 |
|---|---|---|
| 延迟测试 + 自定义测速 URL | ✅ | |
| 延迟颜色阈值 | ✅ [0121] | <400 绿 / <800 橙 / ≥800 红 |
| **测速性能优化** | ✅ [0125] | preprocessTestConfig 隔离单 outbound，冷启动从 30+ outbound 降到 1 个 |
| **TCP 直拨测速** | ✅ [0129] | 关代理时用 NWConnection 直接拨 server:port，几十 ms 完成（接近 NekoBox 速度）；hy2/tuic UDP-only 回退 sing-box fetch |
| **并发测速** | ✅ [0129] | testGroupNodes/testAllNodesClicked 改用 TaskGroup 并发 |
| **测试入口护栏** | ✅ [0126] | 过渡中（切订阅 / 启停代理）禁止测速，避免混合状态 |
| **自动测速间隔/容差** (`urltest.interval` / `tolerance`) | ❌ | URLTest 组多久测一次、切换的延迟容差，可 UI 配 |
| **fallback 自动选择策略** | 🟡 | 已有 urltest/fallback 组，可考虑 UI 暴露 |

---

## 7. 路由 / 分流

| 功能 | 状态 | 备注 |
|---|---|---|
| 自定义规则（domain/ip_cidr/port/rule_set/regex/DNS模式） | ✅ | 增删改 |
| 规则集（geosite/geoip URL + 缓存） | ✅ | |
| **按进程分流** (`process_name` / `process_path`) | 🚧 用户在分支上做 | macOS 很实用 |
| **链式出站** (`detour` / dialer 链) | ❌ | 一个出站经过另一个（前置代理）。进阶少用 |

---

## 8. 流量 / 统计 / 连接

| 功能 | 状态 | 备注 |
|---|---|---|
| 流量持久化（按日聚合 / 7 / 30 天）| ✅ | UserDefaults `tungbox_traffic_history` |
| **TUN-only 模式流量** | ✅ [0142] | 解耦后守护进程 clash_api 在 9091，统计同时拉 9090+9091 |
| **UDP / IPv6 / 短连接流量** | ✅ [0143] | 改用 sing-box 进程级 `uploadTotal`/`downloadTotal`，自动涵盖 QUIC/IPv6/已关闭短流（YouTube 漏算的真因） |
| 活动连接表 | ✅ | clash API /connections，按 9090+9091 合并去重 |
| **连接关闭操作** | ✅ | 单个/全部 closeConnections |
| **clash_api 密钥 / 外部访问** | ❌ | secret + 外部控制器（接 Yacd/Dashboard） |

---

## 9. UI / 体验（已完成的里程碑）

- ✅ **解耦架构** [0119]：TUN 守护进程（utun29 + 9091）与用户代理（7890 + 9090）分进程独立，开关瞬时切换、互不冲突
- ✅ **Toast 通知系统** [0127-0128]：右上角 MD3 卡片，4 种风格，覆盖测速完成/订阅更新/开关/出站模式/小动作（保存/清空日志/规则操作/规则集刷新/主题切换）
- ✅ **订阅卡片重做** [0133-0141]：仿 Clash Verge，左站点名+域名+流量进度条，右刷新按钮（带自转动画）+ 上次刷新+到期；4 卡 2 列网格；intercellSpacing 横向清零对齐
- ✅ **首页节点延迟显示** [0131]：「(自动)」改成绿色 chip；延迟数字 compressionResistance required 不截断；空 name 时显示「(选择中…)」占位
- ✅ **极简悬浮滚动条** [0141]：MD3ThinScroller 7pt 宽（系统一半），无底色占位，autohides + overlay
- ✅ **灰底 #ECECEC** [0141]：MD3TightLabelCell 让 NSTextField 大字号字符紧贴 frame.x 与卡片对齐
- ✅ **切订阅原子流程** [0126]：transitioning 锁 + 关旧 connections + reconcileRuntime(forceRestart)；刷新订阅 A 不再切走当前用的订阅 B [0138]

---

## 10. 其他（未来迭代）

| 功能 | 控制什么 |
|---|---|
| **NTP 服务** | sing-box 内置 NTP 校时（hy2/tuic 对时间敏感时有用） |
| **配置导入/导出 / 多配置管理** | profiles 已有基础，可做更完整的多配置 UI |
| **clash_api secret** | 外部访问 dashboard（Yacd/Razord） |
| **导入时跳过节点提示** | mieru/xhttp/不合法节点 被丢弃，UI 显示「X 个节点协议不支持已跳过」 |

---

## 优先级建议

1. **本地端口可配 + 局域网共享**（高频，竞品标配）
2. **TUN 高级**（stack + MTU + strict_route + EIN）
3. **DNS 设置面板**（上游 + 策略 + FakeIP 开关）
4. **uTLS / Reality / ECH UI**（让用户能手动开关 + 填字段）
5. **自动测速 interval/tolerance** + fallback UI
6. **导入跳过节点提示** + clash secret 外部访问
