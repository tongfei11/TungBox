# TungBox 功能待办（sing-box 特性覆盖）

> 盘点日期：2026-06-24 · 基线版本 0.2.0(0121)
> 说明：每条写清楚「这个功能在 sing-box 里具体控制什么」，方便后续决定做不做、怎么做。
> 状态标记：✅ 已支持 / 🟡 部分支持 / ❌ 未支持 / 🚧 进行中

---

## 1. 协议解析（订阅）

当前订阅解析（`SubscriptionFormatParser` + Clash YAML）支持：

| 协议 | 状态 | 备注 |
|---|---|---|
| Shadowsocks (ss) | ✅ | method + password |
| VMess | ✅ | uuid + alterId + cipher |
| VLess | ✅ | uuid + flow |
| Trojan | ✅ | password |
| Hysteria2 (hy2) | ✅ | password + **obfs/salamander 混淆** + up/down 带宽 |
| TUIC | ✅ | uuid + password |
| SOCKS / SOCKS5 | ✅ | username + password |
| HTTP | ✅ | username + password |
| **Hysteria v1** | ❌ | 老版 hysteria，链接/字段与 hy2 不同（auth_str、协议字段差异） |
| **Naive** | ❌ | naïveproxy（基于 HTTP/2 CONNECT），需要 `type: naive` 映射 |
| **Mieru** | ❌ | mieru 协议（multiplexing + 抗探测），sing-box 1.11+ 支持 |
| **AnyTLS** | ❌ | **订阅里已出现但被静默丢弃**（`default: return nil`），sing-box 1.12+ 支持，需加 `type: anytls` 映射 |

**待办**：补 Hysteria v1 / Naive / Mieru / AnyTLS 的解析映射（截图里要的这几个）。
- 优先 **AnyTLS**（用户订阅里已有，现在直接丢节点，体验最差）。
- 传输层当前支持：ws / h2(http) / grpc；**缺 httpupgrade、quic**（可顺带补）。

---

## 2. DNS 设置（重要，需先理解每项）

> 现在 DNS 是「全自动、写死」的（TUN 用 FakeIP 198.18.0.2 + `ipv4_only` 策略），UI 不可调。
> 下面解释 sing-box 每个 DNS 选项**具体控制什么**，再决定哪些放进 UI。

| 选项 | 控制什么 | 建议 |
|---|---|---|
| **上游 DNS 服务器** (`dns.servers`) | 用哪个 DNS 解析域名。可填 `223.5.5.5`(国内)、`8.8.8.8`、`tls://1.1.1.1`(DoT)、`https://dns.google/dns-query`(DoH)。每个服务器可指定走直连还是走代理(`detour`) | UI 给「国内 DNS / 国外 DNS」两个输入框，支持 udp/tls/https |
| **DNS 策略** (`dns.strategy`) | 解析时优先返回哪种地址：<br>• `prefer_ipv4` 优先 IPv4<br>• `prefer_ipv6` 优先 IPv6<br>• `ipv4_only` 只用 IPv4（**当前默认**，避免无 IPv6 出口时卡顿）<br>• `ipv6_only` 只用 IPv6 | UI 做下拉，默认 ipv4_only |
| **FakeIP** (`dns.fakeip` + 路由 fake-ip) | 给域名分配假 IP(198.18.x.x)，让 TUN 按「域名」分流而不是先真解析。**好处**：少一次 DNS 往返、规避 DNS 污染、规则按域名精确匹配。**代价**：需要 cache_file、某些直连软件会困惑 | UI 给开关（默认开），关掉则用真实解析 |
| **DNS 分流规则** (`dns.rules`) | 不同域名走不同 DNS。典型：国内域名→国内 DNS(直连)，国外域名→代理 DNS(防污染)。和路由规则的 geosite 对应 | 进阶，初版可跟随「出站模式」自动生成 |
| **默认 DNS** (`dns.final`) | 没命中任何 DNS 规则时用哪个 | 跟上游设置走 |
| **缓存** (`independent_cache` / `disable_cache`) | DNS 结果缓存策略 | 一般默认即可，可不暴露 |
| **client_subnet (EDNS)** | 携带客户端子网给上游，CDN 就近解析 | 进阶，可不做 |

**待办**：做一个「DNS 设置」面板 = 国内/国外上游 + 策略下拉 + FakeIP 开关。规则级分流先自动。

---

## 3. TUN 高级选项（要支持，需先理解）

> 现在 TUN 配置写死（auto_route + auto_detect_interface + 物理出口绑定 + ipv4_only）。
> 下面解释每个选项**控制什么**。

| 选项 | 控制什么 | 建议 |
|---|---|---|
| **协议栈** (`stack`) | TUN 流量用哪种网络栈处理：<br>• `system` 用系统栈，**最快**，但个别环境兼容性问题<br>• `gvisor` 用户态栈，**兼容性最好**、更隔离，略慢<br>• `mixed` TCP 走 system、UDP 走 gvisor（折中） | UI 下拉，默认 gvisor 或 mixed（稳） |
| **MTU** (`mtu`) | TUN 网卡的 MTU。默认 9000（大包，吞吐高）。某些网络要降到 1500 防分片丢包 | UI 数字输入，默认 9000，提示「卡顿可试 1500」 |
| **严格路由** (`strict_route`) | 开启后用更强的路由/防火墙规则确保流量不漏出 TUN（防泄漏）。**代价**：可能影响局域网访问、个别 VPN 共存 | UI 开关，默认关（macOS 上 auto_route 已够） |
| **自动路由** (`auto_route`) | 自动改路由表把全局流量导入 TUN。**当前已开**，关掉 TUN 就只是个空壳网卡 | 一般不暴露（核心机制） |
| **endpoint_independent_nat** | UDP 的 NAT 行为。开启对部分游戏/P2P/语音更友好 | UI 开关，进阶 |
| **路由排除** (`route_exclude_address` / `route.rules`) | 哪些 CIDR / 进程不走 TUN（如公司内网、特定 App 直连） | 和「按进程分流」「自定义规则」合并考虑 |
| **TUN 网卡地址** (`inet4_address`) | utun 的虚拟 IP（当前 198.19.0.1） | 一般不暴露 |

