import Foundation

/// Minimal RFC 4180 CSV parser: handles quoted fields, escaped quotes, and
/// newlines inside quotes. Returns rows of fields.
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var i = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            // Skip rows that are entirely empty
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    endField()
                case "\n", "\r\n": // CRLF is a single Character in Swift
                    endRow()
                case "\r":
                    endRow()
                default:
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}
