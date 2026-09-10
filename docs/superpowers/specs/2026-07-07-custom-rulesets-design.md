# 自定义规则集（分流方案）设计文档

- 日期：2026-07-07
- 分支：feature/rules-enhancement
- 修订日期：2026-09-10
- 状态：设计已补充，优化待实施。第 15–20 节为修订后的约束，与前文初版冲突时以修订为准。
- 作用范围：本 spec 只覆盖**层级 1（自定义规则集）**。层级 2（自定义代理组）是后续独立子项目，仅在第 13 节概述。

## 1. 背景与目标

用户希望把"一批域名/IP 统一走某个出站"作为一个**可命名、可整体管理**的单元，典型场景「AI 分流」：把 OpenAI / Claude / Gemini 等域名统一指向某个节点（层级 1），未来指向某个"排除香港的自定义组"（层级 2）。

目标：在**规则页**新增"自定义规则集"，一条规则集 = 名称 + 一个出站 + 一份多行规则清单；可整体启用/停用/编辑/删除；按订阅隔离；持久化为 YAML 文件。

## 2. 术语澄清（避免重复造轮子）

- **单条自定义规则**（已存在）：一条 `TYPE + VALUE + 策略`，策略下拉已包含 `DIRECT / REJECT / Proxy(节点选择) / AUTO(自动选择) + 全部单节点`。**指向单个节点现在就支持**，`outboundForStrategy` 的 `default: return strategy` 直接把节点 tag 当出站。
- **自定义规则集**（本 spec，层级 1）：命名的批量规则束，指向**一个**出站；出站候选**复用现有策略下拉**，不新增节点列表。
- **自定义代理组**（层级 2，后续）：urltest/selector 组，成员为按节点名筛选的子集；其 tag 会加入策略下拉，从而被规则集/单规则选为出站。

## 3. 数据模型

```swift
struct RuleSetEntry: Codable, Equatable {   // 一条规则清单里的一行
    var type: String     // 复用现有类型集：DOMAIN / DOMAIN-SUFFIX / IP-CIDR / ...
    var value: String
}

struct CustomRuleSet: Codable, Equatable {
    var id: UUID
    var subscriptionID: UUID
    var name: String            // 规则集名称，如 "AI"
    var outbound: String        // 出站策略/节点 tag（与策略下拉取值一致，如 "自动选择" / "香港01"）
    var rules: [RuleSetEntry]   // 解析后的规则清单（保存时已严格校验通过）
    var enabled: Bool
    var createdAt: Date
}
```

内存中另需一个**加载期的错误记录**（不进 Codable），用于第 7 节的"手改文件容错"：

```swift
struct RuleSetLoadResult {
    var valid: [CustomRuleSet]
    var invalid: [(fileURL: URL, name: String, error: String)]   // 供 UI 标错、执行时排除
}
```

## 4. 持久化

### 目录结构

```
~/Library/Application Support/TungBox/
  custom-rulesets/                 # 注意：与已有的 rule-sets/（SRS 缓存）区分
    <subscriptionID-UUID>/         # 每个订阅一个文件夹
      <slug>.yml                   # 每个规则集一个文件；slug 由 name 生成，冲突时追加短 id
```

- 文件夹以 `subscriptionID`（UUID）命名，避免订阅名重名/特殊字符问题。
- 删除订阅时，级联删除其 `custom-rulesets/<id>/` 文件夹。

### 单文件 YAML schema（手写序列化/解析，不引入依赖）

```yaml
id: 6F1C…            # UUID，用于稳定标识
name: AI
outbound: 自动选择
enabled: true
rules:
  - DOMAIN, www.google.com
  - DOMAIN-SUFFIX, openai.com
  - IP-CIDR, 1.2.3.0/24
```

- 写：固定字段顺序，`name`/`outbound` 若含特殊字符则用双引号包裹并转义；`rules` 逐行输出 `- TYPE, VALUE`。
- 读：复用项目既有的"手写行式解析"风格（参考 `SubscriptionFormatParser`）。仅需解析这 5 个固定键，其中 `rules` 复用第 6 节的行解析器。

