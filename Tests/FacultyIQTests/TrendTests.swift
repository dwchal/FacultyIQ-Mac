import XCTest
@testable import FacultyIQ

final class TrendTests: XCTestCase {
    private let year = MetricsEngine.currentYear

    /// One work per entry in `workYears`; citation counts_by_year from `citations`.
    private func personData(workYears: [Int], citations: [Int: Int] = [:]) -> PersonData {
        let works = workYears.enumerated().map { i, y in
            Work(id: "W\(i)", title: "W\(i)", year: y, date: nil, type: nil,
                 citedByCount: 0, doi: nil, isOA: nil, oaStatus: nil, venue: nil, authors: nil)
        }
        let counts = citations.map { YearCount(year: $0.key, worksCount: 0, citedByCount: $0.value) }
        return PersonData(
            profile: AuthorProfile(openalexID: "A0", displayName: "", worksCount: works.count,
                                   citedByCount: citations.values.reduce(0, +),
                                   hIndex: nil, i10Index: nil, affiliation: nil,
                                   countsByYear: counts),
            works: works, fetchedAt: Date())
    }

    func testTrendGrowth() {
        // Prior window (y-5…y-3): 2 works; recent window (y-2…y): 3 works.
        let data = personData(
            workYears: [year - 5, year - 4, year - 2, year - 1, year],
            citations: [year - 4: 10, year - 1: 15])
        let trend = MetricsEngine.trendMetrics(data: data)
        XCTAssertEqual(trend.priorWorks, 2)
        XCTAssertEqual(trend.recentWorks, 3)
        XCTAssertEqual(trend.worksGrowth, 50)
        XCTAssertEqual(trend.citationsGrowth, 50)
    }

    func testTrendGrowthNilWhenPriorWindowEmpty() {
        let data = personData(workYears: [year, year - 1])
        let trend = MetricsEngine.trendMetrics(data: data)
        XCTAssertNil(trend.worksGrowth)
        XCTAssertNil(trend.citationsGrowth)
    }

    func testSparklineZeroFillsSpan() {
        let data = personData(workYears: [year, year, year - 9])
        let points = MetricsEngine.worksSparkline(data: data, span: 10)
        XCTAssertEqual(points.count, 10)
        XCTAssertEqual(points.first?.year, year - 9)
        XCTAssertEqual(points.first?.count, 1)
        XCTAssertEqual(points.last?.count, 2)
        XCTAssertEqual(points[1].count, 0)
    }

    func testLinearTrendFitsKnownLine() throws {
        let fit = try XCTUnwrap(MetricsEngine.linearTrend(
            points: [(1, 3), (2, 5), (3, 7), (4, 9)]))
        XCTAssertEqual(fit.slope, 2, accuracy: 1e-9)
        XCTAssertEqual(fit.intercept, 1, accuracy: 1e-9)
    }

    func testLinearTrendNilWithoutVariance() {
        XCTAssertNil(MetricsEngine.linearTrend(points: [(1, 2)]))
        XCTAssertNil(MetricsEngine.linearTrend(points: [(1, 2), (1, 5)]))
    }

    func testYearsToBenchmark() {
        XCTAssertEqual(MetricsEngine.yearsToBenchmark(current: 40, perYear: 5, target: 50), 2)
        XCTAssertNil(MetricsEngine.yearsToBenchmark(current: 50, perYear: 5, target: 50), "already met")
        XCTAssertNil(MetricsEngine.yearsToBenchmark(current: 40, perYear: 0, target: 50), "flat pace")
        XCTAssertNil(MetricsEngine.yearsToBenchmark(current: 40, perYear: -1, target: 50), "negative pace")
    }

    func testCumulativePointsCarryPriorTotal() {
        // 3 works before the window, then 1 per year in the window.
        let byYear = [year - 10: 3, year - 2: 1, year - 1: 1, year: 1]
        let points = MetricsEngine.cumulativePoints(byYear: byYear, span: 3)
        XCTAssertEqual(points.map(\.y), [4, 5, 6])
        XCTAssertEqual(points.first?.x, Double(year - 2))
    }

