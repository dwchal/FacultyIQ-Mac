import Foundation

extension MetricsEngine {
    // MARK: - Cohort comparison

    struct CohortSnapshot: Identifiable {
        var id: UUID
        var name: String
        var memberCount: Int
        var resolvedCount: Int
        var totalWorks: Int
        var totalCitations: Int
        var medianHIndex: Double
        var openAccessPercent: Double?
        var topTopics: [String]
    }

    static func cohortSnapshot(_ cohort: SavedCohort, roster: [FacultyMember],
                               resolutions: [UUID: Resolution],
                               personData: [UUID: PersonData]) -> CohortSnapshot {
        let members = roster.filter { cohort.memberIDs.contains($0.id) }
        let data = Dictionary(uniqueKeysWithValues: members.compactMap { member in
            personData[member.id].map { (member.id, $0) }
        })
        let metrics = allMetrics(roster: members, personData: data)
        let summary = divisionSummary(
            roster: members,
            resolvedCount: members.count { resolutions[$0.id] != nil },
            metrics: metrics)
        return CohortSnapshot(
            id: cohort.id,
            name: cohort.name,
            memberCount: members.count,
            resolvedCount: summary.resolvedCount,
            totalWorks: summary.totalWorks,
            totalCitations: summary.totalCitations,
            medianHIndex: summary.medianHIndex,
            openAccessPercent: summary.oaPercent,
            topTopics: topicCounts(personData: Array(data.values)).prefix(5).map(\.name))
    }

    // MARK: - Provenance and confidence

    struct ProvenanceEntry: Identifiable {
        var metric: String
        var source: String
        var value: String
        var fetchedAt: Date?
        var note: String?

        var id: String { "\(metric)|\(source)" }
    }

    struct DataConfidenceReport: Identifiable {
        var member: FacultyMember
        var score: Int
        var entries: [ProvenanceEntry]
        var warnings: [String]

        var id: UUID { member.id }
        var grade: String {
            switch score {
            case 90...: "Excellent"
            case 75..<90: "Good"
            case 55..<75: "Review"
            default: "Needs attention"
            }
        }
    }