## 5. 规则清单格式（严格）

每行一条，格式固定：

```
TYPE, VALUE
```

- 前导 `- ` 可有可无（兼容直接从 Clash `rules:` 粘贴）。
- 以 `#` 开头的行为注释，忽略。
- 空行忽略。
- 使用 Clash 风格的简易规则，由本地转换器生成 sing-box 配置；不支持原生配置输入。可转换类型、映射及兼容差异统一维护在 Wiki，范围见第 15 节。
- **不做裸行自动识别**（不写 TYPE 一律视为错误）。
- LAN 行无需 VALUE（`- LAN` 合法）。

## 6. 解析与校验

### 保存时（严格，错误即拦截）

1. 逐行解析 `rulesText`（跳过注释/空行）。
2. 每行校验：TYPE 在支持集内；VALUE 复用现有 `validateRuleValue(type:value:)`。
3. 任一行失败 → **阻止保存**，弹出明确错误："第 N 行「原文」：<原因>"。
4. 名称非空、当前订阅内名称不重复；出站必须是当前策略下拉中的有效项。
5. 全部通过 → 组装 `CustomRuleSet` 写入 YAML。

### 加载时（容错，标错但不崩）

- 逐个读取 `custom-rulesets/<currentSubscriptionID>/*.yml`。
- 文件能解析且全部行合法 → 进 `valid`。
- YAML 结构损坏、缺字段、或**任一行非法**（用户手改导致）→ 进 `invalid`，记录文件名与首个错误原因。
- 加载失败**不抛异常、不影响其它规则集**。

### 执行时（生成配置）

- 只展开 `valid && enabled` 的规则集。
- `invalid` 的规则集**自动排除**，绝不进入生成的 sing-box 配置，保证 Core 能正常启动。

## 7. UI

### 规则页

- 工具栏在「添加规则」旁新增「**添加规则集**」按钮。
- 规则集在规则列表中以**独立分区/可折叠条目**呈现，每条显示：名称、出站、规则条数、启用开关、编辑/删除。
- `invalid` 规则集显示**错误态**（红色标识 + 悬浮/副标题提示原因），提供"编辑修复"入口；其开关禁用或显示为不生效。

### 添加/编辑规则集对话框（复用 MD3Dialog）

- **名称**：单行文本。
- **出站规则**：下拉——**复用 `populateRuleStrategyPopup`**（DIRECT/REJECT/Proxy/AUTO + 全部单节点；层级 2 完成后自定义组 tag 也会自动出现在此）。
- **规则清单**：多行文本框（等宽字体），支持粘贴标准格式。旁边附「**规则格式说明 →**」链接，指向我们自己的 wiki（`https://github.com/tongfei11/TungBox/wiki/自定义规则集`），说明支持的类型与写法；wiki 页内容一并补充。
- **「主流 AI」预设按钮**：把第 12 节的清单一键灌入规则清单文本框（若已有内容则追加，去重）。
- 底部"保存"触发第 6 节的严格校验。

## 8. 配置生成集成

- 在现有自定义单规则并入点（`MainWindowController+Rules.swift` 约 746 行，`customRouteRule(type:value:strategy:)` 展开处）旁边，追加"规则集展开"：
  - 对每个 `valid && enabled` 且属于当前订阅的规则集，遍历其 `rules`，用 `customRouteRule(type:value:strategy: outbound)` 生成 route 规则并注入 `route.rules`。
  - 顺序：与现有自定义规则一致的相对位置（自定义规则整体在订阅规则之前，保持"自上而下匹配"语义）。
- 出站 tag 若指向节点/组，沿用 `ensureOutboundSupport` 逻辑确保其存在。

## 9. 与现有单条自定义规则的关系