**待办**：「TUN 设置」里加 协议栈下拉 + MTU 输入 + 严格路由开关 + EIN 开关。

---

## 4. TLS / 传输 高级（重要）

| 功能 | 状态 | 控制什么 / 待办 |
|---|---|---|
| **uTLS 指纹** (`tls.utls.fingerprint`) | 🟡 解析已支持 | 伪装 TLS ClientHello 指纹（chrome/firefox/safari/randomized…）绕过指纹封锁。**待办**：UI 里能查看/手动选择指纹（现在只能跟订阅） |
| **Reality** (`tls.reality`) | 🟡 解析已支持 | public_key + short_id 的抗审查 TLS。**待办**：UI 展示/校验，必要时手动填 |
| **ECH** (`tls.ech`) | ❌ | Encrypted Client Hello，加密 SNI 防 SNI 封锁。**待办**：解析 + UI 开关（config 字段 `ech.enabled` + `ech.config`） |
| **hy2 混淆 (salamander)** | ✅ | 已保留 `obfs.type=salamander` + `obfs-password`，无需额外做 |
| **允许不安全证书** (`tls.insecure`) | ✅ 解析支持 | skip-cert-verify。可在 UI 给个全局/单节点开关（谨慎） |

---

## 5. 入站 / 本地代理（高价值，竞品标配）

| 功能 | 状态 | 控制什么 / 待办 |
|---|---|---|
| **本地端口可配** | ❌（写死 7890） | 混合代理监听端口。**待办**：设置加端口输入框（改 `TungBoxConfig.mixedPort` → 用户可配，校验占用） |
| **局域网共享 (Allow LAN)** | ❌ | 把 `listen` 从 `127.0.0.1` 改成 `0.0.0.0`，让同网段手机/电视走本机代理。**待办**：开关 + 显示本机局域网 IP + 防火墙提示 |
| **入站认证** | ❌ | 本地代理加 用户名/密码（`users`），防同网段他人乱用。**待办**：可选，配合 Allow LAN |
| **独立 SOCKS/HTTP 端口** | ❌（只有 mixed） | 有些 App 只认 SOCKS 或只认 HTTP。mixed 已同时支持两者，一般够用 | 低优先 |

---

## 6. 节点 / 测速

| 功能 | 状态 | 控制什么 / 待办 |
|---|---|---|
| 延迟测试 + 自定义测速 URL | ✅ | 已支持 |
| 延迟颜色阈值 | ✅ | <400 绿 / <800 橙 / ≥800 红（0121 已统一） |
| **自动测速间隔/容差** (`urltest.interval` / `tolerance`) | ❌ | 自动选择组多久测一次、切换的延迟容差。**待办**：URLTest 组可配 interval/tolerance |
| **自动选择策略** | 🟡 | 已有 urltest/fallback 组，可考虑 UI 暴露 fallback |

---

## 7. 路由 / 分流

| 功能 | 状态 | 控制什么 / 待办 |
|---|---|---|
| 自定义规则（domain/ip_cidr/port/rule_set/regex/DNS模式） | ✅ | 已支持增删改 |
| 规则集（geosite/geoip URL + 缓存） | ✅ | 已支持 |
| **按进程分流** (`process_name` / `process_path`) | 🚧 用户在分支上做 | 按 App 进程名走代理/直连。macOS 很实用 |
| **链式出站** (`detour` / dialer 链) | ❌ | 一个出站经过另一个出站（前置代理）。进阶少用 | 未来 |

---

## 8. 其他（未来迭代）

| 功能 | 控制什么 |
|---|---|
| **Multiplex (mux / brutal)** | 多路复用，减少握手、brutal 拥塞控制提速。`outbound.multiplex` |
| **NTP 服务** | sing-box 内置 NTP 校时（hy2/tuic 对时间敏感时有用） |
| **配置导入/导出 / 多配置管理** | profiles 已有基础，可做更完整的多配置 UI |
| **TUN-only 模式统计** | 解耦后守护进程 clash_api 在 9091，GUI 目前查 9090；TUN-only 时统计不显示，需让 GUI 在 TUN-only 时查 9091 |
| **clash_api 密钥/外部访问** | secret + 外部控制器（接 Yacd/Dashboard） |

---

## 优先级建议（个人排序，待确认）

1. **AnyTLS 解析**（订阅里已有、现在直接丢节点）→ 顺带 Naive/Mieru/Hysteria v1
2. **DNS 设置面板**（上游 + 策略 + FakeIP 开关）
3. **本地端口可配 + 局域网共享**
4. **TUN 高级**（stack + MTU + strict_route）
5. **ECH + uTLS/Reality 的 UI**
6. 自动测速间隔/容差、Multiplex 等