    static func dataConfidence(member: FacultyMember, resolution: Resolution?,
                               data: PersonData?, enrichment: Enrichment?,
                               now: Date = Date()) -> DataConfidenceReport {
        guard let resolution, let data else {
            return DataConfidenceReport(
                member: member, score: 0, entries: [],
                warnings: [resolution == nil ? "Identity is unresolved." : "Metrics have not been fetched."])
        }

        let metrics = personMetrics(member: member, data: data)
        var score = 100
        var warnings: [String] = []
        var entries = [
            ProvenanceEntry(metric: "Identity", source: "OpenAlex",
                            value: resolution.displayName, fetchedAt: data.fetchedAt,
                            note: resolution.method.rawValue),
            ProvenanceEntry(metric: "Works", source: "OpenAlex",
                            value: metrics.worksCount.formatted(), fetchedAt: data.fetchedAt),
            ProvenanceEntry(metric: "Citations", source: "OpenAlex",
                            value: metrics.citations.formatted(), fetchedAt: data.fetchedAt),
            ProvenanceEntry(metric: "h-index", source: "OpenAlex",
                            value: metrics.hIndex.formatted(), fetchedAt: data.fetchedAt),
        ]

        if member.orcid?.isEmpty != false {
            score -= 8
            warnings.append("No ORCID is recorded for durable identity matching.")
        }
        if resolution.method == .manual {
            score -= 5
            warnings.append("Identity was selected by name rather than resolved from an external ID.")
        }

        let age = now.timeIntervalSince(data.fetchedAt) / 86_400
        if age > 30 {
            score -= 18
            warnings.append("OpenAlex data is more than 30 days old.")
        } else if age > 7 {
            score -= 6
            warnings.append("OpenAlex data is older than the seven-day cache window.")
        }

        if !data.works.isEmpty {
            let doiCoverage = Double(data.works.count { $0.doi != nil }) / Double(data.works.count)
            let authorCoverage = Double(data.works.count { $0.authors != nil }) / Double(data.works.count)
            let topicCoverage = Double(data.works.count { $0.topicName != nil }) / Double(data.works.count)
            entries.append(ProvenanceEntry(
                metric: "DOI coverage", source: "OpenAlex",
                value: doiCoverage.formatted(.percent.precision(.fractionLength(0))),
                fetchedAt: data.fetchedAt))
            entries.append(ProvenanceEntry(
                metric: "Topic coverage", source: "OpenAlex",
                value: topicCoverage.formatted(.percent.precision(.fractionLength(0))),
                fetchedAt: data.fetchedAt))
            if doiCoverage < 0.5 {
                score -= 8
                warnings.append("Fewer than half of works have a DOI; cross-source reconciliation is limited.")
            }
            if authorCoverage < 0.9 {
                score -= 8
                warnings.append("Some works predate authorship tracking; collaboration metrics undercount.")
            }
            if topicCoverage < 0.8 {
                score -= 8
                warnings.append("Topic coverage is incomplete; opportunity matching may be weaker.")
            }
        }

        if let scopus = enrichment?.scopus, let author = scopus.author {
            if let value = author.documentCount {
                entries.append(ProvenanceEntry(metric: "Works", source: "Scopus",
                                                value: value.formatted(),
                                                fetchedAt: scopus.fetchedAt))
                if relativeDifference(value, metrics.worksCount) > 0.15 {
                    score -= 8
                    warnings.append("OpenAlex and Scopus publication counts differ by more than 15%.")
                }
            }
            if let value = author.citationCount {
                entries.append(ProvenanceEntry(metric: "Citations", source: "Scopus",
                                                value: value.formatted(),
                                                fetchedAt: scopus.fetchedAt))
                if relativeDifference(value, metrics.citations) > 0.20 {
                    score -= 8
                    warnings.append("OpenAlex and Scopus citation counts differ by more than 20%.")
                }
            }
            if let value = author.hIndex {
                entries.append(ProvenanceEntry(metric: "h-index", source: "Scopus",
                                                value: value.formatted(),
                                                fetchedAt: scopus.fetchedAt))
                if abs(value - metrics.hIndex) > 3 {
                    score -= 6
                    warnings.append("OpenAlex and Scopus h-index values differ by more than three.")
                }
            }
        }
        if let icite = enrichment?.icite {
            entries.append(ProvenanceEntry(
                metric: "RCR coverage", source: "NIH iCite",
                value: "\(icite.byPMID.count) works", fetchedAt: icite.fetchedAt))
        }
        if let grants = enrichment?.grants {
            entries.append(ProvenanceEntry(
                metric: "NIH grants", source: "NIH RePORTER",
                value: grants.grants.count.formatted(), fetchedAt: grants.fetchedAt))
        }
        if let nsf = enrichment?.nsf {
            entries.append(ProvenanceEntry(
                metric: "NSF awards", source: "NSF",
                value: nsf.awards.count.formatted(), fetchedAt: nsf.fetchedAt))
        }

        return DataConfidenceReport(
            member: member, score: max(0, score),
            entries: entries, warnings: warnings)
    }

    private static func relativeDifference(_ lhs: Int, _ rhs: Int) -> Double {
        Double(abs(lhs - rhs)) / Double(max(max(lhs, rhs), 1))
    }

    // MARK: - Opportunity matching

    struct OpportunityFacultyMatch: Identifiable {
        var member: FacultyMember
        var score: Int
        var matchedTopics: [String]
        var reasons: [String]

        var id: UUID { member.id }
    }

