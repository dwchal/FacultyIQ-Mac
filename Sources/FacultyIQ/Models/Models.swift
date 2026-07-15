import Foundation

// MARK: - Roster

struct FacultyMember: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var email: String?
    var rank: String?
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

// MARK: - Shared helpers

extension Collection where Element: BinaryFloatingPoint {
    /// Median of the collection; 0 when empty.
    var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted().map { Double($0) }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
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
