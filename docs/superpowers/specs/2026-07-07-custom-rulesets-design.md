# 自定义规则集（分流方案）设计文档

- 日期：2026-07-07
- 分支：feature/rules-enhancement
- 状态：待评审
- 作用范围：本 spec 只覆盖**层级 1（自定义规则集）**。层级 2（自定义代理组）是后续独立子项目，仅在第 14 节概述。

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
- `TYPE` 必须是**已支持类型集**中的一个（DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD / DOMAIN-WILDCARD / DOMAIN-REGEX / RULE-SET / IP-CIDR / IP-CIDR6 / GEOIP / LAN / SRC-IP / PROCESS-NAME / PROCESS-PATH / URL-REGEX / DEST-PORT / PROTOCOL / NETWORK）。
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

- 假设 `nodes` 属性反映当前订阅节点，随订阅切换更新（用于出站下拉与失效校验）。
- 未决（留待实现或评审）：规则集在规则页是"独立分区"还是"与单规则混排的可折叠块"——倾向独立分区置于列表顶部。
