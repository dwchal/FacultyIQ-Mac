import XCTest
@testable import FacultyIQ

final class SortingTests: XCTestCase {
    private func key(_ name: String) -> String {
        FacultyMember(name: name).surnameSortKey
    }

    func testSurnameSortKey() {
        XCTAssertEqual(key("Omar Abu Saleh"), "saleh")
        XCTAssertEqual(key("Mary Jo Kasten"), "kasten")
        XCTAssertEqual(key("Douglas R. Osmon"), "osmon")
        XCTAssertEqual(key("Doe, John"), "doe")
        XCTAssertEqual(key("Abu Saleh, Omar"), "saleh")
        XCTAssertEqual(key("José García"), "garcia")
        XCTAssertEqual(key("John Smith Jr."), "smith")
        XCTAssertEqual(key("Sam Jones III"), "jones")
        XCTAssertEqual(key("Priya Sampathkumar MD"), "sampathkumar")
        XCTAssertEqual(key("Cher"), "cher")
    }

    func testAlphabeticalBySurname() {
        let names = ["Mary Jo Kasten", "Omar Abu Saleh", "Elie Berbari", "Aaron Tande"]
        let sorted = names.map { FacultyMember(name: $0) }
            .sorted { ($0.surnameSortKey, $0.name) < ($1.surnameSortKey, $1.name) }
            .map(\.name)
        XCTAssertEqual(sorted, ["Elie Berbari", "Mary Jo Kasten", "Omar Abu Saleh", "Aaron Tande"])
    }
}
