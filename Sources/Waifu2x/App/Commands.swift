import AppKit
import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("О приложении Waifu2x") {
                AboutPanel.show()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Открыть…") {
                model.presentOpenPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Экспортировать…") {
                model.exportSelected()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.selectedItem == nil)

            Button("Экспортировать всё…") {
                model.exportAll()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model.items.isEmpty)
        }

        CommandMenu("Изображение") {
            Button("Улучшить") {
                model.improveSelected()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.selectedItem == nil || model.isProcessing)

            Button("Улучшить всё") {
                model.improveAll()
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(model.items.isEmpty || model.isProcessing)

            Divider()

            Button("Отмена") {
                model.cancelProcessing()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!model.isProcessing)
        }

        CommandGroup(replacing: .sidebar) {
            Button("Показать/Скрыть боковую панель") {
                model.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }

        CommandGroup(after: .sidebar) {
            Button(LocalizedStringKey(model.inspectorPresented ? "Скрыть инспектор" : "Показать инспектор")) {
                model.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.option, .command])

            Divider()

            Button(LocalizedStringKey(model.compareEnabled ? "Скрыть сравнение" : "Сравнить до и после")) {
                model.toggleCompare()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(!model.canCompare)

            Divider()

            Button("Увеличить") {
                model.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(model.selectedItem == nil)

            Button("Уменьшить") {
                model.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(model.selectedItem == nil)

            Button("Вписать") {
                model.zoomToFit()
            }
            .keyboardShortcut("9", modifiers: .command)
            .disabled(model.selectedItem == nil)

            Button("Фактический размер") {
                model.zoomToActualSize()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(model.selectedItem == nil)
        }
    }
}

// MARK: - About panel

enum AboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let creditLines = [
            L10n.t("Апскейлер изображений на базе waifu2x"),
            L10n.t("Обработка выполняется локально на этом Mac."),
            "MIT License",
        ]
        let credits = NSMutableAttributedString(
            string: creditLines.joined(separator: "\n") + "\n",
            attributes: baseAttributes
        )

        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.linkColor,
            .link: URL(string: "https://github.com/nagadomi/waifu2x")!,
            .paragraphStyle: paragraph,
        ]
        credits.append(
            NSAttributedString(
                string: "github.com/nagadomi/waifu2x",
                attributes: linkAttributes
            )
        )

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Waifu2x",
            .applicationVersion: version,
            .version: build,
            .credits: credits,
        ]

        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}
