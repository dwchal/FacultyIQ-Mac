import Foundation

/// Trend, trajectory, and rank-prediction analytics — the counterpart of the
/// Shiny app's utils_prediction.R plus linear time-to-target projections.
extension MetricsEngine {
    // MARK: Per-year maps

    /// Works published per year, from the fetched work records.
    static func worksByYear(_ data: PersonData) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for work in data.works {
            if let y = work.year { counts[y, default: 0] += 1 }
        }
        return counts
    }

    /// Citations received per year, from the profile's counts_by_year
    /// (OpenAlex covers roughly the last decade).
    static func citationsByYear(_ data: PersonData) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: data.profile.countsByYear.map { ($0.year, $0.citedByCount) })
    }

    // MARK: Growth

    /// Recent-versus-prior comparison: the last three calendar years against
    /// the three before that.
    static func trendMetrics(data: PersonData) -> TrendMetrics {
        let y = currentYear
        let recentYears = (y - 2)...y
        let priorYears = (y - 5)...(y - 3)
        func sum(_ map: [Int: Int], _ range: ClosedRange<Int>) -> Int {
            range.reduce(0) { $0 + (map[$1] ?? 0) }
        }
        func growth(recent: Int, prior: Int) -> Double? {
            prior > 0 ? 100 * Double(recent - prior) / Double(prior) : nil
        }
        let works = worksByYear(data)
        let cites = citationsByYear(data)
        let recentWorks = sum(works, recentYears)
        let priorWorks = sum(works, priorYears)
        let recentCitations = sum(cites, recentYears)
        let priorCitations = sum(cites, priorYears)
        return TrendMetrics(
            recentYears: recentYears,
            priorYears: priorYears,
            recentWorks: recentWorks,
            priorWorks: priorWorks,
            recentCitations: recentCitations,
            priorCitations: priorCitations,
            worksGrowth: growth(recent: recentWorks, prior: priorWorks),
            citationsGrowth: growth(recent: recentCitations, prior: priorCitations)
        )
    }

    /// Works per year over the trailing `span` years, zero-filled so
    /// sparklines have a point for every year.
    static func worksSparkline(data: PersonData, span: Int = 10) -> [(year: Int, count: Int)] {
        let byYear = worksByYear(data)
        return ((currentYear - span + 1)...currentYear).map { (year: $0, count: byYear[$0] ?? 0) }
    }

    // MARK: Linear trajectory

    /// Least-squares fit; nil with fewer than two points or no x variance.
    static func linearTrend(points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double)? {
        guard points.count >= 2 else { return nil }
        let n = Double(points.count)
        let meanX = points.map(\.x).reduce(0, +) / n
        let meanY = points.map(\.y).reduce(0, +) / n
        let sxx = points.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let sxy = points.map { ($0.x - meanX) * ($0.y - meanY) }.reduce(0, +)
        let slope = sxy / sxx
        return (slope: slope, intercept: meanY - slope * meanX)
    }

    /// Years until `current` reaches `target` at `perYear`; nil when already
    /// met or when the pace is flat or negative.
    static func yearsToBenchmark(current: Double, perYear: Double, target: Double) -> Double? {
        guard current < target, perYear > 0 else { return nil }
        return (target - current) / perYear
    }

    /// Cumulative totals through each of the trailing `span` years — the
    /// series whose least-squares slope is the person's current pace.
    static func cumulativePoints(byYear: [Int: Int], span: Int = 5) -> [(x: Double, y: Double)] {
        let firstYear = currentYear - span + 1
        var running = byYear.filter { $0.key < firstYear }.values.reduce(0, +)
        return (firstYear...currentYear).map { year in
            running += byYear[year] ?? 0
            return (x: Double(year), y: Double(running))
        }
    }

    /// Time-to-target projections for a member's unmet next-rank checks.
    /// Works and citations project from the trailing five-year pace; the
    /// h-index has no meaningful linear pace and is never projected.
    static func trajectoryProjections(data: PersonData,
                                      promotion: PromotionProgress) -> [TrajectoryProjection] {
        let paces: [String: Double] = [
            "Works": linearTrend(points: cumulativePoints(byYear: worksByYear(data)))?.slope,
            "Citations": linearTrend(points: cumulativePoints(byYear: citationsByYear(data)))?.slope,
        ].compactMapValues(\.self)
        return promotion.checks.compactMap { check in
            guard !check.met, let pace = paces[check.label],
                  let years = yearsToBenchmark(current: Double(check.value),
                                               perYear: pace, target: check.benchmark)
            else { return nil }
            return TrajectoryProjection(
                label: check.label, current: check.value, target: check.benchmark,
                perYear: pace, yearsToTarget: years)
        }
    }

    // MARK: Career-normalized comparison

    /// Cumulative works by career year (years since first publication).
    static func careerWorksSeries(data: PersonData) -> [(careerYear: Int, cumulativeWorks: Int)] {
        let byYear = worksByYear(data)
        guard let firstYear = byYear.keys.min(), firstYear <= currentYear else { return [] }
        var running = 0
        return (firstYear...currentYear).map { year in
            running += byYear[year] ?? 0
            return (careerYear: year - firstYear + 1, cumulativeWorks: running)
        }
    }

    /// Median cumulative works at each career year across the cohort, at
    /// career years where at least two people have reached that point.
    static func careerMedianSeries(personData: [PersonData]) -> [(careerYear: Int, median: Double)] {
        let seriesList = personData.map { careerWorksSeries(data: $0) }.filter { !$0.isEmpty }
        guard let longest = seriesList.map(\.count).max(), seriesList.count >= 2 else { return [] }
        return (1...longest).compactMap { t in
            let values = seriesList.compactMap { $0.count >= t ? Double($0[t - 1].cumulativeWorks) : nil }
            guard values.count >= 2 else { return nil }
            return (careerYear: t, median: values.median)
        }
    }

    // MARK: Rank prediction

    /// Feature weights from the Shiny app's compute_rank_distances().
    private static let predictionFeatures: [(extract: (PersonMetrics) -> Double, weight: Double)] = [
        ({ Double($0.worksCount) }, 1.0),
        ({ Double($0.citations) }, 1.0),
        ({ Double($0.hIndex) }, 1.5),
        ({ Double($0.i10Index) }, 0.8),
        ({ Double($0.careerYears) }, 0.5),
        ({ $0.worksPerYear }, 0.7),
    ]

    /// Port of predict_faculty_rank(): weighted normalized distance from the
    /// member's metrics to each rank's median profile; the nearest rank wins,
    /// with confidence 1 − d₁/d₂. Each feature is scaled by the spread of the
    /// rank medians so dimensions are comparable; features whose medians don't
    /// separate the ranks carry no signal and are skipped. Needs at least two
    /// ranks in the cohort.
    static func rankPrediction(for member: PersonMetrics,
                               cohort: [PersonMetrics]) -> RankPrediction? {
        let byRank = Dictionary(grouping: cohort.filter { $0.rank != nil }, by: { $0.rank! })
        guard byRank.count >= 2 else { return nil }

        let medians = byRank.mapValues { group in
            predictionFeatures.map { feature in group.map(feature.extract).median }
        }
        var distances: [(rank: AcademicRank, distance: Double)] = []
        for (rank, rankMedians) in medians {
            var distance = 0.0
            var weightSum = 0.0
            for (i, feature) in predictionFeatures.enumerated() {
                let featureMedians = medians.values.map { $0[i] }
                let spread = featureMedians.max()! - featureMedians.min()!
                guard spread > 0 else { continue }
                distance += feature.weight * abs(feature.extract(member) - rankMedians[i]) / spread
                weightSum += feature.weight
            }
            guard weightSum > 0 else { return nil }
            distances.append((rank, distance / weightSum))
        }
        let sorted = distances.sorted { $0.distance < $1.distance }
        let best = sorted[0]
        let confidence = sorted.count >= 2 && sorted[1].distance > 0
            ? (1 - best.distance / sorted[1].distance).clamped(to: 0...1)
            : 0
        return RankPrediction(rank: best.rank, confidence: confidence)
    }
}
