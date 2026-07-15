import AppKit
import SwiftUI

/// Composes SwiftUI pages into a single vector PDF via ImageRenderer's
/// CGContext path (text stays selectable, charts stay crisp). Report pages
/// must avoid AppKit-backed views — Table, ScrollView, List — which
/// ImageRenderer silently drops; build tables with Grid instead. Pages are
/// forced to light appearance so the appearance-dynamic palette colors
/// resolve to their light variants on paper.
@MainActor
enum PDFComposer {
    /// US Letter in PDF points.
    nonisolated static let letterSize = CGSize(width: 612, height: 792)

    static func write(pages: [AnyView], pageSize: CGSize = letterSize, to url: URL) throws {
        guard !pages.isEmpty else { throw PDFError.noPages }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFError.cannotCreateContext
        }
        for page in pages {
            let renderer = ImageRenderer(content:
                page
                    .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            )
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, render in
                context.beginPDFPage(nil)
                render(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
    }

    enum PDFError: LocalizedError {
        case noPages
        case cannotCreateContext

        var errorDescription: String? {
            switch self {
            case .noPages: "There is nothing to export yet."
            case .cannotCreateContext: "Could not create the PDF file."
            }
        }
    }
}
