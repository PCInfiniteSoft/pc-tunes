import AppKit
import SwiftUI
import Combine

/// The app is a plain AppKit accessory app hosting SwiftUI views, not a SwiftUI `App`.
///
/// It began as a SwiftUI `MenuBarExtra`, which regressed on macOS 26.6 built with the
/// Xcode 27 toolchain: the status item was created and then torn straight back down as
/// SwiftUI called `terminate:` on itself. Driving `NSApplication` directly — the
/// ordinary way a menu bar utility is built — keeps the process alive and creates the
/// item through AppKit. The dropdown and the settings window are the same SwiftUI views,
/// each hosted in AppKit.
///
/// The app is an accessory (no Dock icon) through `LSUIElement` in Info.plist, set by
/// `build.sh`. On macOS 26.6 a bundled app *without* that flag never gets its status item
/// adopted into the menu bar — the item's window is placed off-screen and stays there —
/// so the flag is what makes the icon appear, and no `setActivationPolicy` call is needed.
/// Because Launch Services caches the flag per bundle id, `build.sh` re-registers the
/// bundle so a machine that once ran a build without it picks up the change.
@main
enum PCTunesMain {
    /// Retains the delegate for the process's lifetime; `NSApplication.delegate` is weak.
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PlayerModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.image
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        let host = NSHostingController(
            rootView: MenuContent(model: model, openSettings: { [weak self] in self?.showSettings() })
        )
        // Let the popover follow the view's own size, so expanding "Up next" grows it
        // rather than clipping.
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        self.popover = popover

        // The label mirrors `menuBarTitle`; `objectWillChange` fires just before any
        // published change, so the read is deferred a tick to see the new value.
        cancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateButtonTitle() }
            }
        updateButtonTitle()
    }

    private func updateButtonTitle() {
        statusItem?.button?.title = model.menuBarTitle.map { " \($0)" } ?? ""
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // An accessory app is never the active app, so the popover opens behind the
        // frontmost window and its text fields cannot take focus until it is activated.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Opens (or re-focuses) the settings window, holding the same SwiftUI `SettingsView`.
    /// Built by hand rather than through a SwiftUI `Settings` scene, which only exists
    /// inside a SwiftUI `App`.
    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "PC Tunes Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
