import Foundation

var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures += 1; print("FAIL: \(message)") }
}
for input in ["DOMAIN-SUFFIX, openai.com, Proxy", "IP-CIDR, invalid/999", "IP-CIDR6, 1.2.3.4/24", "DOMAIN-REGEX, [", "LAN, unexpected"] {
    expect(!RuleSetFormat.parseRules(input).errors.isEmpty, "reject \(input)")
}
for input in ["DOMAIN-SUFFIX, openai.com", "IP-CIDR, 192.168.0.0/16", "IP-CIDR6, 2001:db8::/32", "LAN", "DOMAIN-REGEX, ^a{1,3}\\.com$"] {
    expect(RuleSetFormat.parseRules(input).errors.isEmpty, "accept \(input)")
}
let sub = UUID()
let set = CustomRuleSet(id: UUID(), subscriptionID: sub, name: "AI: #1", outbound: "Proxy", rules: [RuleSetEntry(type: "DOMAIN-SUFFIX", value: "openai.com")], enabled: true, createdAt: Date(timeIntervalSince1970: 100))
let yaml = RuleSetFormat.serialize(set)
if case .success(let loaded) = RuleSetFormat.deserialize(yaml, subscriptionID: sub) { expect(loaded == set, "YAML round trip") } else { expect(false, "load valid YAML") }
for broken in ["name: AI\noutbound: Proxy\n", yaml.replacingOccurrences(of: "enabled: true", with: "enabled: maybe"), yaml + "name: other\n", yaml.replacingOccurrences(of: "  - DOMAIN-SUFFIX, openai.com", with: "  broken line")] {
    if case .success = RuleSetFormat.deserialize(broken, subscriptionID: sub) { expect(false, "reject malformed YAML") }
}

let base: [[String: Any]] = [["action": "sniff"], ["action": "route", "outbound": "Proxy"]]
let generated = RuleRouting.customRouteRule(type: "DOMAIN-SUFFIX", value: "openai.com", strategy: "DIRECT")
let rebuilt = RuleRouting.rebuild(base: base, generated: [generated])
expect(rebuilt[1]["domain_suffix"] as? String == "openai.com", "custom route precedes explicit catchall")
expect(NSArray(array: RuleRouting.rebuild(base: base, generated: [])).isEqual(to: base), "removal restores exact base")
let sameBase = [generated]
expect(RuleRouting.rebuild(base: sameBase, generated: [generated]).count == 2, "identical subscription rule retained")
expect(RuleRouting.rebuild(base: sameBase, generated: []).count == 1, "disable does not delete subscription rule")
let reject = RuleRouting.customRouteRule(type: "DOMAIN", value: "blocked.example", strategy: "REJECT")
expect(reject["action"] as? String == "reject" && reject["outbound"] == nil, "reject uses action")
expect(RuleRouting.referenceError(type: "LAN", value: "", strategy: "missing", config: [:]) != nil, "missing outbound rejected")
expect(RuleRouting.referenceError(type: "GEOIP", value: "us", strategy: "DIRECT", config: [:]) != nil, "missing geoip resource rejected")
expect(RuleRouting.referenceError(type: "RULE-SET", value: "cn", strategy: "DIRECT", config: ["route": ["rule_set": [["tag": "cn"]]]]) == nil, "existing rule-set accepted")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let store = Store(baseURL: directory)
try store.saveRuleSet(set)
expect(store.loadRuleSets(for: sub).valid == [set], "store round trip")
expect(store.loadRuleSets(for: UUID()).valid.isEmpty, "subscription isolation")
let duplicate = store.ruleSetsFolder(for: sub).appendingPathComponent("copy.yml")
try Data(yaml.utf8).write(to: duplicate)
expect(store.loadRuleSets(for: sub).valid.isEmpty, "duplicate UUID excluded")
try store.deleteRuleSetFile(at: duplicate)
try store.deleteRuleSet(set)
expect(store.loadRuleSets(for: sub).valid.isEmpty, "delete persisted")
do { try store.deleteRuleSet(set); expect(false, "missing file deletion must throw") } catch {}
let blockedID = UUID()
try Data("not a directory".utf8).write(to: store.ruleSetsFolder(for: blockedID))
var blocked = set; blocked.subscriptionID = blockedID
 do { try store.saveRuleSet(blocked); expect(false, "write failure must throw") } catch {}
do { _ = try store.baseRouteRules(for: sub); expect(false, "legacy baseline must not be guessed") } catch {}
let configText = String(data: try JSONSerialization.data(withJSONObject: ["route": ["rules": base]]), encoding: .utf8)!
try store.saveRuleBase(configText, for: sub)
let loadedBase = try store.baseRouteRules(for: sub)
expect(NSArray(array: loadedBase).isEqual(to: base), "independent base preserved")
try store.saveRuleProjection(configText, for: sub)
try store.verifyRuleProjection(base, for: sub)
do { try store.verifyRuleProjection([generated], for: sub); expect(false, "manual route edit protected") } catch {}

if let corePath = ProcessInfo.processInfo.environment["TUNGBOX_CORE_PATH"] {
    let url = directory.appendingPathComponent("check.json")
    let config: [String: Any] = ["outbounds": [["type": "direct", "tag": TungBoxConfig.tagDirect]], "route": ["rules": [generated, reject]]]
    try JSONSerialization.data(withJSONObject: config).write(to: url)
    let process = Process(); process.executableURL = URL(fileURLWithPath: corePath)
    process.arguments = ["check", "-c", url.path]
    try process.run(); process.waitUntilExit()
    expect(process.terminationStatus == 0, "actual core accepts route and reject")
}

if let fixtureDirectory = ProcessInfo.processInfo.environment["TUNGBOX_RULE_FIXTURES"] {
    let direct = RuleRouting.customRouteRule(type: "IP-CIDR", value: "127.0.0.1/32", strategy: "DIRECT")
    let fallback: [[String: Any]] = [["action": "reject"]]
    let fixtures = [
        "enabled": RuleRouting.rebuild(base: fallback, generated: [direct]),
        "disabled": RuleRouting.rebuild(base: fallback, generated: []),
        "subscription-preserved": RuleRouting.rebuild(base: [direct] + fallback, generated: [])
    ]
    for (name, rules) in fixtures {
        let config: [String: Any] = ["outbounds": [["type": "direct", "tag": TungBoxConfig.tagDirect]], "route": ["rules": rules]]
        try JSONSerialization.data(withJSONObject: config).write(to: URL(fileURLWithPath: fixtureDirectory).appendingPathComponent("\(name).json"))
    }
}
if failures > 0 { print("\(failures) failures"); exit(1) }
print("Rule-set regression tests passed")
