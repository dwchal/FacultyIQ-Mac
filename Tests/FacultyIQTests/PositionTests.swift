import XCTest
@testable import FacultyIQ

/// Authorship-position analytics: independent h-index, topic roles, the
/// independence trajectory, mentorship pairs, and the position-aware
/// misattribution heuristic.
final class PositionTests: XCTestCase {
    private func author(_ id: String, position: AuthorPosition? = nil,
                        corresponding: Bool? = nil) -> WorkAuthor {
        WorkAuthor(openalexID: id, displayName: id, position: position,
                   isCorresponding: corresponding)
    }

    private func work(_ id: String, year: Int? = 2020, cites: Int = 0,
                      topic: String? = nil, field: String? = nil,
                      authors: [WorkAuthor]? = nil) -> Work {
        Work(id: id, title: id, year: year, date: nil, type: nil, citedByCount: cites,
             doi: nil, isOA: nil, oaStatus: nil, venue: nil, authors: authors,
             topicName: topic, topicField: field)
    }

    private func personData(_ works: [Work], authorID: String = "A1") -> PersonData {
        PersonData(
            profile: AuthorProfile(openalexID: authorID, displayName: "Me",
                                   worksCount: works.count,
                                   citedByCount: works.map(\.citedByCount).reduce(0, +),
                                   hIndex: nil, i10Index: nil, affiliation: nil,
                                   countsByYear: []),
            works: works, fetchedAt: Date())
    }

    // MARK: Independent h-index

    func testIndependentHIndexCountsOnlyLedWorks() {
        let data = personData([
            work("W1", cites: 10, authors: [author("A1", position: .first)]),
            work("W2", cites: 10, authors: [author("A1", position: .last)]),
            work("W3", cites: 10, authors: [author("A1", position: .middle, corresponding: true)]),
            work("W4", cites: 100, authors: [author("A1", position: .middle)]),  // not led
            work("W5", cites: 100, authors: [author("A1", position: .middle)]),  // not led
        ])
        // Led citations [10, 10, 10] → h = 3, despite two 100-cite middle works.
        XCTAssertEqual(MetricsEngine.independentHIndex(data: data, authorID: "A1"), 3)
    }

    func testIndependentHIndexNilWithoutPositionData() {
        let data = personData([
            work("W1", cites: 50, authors: [author("A1")]),  // pre-position fetch
            work("W2", cites: 50),
        ])
        XCTAssertNil(MetricsEngine.independentHIndex(data: data, authorID: "A1"))
    }

    // MARK: Topic roles

    func testPersonTopicRolesSplitLedFromContributed() {
        let data = personData([
            work("W1", topic: "Sepsis", authors: [author("A1", position: .first)]),
            work("W2", topic: "Sepsis", authors: [author("A1", position: .middle)]),
            work("W3", topic: "Sepsis", authors: [author("A1", position: .last)]),
            work("W4", topic: "Imaging", authors: [author("A1", position: .middle)]),
        ])
        let roles = MetricsEngine.personTopicRoles(data: data)
        XCTAssertEqual(roles.first?.name, "Sepsis")
        XCTAssertEqual(roles.first?.works, 3)
        XCTAssertEqual(roles.first?.led, 2)
        XCTAssertEqual(roles.last?.led, 0)
    }

    func testTopicCountsTrackLedWorks() {
        let a = personData([
            work("W1", topic: "Sepsis", authors: [author("A1", position: .last), author("B1", position: .first)]),
            work("W2", topic: "Sepsis", authors: [author("A1", position: .middle)]),
        ], authorID: "A1")
        // Shared work W1: B1 is first author, so it's led from B's side too;
        // the cohort counts it once.
        let b = personData([
            work("W1", topic: "Sepsis", authors: [author("A1", position: .last), author("B1", position: .first)]),
        ], authorID: "B1")
        let counts = MetricsEngine.topicCounts(personData: [a, b])
        XCTAssertEqual(counts.first?.works, 2)
        XCTAssertEqual(counts.first?.led, 1)
    }

    // MARK: Independence trajectory

