import AppKit
import SwiftUI

enum Theme {
    // Layout
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarIdealWidth: CGFloat = 264
    static let sidebarMaxWidth: CGFloat = 300
    static let inspectorMinWidth: CGFloat = 284
    static let inspectorIdealWidth: CGFloat = 304
    static let inspectorMaxWidth: CGFloat = 340
    static let detailMinWidth: CGFloat = 480
    static let thumbnailSize: CGFloat = 44
    static let cardCornerRadius: CGFloat = 10

    // Surfaces
    static var canvasBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    static var hairline: Color {
        Color(nsColor: .separatorColor)
    }

    static var cardBorder: Color {
        Color(nsColor: .separatorColor).opacity(0.75)
    }

    static var barBorder: Color {
        Color(nsColor: .separatorColor).opacity(0.8)
    }

    static var cardShadow: Color {
        Color.black.opacity(0.22)
    }

    static func statusColor(for status: ItemStatus) -> Color {
        switch status {
        case .queued:
            return Color(nsColor: .tertiaryLabelColor)
        case .processing:
            return Color.accentColor
        case .done:
            return Color(nsColor: .systemGreen)
        case .failed:
            return Color(nsColor: .systemOrange)
        }
    }

    static func engineColor(for kind: EngineStatus.Kind) -> Color {
        switch kind {
        case .coreML:
            return Color(nsColor: .systemGreen)
        case .fallback:
            return Color(nsColor: .systemOrange)
        case .unavailable:
            return Color(nsColor: .systemRed)
        }
    }
}

// MARK: - Localized copy for engine types

extension UpscaleOptions.Style {
    var localizedTitle: String {
        switch self {
        case .anime: return L10n.t("Аниме и арт")
        case .photo: return L10n.t("Фото")
        }
    }
}

extension UpscaleOptions.Denoise {
    var localizedTitle: String {
        switch self {
        case .off: return L10n.t("Выкл.")
        case .minimal: return L10n.t("Минимум")
        case .low: return L10n.t("Слабое")
        case .medium: return L10n.t("Среднее")
        case .high: return L10n.t("Сильное")
        }
    }
}

extension EngineStatus.Kind {
    var shortLabel: String {
        switch self {
        case .coreML: return "Core ML"
        case .fallback: return "Lanczos"
        case .unavailable: return L10n.t("Недоступен")
        }
    }
}

// MARK: - Small shared formatting helpers

enum Formatting {
    static func pixelSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
    }

    static func compactPixelSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    static func imagesCount(_ count: Int) -> String {
        L10n.imagesCount(count)
    }
}
