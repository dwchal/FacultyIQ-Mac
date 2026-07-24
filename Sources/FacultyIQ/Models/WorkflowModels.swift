import Foundation

// MARK: - Saved cohorts

/// A named, explicit faculty set that can be reused as the scope for every
/// analysis tab. IDs rather than copied roster rows keep edits to a member in
/// sync while allowing arbitrary cross-division cohorts.
struct SavedCohort: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var memberIDs: Set<UUID>
    var createdAt = Date()
    var updatedAt = Date()
}

// MARK: - Funding opportunities

/// Compact Grants.gov search result. The radar deliberately persists only the
/// public catalog fields it displays; full announcements remain on Grants.gov.
struct FundingOpportunity: Identifiable, Codable, Hashable {
    var id: String
    var number: String
    var title: String
    var agencyCode: String
    var agencyName: String
    var openDate: Date?
    var closeDate: Date?
    var status: String
    var assistanceListings: [String]
    var matchedQuery: String
    var fetchedAt: Date

    var detailsURL: URL? {
        URL(string: "https://www.grants.gov/search-results-detail/\(id)")
    }
}

// MARK: - Publication reconciliation

enum PublicationImportFormat: String, Codable, CaseIterable {
    case bibtex = "BibTeX"
    case ris = "RIS"
    case csv = "CSV"
}

enum ReconciliationDisposition: String, Codable, CaseIterable {
    case pending
    case resolved
    case ignored

    var label: String {
        switch self {
        case .pending: "Pending"
        case .resolved: "Resolved"
        case .ignored: "Ignored"
        }
    }
}

/// One publication imported from a CV/reference export for comparison with a
/// member's OpenAlex record.
struct ImportedPublication: Identifiable, Codable, Hashable {
    var id = UUID()
    var memberID: UUID
    var title: String
    var doi: String?
    var year: Int?
    var sourceFormat: PublicationImportFormat
    var importedAt = Date()
    var disposition: ReconciliationDisposition = .pending
}

enum ReconciliationMatchKind: Int, Comparable {
    case missing = 0
    case title = 1
    case doi = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .missing: "Missing"
        case .title: "Title match"
        case .doi: "DOI match"
        }
    }
}

struct ReconciliationMatch: Identifiable {
    var imported: ImportedPublication
    var kind: ReconciliationMatchKind
    var matchedWork: Work?

    var id: UUID { imported.id }
}
