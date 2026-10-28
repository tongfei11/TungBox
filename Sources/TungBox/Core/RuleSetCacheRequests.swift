import Foundation
import Darwin

/// UI-owned request generations prevent old downloads from publishing over a newer refresh.
@MainActor
final class RuleSetCacheRequests {
    private static let owners = NSMapTable<AnyObject, RuleSetCacheRequests>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var requests: [String: UUID] = [:]
    private var rowsRequest = UUID()
    func beginRows() -> UUID { rowsRequest = UUID(); return rowsRequest }
    func isCurrentRows(_ request: UUID) -> Bool { rowsRequest == request }

    static func forOwner(_ owner: AnyObject) -> RuleSetCacheRequests {
        if let state = owners.object(forKey: owner) { return state }
        let state = RuleSetCacheRequests()
        owners.setObject(state, forKey: owner)
        return state
    }

    func begin(tag: String) -> UUID {
        let request = UUID()
        requests[tag] = request
        return request
    }

    func finish(tag: String, request: UUID) -> Bool {
        guard requests[tag] == request else { return false }
        requests.removeValue(forKey: tag)
        return true
    }

    struct RefreshSummary: Equatable {
        var succeeded = 0
        var failed = 0
        var discarded = 0
    }
    private var manualRequests: Set<UUID> = []
    private var summary = RefreshSummary()

    func beginManualRefresh() {
        manualRequests.removeAll()
        summary = RefreshSummary()
    }

    func trackManual(_ request: UUID) { manualRequests.insert(request) }

    func completeManual(_ request: UUID, succeeded: Bool, discarded: Bool = false) -> RefreshSummary? {
        guard manualRequests.remove(request) != nil else { return nil }
        if discarded { summary.discarded += 1 }
        else if succeeded { summary.succeeded += 1 }
        else { summary.failed += 1 }
        return manualRequests.isEmpty ? summary : nil
    }

    func invalidate() {
        requests.removeAll()
        rowsRequest = UUID()
        manualRequests.removeAll()
    }

    /// Hard links preserve old contents; atomic rename keeps each live path continuously readable.
    static func publish(srs: URL?, json: URL, toSRS: URL, toJSON: URL) throws {
        let files = (srs.map { [($0, toSRS)] } ?? []) + [(json, toJSON)]
        let fm = FileManager.default
        var backups: [(URL, URL)] = []
        var installed: [URL] = []
        do {
            for (source, destination) in files {
                if fm.fileExists(atPath: destination.path) {
                    let backup = destination.deletingLastPathComponent().appendingPathComponent(".backup-\(UUID().uuidString)")
                    try fm.linkItem(at: destination, to: backup)
                    backups.append((backup, destination))
                }
                try atomicRename(source, destination)
                installed.append(destination)
            }
        } catch {
            let backedUp = Set(backups.map { $0.1 })
            for destination in installed where !backedUp.contains(destination) { try? fm.removeItem(at: destination) }
            for (backup, destination) in backups {
                do {
                    try atomicRename(backup, destination)
                    // rename is a no-op when both paths still reference the same inode.
                    try? fm.removeItem(at: backup)
                } catch {
                    // Keep the backup if restoration fails so the original remains recoverable.
                }
            }
            throw error
        }
        for (backup, _) in backups { try? fm.removeItem(at: backup) }
    }

    private static func atomicRename(_ source: URL, _ destination: URL) throws {
        guard Darwin.rename(source.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

}