    func testSeniorShareByYear() {
        let y = MetricsEngine.currentYear
        let data = personData([
            work("W1", year: y - 1, authors: [author("A1", position: .first)]),
            work("W2", year: y - 1, authors: [author("A1", position: .last)]),
            work("W3", year: y, authors: [author("A1", position: .last)]),
            work("W4", year: y, authors: [author("A1")]),  // unpositioned: skipped
        ])
        let shares = MetricsEngine.seniorShareByYear(data: data, authorID: "A1")
        XCTAssertEqual(shares.map(\.year), [y - 1, y])
        XCTAssertEqual(shares[0].share, 50)
        XCTAssertEqual(shares[1].share, 100)
        XCTAssertEqual(shares[1].positioned, 1)
    }

    func testSeniorTransitionYearFindsCrossover() {
        let y = MetricsEngine.currentYear
        let first = { (year: Int) in self.work("F\(year)", year: year, authors: [self.author("A1", position: .first)]) }
        let last = { (id: String, year: Int) in self.work(id, year: year, authors: [self.author("A1", position: .last)]) }
        let data = personData([
            first(y - 8), first(y - 7),
            last("L1", y - 5), last("L2", y - 4),
            last("L3", y - 1), last("L4", y),
        ])
        // First 3-year window with ≥2 last-author works and last ≥ first: y-4.
        XCTAssertEqual(MetricsEngine.seniorTransitionYear(data: data, authorID: "A1"), y - 4)
    }

    func testSeniorTransitionYearNilWhenNeverOrSlippedBack() {
        let y = MetricsEngine.currentYear
        let allFirst = personData([
            work("W1", year: y - 1, authors: [author("A1", position: .first)]),
            work("W2", year: y, authors: [author("A1", position: .first)]),
        ])
        XCTAssertNil(MetricsEngine.seniorTransitionYear(data: allFirst, authorID: "A1"))

        // Crossed years ago but the current window is first-author again.
        let slipped = personData([
            work("L1", year: y - 8, authors: [author("A1", position: .last)]),
            work("L2", year: y - 7, authors: [author("A1", position: .last)]),
            work("F1", year: y - 1, authors: [author("A1", position: .first)]),
            work("F2", year: y, authors: [author("A1", position: .first)]),
        ])
        XCTAssertNil(MetricsEngine.seniorTransitionYear(data: slipped, authorID: "A1"))
    }

    func testSeniorTransitionYearAnchorsAtLastActiveYear() {
        // An emeritus member who crossed decades ago and then stopped
        // publishing: the crossover must not be hidden just because the
        // current calendar window is empty.
        let y = MetricsEngine.currentYear
        let data = personData([
            work("F1", year: y - 30, authors: [author("A1", position: .first)]),
            work("F2", year: y - 29, authors: [author("A1", position: .first)]),
            work("L1", year: y - 25, authors: [author("A1", position: .last)]),
            work("L2", year: y - 24, authors: [author("A1", position: .last)]),
            work("L3", year: y - 20, authors: [author("A1", position: .last)]),
            work("L4", year: y - 19, authors: [author("A1", position: .last)]),
            // A sparse tail (one late senior work, below the 2-work window
            // threshold) must not hide the crossover either.
            work("L5", year: y - 10, authors: [author("A1", position: .last)]),
        ])
        XCTAssertEqual(MetricsEngine.seniorTransitionYear(data: data, authorID: "A1"), y - 24)
    }

    func testPersonMetricsCarriesPositionFields() {
        let y = MetricsEngine.currentYear
        let member = FacultyMember(name: "Alice")
        let data = personData([
            work("W1", year: y, cites: 5, authors: [author("A1", position: .last)]),
            work("W2", year: y - 1, cites: 5, authors: [author("A1", position: .first)]),
            work("W3", year: y - 20, cites: 5, authors: [author("A1", position: .first)]),
        ])
        let m = MetricsEngine.personMetrics(member: member, data: data)
        XCTAssertEqual(m.positionTracked, 3)
        XCTAssertEqual(m.firstAuthorWorks, 2)
        XCTAssertEqual(m.seniorAuthorWorks, 1)
        XCTAssertEqual(m.seniorShare5y, 50)  // last-author on 1 of 2 recent positioned works
        XCTAssertEqual(m.independentHIndex, 3)

        let csv = MetricsEngine.metricsCSV(metrics: [m], roster: [member])
        XCTAssertTrue(csv.contains("Independent h-index,First Author Works,Senior Author Works,Senior Share 5y %"))
        XCTAssertTrue(csv.contains("Alice"))
    }

