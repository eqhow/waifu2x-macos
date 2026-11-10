import Foundation

/// Runtime localization for strings that aren't SwiftUI `LocalizedStringKey`
/// literals (AppKit panels, engine status, errors, dynamic labels).
///
/// Russian is the source language. `Support/Resources/en.lproj` contains the
/// English translations; `ru.lproj` marks Russian as available. macOS chooses
/// the matching localization from the user's system language, falling back to
/// English for every other language.
enum L10n {
    static var languageCode: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru") ? "ru" : "en"
    }

    static var isRussian: Bool { languageCode == "ru" }

    static var locale: Locale { Locale(identifier: languageCode) }

    /// Localizes a runtime string key against the main app bundle.
    static func t(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }

    /// Localizes a format string and substitutes arguments.
    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: arguments)
    }

    static func imagesCount(_ count: Int) -> String {
        if isRussian {
            let mod100 = count % 100
            let mod10 = count % 10
            let word: String
            if mod100 >= 11 && mod100 <= 14 {
                word = "изображений"
            } else if mod10 == 1 {
                word = "изображение"
            } else if mod10 >= 2 && mod10 <= 4 {
                word = "изображения"
            } else {
                word = "изображений"
            }
            return "\(count) \(word)"
        }
        return count == 1 ? "1 image" : "\(count) images"
    }
}