- 两者**共存**：单条规则用于零散补充；规则集用于成套方案。
- 均按 `subscriptionID` 过滤；均在订阅刷新后自动重新并入。
- 存储分离：单规则仍在 `custom-rules.json`；规则集在 `custom-rulesets/<sub>/`。

## 10. 生命周期与边界

- **切换订阅**：读取新订阅文件夹下的规则集；UI 刷新。
- **删除订阅**：级联删除 `custom-rulesets/<id>/`。
- **重命名规则集**：允许；slug/文件名随之变更（旧文件删除、新文件写入），`id` 不变。
- **重名**：同一订阅内名称唯一，保存时校验拦截。
- **空规则集**（rules 为空）：允许保存但不产生任何 route 规则（或保存时提示"清单为空"）——默认**允许**，视为占位草稿。
- **出站失效**（所选节点在新订阅中不存在）：生成时该规则集出站 tag 找不到 → 标错并排除；UI 提示"出站不存在，请重新选择"。

## 11. 主流 AI 预设（初版清单，可维护）

以 `DOMAIN-SUFFIX` 为主，初版覆盖：

```
- DOMAIN-SUFFIX, openai.com
- DOMAIN-SUFFIX, chatgpt.com
- DOMAIN-SUFFIX, oaistatic.com
- DOMAIN-SUFFIX, oaiusercontent.com
- DOMAIN-SUFFIX, anthropic.com
- DOMAIN-SUFFIX, claude.ai
- DOMAIN-SUFFIX, gemini.google.com
- DOMAIN-SUFFIX, generativelanguage.googleapis.com
- DOMAIN-SUFFIX, ai.google.dev
- DOMAIN-SUFFIX, x.ai
- DOMAIN-SUFFIX, grok.com
- DOMAIN-SUFFIX, perplexity.ai
- DOMAIN-SUFFIX, poe.com
- DOMAIN-SUFFIX, copilot.microsoft.com
```

清单以常量维护，后续可扩充；预设仅"填入"，用户可增删后再保存。

## 12. 验证 / 测试

- 单元级：行解析器（合法/非法/注释/空行/前导 `-`/LAN 无值）；YAML 读写往返；严格校验错误信息。
- 集成级：用打包核心 `sing-box check` 校验"含规则集展开的生成配置"能通过。
- 手改破坏：故意写坏一个 `.yml`，确认 UI 标错、生成配置排除、Core 正常启动。
- 订阅切换/删除：确认隔离与级联清理。

## 13. 层级 2 概述（后续独立子项目，另写 spec）

- 自定义代理组：`{ name, type(selector/urltest), 节点名 include/exclude 关键字, subscriptionID }`。
- 生成配置时按关键字从当前节点列表筛出成员 tag，构造 urltest/selector 出站，tag 加入策略下拉。
- 与本 spec 解耦：一旦组的 tag 进入策略下拉，规则集/单规则即可选它作为出站。

## 14. 假设与未决

- 节点列表用于展示，引用有效性以最终候选配置为准，不依赖 `nodes` 完整性的假设。
- 未决（留待实现或评审）：规则集在规则页是"独立分区"还是"与单规则混排的可折叠块"——倾向独立分区置于列表顶部。

## 15. 简易规则范围与 Wiki 分工（修订）