    // MARK: Mentorship pairs

    func testMentorshipEdgesPairSeniorWithFirstAuthor() {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        let resolutions = [
            alice.id: Resolution(openalexID: "A1", displayName: "Alice", method: .manual),
            bob.id: Resolution(openalexID: "B1", displayName: "Bob", method: .manual),
        ]
        let shared1 = work("W1", authors: [author("B1", position: .first),
                                           author("X1", position: .middle),
                                           author("A1", position: .last)])
        let shared2 = work("W2", authors: [author("B1", position: .first),
                                           author("A1", position: .last)])
        // Reverse pairing on W3, and a solo-authored work that must not self-pair.
        let reversed = work("W3", authors: [author("A1", position: .first),
                                            author("B1", position: .last)])
        let solo = work("W4", authors: [author("A1", position: .first),
                                        author("A1", position: .last)])
        let edges = MetricsEngine.mentorshipEdges(
            roster: [alice, bob],
            resolutions: resolutions,
            personData: [alice.id: personData([shared1, shared2, reversed, solo], authorID: "A1"),
                         bob.id: personData([shared1, shared2, reversed], authorID: "B1")])
        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges[0].mentor, alice.id)  // heaviest first
        XCTAssertEqual(edges[0].mentee, bob.id)
        XCTAssertEqual(edges[0].weight, 2)         // shared works counted once, not per member
        XCTAssertEqual(edges[1].mentor, bob.id)
        XCTAssertEqual(edges[1].weight, 1)

        let csv = MetricsEngine.mentorshipCSV(edges: edges, roster: [alice, bob])
        XCTAssertTrue(csv.hasPrefix("Senior Author (mentor),First Author (mentee),Shared Works\n"))
        XCTAssertTrue(csv.contains("Alice,Bob,2\n"))
    }

    func testMentorshipEdgesPreferPositionedCopyOfSharedWork() {
        let alice = FacultyMember(name: "Alice")
        let bob = FacultyMember(name: "Bob")
        let resolutions = [
            alice.id: Resolution(openalexID: "A1", displayName: "Alice", method: .manual),
            bob.id: Resolution(openalexID: "B1", displayName: "Bob", method: .manual),
        ]
        // The same work in two members' lists: one copy predates position
        // tracking. The positioned copy must win no matter the iteration order.
        let positioned = work("W1", authors: [author("B1", position: .first),
                                              author("A1", position: .last)])
        let stale = work("W1", authors: [author("B1"), author("A1")])
        for data in [[alice.id: personData([positioned], authorID: "A1"),
                      bob.id: personData([stale], authorID: "B1")],
                     [alice.id: personData([stale], authorID: "A1"),
                      bob.id: personData([positioned], authorID: "B1")]] {
            let edges = MetricsEngine.mentorshipEdges(
                roster: [alice, bob], resolutions: resolutions, personData: data)
            XCTAssertEqual(edges.count, 1)
            XCTAssertEqual(edges.first?.mentor, alice.id)
        }
    }

    // MARK: Position-aware misattribution

    func testSuspectWorksSparedWhenLedUnlessSingleExcursion() {
        var works = (1...100).map { work("M\($0)", field: "Medicine",
                                         authors: [author("A1", position: .middle)]) }
        // Threshold is max(1, 2% of tagged) = 2. Economics (2 works, led) is
        // spared; Chemistry (2 works, middle) stays flagged; the single led
        // Physics excursion is still flagged.
        works += [work("E1", field: "Economics", authors: [author("A1", position: .first)]),
                  work("E2", field: "Economics", authors: [author("A1", position: .last)]),
                  work("C1", field: "Chemistry", authors: [author("A1", position: .middle)]),
                  work("C2", field: "Chemistry", authors: [author("A1", position: .middle)]),
                  work("P1", field: "Physics", authors: [author("A1", position: .first)])]
        let flagged = MetricsEngine.suspectWorkIDs(works: works, authorID: "A1")
        XCTAssertEqual(flagged, ["C1", "C2", "P1"])
        // Without an author ID the original field-only rule applies.
        XCTAssertEqual(MetricsEngine.suspectWorkIDs(works: works),
                       ["E1", "E2", "C1", "C2", "P1"])
    }
}