    func testTrajectoryProjectionsSkipMetAndUnprojectable() {
        // Steady 2 works/year for the last 5 years.
        let data = personData(workYears: (0..<5).flatMap { [year - $0, year - $0] })
        let metrics = PersonMetrics(
            memberID: UUID(), name: "X", rank: .associate, rawRank: nil,
            worksCount: 10, citations: 0, hIndex: 3, i10Index: 0,
            citationsPerWork: 0, worksPerYear: 2, oaPercent: nil,
            recentWorks5y: 10, firstPubYear: year - 4, careerYears: 5)
        let promotion = PromotionProgress(
            metrics: metrics, currentRank: .associate, targetRank: .full,
            checks: [
                .init(label: "Works", value: 10, benchmark: 16),      // unmet, 2/yr → 3 years
                .init(label: "Citations", value: 0, benchmark: 100),  // unmet, no citation pace
                .init(label: "h-index", value: 3, benchmark: 2),      // met
            ])
        let projections = MetricsEngine.trajectoryProjections(data: data, promotion: promotion)
        XCTAssertEqual(projections.map(\.label), ["Works"])
        XCTAssertEqual(projections[0].yearsToTarget, 3, accuracy: 1e-9)
        XCTAssertEqual(projections[0].targetYear, year + 3)
    }

    func testCareerWorksSeriesNormalizesToFirstPublication() {
        let data = personData(workYears: [year - 3, year - 3, year - 1])
        let series = MetricsEngine.careerWorksSeries(data: data)
        XCTAssertEqual(series.count, 4)
        XCTAssertEqual(series.map(\.careerYear), [1, 2, 3, 4])
        XCTAssertEqual(series.map(\.cumulativeWorks), [2, 2, 3, 3])
    }

    func testCareerMedianSeriesRequiresTwoPeople() {
        let a = personData(workYears: [year - 2, year - 1, year])
        XCTAssertTrue(MetricsEngine.careerMedianSeries(personData: [a]).isEmpty)

        let b = personData(workYears: [year - 4, year])
        let median = MetricsEngine.careerMedianSeries(personData: [a, b])
        // Overlap is limited to career years both have reached (a spans 3).
        XCTAssertEqual(median.count, 3)
        XCTAssertEqual(median[0].careerYear, 1)
        XCTAssertEqual(median[0].median, 1)
    }

    func testRankPrediction() {
        func metrics(_ name: String, rank: AcademicRank?, works: Int, cites: Int, h: Int,
                     years: Int) -> PersonMetrics {
            PersonMetrics(
                memberID: UUID(), name: name, rank: rank, rawRank: rank?.label,
                worksCount: works, citations: cites, hIndex: h, i10Index: h,
                citationsPerWork: 0, worksPerYear: Double(works) / Double(years),
                oaPercent: nil, recentWorks5y: 0, firstPubYear: nil, careerYears: years)
        }
        let cohort = [
            metrics("Asst A", rank: .assistant, works: 10, cites: 200, h: 5, years: 4),
            metrics("Asst B", rank: .assistant, works: 14, cites: 300, h: 6, years: 5),
            metrics("Full A", rank: .full, works: 120, cites: 6000, h: 35, years: 25),
            metrics("Full B", rank: .full, works: 150, cites: 8000, h: 40, years: 28),
        ]
        // A full-professor-shaped profile should predict .full decisively.
        let strong = metrics("Test", rank: .associate, works: 130, cites: 7000, h: 37, years: 26)
        let prediction = MetricsEngine.rankPrediction(for: strong, cohort: cohort)
        XCTAssertEqual(prediction?.rank, .full)
        XCTAssertGreaterThan(prediction?.confidence ?? 0, 0.5)

        // A single-rank cohort can't discriminate.
        XCTAssertNil(MetricsEngine.rankPrediction(for: strong, cohort: Array(cohort.prefix(2))))
    }
}
