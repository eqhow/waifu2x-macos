import AppKit
import Foundation

extension Notification.Name {
    static let waifu2xOpenImages = Notification.Name("Waifu2xOpenImages")
}

/// Thread-safe holding area for files delivered through Finder's "Open With"
/// before the SwiftUI view hierarchy exists.
final class PendingOpenImages: @unchecked Sendable {
    static let shared = PendingOpenImages()

    private let lock = NSLock()
    private var urls: [URL] = []

    private init() {}

    func append(_ newURLs: [URL]) {
        guard !newURLs.isEmpty else { return }
        lock.lock()
        urls.append(contentsOf: newURLs)
        lock.unlock()
    }

    func takeAll() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        let copy = urls
        urls.removeAll()
        return copy
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            self.removeDuplicateSidebarCommands()
        }
    }

    /// SwiftUI adds an unlocalized "Toggle Sidebar" item to the Help menu next
    /// to the app's own localized sidebar command. Remove the duplicate.
    private func removeDuplicateSidebarCommands() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let sidebarSelector = Selector(("toggleSidebar:"))
        for menu in mainMenu.items.compactMap(\.submenu) {
            for item in menu.items.reversed() where item.action == sidebarSelector {
                menu.removeItem(item)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        PendingOpenImages.shared.append(urls)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .waifu2xOpenImages, object: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
