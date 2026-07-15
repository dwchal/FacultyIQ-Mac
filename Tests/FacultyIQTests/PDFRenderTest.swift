import XCTest
@testable import FacultyIQ

final class WorkChunkingTests: XCTestCase {
    private func works(_ n: Int) -> [Work] {
        (0..<n).map {
            Work(id: "W\($0)", title: "Work \($0)", year: 2020, date: nil, type: nil,
                 citedByCount: 1000 - $0, doi: nil, isOA: nil, oaStatus: nil,
                 venue: nil, authors: nil)
        }
    }

    func testChunkingMath() {
        XCTAssertTrue(DossierPages.workChunks([]).isEmpty)
        XCTAssertEqual(DossierPages.workChunks(works(5)).map(\.count), [5])
        XCTAssertEqual(DossierPages.workChunks(works(22)).map(\.count), [22])
        XCTAssertEqual(DossierPages.workChunks(works(23)).map(\.count), [22, 1])
        // Capped at the top-works limit (44 → two full pages).
        XCTAssertEqual(DossierPages.workChunks(works(500)).map(\.count), [22, 22])
    }

    func testChunksAreTopCited() {
        let chunks = DossierPages.workChunks(works(100).shuffled())
        XCTAssertEqual(chunks[0].first?.citedByCount, 1000)
        let flat = chunks.flatMap { $0 }
        XCTAssertEqual(flat, flat.sorted { $0.citedByCount > $1.citedByCount })
    }
}

/// Writes the dossier + summary PDFs from fixtures and checks page counts.
/// Set RENDER_OUT=<dir> to keep the PDFs for visual inspection; otherwise
/// they go to a temporary directory.
final class PDFRenderTest: XCTestCase {
    private let year = MetricsEngine.currentYear

    private func fixtures() -> (member: FacultyMember, data: PersonData, metrics: PersonMetrics) {
        var member = FacultyMember(name: "Sarah Chen")
        member.rank = "Associate Professor"
        member.division = "Infectious Diseases"
        member.orcid = "0000-0002-1825-0097"
        let works = (0..<30).map { i in
            Work(id: "W\(i)", title: "A longer paper title about antimicrobial stewardship and outcomes, part \(i)",
                 year: year - (i % 12), date: nil, type: "article",
                 citedByCount: 400 - i * 12, doi: "https://doi.org/10.0/\(i)",
                 isOA: i.isMultiple(of: 2), oaStatus: "gold",
                 venue: "Clinical Infectious Diseases", authors: nil)
        }
        let counts = (0..<10).map { YearCount(year: year - $0, worksCount: 3, citedByCount: 800 - $0 * 40) }
        let data = PersonData(
            profile: AuthorProfile(openalexID: "A5000000001", displayName: "Sarah Chen",
                                   worksCount: works.count, citedByCount: 6200,
                                   hIndex: 24, i10Index: 40,
                                   affiliation: "University Medical Center",
                                   countsByYear: counts),
            works: works, fetchedAt: Date())
        let metrics = MetricsEngine.personMetrics(member: member, data: data)
        return (member, data, metrics)
    }

    @MainActor
    func testDossierAndSummaryPDFs() throws {
        let outDir = ProcessInfo.processInfo.environment["RENDER_OUT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let (member, data, metrics) = fixtures()
        let promotion = PromotionProgress(
            metrics: metrics, currentRank: .associate, targetRank: .full,
            checks: [
                .init(label: "Works", value: metrics.worksCount, benchmark: 60),
                .init(label: "Citations", value: metrics.citations, benchmark: 5000),
                .init(label: "h-index", value: metrics.hIndex, benchmark: 30),
            ])

        // Dossier: 30 works → overview + 2 works pages.
        let dossierURL = outDir.appendingPathComponent("test_dossier.pdf")
        try PDFComposer.write(
            pages: DossierPages.pages(member: member, data: data, resolution: nil,
                                      metrics: metrics, promotion: promotion),
            to: dossierURL)
        let dossier = try XCTUnwrap(CGPDFDocument(dossierURL as CFURL))
        XCTAssertEqual(dossier.numberOfPages, 3)

        // Summary from a two-person cohort.
        let summary = MetricsEngine.divisionSummary(
            roster: [member], resolvedCount: 1, metrics: [metrics])
        let summaryURL = outDir.appendingPathComponent("test_summary.pdf")
        try PDFComposer.write(
            pages: SummaryPages.pages(summary: summary, metrics: [metrics],
                                      personData: [data],
                                      benchmarks: MetricsEngine.rankBenchmarks(metrics: [metrics]),
                                      divisionName: "Infectious Diseases"),
            to: summaryURL)
        let report = try XCTUnwrap(CGPDFDocument(summaryURL as CFURL))
        XCTAssertEqual(report.numberOfPages, 2)

        let size = try XCTUnwrap(FileManager.default
            .attributesOfItem(atPath: dossierURL.path)[.size] as? Int)
        XCTAssertGreaterThan(size, 10_000, "suspiciously small PDF — pages may be blank")
    }
}
