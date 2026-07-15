import SwiftUI

// Print-styled building blocks shared by the report page builders. Flat
// fills only (materials like .quaternary don't render in ImageRenderer),
// and no AppKit-backed views.

enum ReportStyle {
    static let pageMargin: CGFloat = 36
    static let cardFill = Color(.sRGB, white: 0.955)
    static let barTrack = Color(.sRGB, white: 0.88)
    static let rowRule = Color(.sRGB, white: 0.85)

    static var generatedLine: String {
        "generated \(Date().formatted(date: .abbreviated, time: .omitted))"
    }
}

/// Full-page scaffold: margins, top-leading content, footer line.
struct ReportPage<Content: View>: View {
    let footer: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Spacer(minLength: 0)
            Text(footer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(ReportStyle.pageMargin)
        .foregroundStyle(.black)
    }
}

struct ReportTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ReportStyle.cardFill, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// ProgressView replacement that renders in ImageRenderer: a capsule track
/// with a proportional fill.
struct ReportBar: View {
    let fraction: Double     // 0…1
    let color: Color
    var width: CGFloat = 180

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(ReportStyle.barTrack)
            Capsule().fill(color)
                .frame(width: max(width * fraction.clamped(to: 0...1), 3))
        }
        .frame(width: width, height: 6)
    }
}
