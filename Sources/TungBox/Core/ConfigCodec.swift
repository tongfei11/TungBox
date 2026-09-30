import Foundation

/// JSON 读写只处理配置对象，不转换字段，也不访问 UI 或持久化。
enum ConfigCodec {
    /// 无效 JSON 或非对象顶层返回 nil，沿用控制器原有解析行为。
    static func parseObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    /// 保留原有缩进、键排序与 Foundation 错误；数组顺序不变。
    static func render(_ config: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }
}
