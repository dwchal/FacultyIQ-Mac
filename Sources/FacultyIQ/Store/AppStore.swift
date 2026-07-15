import Foundation
import SwiftUI

/// Central app state: roster, identity resolutions, fetched data, and the
/// async workflow operations. Persists itself as JSON in Application Support.
@MainActor
final class AppStore: ObservableObject {
    @Published var roster: [FacultyMember] = []
    @Published var resolutions: [UUID: Resolution] = [:]
    @Published var personData: [UUID: PersonData] = [:]

    /// Restricts every analysis tab (dashboard, profiles, promotion, network,
    /// export) to one division; nil shows everyone. Session-only, not persisted.
    @Published var divisionFilter: String? = nil

    @Published var isBusy = false
    @Published var progressText = ""
    @Published var progress: Double? = nil   // 0...1 while a batch runs
    @Published var lastError: String?

    private let client = OpenAlexClient.shared

    init() {
        load()
    }

    // MARK: Derived state

    /// Distinct divisions present in the roster, sorted.
    var divisions: [String] {
        Array(Set(roster.compactMap(\.division))).sorted()
    }

    /// The roster as the analysis tabs see it: everyone, or one division.
    var filteredRoster: [FacultyMember] {
        guard let filter = divisionFilter, divisions.contains(filter) else { return roster }
        return roster.filter { $0.division == filter }
    }

    var filteredPersonData: [PersonData] {
        filteredRoster.compactMap { personData[$0.id] }
    }

    var metrics: [PersonMetrics] {
        MetricsEngine.allMetrics(roster: filteredRoster, personData: personData)
    }

    var summary: DivisionSummary {
        MetricsEngine.divisionSummary(
            roster: filteredRoster,
            resolvedCount: filteredRoster.count { resolutions[$0.id] != nil },
            metrics: metrics)
    }

    var benchmarks: [RankBenchmark] {
        MetricsEngine.rankBenchmarks(metrics: metrics)
    }

    var promotionCandidates: [PromotionCandidate] {
        MetricsEngine.promotionCandidates(metrics: metrics, benchmarks: benchmarks)
    }

    var promotionProgress: [PromotionProgress] {
        MetricsEngine.promotionProgress(metrics: metrics, benchmarks: benchmarks)
    }

    var coauthorNetwork: CoauthorNetwork {
        MetricsEngine.coauthorNetwork(
            roster: filteredRoster, resolutions: resolutions, personData: personData)
    }

    func resolution(for member: FacultyMember) -> Resolution? {
        resolutions[member.id]
    }

    /// Members whose data the next refreshData() call would bring up to date:
    /// unresolved with an ORCID/Scopus ID, or resolved but not yet fetched.
    var pendingRefreshCount: Int {
        roster.count { member in
            if resolutions[member.id] == nil {
                member.orcid != nil || member.scopusID != nil
            } else {
                personData[member.id] == nil
            }
        }
    }

    // MARK: Roster

