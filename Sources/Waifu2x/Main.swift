import Foundation
import SwiftUI

@main
enum Waifu2xMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        // Headless mode is used for automated verification and power users:
        //   Waifu2x --upscale input.png --output out.png --noise 1 --scale 2
        if arguments.contains("--upscale") || arguments.contains("--help") || arguments.contains("--models") {
            exit(CLI.run(arguments))
        }

        Waifu2xApp.main()
    }
}
