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

// MARK: - NSF Awards

/// One NSF award. NSF has no core-project grouping like RePORTER's — each
/// award ID is its own record — so awards map one-to-one onto API rows.
struct NSFAward: Codable, Hashable, Identifiable {
    var awardID: String          // e.g. "2548111"
    var title: String
    var agency: String           // "NSF"
    var program: String?
    var organization: String?
    var piName: String?
    var isPI: Bool               // false = matched as a co-PI
    var startDate: Date?
    var endDate: Date?
    var totalAward: Int          // estimated total, falling back to obligated

    var id: String { awardID }
}

struct NSFData: Codable, Hashable {
    var awards: [NSFAward]
    var confirmedPIName: String  // the name string the awards were confirmed against
    var fetchedAt: Date
}

// MARK: - Work-level funders (OpenAlex)

/// A funder credited on the cohort's publications, from OpenAlex work grants.
/// Unlike RePORTER and NSF this needs no name matching — the funder is
/// recorded on the paper itself — so it covers every agency and foundation at
/// once, at the cost of knowing only "who funded this paper", not amounts.
struct FunderCredit: Identifiable, Hashable {
    var funderID: String         // OpenAlex funder ID, e.g. "F4320306076"
    var name: String
    var works: Int               // distinct cohort works crediting this funder
    var people: Int              // roster members with ≥1 work crediting it
    var awardCount: Int          // distinct award IDs seen

    var id: String { funderID }
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

// MARK: - OpenAlex journal metrics (keyless Scopus fallback)

/// Journal quality from the OpenAlex sources index, keyed by linking ISSN.
/// Keyless and available to everyone, unlike Scopus CiteScore — so this is
/// the default tier, upgraded per journal wherever Scopus data exists.
///
/// `twoYearMeanCitedness` is OpenAlex's impact-factor analogue (mean citations
/// in the last two years). It has no published quartile, so quartiles here are
/// derived within the cohort's own venue set rather than against all journals
/// in the field — a relative reading, and labeled as such in the UI.
struct OpenAlexJournalMetrics: Codable, Hashable {
    var issn: String
    var sourceID: String         // e.g. "S62468778"
    var title: String?
    var twoYearMeanCitedness: Double?
    var hIndex: Int?
    var worksCount: Int?
    var isOA: Bool?
    var isInDOAJ: Bool?
}

/// Cohort-wide journal metrics fetched from OpenAlex, stored once for the
/// whole workspace rather than per member — journals are shared across the
/// roster, and the lookup is keyed by ISSN either way.
struct OpenAlexJournalData: Codable, Hashable {
    var byISSN: [String: OpenAlexJournalMetrics]
    var fetchedAt: Date
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
    /// Peer institutions the sample was restricted to; nil for the
    /// unrestricted field-wide sample. Optional (not defaulted-non-optional)
    /// so archives saved before this field existed still decode.
    var institutionNames: [String]? = nil
}

/// One institution in the user-curated peer-benchmark list, resolved to its
/// OpenAlex ID via institution-name search.
struct PeerInstitution: Identifiable, Codable, Hashable {
    var id: String            // OpenAlex short institution ID, e.g. "I1330342723"
    var displayName: String
}

// MARK: - Container

struct Enrichment: Codable, Hashable {
    var icite: ICiteData?
    var grants: GrantData?
    var semanticScholar: S2Data?
    var peerCohort: PeerCohortData?
    var peerInstitutionCohort: PeerCohortData?
    var scopus: ScopusData?
    var trials: TrialsData?
    var nsf: NSFData?

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
