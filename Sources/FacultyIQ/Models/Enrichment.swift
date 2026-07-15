import Foundation

// Optional per-member data from the enrichment sources (NIH iCite, NIH
// RePORTER, Semantic Scholar), fetched in a separate opt-in phase after the
// OpenAlex fetch and persisted alongside — but separate from — PersonData,
// which is replaced wholesale on refetch.

// MARK: - NIH iCite

/// Field-normalized citation metrics for one PubMed-indexed work.
struct WorkCitationMetrics: Codable, Hashable {
    var pmid: String
    var rcr: Double?             // relative_citation_ratio (1.0 = NIH field average)
    var nihPercentile: Double?
    var citationsPerYear: Double?
    var apt: Double?             // approximate potential to translate (0…1)
}

struct ICiteData: Codable, Hashable {
    var byPMID: [String: WorkCitationMetrics]
    var fetchedAt: Date
}

// MARK: - NIH RePORTER

/// One NIH project, with its fiscal-year rows collapsed onto the core
/// project number.
struct Grant: Codable, Hashable, Identifiable {
    var coreProjectNum: String   // e.g. "U24HG007346"
    var latestProjectNum: String // e.g. "5U24HG007346-08"
    var title: String
    var activityCode: String?    // e.g. "R01"
    var fiscalYears: [Int]       // sorted ascending
    var totalAward: Int          // summed award_amount across fiscal years
    var startDate: String?
    var endDate: String?
    var orgName: String?
    var awardsByFiscalYear: [Int: Int]? = nil  // FY → awarded; nil = pre-breakdown fetch

    var id: String { coreProjectNum }
}

struct GrantData: Codable, Hashable {
    var grants: [Grant]
    var confirmedProfileID: Int  // RePORTER PI profile id the grants belong to
    var confirmedPIName: String?
    var fetchedAt: Date
}

/// A principal-investigator candidate from a RePORTER name search — name
/// search is fuzzy, so grants are only attached to a confirmed profile.
struct PICandidate: Identifiable, Hashable {
    var profileID: Int
    var name: String
    var orgName: String?
    var projectCount: Int        // distinct core projects
    var latestFiscalYear: Int?

    var id: Int { profileID }
}

// MARK: - Semantic Scholar

struct S2Data: Codable, Hashable {
    var authorID: String
    var hIndex: Int?
    var paperCount: Int?
    var citationCount: Int?
    var influentialByDOI: [String: Int]  // bare lowercase DOI → influential citations
    var fetchedAt: Date
}

// MARK: - Container

struct Enrichment: Codable, Hashable {
    var icite: ICiteData?
    var grants: GrantData?
    var semanticScholar: S2Data?
}

extension String {
    /// Normalize a DOI for dictionary keys: lowercase, no resolver prefix.
    var bareDOI: String {
        lowercased()
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
    }
}
