import Foundation

/// A shared rollback boundary for the independently running TUN and user Core.
@MainActor
enum RuntimeConfigurationUpdate {
    struct Services {
        let current: () -> Bool
        let updateTun: () async throws -> Void
        let updateProxy: () async throws -> Void
        let restoreTun: () async throws -> Void
    }

    static func apply(tun: Bool, proxy: Bool, services: Services) async throws -> Bool {
        guard services.current() else { return false }
        var tunAttempted = false
        do {
            if tun {
                tunAttempted = true
                try await services.updateTun()
            }
            guard services.current() else { return false }
            if proxy { try await services.updateProxy() }
            return services.current()
        } catch RuntimeCoordinator.OperationError.superseded { return false }
        catch {
            guard services.current() else { return false }
            let applyError = error
            if tunAttempted {
                do { try await services.restoreTun() }
                catch { throw NSError.user("更新失败：\(applyError.localizedDescription)；TUN 恢复失败：\(error.localizedDescription)") }
            }
            throw applyError
        }
    }
}
