#if DEBUG
import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Development-only bridge used to drive and photograph the UI from automated
/// verification scripts. Compiled only into debug builds.
@MainActor
enum DebugBridge {
    private static var observer: NSObjectProtocol?
    private static weak var model: AppModel?

    static func start(model: AppModel) {
        guard ProcessInfo.processInfo.environment["WAIFU2X_AUTOMATION"] == "1" else { return }
        guard observer == nil else { return }
        self.model = model

        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.waifu2x.debug.command"),
            object: nil,
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let command = info["command"] as? String else { return }
            Task { @MainActor in
                handle(command: command, info: info)
            }
        }
    }

    private static func handle(command: String, info: [AnyHashable: Any]) {
        guard let model else { return }
        switch command {
        case "import":
            if let paths = info["paths"] as? [String] {
                model.importImages(urls: paths.map { URL(fileURLWithPath: $0) })
            }
        case "improve":
            model.improveSelected()
        case "improveAll":
            model.improveAll()
        case "cancel":
            model.cancelProcessing()
        case "compareOn":
            if model.canCompare { model.compareEnabled = true }
        case "compareOff":
            model.compareEnabled = false
        case "compareFraction":
            if let value = info["value"] as? Double {
                model.compareFraction = min(max(CGFloat(value), 0.02), 0.98)
            }
        case "fit":
            model.zoomToFit()
        case "actual":
            model.zoomToActualSize()
        case "selectFirst":
            if let first = model.items.first {
                model.selection = first.id
            }
        case "selectIndex":
            if let value = info["value"] as? Double {
                let index = Int(value)
                if model.items.indices.contains(index) {
                    model.selection = model.items[index].id
                }
            }
        case "activate":
            activateMainWindow()
        case "capture":
            guard let path = info["path"] as? String else { return }
            captureMainWindow(to: path)
        case "captureSettings":
            guard let path = info["path"] as? String else { return }
            captureSettings(to: path)
        case "settingsTab":
            if let value = info["value"] as? Double {
                UserDefaults.standard.set(Int(value), forKey: "settingsTab")
            }
        case "settings":
            openSettings()
        case "settingsKey":
            sendSettingsShortcut()
        case "about":
            AboutPanel.show()
        case "appearance":
            if let name = info["value"] as? String {
                switch name {
                case "light": NSApp.appearance = NSAppearance(named: .aqua)
                case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                default: NSApp.appearance = nil
                }
            }
        case "dump":
            if let path = info["path"] as? String {
                dumpState(to: path)
            }
        case "captureAll":
            guard let path = info["path"] as? String else { return }
            captureAllWindows(toPrefix: path)
        default:
            break
        }
    }

    private static func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: {
            $0.isVisible && $0.contentView != nil && $0.frame.width > 400 && $0.title == "Waifu2x"
        }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func captureMainWindow(to path: String) {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.contentView != nil && $0.frame.width > 400 && $0.title != "Настройки" && $0.title != "Settings" && $0.title != "Основные" && $0.title != "Движок" && $0.title != "Благодарности"
        }) else { return }
        window.makeKeyAndOrderFront(nil)
        capture(window: window, to: path)
    }

    private static func captureWindow(titled titles: [String], to path: String) {
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && titles.contains($0.title)
        }) else { return }
        capture(window: window, to: path)
    }

    private static func captureSettings(to path: String) {
        NSApp.activate(ignoringOtherApps: true)
        let mainTitle = "Waifu2x"
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.contentView != nil && $0.title != mainTitle && $0.frame.width > 180
        }) else { return }
        capture(window: window, to: path)
    }

    private static func captureAllWindows(toPrefix prefix: String) {
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            capture(window: window, to: "\(prefix)-\(index)-\(window.title).png")
        }
    }

    private static func capture(window: NSWindow, to path: String) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Give AppKit a moment to redraw the window in its active/key state.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            captureNow(window: window, to: path)
        }
    }

    private static func captureNow(window: NSWindow, to path: String) {
        window.displayIfNeeded()

        // Preferred path: the theme frame includes the titlebar, toolbar and
        // traffic lights. It works without screen-recording permission because
        // the app is photographing itself.
        if let frameView = window.contentView?.superview {
            let bounds = frameView.bounds
            if let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) {
                frameView.cacheDisplay(in: bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                    return
                }
            }
        }

        // Fallback: content view only.
        guard let contentView = window.contentView else { return }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        contentView.cacheDisplay(in: bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func dumpState(to path: String) {
        var lines: [String] = []
        func walk(_ menu: NSMenu, level: Int) {
            for item in menu.items {
                let indent = String(repeating: "  ", count: level)
                var line = "\(indent)\(item.title)"
                if !item.keyEquivalent.isEmpty {
                    line += " [\(item.keyEquivalentModifierMask.rawValue):\(item.keyEquivalent)]"
                }
                if let action = item.action {
                    line += " action=\(NSStringFromSelector(action))"
                }
                if item.isSeparatorItem { line = "\(indent)---" }
                lines.append(line)
                if let submenu = item.submenu { walk(submenu, level: level + 1) }
            }
        }
        if let main = NSApp.mainMenu { walk(main, level: 0) }
        lines.append("")
        lines.append("WINDOWS")
        for window in NSApp.windows {
            lines.append("\(window.title) | visible=\(window.isVisible) | frame=\(window.frame)")
        }
        lines.append("")
        if let model {
            lines.append("OPTIONS style=\(model.options.style.rawValue) denoise=\(model.options.denoise.rawValue) scale=\(model.options.scale.rawValue)")
            lines.append("STATUS \(model.engineStatus.title) | \(model.engineStatus.detail) | ready=\(model.engineStatus.isReady) | kind=\(model.engineStatus.kind.rawValue)")
        } else {
            lines.append("OPTIONS nil")
            lines.append("STATUS nil")
        }
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) {
            return
        }
        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let index = appMenu.items.firstIndex(where: {
               $0.title.contains("Настрой") || $0.title.contains("Settings")
           }) {
            appMenu.performActionForItem(at: index)
        }
    }

    private static func sendSettingsShortcut() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else { return }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43
        )
        if let event { NSApp.postEvent(event, atStart: false) }
    }
}

#endif
