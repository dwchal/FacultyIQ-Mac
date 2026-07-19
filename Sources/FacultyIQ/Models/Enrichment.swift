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

// MARK: - Scopus (Elsevier)

/// Author-level metrics from Scopus — the counts promotion committees
/// typically require, kept alongside the OpenAlex numbers for comparison.
struct ScopusAuthorMetrics: Codable, Hashable {
    var scopusAuthorID: String
    var documentCount: Int?
    var citedByCount: Int?       // documents citing this author
    var citationCount: Int?      // total citations received
    var hIndex: Int?
    var currentAffiliation: String?
}

/// Journal quality metrics from the Scopus Serial Title API, keyed by ISSN.
struct ScopusJournalMetrics: Codable, Hashable {
    var issn: String
    var title: String?
    var citeScore: Double?
    var citeScoreYear: Int?
    var topPercentile: Double?   // best subject-area CiteScore percentile, 0…99
    var snip: Double?
    var sjr: Double?

    /// CiteScore quartile from the best subject-area percentile (Q1 = top 25%).
    var quartile: Int? {
        guard let topPercentile else { return nil }
        switch topPercentile {
        case 75...: return 1
        case 50..<75: return 2
        case 25..<50: return 3
        default: return 4
        }
    }
}

/// One document on the author's Scopus record, for coverage cross-checks.
struct ScopusDocRef: Codable, Hashable {
    var eid: String              // e.g. "2-s2.0-85141234567"
    var doi: String?
    var title: String?
    var coverDate: String?
}

struct ScopusData: Codable, Hashable {
    var author: ScopusAuthorMetrics?
    var journalByISSN: [String: ScopusJournalMetrics]
    var documents: [ScopusDocRef]?  // nil until the coverage audit fetches them
    var fetchedAt: Date
}

/// An author candidate from a Scopus name search — like RePORTER PI search,
/// name matching is fuzzy, so metrics are only attached after the user
/// confirms a candidate (which also writes the ID back to the roster).
struct ScopusAuthorCandidate: Identifiable, Hashable {
    var scopusID: String
    var name: String
    var affiliation: String?
    var city: String?
    var documentCount: Int?

    var id: String { scopusID }
}

// MARK: - ClinicalTrials.gov

/// One registered trial where the member is an overall official.
struct ClinicalTrial: Codable, Hashable, Identifiable {
    var nctID: String            // e.g. "NCT04280705"
    var title: String
    var status: String?          // e.g. "RECRUITING", "COMPLETED"
    var phase: String?           // e.g. "PHASE3", "PHASE2/PHASE3"
    var role: String?            // PRINCIPAL_INVESTIGATOR | STUDY_CHAIR | STUDY_DIRECTOR
    var sponsor: String?
    var startDate: String?       // "YYYY-MM" or "YYYY-MM-DD"
    var completionDate: String?
    var enrollment: Int?

    var id: String { nctID }
}

struct TrialsData: Codable, Hashable {
    var trials: [ClinicalTrial]
    var fetchedAt: Date
}

// MARK: - Peer benchmark cohort

/// Where a member stands within a random OpenAlex sample of authors active on
/// their dominant topic — field-wide context the division's internal
/// benchmarks can't give.
struct PeerCohortData: Codable, Hashable {
    var topicName: String
    var topicID: String          // OpenAlex topic, e.g. "T10624"
    var cohortSize: Int
    var worksPercentile: Double  // member's standing in the cohort, 0…100
    var citationsPercentile: Double
    var hIndexPercentile: Double
    var fetchedAt: Date
}

// MARK: - Container

struct Enrichment: Codable, Hashable {
    var icite: ICiteData?
    var grants: GrantData?
    var semanticScholar: S2Data?
    var peerCohort: PeerCohortData?
    var scopus: ScopusData?
    var trials: TrialsData?

    /// Core project numbers the user removed by hand (RePORTER name matching
    /// occasionally attaches someone else's grant). Kept separate from
    /// GrantData, which is replaced wholesale on re-attach, so removals
    /// survive every future fetch.
    var excludedGrants: Set<String>? = nil

    /// The given grants minus the ones the user removed by hand.
    func filteringExcluded(_ grants: [Grant]) -> [Grant] {
        guard let excludedGrants, !excludedGrants.isEmpty else { return grants }
        return grants.filter { !excludedGrants.contains($0.coreProjectNum) }
    }
}

extension String {
    /// Normalize a DOI for dictionary keys: lowercase, no resolver prefix.
    var bareDOI: String {
        lowercased()
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
    }
}
