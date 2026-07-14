import AppKit
import SwiftUI

/// Chart colors: a CVD-validated categorical palette with per-appearance
/// steps (light / dark selected separately, not auto-flipped). Series slots
/// are assigned in fixed order and never cycled.
enum ChartPalette {
    static let series1 = dynamicColor(light: 0x2A78D6, dark: 0x3987E5) // blue
    static let series2 = dynamicColor(light: 0x1BAF7A, dark: 0x199E70) // aqua
    static let series3 = dynamicColor(light: 0xEDA100, dark: 0xC98500) // yellow
    static let series4 = dynamicColor(light: 0x008300, dark: 0x008300) // green

    /// Lighter sequential step of the series-1 blue, for secondary emphasis.
    static let series1Light = dynamicColor(light: 0x86B6EF, dark: 0x1C5CAB)

    static let positive = dynamicColor(light: 0x006300, dark: 0x0CA30C)
    static let critical = dynamicColor(light: 0xD03B3B, dark: 0xD03B3B)

    private static func dynamicColor(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
