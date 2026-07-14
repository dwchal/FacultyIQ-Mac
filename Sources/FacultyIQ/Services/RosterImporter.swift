import Foundation

/// Imports a faculty roster CSV, mapping messy survey-style headers onto
/// FacultyMember fields with keyword heuristics (mirrors the R app's
/// utils_validation column mapping).
enum RosterImporter {
    enum ImportError: LocalizedError {
        case unreadable
        case noHeader
        case noNameColumn

        var errorDescription: String? {
            switch self {
            case .unreadable: "Could not read the file as text (UTF-8)."
            case .noHeader: "The file appears to be empty."
            case .noNameColumn: "No column matching \"Name\" was found in the header row."
            }
        }
    }

    static func importRoster(from url: URL) throws -> [FacultyMember] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }
        return try importRoster(fromText: text)
    }

    static func importRoster(fromText text: String) throws -> [FacultyMember] {
        let rows = CSVParser.parse(text)
        guard let header = rows.first else { throw ImportError.noHeader }
        let mapping = mapColumns(header)
        guard mapping[.name] != nil else { throw ImportError.noNameColumn }

        return rows.dropFirst().compactMap { row in
            func value(_ field: Field) -> String? {
                guard let idx = mapping[field], idx < row.count else { return nil }
                let v = row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }
            guard let name = value(.name) else { return nil }
            return FacultyMember(
                name: name,
                email: value(.email),
                rank: value(.rank),
                lastPromotionYear: value(.lastPromotion)?.extractedYear,
                hireYear: value(.hireDate)?.extractedYear,
                assistantStartYear: value(.assistantStart)?.extractedYear,
                associateStartYear: value(.associateStart)?.extractedYear,
                fullStartYear: value(.fullStart)?.extractedYear,
                selfReportedPubs: value(.selfReportedPubs).flatMap { Int($0) },
                scopusID: value(.scopusID)?.filter(\.isNumber).nilIfEmpty,
                scholarID: value(.scholarID),
                orcid: value(.orcid).map(cleanORCID),
                semanticScholarID: value(.semanticScholarID),
                associations: value(.associations)
            )
        }
    }

    enum Field: CaseIterable {
        case name, email, rank, lastPromotion, hireDate
        case assistantStart, associateStart, fullStart
        case selfReportedPubs, scopusID, scholarID, orcid, semanticScholarID
        case associations
    }

    /// Match each field to the best header column by keyword.
    static func mapColumns(_ header: [String]) -> [Field: Int] {
        let lowered = header.map { $0.lowercased() }
        var mapping: [Field: Int] = [:]

        func firstIndex(where predicate: (String) -> Bool) -> Int? {
            lowered.firstIndex(where: predicate)
        }

        // Exact "name" wins; otherwise a column containing "name" that isn't
        // a username/display-name style column.
        mapping[.name] = firstIndex { $0 == "name" || $0 == "full name" || $0 == "faculty name" }
            ?? firstIndex { $0.contains("name") && !$0.contains("username") && !$0.contains("user name") }
        mapping[.email] = firstIndex { $0.contains("email") || $0.contains("e-mail") }
        mapping[.rank] = firstIndex { $0.contains("rank") }
        mapping[.lastPromotion] = firstIndex { $0.contains("promotion") }
        mapping[.hireDate] = firstIndex { $0.contains("hire") }
        mapping[.assistantStart] = firstIndex { $0.contains("assistant") && ($0.contains("start") || $0.contains("date")) }
        mapping[.associateStart] = firstIndex { $0.contains("associate") && ($0.contains("start") || $0.contains("date")) }
        mapping[.fullStart] = firstIndex { $0.contains("full") && ($0.contains("start") || $0.contains("date")) }
        mapping[.selfReportedPubs] = firstIndex { $0.contains("reaims") || ($0.contains("publication") && $0.contains("how many")) }
            ?? firstIndex { $0.contains("publication") && $0.contains("count") }
        mapping[.scopusID] = firstIndex { $0.contains("scopus") }
        mapping[.scholarID] = firstIndex { $0.contains("scholar") && !$0.contains("semantic") }
        mapping[.orcid] = firstIndex { $0.contains("orcid") }
        mapping[.semanticScholarID] = firstIndex { $0.contains("semantic") }
        mapping[.associations] = firstIndex { $0.contains("association") || $0.contains("specialty") }
        return mapping.compactMapValues { $0 }
    }

    /// Normalize ORCID input: accepts bare IDs or orcid.org URLs.
    static func cleanORCID(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://orcid.org/", "http://orcid.org/", "orcid.org/"] {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
            }
        }
        return s
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
