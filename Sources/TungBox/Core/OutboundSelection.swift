import Foundation

/// Resolves the selector appropriate to the mode, without reading window state.
enum OutboundSelection {
    static func group(for mode: String) -> String {
        mode.caseInsensitiveCompare("Global") == .orderedSame ? TungBoxConfig.tagGlobal : TungBoxConfig.tagManual
    }

    static func resolve(group: String, proxiesObject: [String: Any]?, groups: [NodeGroupInfo],
                        configText: String, fallback: String = "默认") -> (name: String, isAuto: Bool) {
        let proxies = proxiesObject?["proxies"] as? [String: Any]
        var current = group
        var automatic = false
        var visited = Set<String>()
        let outbounds = ConfigCodec.parseObject(from: configText)?["outbounds"] as? [[String: Any]] ?? []
        while visited.insert(current).inserted {
            if let runtime = proxies?[current] as? [String: Any],
               let now = runtime["now"] as? String, !now.isEmpty {
                let type = (runtime["type"] as? String ?? "").lowercased()
                automatic = automatic || current == TungBoxConfig.tagAuto || ["urltest", "url-test", "fallback"].contains(type)
                current = now
            } else if let saved = groups.first(where: { $0.tag == current }) {
                automatic = automatic || ["urltest", "url-test", "fallback"].contains(saved.type.lowercased())
                guard !saved.current.isEmpty else { break }
                current = saved.current
            } else if let saved = outbounds.first(where: { $0["tag"] as? String == current }),
                      let node = saved["default"] as? String, !node.isEmpty {
                current = node
            } else { break }
        }
        return (current == group && !visited.isEmpty ? fallback : current, automatic)
    }
}