- 本功能保持“名称 + 统一出站 + 多行规则清单”，不增加原生 JSON 模式、模式切换、逻辑组合编辑器或逐条 action 配置。
- 输入采用 Clash 风格的 `TYPE, VALUE`，由 TungBox 本地转换为 sing-box 路由规则。清单各行独立匹配，通常为 OR 关系；统一出站决定转发或拒绝动作，用户无需编辑 action。
- Clash 风格规则语法与 Clash API 是两个概念：当前 `customRouteRule` / `applyCustomRules` 在本地生成 sing-box 配置；`ClashAPI` 用于节点选择、测速、连接和流量等运行管理，不负责规则语法转译。
- 能力范围以已有转换器能够正确表达的简易类型为基础，不承诺全部 Clash 或 sing-box 配置语法。新增类型按实际需求补充转换和验证，不扩展为复杂配置编辑功能。
- 映射表、兼容写法和示例维护在 Wiki：覆盖 URL 与域名正则差异、通配符、GEOIP 资源引用、LAN、协议嗅探、Clash 三段格式及 no-resolve。无法正确转译的输入明确报错，不静默近似转换或吞掉额外参数。
- 本功能要求两段规则；完整 Clash 三段规则及附加参数不自动导入，提示按 Wiki 改为两段清单，由统一出站选择策略。
- `RULE-SET` 引用最终配置中已定义的 sing-box rule-set tag；不引用另一份 TungBox 方案，也不自动创建远程规则资源。
- Wiki 说明域名信息、嗅探和 DNS 前提；软件仅保留格式说明链接与必要错误提示，内部共享现有类型校验与转换逻辑，避免多处名单不一致。

## 16. 动作、顺序与生成内容归属（修订）

- action 是匹配后的处理，必须区分终结动作（route、reject、hijack-dns 等）和非终结动作（sniff、resolve、route-options 等）。不能因为规则存在 action 字段，就把它排在自定义分流前面。
- 应用生成部分的固定顺序：必要的 DNS 接管和嗅探准备 → 显式全局／直连模式覆盖 → 单条自定义规则 → 自定义方案 → 普通订阅路由 → final。全局／直连模式覆盖自定义分流。
- 只按应用掌握的来源和用途安排准备规则；基础配置中已有规则的内部顺序保持不变，不任意抽取所有 sniff/resolve 提前执行。未知动作交由核心解释，不当作准备动作跳过。
- 方案增加持久化 order，平局按 createdAt、UUID 稳定排序；组内保持输入顺序，界面显示实际顺序。首版可固定排序，不要求拖动。终结动作命中后决定去向，非终结动作继续执行后续规则。
- 简易转发明确生成 action: route 与 outbound，REJECT 生成 action: reject，不再新建 block 出站。兼容转换在统一阶段完成，再校验最终配置。
- 每个订阅保存基础配置，与生成配置、最后成功运行配置分离。每次从基础配置叠加当前有效自定义数据，禁止按 JSON 内容相同判断规则归属或删除订阅规则。
- 启停、编辑、删除、手改及损坏 YAML 都触发完整重建，保证旧方案规则不残留。不能把“无效方案不再追加”等同于“历史规则已经清理”。
- 基础配置作为持久编辑入口，生成配置只读预览；迁移现有编辑行为时明确编辑对象。应用侧保存来源信息，不向核心规则写入不支持的私有字段。
- 旧版本仅有混合配置时，优先使用保存的原始订阅配置；无法可靠恢复来源时备份原件，要求选择基础配置，禁止按内容猜测删除。迁移完成前保留旧运行配置。

## 17. 引用失效、保存与应用（修订）

- enabled 表示用户意图，valid 表示当前配置下可用；另行记录 savedRevision、appliedRevision 和应用错误，区分已保存、待应用、已生效、应用失败。
- 出站和原生 rule-set 等引用以最终候选配置验证；ensureOutboundSupport 当前只补部分内置出站，不能保证任意节点或组存在。
- 出站缺失时保留原值并标错，禁止编辑器默认改选 Proxy。失效方案排除后，明确提示流量会继续匹配后续规则，可能改走其他节点或直连。
- 流程：输入校验 → 生成候选配置 → 当前核心 check → 暂存并提交文件 → 核心运行时应用 → 确认结果并记录 revision。写入错误必须向上返回，不得使用 try? 吞掉失败后提示成功。
- 多文件保存需要提交记录与恢复机制，单文件原子写入不代表整体事务。应用失败保留已保存意图与错误状态，继续使用或恢复最后成功运行配置，并支持重试。
- 核心停止时显示“已保存，待启动应用”；运行时使用实际支持的重新加载或受控重启，并提示现有连接可能受影响。不能把写入配置文件视为已经生效。
- 外部修改通过目录监听和去抖检测，并在启动、切换订阅、手动刷新时补充扫描。编辑期间外部文件变化需要冲突提示，不能覆盖未保存内容。
- 加载错误隔离单个方案；完整候选配置仍必须检查。候选检查失败时保留旧运行配置，不能宣称排除坏文件即可保证整个 Core 启动。