    func importRoster(from url: URL) {
        do {
            let members = try RosterImporter.importRoster(from: url)
            replaceRoster(with: members)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadSampleRoster() {
        guard let members = try? RosterImporter.importRoster(fromText: sampleRosterCSV) else { return }
        replaceRoster(with: members)
    }

    private func replaceRoster(with members: [FacultyMember]) {
        roster = members
        // Keep resolutions/data only makes sense per-roster; new roster resets them.
        resolutions = [:]
        personData = [:]
        divisionFilter = nil
        lastError = nil
        save()
    }

    func addMember(_ member: FacultyMember) {
        roster.append(member)
        save()
    }

    func updateMember(_ member: FacultyMember) {
        guard let index = roster.firstIndex(where: { $0.id == member.id }) else { return }
        let old = roster[index]
        roster[index] = member
        // A changed ORCID or Scopus ID means the member may resolve to a
        // different author, so the old resolution and data no longer apply.
        if old.orcid != member.orcid || old.scopusID != member.scopusID {
            resolutions[member.id] = nil
            personData[member.id] = nil
        }
        save()
    }

    func removeMembers(_ ids: Set<UUID>) {
        roster.removeAll { ids.contains($0.id) }
        for id in ids {
            resolutions[id] = nil
            personData[id] = nil
        }
        save()
    }

    func clearAll() {
        roster = []
        resolutions = [:]
        personData = [:]
        divisionFilter = nil
        save()
    }

    // MARK: Resolution

    /// Resolve every member that has an ORCID or Scopus ID and isn't resolved yet.
    func autoResolveAll() async {
        let pending = roster.filter { resolutions[$0.id] == nil && ($0.orcid != nil || $0.scopusID != nil) }
        guard !pending.isEmpty else { return }
        await runBatch(label: "Resolving", items: pending) { member in
            try await self.autoResolve(member)
        }
    }

    private func autoResolve(_ member: FacultyMember) async throws {
        var candidate: AuthorCandidate?
        var method = ResolutionMethod.orcid
        if let orcid = member.orcid {
            candidate = try await client.authorByORCID(orcid)
        }
        if candidate == nil, let scopus = member.scopusID {
            candidate = try await client.authorByScopus(scopus)
            method = .scopus
        }
        if let candidate {
            resolve(member, with: candidate, method: method)
        }
    }

    func resolve(_ member: FacultyMember, with candidate: AuthorCandidate, method: ResolutionMethod) {
        // Data fetched for a previously resolved author doesn't carry over.
        if resolutions[member.id]?.openalexID != candidate.openalexID {
            personData[member.id] = nil
        }
        resolutions[member.id] = Resolution(
            openalexID: candidate.openalexID,
            displayName: candidate.displayName,
            method: method,
            affiliation: candidate.affiliation,
            orcid: candidate.orcid
        )
        save()
    }

    func unresolve(_ member: FacultyMember) {
        resolutions[member.id] = nil
        personData[member.id] = nil
        save()
    }

    func searchAuthors(name: String) async -> [AuthorCandidate] {
        do {
            return try await client.searchAuthors(name: name)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    // MARK: Fetch

    /// Catch up after roster or resolution edits: auto-resolve members that
    /// gained an ORCID/Scopus ID, then fetch data for anyone missing it.
    func refreshData() async {
        await autoResolveAll()
        await fetchAll()
    }

    /// Fetch profile + works for every resolved member without data.
    func fetchAll(refresh: Bool = false) async {
        let pending = roster.filter { member in
            resolutions[member.id] != nil && (refresh || personData[member.id] == nil)
        }
        guard !pending.isEmpty else { return }
        await runBatch(label: "Fetching", items: pending) { member in
            try await self.fetchOne(member)
        }
    }

    func fetchOne(_ member: FacultyMember) async throws {
        guard let resolution = resolutions[member.id] else { return }
        let profile = try await client.author(id: resolution.openalexID)
        let works = try await client.works(authorID: resolution.openalexID)
        personData[member.id] = PersonData(profile: profile, works: works, fetchedAt: Date())
        save()
    }

    /// Run an async operation over members with progress reporting; individual
    /// failures are collected rather than aborting the batch.
    private func runBatch(label: String,
                          items: [FacultyMember],
                          operation: @escaping (FacultyMember) async throws -> Void) async {
        isBusy = true
        lastError = nil
        var failures: [String] = []
        for (i, member) in items.enumerated() {
            progress = Double(i) / Double(items.count)
            progressText = "\(label) \(member.name) (\(i + 1)/\(items.count))…"
            do {
                try await operation(member)
            } catch {
                failures.append("\(member.name): \(error.localizedDescription)")
            }
        }
        progress = nil
        progressText = ""
        isBusy = false
        if !failures.isEmpty {
            lastError = failures.joined(separator: "\n")
        }
        save()
    }

    // MARK: Persistence

    private struct SavedState: Codable {
        var roster: [FacultyMember]
        var resolutions: [UUID: Resolution]
        var personData: [UUID: PersonData]
    }

    private var stateURL: URL {
        CacheStore.supportDirectory.appendingPathComponent("state.json")
    }

    func save() {
        let state = SavedState(roster: roster, resolutions: resolutions, personData: personData)
        do {
            try FileManager.default.createDirectory(
                at: CacheStore.supportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            lastError = "Could not save state: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        roster = state.roster
        resolutions = state.resolutions
        personData = state.personData
    }
}
