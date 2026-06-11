import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupHotkey()
        configureWindow()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean up resources
    }

    // MARK: - Window Management

    func configureWindow() {
        if let window = NSApplication.shared.windows.first {
            mainWindow = window
            window.setFrame(NSRect(x: 100, y: 100, width: 600, height: 700), display: true)
            window.minSize = NSSize(width: 400, height: 500)
            window.isReleasedWhenClosed = false
        }
    }

    // MARK: - Hotkey Setup

    func setupHotkey() {
        // Register global hotkey (Cmd+Shift+K to show/hide window)
        let hotKeyCode: UInt32 = 40 // K key
        let modifiers: UInt = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == hotKeyCode && event.modifierFlags.contains([.command, .shift]) {
                self.toggleMainWindow()
            }
        }
    }

    func toggleMainWindow() {
        if let window = mainWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}
