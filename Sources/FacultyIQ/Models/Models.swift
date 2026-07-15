import Foundation

// MARK: - Roster

struct FacultyMember: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var email: String?
    var rank: String?
    var division: String?
    var lastPromotionYear: Int?
    var hireYear: Int?
    var assistantStartYear: Int?
    var associateStartYear: Int?
    var fullStartYear: Int?
    var selfReportedPubs: Int?
    var scopusID: String?
    var scholarID: String?
    var orcid: String?
    var semanticScholarID: String?
    var associations: String?
}

enum AcademicRank: Int, CaseIterable, Comparable {
    case instructor = 1
    case assistant = 2
    case associate = 3
    case full = 4

    static func < (lhs: AcademicRank, rhs: AcademicRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .instructor: "Instructor"
        case .assistant: "Assistant Professor"
        case .associate: "Associate Professor"
        case .full: "Full Professor"
        }
    }

    var next: AcademicRank? {
        AcademicRank(rawValue: rawValue + 1)
    }

    /// Standardize free-text rank strings, mirroring the R app's standardize_rank().
    static func parse(_ raw: String?) -> AcademicRank? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if s.contains("instructor") || s.contains("lecturer") { return .instructor }
        if s.contains("assistant") { return .assistant }
        if s.contains("associate") { return .associate }
        if s.contains("full") || s == "professor" { return .full }
        return nil
    }
}

// MARK: - Resolution

enum ResolutionMethod: String, Codable {
    case orcid = "ORCID"
    case scopus = "Scopus ID"
    case manual = "Manual search"
}

struct Resolution: Codable, Hashable {
    var openalexID: String       // short form, e.g. "A5070446713"
    var displayName: String
    var method: ResolutionMethod
    var affiliation: String?
    var orcid: String?
}

/// A candidate author returned by search or ID lookup.
struct AuthorCandidate: Identifiable, Hashable {
    var openalexID: String
    var displayName: String
    var worksCount: Int
    var citedByCount: Int
    var hIndex: Int?
    var i10Index: Int?
    var affiliation: String?
    var orcid: String?

    var id: String { openalexID }
}

// MARK: - Fetched data

struct YearCount: Codable, Hashable {
    var year: Int
    var worksCount: Int
    var citedByCount: Int
}

struct AuthorProfile: Codable, Hashable {
    var openalexID: String
    var displayName: String
    var worksCount: Int
    var citedByCount: Int
    var hIndex: Int?
    var i10Index: Int?
    var affiliation: String?
    var countsByYear: [YearCount]
}

struct Work: Identifiable, Codable, Hashable {
    var id: String               // short form, e.g. "W1986407511"
    var title: String
    var year: Int?
    var date: String?
    var type: String?
    var citedByCount: Int
    var doi: String?
    var pmid: String? = nil      // nil = not PubMed-indexed, or fetched before pmids were tracked
    var isOA: Bool?
    var oaStatus: String?
    var venue: String?
    var authors: [WorkAuthor]?   // nil = fetched before authorships were tracked
}

struct WorkAuthor: Codable, Hashable {
    var openalexID: String       // short form, e.g. "A5070446713"
    var displayName: String
}

struct PersonData: Codable, Hashable {
    var profile: AuthorProfile
    var works: [Work]
    var fetchedAt: Date
}

// MARK: - Computed metrics

struct PersonMetrics: Identifiable, Hashable {
    var memberID: UUID
    var name: String
    var rank: AcademicRank?
    var rawRank: String?
    var worksCount: Int
    var citations: Int
    var hIndex: Int
    var i10Index: Int
    var citationsPerWork: Double
    var worksPerYear: Double
    var oaPercent: Double?       // nil when no works carry OA info
    var recentWorks5y: Int
    var firstPubYear: Int?
    var careerYears: Int

    var id: UUID { memberID }
}

struct DivisionSummary {
    var facultyCount: Int
    var resolvedCount: Int
    var totalWorks: Int
    var totalCitations: Int
    var medianHIndex: Double
    var medianWorksPerYear: Double
    var oaPercent: Double?
}

struct RankBenchmark: Identifiable {
    var rank: AcademicRank
    var count: Int
    var medianWorks: Double
    var medianCitations: Double
    var medianHIndex: Double
    var medianWorksPerYear: Double
    // Promotion targets: the 25th percentile of current rank-holders — the
    // low end of the rank, since accumulated medians overstate the bar
    // people actually cleared at promotion.
    var targetWorks: Double
    var targetCitations: Double
    var targetHIndex: Double

    var id: Int { rank.rawValue }
}

