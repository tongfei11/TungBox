import Foundation
import Security

enum LocalAPISecret {
    private static let secretsDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first!.appendingPathComponent("TungBox/secrets", isDirectory: true)

    static let userProxy = loadApplicationSecret(named: "user-api-secret")
    static let tunDaemon = loadApplicationSecret(named: "tun-api-secret")

    private static func loadApplicationSecret(named name: String) -> String {
        do {
            return try loadOrCreate(at: secretsDirectory.appendingPathComponent(name))
        } catch {
            preconditionFailure("无法安全初始化本地控制接口密钥：\(error.localizedDescription)")
        }
    }

    static func secret(forPort port: Int) -> String {
        port == TungBoxConfig.tunDaemonClashPort ? tunDaemon : userProxy
    }

    static func secret(forPort port: Int, userSecret: String, tunSecret: String) -> String {
        port == TungBoxConfig.tunDaemonClashPort ? tunSecret : userSecret
    }

    static func loadOrCreate(at url: URL) throws -> String {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()

        if fileManager.fileExists(atPath: directory.path) {
            let attributes = try fileManager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw NSError.user("本地控制接口密钥目录无效")
            }
        } else {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        if fileManager.fileExists(atPath: url.path) {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw NSError.user("本地控制接口密钥文件无效")
            }
            let existing = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil {
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                return existing
            }
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NSError.user("无法生成本地控制接口密钥")
        }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        try Data((secret + "\n").utf8).write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return secret
    }
}

enum LocalAPIConfiguration {
    static func containsSecret(in config: [String: Any]) -> Bool {
        let experimental = config["experimental"] as? [String: Any]
        let clashAPI = experimental?["clash_api"] as? [String: Any]
        return clashAPI?["secret"] != nil
    }

    static func authenticated(
        _ config: [String: Any],
        listen: String,
        secret: String
    ) -> [String: Any] {
        var config = config
        var experimental = config["experimental"] as? [String: Any] ?? [:]
        var clashAPI = experimental["clash_api"] as? [String: Any] ?? [:]
        clashAPI["external_controller"] = listen
        clashAPI["secret"] = secret
        experimental["clash_api"] = clashAPI
        config["experimental"] = experimental
        return config
    }

    static func removingSecret(from config: [String: Any]) -> [String: Any] {
        var config = config
        guard var experimental = config["experimental"] as? [String: Any],
              var clashAPI = experimental["clash_api"] as? [String: Any] else {
            return config
        }
        clashAPI.removeValue(forKey: "secret")
        experimental["clash_api"] = clashAPI
        config["experimental"] = experimental
        return config
    }
}
