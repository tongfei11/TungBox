import Foundation

/// Settings reloads yield to user switch operations and configuration transactions.
@MainActor
enum TUNSettingsUpdate {
    enum Outcome: Equatable {
        case deferred, saved, reloadRequested, failed, superseded
    }

    static func apply(isCurrent: () -> Bool, isBusy: () -> Bool, tunEnabled: () -> Bool,
                      reload: () async -> Bool) async -> Outcome {
        guard isCurrent() else { return .superseded }
        guard !isBusy() else { return .deferred }
        guard tunEnabled() else { return .saved }
        let success = await reload()
        guard isCurrent(), tunEnabled() else { return .superseded }
        return success ? .reloadRequested : .failed
    }
}