/// One pair of roster members with shared publications. Members are ordered
/// canonically (memberA.uuidString < memberB.uuidString) so each pair appears once.
struct CoauthorEdge: Identifiable, Hashable {
    var memberA: UUID
    var memberB: UUID
    var weight: Int              // number of distinct shared works

    var id: String { "\(memberA.uuidString)|\(memberB.uuidString)" }

    func involves(_ member: UUID) -> Bool { memberA == member || memberB == member }

    func other(than member: UUID) -> UUID? {
        if memberA == member { return memberB }
        if memberB == member { return memberA }
        return nil
    }
}

struct CoauthorNode: Identifiable, Hashable {
    var memberID: UUID
    var name: String
    var rank: AcademicRank?      // parsed; nil when unknown/unparseable
    var worksCount: Int          // works fetched for this member
    var degree: Int              // distinct roster coauthors
    var sharedWorks: Int         // sum of edge weights touching this node

    var id: UUID { memberID }
}

struct CoauthorNetwork {
    var nodes: [CoauthorNode]    // resolved + fetched members, sorted by name
    var edges: [CoauthorEdge]    // sorted by weight desc, then id
    var staleAuthorData: Bool    // some member's works predate authorship tracking
}

struct PromotionCandidate: Identifiable {
    var metrics: PersonMetrics
    var currentRank: AcademicRank
    var targetRank: AcademicRank
    var exceededMetrics: [String] // e.g. ["Works", "h-index"]

    var id: UUID { metrics.memberID }
}

/// One member's standing against the next rank's median benchmarks.
struct PromotionProgress: Identifiable {
    struct MetricCheck: Identifiable {
        var label: String        // "Works", "Citations", "h-index"
        var value: Int
        var benchmark: Double

        var met: Bool { Double(value) >= benchmark }
        /// How much is missing to reach the benchmark (0 when met).
        var gap: Int { max(0, Int(benchmark.rounded(.up)) - value) }
        var id: String { label }
    }

    var metrics: PersonMetrics
    var currentRank: AcademicRank
    var targetRank: AcademicRank
    var checks: [MetricCheck]

    var metCount: Int { checks.count(where: \.met) }
    /// 0…3, how far along the three metrics are (each capped at its benchmark).
    var closeness: Double {
        checks.map { min(Double($0.value) / max($0.benchmark, 1), 1) }.reduce(0, +)
    }
    var id: UUID { metrics.memberID }
}

// MARK: - Trends & prediction

/// Recent-versus-prior activity comparison (last 3 calendar years vs the 3 before).
struct TrendMetrics {
    var recentYears: ClosedRange<Int>
    var priorYears: ClosedRange<Int>
    var recentWorks: Int
    var priorWorks: Int
    var recentCitations: Int
    var priorCitations: Int
    var worksGrowth: Double?      // percent change; nil when the prior window is 0
    var citationsGrowth: Double?
}

/// Time-to-target estimate for one unmet promotion check at the current pace.
struct TrajectoryProjection: Identifiable {
    var label: String             // matches PromotionProgress.MetricCheck.label
    var current: Int
    var target: Double
    var perYear: Double           // fitted pace (units per year)
    var yearsToTarget: Double

    var targetYear: Int { MetricsEngine.currentYear + Int(yearsToTarget.rounded(.up)) }
    var id: String { label }
}

/// Nearest-rank prediction from the weighted rank-distance model.
struct RankPrediction {
    var rank: AcademicRank
    var confidence: Double        // 0…1, 1 − d₁/d₂
}

// MARK: - Shared helpers

extension Collection where Element: BinaryFloatingPoint {
    /// Median of the collection; 0 when empty.
    var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted().map { Double($0) }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Linearly interpolated percentile (0...1), the R-7/NumPy default; 0 when empty.
    func percentile(_ p: Double) -> Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted().map { Double($0) }
        let position = p.clamped(to: 0...1) * Double(sorted.count - 1)
        let lower = Int(position)
        guard lower + 1 < sorted.count else { return sorted[lower] }
        return sorted[lower] + (position - Double(lower)) * (sorted[lower + 1] - sorted[lower])
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension String {
    /// Extract the first plausible 4-digit year (1900–2099) from a messy date string.
    var extractedYear: Int? {
        guard let range = self.range(of: #"(19|20)\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return Int(self[range])
    }

    /// Strip the OpenAlex URL prefix: "https://openalex.org/A123" -> "A123".
    var shortOpenAlexID: String {
        replacingOccurrences(of: "https://openalex.org/", with: "")
    }
}
