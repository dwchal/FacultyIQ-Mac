import Foundation

/// Metrics over the enrichment sources (iCite RCR, NIH funding).
extension MetricsEngine {
    // MARK: iCite

    /// Mean Relative Citation Ratio across the works iCite scored; nil when
    /// no works carry RCR data.
    static func meanRCR(works: [Work], icite: ICiteData?) -> Double? {
        guard let icite else { return nil }
        let values = works.compactMap { work in
            work.pmid.flatMap { icite.byPMID[$0]?.rcr }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Median of the per-person mean RCRs in view; nil when no one has data.
    static func medianRCR(roster: [FacultyMember],
                          personData: [UUID: PersonData],
                          enrichment: [UUID: Enrichment]) -> Double? {
        let means = roster.compactMap { member in
            personData[member.id].flatMap {
                meanRCR(works: $0.works, icite: enrichment[member.id]?.icite)
            }
        }
        return means.isEmpty ? nil : means.median
    }

    // MARK: NIH funding

    /// NIH "R01-equivalent" research activity codes.
    static let r01EquivalentCodes: Set<String> = [
        "R01", "R23", "R29", "R37", "R56", "RF1", "RL1", "U01", "DP1", "DP2", "DP5",
    ]

    struct FundingSummary {
        var totalAwarded: Int
        var grantCount: Int
        var activeCount: Int
        var r01EquivalentCount: Int
    }

    static func fundingSummary(_ grants: [Grant]) -> FundingSummary {
        let active = grants.count { grant in
            if let endYear = grant.endDate?.extractedYear {
                endYear >= currentYear
            } else {
                (grant.fiscalYears.last ?? 0) >= currentYear - 1
            }
        }
        return FundingSummary(
            totalAwarded: grants.map(\.totalAward).reduce(0, +),
            grantCount: grants.count,
            activeCount: active,
            r01EquivalentCount: grants.count {
                $0.activityCode.map(r01EquivalentCodes.contains) ?? false
            })
    }

    static func grantsCSV(roster: [FacultyMember],
                          enrichment: [UUID: Enrichment]) -> String {
        var lines = ["Name,Core Project,Activity,Title,Organization,First FY,Latest FY,Total Award"]
        for member in roster.sorted(by: { $0.name < $1.name }) {
            for grant in enrichment[member.id]?.grants?.grants ?? [] {
                lines.append([
                    member.name,
                    grant.coreProjectNum,
                    grant.activityCode ?? "",
                    grant.title,
                    grant.orgName ?? "",
                    grant.fiscalYears.first.map(String.init) ?? "",
                    grant.fiscalYears.last.map(String.init) ?? "",
                    String(grant.totalAward),
                ].map(csvEscape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
