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

    func testTrendGrowth() throws {
        // Prior window (y-5…y-3): 2 works; recent window (y-2…y): 3 works.
        let data = personData(
            workYears: [year - 5, year - 4, year - 2, year - 1, year],
            citations: [year - 4: 10, year - 1: 15])
        // Year fully elapsed → plain 3y-vs-3y comparison: 3 vs 2 = +50%.
        let trend = MetricsEngine.trendMetrics(data: data, currentYearFraction: 1)
        XCTAssertEqual(trend.priorWorks, 2)
        XCTAssertEqual(trend.recentWorks, 3)
        XCTAssertEqual(try XCTUnwrap(trend.worksGrowth), 50, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(trend.citationsGrowth), 50, accuracy: 1e-9)
    }

    func testTrendGrowthProRatesCurrentYear() throws {
        // 1 work per year in both windows. Halfway through the current year
        // the recent window spans 2.5 years, so a raw count comparison would
        // show a slump; the annualized rate should show +20%.
        let data = personData(workYears: [year - 5, year - 4, year - 3,
                                          year - 2, year - 1, year])
        let trend = MetricsEngine.trendMetrics(data: data, currentYearFraction: 0.5)
        let growth = try XCTUnwrap(trend.worksGrowth)
        XCTAssertEqual(growth, 20, accuracy: 1e-9)   // (3/2.5) / (3/3) − 1
        XCTAssertEqual(trend.currentYearFraction, 0.5)

        // And the default fraction stays in bounds.
        XCTAssertTrue((0...1).contains(MetricsEngine.currentYearFraction))
    }

    func testDivisionTrendSumsAcrossCohort() throws {
        // Two people, each 1 work/yr in the prior window; person B doubles
        // output in the recent window. Cohort: prior 6, recent 9 → +50%
        // at a fully elapsed year.
        let a = personData(workYears: [year - 5, year - 4, year - 3,
                                       year - 2, year - 1, year])
        let b = personData(workYears: [year - 5, year - 4, year - 3,
                                       year - 2, year - 2, year - 1, year - 1, year, year])
        let trend = MetricsEngine.divisionTrend(personData: [a, b], currentYearFraction: 1)
        XCTAssertEqual(trend.priorWorks, 6)
        XCTAssertEqual(trend.recentWorks, 9)
        XCTAssertEqual(try XCTUnwrap(trend.worksGrowth), 50, accuracy: 1e-9)
    }

    func testTrendGrowthNilWhenPriorWindowEmpty() {
        let data = personData(workYears: [year, year - 1])
        let trend = MetricsEngine.trendMetrics(data: data, currentYearFraction: 0.5)
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

    func testCareerMedianNilBelowMinimumPool() {
        let a = personData(workYears: [year - 2, year - 1, year])
        let b = personData(workYears: [year - 4, year])
        XCTAssertNil(MetricsEngine.careerMedianSeries(personData: [a, b], span: 3))
    }

    func testCareerMedianUsesFixedPoolAndStaysMonotone() {
        // Two 10-year careers with one early work each, two 4-year careers
        // with steady output. The per-year-pool median used to jump to the
        // high performers early and dip once they aged out; the balanced
        // panel fixes the pool (all four) and trims the span to what they
        // all cover, so the line can only rise.
        let longA = personData(workYears: [year - 9])
        let longB = personData(workYears: [year - 9])
        let shortC = personData(workYears: [year - 3, year - 2, year - 1, year])
        let shortD = personData(workYears: [year - 3, year - 2, year - 1, year])

        let median = MetricsEngine.careerMedianSeries(
            personData: [longA, longB, shortC, shortD], span: 10)
        XCTAssertEqual(median?.span, 4)      // longest stretch ≥3 members cover
        XCTAssertEqual(median?.poolSize, 4)
        XCTAssertEqual(median?.series.map(\.median), [1, 1.5, 2, 2.5])
        // A junior member's chart only asks for their own span; the pool
        // stays fixed over that shorter range.
        let junior = MetricsEngine.careerMedianSeries(
            personData: [longA, longB, shortC, shortD], span: 2)
        XCTAssertEqual(junior?.span, 2)
        XCTAssertEqual(junior?.poolSize, 4)
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
