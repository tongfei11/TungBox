import AppKit
import Foundation

extension MainWindowController {
    func checkAppUpdateInBackground() {
        if case .checking = appUpdateCheckState {
            return
        }

        appUpdateCheckState = .checking

        Task {
            do {
                let release = try await AppUpdater.latestRelease()
                await MainActor.run { [weak self] in
                    self?.handleAppUpdateCheck(release)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.appUpdateCheckState = .failed(error.localizedDescription)
                    self?.appVersionFooter.showsNewBadge = false
                    self?.appendLog("[TungBox] 应用更新检查失败：\(error.localizedDescription)\n")
                }
            }
        }
    }

    private func handleAppUpdateCheck(_ release: AppRelease) {
        latestAppRelease = release
        if AppUpdater.isNewer(release) {
            appUpdateCheckState = .available(release)
            appVersionFooter.showsNewBadge = true
            appendLog("[TungBox] 发现应用更新：\(TungBoxVersion.release) -> \(release.version)\n")
        } else {
            appUpdateCheckState = .upToDate(release)
            appVersionFooter.showsNewBadge = false
            appendLog("[TungBox] 应用已是最新版本：\(TungBoxVersion.release)\n")
        }
    }

    @objc func appVersionFooterClicked() {
        switch appUpdateCheckState {
        case .available(let release):
            showAppUpdateDialog(release)
        case .checking:
            showToast("正在检查应用更新...")
        case .upToDate:
            showToast("TungBox 已是最新版：\(TungBoxVersion.release)")
        case .failed, .notChecked:
            showToast("打开控制台时会自动检查更新")
        }
    }

    private func showAppUpdateDialog(_ release: AppRelease) {
        let noteLines = release.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let titleLikeLines = Set([
            release.name,
            "TungBox \(release.version)",
            release.tag,
            "v\(release.version)"
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let displayLines = noteLines.enumerated().filter { index, line in
            if index == 0 {
                return !titleLikeLines.contains(line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
            return true
        }
        let notes = displayLines
            .map(\.element)
            .prefix(14)
            .joined(separator: "\n")
        let noteText = notes.isEmpty ? "该 Release 暂无发布说明。" : notes

        let notesView = NSTextView()
        notesView.string = noteText
        notesView.isEditable = false
        notesView.isSelectable = true
        notesView.drawsBackground = false
        notesView.textColor = MD3.onSurfaceVariant
        notesView.font = .systemFont(ofSize: 13)
        notesView.textContainerInset = NSSize(width: 0, height: 0)
        notesView.isVerticallyResizable = true
        notesView.isHorizontallyResizable = false
        notesView.autoresizingMask = [.width]
        notesView.textContainer?.widthTracksTextView = true
        notesView.textContainer?.containerSize = NSSize(
            width: 440,
            height: CGFloat.greatestFiniteMagnitude
        )
        notesView.minSize = NSSize(width: 0, height: 0)
        notesView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = notesView
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let dialog = showMD3Dialog(
            title: "发现 TungBox 更新",
            message: "当前版本：\(TungBoxVersion.release)\n最新版本：\(release.version)",
            customView: scroll,
            confirmTitle: "打开 Release",
            cancelTitle: "稍后"
        )
        dialog.onConfirm = { [weak dialog] in
            NSWorkspace.shared.open(release.htmlURL)
            dialog?.dismiss()
        }
        dialog.onCancel = { [weak dialog] in
            dialog?.dismiss()
        }
    }
}
