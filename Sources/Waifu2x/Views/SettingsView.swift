import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("settingsTab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tag(0)
                .tabItem {
                    Label("Основные", systemImage: "gearshape")
                }

            EngineSettingsView()
                .tag(1)
                .tabItem {
                    Label("Движок", systemImage: "cpu")
                }

            CreditsSettingsView()
                .tag(2)
                .tabItem {
                    Label("Благодарности", systemImage: "heart")
                }
        }
        .frame(width: 520, height: 400)
        .environmentObject(model)
    }
}

// MARK: - Основные

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(SettingsKeys.style) private var defaultStyle = UpscaleOptions.Style.anime.rawValue
    @AppStorage(SettingsKeys.denoise) private var defaultDenoise = UpscaleOptions.Denoise.low.rawValue
    @AppStorage(SettingsKeys.scale) private var defaultScale = UpscaleOptions.Scale.x2.rawValue
    @AppStorage(SettingsKeys.autoCompare) private var autoCompare = true

    var body: some View {
        Form {
            Section {
                Picker("Стиль", selection: $defaultStyle) {
                    ForEach(UpscaleOptions.Style.allCases) { style in
                        Text(style.localizedTitle).tag(style.rawValue)
                    }
                }

                Picker("Шумоподавление", selection: $defaultDenoise) {
                    ForEach(UpscaleOptions.Denoise.allCases) { level in
                        Text(level.localizedTitle).tag(level.rawValue)
                    }
                }

                Picker("Масштаб", selection: $defaultScale) {
                    ForEach(UpscaleOptions.Scale.allCases) { scale in
                        Text("\(scale.rawValue)×").tag(scale.rawValue)
                    }
                }
            } header: {
                Text("Апскейл по умолчанию")
            }

            Section {
                Toggle("Сравнивать результат с оригиналом", isOn: $autoCompare)

                Text("Значения по умолчанию применяются к новым изображениям.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: defaultStyle) { _, _ in
            model.syncOptionsFromDefaults()
        }
        .onChange(of: defaultDenoise) { _, _ in
            model.syncOptionsFromDefaults()
        }
        .onChange(of: defaultScale) { _, _ in
            model.syncOptionsFromDefaults()
        }
    }
}

// MARK: - Движок

private struct EngineSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 8) {
                    StatusDot(color: Theme.engineColor(for: model.engineStatus.kind))
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.engineStatus.title)
                            .font(.callout.weight(.medium))

                        Text(model.engineStatus.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if model.isPreparingEngine {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if model.engineStatus.kind == .fallback {
                    Text("Core ML недоступен — используется резервный Lanczos-движок.")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Проверить модели") {
                    model.prepareEngine(force: true)
                }
                .controlSize(.small)
                .disabled(model.isPreparingEngine)
            } header: {
                Text("Состояние")
            }

            Section {
                Text("10 моделей waifu2x UpConv7 · 2× · Core ML")
                    .font(.callout)

                Text("Обработка выполняется локально. Изображения не покидают Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Благодарности

private struct CreditsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Waifu2x")
                        .font(.title3.weight(.semibold))
                    Text("Апскейлер изображений для macOS")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                creditLine("waifu2x", "© nagadomi")
                creditLine("Caffe-реализация", "© lltcggie")
                creditLine("Core ML-конверсия", "© imxieyi")
                creditLine("Лицензия", "MIT License")
            }
            .font(.callout)

            Button("github.com/nagadomi/waifu2x") {
                if let url = URL(string: "https://github.com/nagadomi/waifu2x") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .help("Открыть репозиторий waifu2x в браузере")

            Divider()

            Text("MIT License")
                .font(.caption.weight(.semibold))

            ScrollView {
                Text(Self.mitLicense)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 132)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
            )

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func creditLine(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 126, alignment: .leading)
            Text(value)
        }
    }

    private static let mitLicense = """
    MIT License

    Copyright (c) 2015 nagadomi

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}
