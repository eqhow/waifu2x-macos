import Foundation
import CoreGraphics

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Waifu2x"

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] else {
    exit(1)
}

for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
    guard owner == target, layer == 0, alpha > 0 else { continue }
    if let number = window[kCGWindowNumber as String] as? Int {
        print(number)
        exit(0)
    }
}

exit(2)
