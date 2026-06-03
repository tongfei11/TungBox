import AppKit
import Foundation

extension MainWindowController {
    func checkAppUpdateInBackground(showResult: Bool) {
        if case .checking = appUpdateCheckState {
            if showResult {
                showToast("正在检查应用更新...")
            }
            return
        }

        appUpdateCheckState = .checking
        if showResult {
            showToast("正在检查应用更新...")
        }

        Task {
            do {
                let release = try await AppUpdater.latestRelease()
                await MainActor.run { [weak self] in
                    self?.handleAppUpdateCheck(release, showResult: showResult)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.appUpdateCheckState = .failed(error.localizedDescription)
                    self?.appVersionFooter.showsNewBadge = false
                    if showResult {
                        self?.showToast("应用更新检查失败")
                        self?.showError(error)
                    }
                }
            }
        }
    }

    private func handleAppUpdateCheck(_ release: AppRelease, showResult: Bool) {
        latestAppRelease = release
        if AppUpdater.isNewer(release) {
            appUpdateCheckState = .available(release)
            appVersionFooter.showsNewBadge = true
            appendLog("[TungBox] 发现应用更新：\(TungBoxVersion.release) -> \(release.version)\n")
            if showResult {
                showAppUpdateDialog(release)
            }
        } else {
            appUpdateCheckState = .upToDate(release)
            appVersionFooter.showsNewBadge = false
            if showResult {
                showToast("TungBox 已是最新版：\(TungBoxVersion.release)")
            }
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
            checkAppUpdateInBackground(showResult: true)
        }
    }

    private func showAppUpdateDialog(_ release: AppRelease) {
        let notes = release.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .prefix(12)
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

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = notesView
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let dialog = showMD3Dialog(
            title: "发现 TungBox 更新",
            message: "当前版本：\(TungBoxVersion.release)\n最新版本：\(release.version)\n\n\(release.name)",
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
