import AppKit

// AppDelegate owns launch, reopen and termination; it retains the main window controller.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
