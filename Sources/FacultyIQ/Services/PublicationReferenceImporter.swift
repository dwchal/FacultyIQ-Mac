import Foundation

/// Reads the common files faculty export from ORCID, reference managers, and
/// CV systems. Matching is handled separately so parsing remains testable.
enum PublicationReferenceImporter {
    enum ImportError: LocalizedError {
        case unreadable
        case unsupported
        case noRecords

        var errorDescription: String? {
            switch self {
            case .unreadable: "Could not read the publication file as text."
            case .unsupported: "Use a BibTeX (.bib), RIS (.ris), or CSV file."
            case .noRecords: "No publications with titles were found in that file."
            }
        }
    }

    static func importFile(_ url: URL, memberID: UUID) throws -> [ImportedPublication] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }
        let format: PublicationImportFormat
        switch url.pathExtension.lowercased() {
        case "bib", "bibtex": format = .bibtex
        case "ris": format = .ris
        case "csv": format = .csv
        default: throw ImportError.unsupported
        }
        let records = try importText(text, format: format, memberID: memberID)
        guard !records.isEmpty else { throw ImportError.noRecords }
        return records
    }

    static func importText(_ text: String, format: PublicationImportFormat,
                           memberID: UUID) throws -> [ImportedPublication] {
        let values: [(title: String, doi: String?, year: Int?)]
        switch format {
        case .bibtex: values = bibtex(text)
        case .ris: values = ris(text)
        case .csv: values = csv(text)
        }
        return values.compactMap { value in
            let title = clean(value.title)
            guard !title.isEmpty else { return nil }
            return ImportedPublication(
                memberID: memberID, title: title,
                doi: value.doi.map(normalizeDOI)?.nilIfEmpty,
                year: value.year, sourceFormat: format)
        }
    }

    private static func ris(_ text: String) -> [(String, String?, Int?)] {
        var result: [(String, String?, Int?)] = []
        var title: String?
        var doi: String?
        var year: Int?
        for line in text.components(separatedBy: .newlines) {
            guard line.count >= 2 else { continue }
            let tag = String(line.prefix(2)).uppercased()
            let value = line.range(of: "  - ").map {
                String(line[$0.upperBound...]).trimmingCharacters(in: .whitespaces)
            } ?? ""
            switch tag {
            case "TI", "T1":
                if title == nil { title = value }
            case "DO": doi = value
            case "PY", "Y1": year = value.extractedYear
            case "ER":
                if let title { result.append((title, doi, year)) }
                title = nil
                doi = nil
                year = nil
            default: break
            }
        }
        if let title { result.append((title, doi, year)) }
        return result
    }

    private static func bibtex(_ text: String) -> [(String, String?, Int?)] {
        entryBlocks(text).compactMap { block in
            guard let title = bibField("title", in: block) else { return nil }
            let doi = bibField("doi", in: block)
            let year = bibField("year", in: block)?.extractedYear
            return (title, doi, year)
        }
    }

    /// Split at top-level BibTeX entries while respecting nested braces in
    /// titles. This is intentionally a reference importer, not a full BibTeX
    /// interpreter; concatenated macros are left as their visible text.
    private static func entryBlocks(_ text: String) -> [String] {
        var blocks: [String] = []
        var start: String.Index?
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "@", depth == 0 { start = index }
            if start != nil {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0, let blockStart = start {
                        blocks.append(String(text[blockStart...index]))
                        start = nil
                    }
                }
            }
            index = text.index(after: index)
        }
        return blocks
    }

    private static func bibField(_ name: String, in block: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?is)\b\#(escaped)\s*=\s*(?:\{((?:[^{}]|\{[^{}]*\})*)\}|\"([^\"]*)\"|([^,\n}]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block))
        else { return nil }
        for capture in 1...3 where match.range(at: capture).location != NSNotFound {
            if let range = Range(match.range(at: capture), in: block) {
                return String(block[range])
            }
        }
        return nil
    }

    private static func csv(_ text: String) -> [(String, String?, Int?)] {
        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return [] }
        let normalized = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let titleIndex = normalized.firstIndex {
            $0 == "title" || $0.contains("publication title") || $0.contains("work title")
        }
        guard let titleIndex else { return [] }
        let doiIndex = normalized.firstIndex { $0 == "doi" || $0.contains("digital object") }
        let yearIndex = normalized.firstIndex { $0 == "year" || $0.contains("publication year") }
        return rows.dropFirst().compactMap { row in
            guard titleIndex < row.count else { return nil }
            let doi = doiIndex.flatMap { $0 < row.count ? row[$0] : nil }
            let year = yearIndex.flatMap { $0 < row.count ? row[$0].extractedYear : nil }
            return (row[titleIndex], doi, year)
        }
    }

    static func normalizeDOI(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .bareDOI
            .replacingOccurrences(of: "doi:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedTitle(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