    static func opportunityFacultyMatches(
        opportunity: FundingOpportunity,
        roster: [FacultyMember],
        personData: [UUID: PersonData],
        enrichment: [UUID: Enrichment],
        limit: Int = 8
    ) -> [OpportunityFacultyMatch] {
        let opportunityTokens = searchTokens(opportunity.title + " " + opportunity.matchedQuery)
        return roster.compactMap { member -> OpportunityFacultyMatch? in
            guard let data = personData[member.id] else { return nil }
            let roles = personTopicRoles(data: data, limit: 12)
            var score = 0
            var matched: [(String, Int)] = []
            for topic in roles {
                let overlap = opportunityTokens.intersection(searchTokens(topic.name)).count
                guard overlap > 0 else { continue }
                let topicScore = overlap * min(topic.works + topic.led, 12)
                score += topicScore
                matched.append((topic.name, topicScore))
            }

            var reasons: [String] = []
            let agency = opportunity.agencyName.lowercased()
            if agency.contains("health") || agency.contains("nih") {
                let grants = enrichment[member.id]?.grants?.grants.count ?? 0
                if grants > 0 {
                    score += min(grants, 5) * 2
                    reasons.append("Prior NIH funding")
                }
            }
            if agency.contains("science foundation") || opportunity.agencyCode.hasPrefix("NSF") {
                let awards = enrichment[member.id]?.nsf?.awards.count ?? 0
                if awards > 0 {
                    score += min(awards, 5) * 2
                    reasons.append("Prior NSF funding")
                }
            }
            let metric = personMetrics(member: member, data: data)
            if metric.seniorAuthorWorks >= 5 {
                score += 2
                reasons.append("Established research leadership")
            }
            guard score > 0 else { return nil }
            let topics = matched.sorted { ($0.1, $1.0) > ($1.1, $0.0) }.prefix(4).map(\.0)
            if !topics.isEmpty { reasons.insert("Topic match: \(topics.joined(separator: ", "))", at: 0) }
            return OpportunityFacultyMatch(
                member: member, score: score,
                matchedTopics: topics, reasons: reasons)
        }
        .sorted { ($0.score, $1.member.name) > ($1.score, $0.member.name) }
        .prefix(limit)
        .map { $0 }
    }

    static func suggestedOpportunityQueries(personData: [PersonData], limit: Int = 8) -> [String] {
        topicCounts(personData: personData)
            .filter { $0.works >= 2 }
            .prefix(limit)
            .map(\.name)
    }

    private static func searchTokens(_ value: String) -> Set<String> {
        let stop: Set<String> = [
            "and", "the", "for", "with", "from", "into", "using", "through",
            "research", "development", "program", "project", "clinical", "trial",
            "optional", "advanced", "early", "stage", "management", "support",
        ]
        return Set(value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stop.contains($0) })
    }

    // MARK: - Publication reconciliation

    static func reconciliationMatches(imported: [ImportedPublication],
                                      works: [Work]) -> [ReconciliationMatch] {
        var byDOI: [String: Work] = [:]
        for work in works {
            if let doi = work.doi {
                byDOI[PublicationReferenceImporter.normalizeDOI(doi)] = work
            }
        }
        let byTitle = Dictionary(grouping: works) {
            PublicationReferenceImporter.normalizedTitle($0.title)
        }
        return imported.map { publication in
            if let doi = publication.doi.map(PublicationReferenceImporter.normalizeDOI),
               let work = byDOI[doi] {
                return ReconciliationMatch(imported: publication, kind: .doi, matchedWork: work)
            }
            let key = PublicationReferenceImporter.normalizedTitle(publication.title)
            if let work = byTitle[key]?.first {
                return ReconciliationMatch(imported: publication, kind: .title, matchedWork: work)
            }
            return ReconciliationMatch(imported: publication, kind: .missing, matchedWork: nil)
        }
        .sorted {
            ($0.imported.disposition == .pending ? 0 : 1, $0.kind.rawValue,
             -($0.imported.year ?? 0), $0.imported.title)
            < ($1.imported.disposition == .pending ? 0 : 1, $1.kind.rawValue,
               -($1.imported.year ?? 0), $1.imported.title)
        }
    }
}