## 18. 数据与文件格式（修订）

- 保留第 3 节 entries 与统一 outbound 模型，仅补充 schemaVersion 和稳定 order，不增加双模式或任意 JSON 载荷。
- 持续使用当前实现的 `<ruleSetID-UUID>.yml` 文件名，重命名只改变名称，文件名与 UUID 不变，替代初版 slug 方案。
- YAML 继续保存元数据、outbound 和两段 rules 清单；不增加原生 JSON 块字段。
- 缺少 schemaVersion 的旧文件按明确迁移规则处理。缺失或非法 UUID 不得每次随机生成；如需补全必须一次性保存稳定结果。缺少 rules 与显式空清单不同。
- 检查必填字段、重复键、字段类型、同订阅重名和重复 UUID；enabled 只接受布尔值。明确 YAML 引号、注释、转义、换行行为，禁止默默忽略损坏结构。
- 不再强制手写解析器和零依赖：解析方案必须支持既定格式并通过往返测试。未知元数据保留或明确报错，已有规则值必须无损保留。
- 简易 CIDR 验证真实地址、地址族和前缀长度，不能只检查斜杠；正则以实际核心接受为准。错误提供方案名和行号或 JSON 路径。
- 当前更新器接受 1.12.x / 1.13.x。转换结果必须兼容实际核心版本与构建；升级或切换后重新检查生成配置。核心缺失时只能保留待验证草稿，不宣称校验通过。

## 19. 验收补充

- 已支持的两段规则正确转译并使用统一出站；不支持的类型、三段输入及附加参数提供清晰错误，不静默改变语义。
- 简易格式非法 CIDR、正则、额外参数正确报错；核心错误可对应到方案及规则行。空方案不生成兜底匹配规则。
- YAML 旧格式迁移、缺字段、重复键／UUID／名称、非法布尔值、特殊字符覆盖。
- 订阅含显式 action: route 兜底时，自定义 OpenAI 分流仍能优先命中；准备动作、模式覆盖、自定义重叠规则和稳定顺序符合约定。
- 手改、删除、破坏 YAML 后没有旧规则残留；同内容订阅规则不被误删；基础配置迁移保留用户修改。
- 出站、DNS server、原生规则集引用失效可定位，编辑不静默换策略；订阅刷新和核心切换后重新检查。
- 写入、应用和恢复失败时状态准确，旧可用配置保留；保存与运行 revision 不混淆。
- 系统代理与 TUN 下验证域名、IP、协议及进程的实际分流，分别观察新旧连接。静态 check 通过不能替代实际命中测试。
- Wiki 简易映射表、两段规则示例、兼容差异、嗅探／DNS 前提及失效回落说明完成，软件内链接可达。

## 20. 实施顺序与参考

1. 基础配置来源、迁移与重建；动作和优先级回归。
2. 简易规则转换与校验、必要文件迁移、引用校验与失效状态。
3. 保存／应用／恢复流程、外部修改检测及完整验收。
4. Wiki 更新、界面状态与设计核对；完成后再开展自定义代理组。

本次仅修订设计，不代表这些优化已实现，也不代表 Wiki 已发布。

- [sing-box 路由规则](https://sing-box.sagernet.org/configuration/route/rule/)
- [sing-box 动作](https://sing-box.sagernet.org/configuration/route/rule_action/)
- [sing-box 原生规则集](https://sing-box.sagernet.org/configuration/rule-set/)
- [sing-box 协议嗅探](https://sing-box.sagernet.org/configuration/route/sniff/)
